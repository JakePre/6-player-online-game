extends Control
## Client app shell (M2-01): owns screen routing and hosts the always-visible
## connection status indicator. Navigation follows the server's view of the
## session via NetManager signals (SPEC $4): main menu -> room after a join,
## back to the main menu on leave or server loss. Also hosts the shared error
## toasts and the reconnect overlay (M6-03): a drop while in a room retries
## the saved session instead of silently dumping the player to the menu.

const SCREENS := {
	&"main_menu": "res://src/client/screens/main_menu.tscn",
	&"settings": "res://src/client/screens/settings_menu.tscn",
	&"stats": "res://src/client/screens/stats_screen.tscn",
	&"credits": "res://src/client/screens/credits_screen.tscn",
	&"room": "res://src/lobby/lobby.tscn",
	&"match": "res://src/match/match_screen.tscn",
}
const ROOM_SCREENS: Array[StringName] = [&"room", &"match"]
## A frame longer than this is worth a diagnostics note (M18-07); rate-limited
## so a rough patch logs one line, not one per frame.
const PERF_SPIKE_SEC := 0.1
const PERF_SPIKE_COOLDOWN_SEC := 2.0

var _current_screen: Node
var _current_id := &""
var _transition: ScreenTransition
var _perf_spike_cooldown := 0.0

@onready var _screen_host: Control = $ScreenHost
@onready var _reconnect_overlay: Control = $ReconnectOverlay
@onready var _toasts: Toasts = $Toasts


func _ready() -> void:
	# One shared theme at the root (M6-04); every screen inherits it.
	theme = PartyTheme.build()
	# Shared screen-change transition (M16-02); added last so its cover sits
	# above the mounted screens during a reveal.
	_transition = ScreenTransition.new()
	add_child(_transition)
	SettingsStore.apply(SettingsStore.load_settings(), get_window())
	# Diagnostics log (M18-07): if the opt-in setting just started it, note the
	# session so a bug report's log has the client's version/OS/resolution.
	if DiagnosticsLog.is_active():
		var window_size := DisplayServer.window_get_size()
		(
			DiagnosticsLog
			. event(
				&"app",
				&"boot",
				{
					"version": AppVersion.VERSION,
					"os": OS.get_name(),
					"resolution": "%dx%d" % [window_size.x, window_size.y],
				}
			)
		)
	InputGlyphs.device_changed.connect(
		func(device: InputGlyphs.Device) -> void:
			DiagnosticsLog.event(
				&"input", &"device_change", {"device": InputGlyphs.Device.keys()[device]}
			)
	)
	NetManager.joined_room.connect(_on_joined_room)
	NetManager.room_updated.connect(_on_room_updated)
	NetManager.join_failed.connect(_on_join_failed)
	NetManager.match_start_failed.connect(_on_match_start_failed)
	NetManager.kicked.connect(
		func() -> void: _toasts.show_toast("Removed from the room by the host.")
	)
	NetManager.left_room.connect(func() -> void: goto_screen(&"main_menu"))
	NetManager.server_disconnected.connect(_on_server_disconnected)
	_reconnect_overlay.closed.connect(_on_reconnect_closed)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Pads plugged in before launch never fire joy_connection_changed
	# (M18-05 first-run audit): acknowledge them once the shell is up, so a
	# player who sat down with a controller knows the game sees it.
	for device in Input.get_connected_joypads():
		_on_joy_connection_changed.call_deferred(device, true)
	goto_screen(&"main_menu")


## Diagnostics log (M18-07): a long frame worth a note, rate-limited so a
## rough patch costs one line, not one per frame. No-op while logging is off.
func _process(delta: float) -> void:
	if not DiagnosticsLog.is_active():
		return
	_perf_spike_cooldown = maxf(0.0, _perf_spike_cooldown - delta)
	if delta > PERF_SPIKE_SEC and _perf_spike_cooldown <= 0.0:
		_perf_spike_cooldown = PERF_SPIKE_COOLDOWN_SEC
		DiagnosticsLog.warn(&"perf", &"spike", {"frame_ms": snappedf(delta * 1000.0, 0.1)})


func goto_screen(id: StringName) -> void:
	assert(SCREENS.has(id), "Unknown screen id: %s" % id)
	# The very first mount (boot -> menu) swaps with no transition, so launch
	# has no dark flash; every later change reveals from behind the cover.
	var animate := _current_screen != null
	if _current_screen != null:
		_current_screen.queue_free()
	var scene_path: String = SCREENS[id]
	var scene: PackedScene = load(scene_path)
	_current_screen = scene.instantiate()
	# Screens request navigation (e.g. main menu -> settings) by declaring a
	# `navigate(screen: StringName)` signal; server-driven routing stays above.
	if _current_screen.has_signal("navigate"):
		_current_screen.connect("navigate", goto_screen)
	_screen_host.add_child(_current_screen)
	_current_id = id
	AudioManager.play_music(&"round" if id == &"match" else &"menu")
	if animate and _transition != null:
		_transition.reveal()


func _on_joined_room(_code: String, _slot: int, _token: String) -> void:
	goto_screen(&"room")


## The server's room state decides which screen is right (SPEC $4): lobby
## while LOBBY, match chrome while IN_MATCH. Covers match start, the podium
## returning everyone to the lobby, and rejoining into a running match.
func _on_room_updated(state: Dictionary) -> void:
	if state.state == Room.State.IN_MATCH and _current_id == &"room":
		goto_screen(&"match")
	elif state.state == Room.State.LOBBY and _current_id == &"match":
		goto_screen(&"room")


## A drop while in a room goes to the reconnect overlay (SPEC $11) as long as
## there is a saved session to retry; everywhere else the menu is the right
## place, with a toast so the drop is not silent.
func _on_server_disconnected() -> void:
	if _current_id in ROOM_SCREENS:
		var saved := SessionStore.load_session()
		if not String(saved.get("code", "")).is_empty():
			_reconnect_overlay.begin(saved)
			return
	_toasts.show_toast("Connection to the server was lost.")
	goto_screen(&"main_menu")


func _on_reconnect_closed(rejoined: bool) -> void:
	if rejoined:
		return
	_toasts.show_toast("Left the session. You can rejoin from the menu.")
	goto_screen(&"main_menu")


## The main menu reports join failures inline next to its form, and the
## reconnect overlay owns failures during its own retries; toast everywhere
## else so refusals (room full, bad code, version mismatch) are never silent.
func _on_join_failed(reason: int) -> void:
	if _current_id == &"main_menu" or _reconnect_overlay.visible:
		return
	_toasts.show_toast(JoinFailureText.describe(reason))


func _on_match_start_failed(reason: String) -> void:
	_toasts.show_toast("Could not start the match: %s" % reason)


## Hot-plug feedback (M17-01): pads announce themselves so players know the
## game saw them, and unrecognized GUIDs are logged so unmapped hardware is
## diagnosable straight from a player report.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected:
		_toasts.show_toast("Controller disconnected.")
		return
	var joy_name := Input.get_joy_name(device)
	if Input.is_joy_known(device):
		_toasts.show_toast(
			"Controller connected: %s" % joy_name, Toasts.DEFAULT_DURATION_SEC, PartyTheme.SUCCESS
		)
	else:
		push_warning(
			(
				"Unrecognized controller '%s' (GUID %s) — generic mapping"
				% [joy_name, Input.get_joy_guid(device)]
			)
		)
		_toasts.show_toast(
			"Controller '%s' not in the mapping database — using a generic layout." % joy_name,
			Toasts.DEFAULT_DURATION_SEC,
			PartyTheme.INFO
		)
