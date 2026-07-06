extends Control
## Main menu (M2-01): host a room, join by code, or rejoin the last session
## (SPEC $4, $9). Connect defaults: last session > settings override (M2-05)
## > DEFAULT_ADDRESS, tweakable per-launch in the Advanced fold-out. All
## traffic goes through the NetManager autoload.

## Picked up by the app shell router (see AppShell.goto_screen).
signal navigate(screen: StringName)

enum PendingRequest { NONE, HOST, JOIN, REJOIN }

## The public game server (owner-hosted). Local dev overrides via the
## Advanced fold-out or Settings > Network (see scripts/dev-client.sh).
const DEFAULT_ADDRESS := "celestrum.com"

var _pending := PendingRequest.NONE
## Pre-connection reachability status for the configured server (#607).
var _probe := ServerProbe.new()
## In-flight probe transport (#676): its own throwaway peer, never
## `multiplayer.multiplayer_peer`, so it cannot fight the debug launcher or a
## real Host/Join for the shared transport. Null when no probe is running.
var _probe_transport: ServerReachabilityProbe
var _pending_code := ""
var _pending_token := ""
## Self-update flow (#144): filled by the checker, consumed by the button.
var _update_version := ""
var _update_url := ""
var _update_checker: UpdateChecker
var _updater: Updater

@onready var _name_edit: LineEdit = %NameEdit
@onready var _code_edit: LineEdit = %CodeEdit
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _rejoin_button: Button = %RejoinButton
@onready var _settings_button: Button = %SettingsButton
@onready var _credits_button: Button = %CreditsButton
@onready var _quit_button: Button = %QuitButton
@onready var _advanced_toggle: CheckButton = %AdvancedToggle
@onready var _advanced_box: Control = %AdvancedBox
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _port_edit: LineEdit = %PortEdit
@onready var _status_label: Label = %StatusLabel
@onready var _server_chip: Label = %ServerStatusChip
@onready var _retry_button: Button = %ProbeRetryButton
@onready var _update_button: Button = %UpdateButton


func _ready() -> void:
	NetManager.connected_to_server.connect(_on_connected_to_server)
	NetManager.connection_failed.connect(_on_connection_failed)
	NetManager.joined_room.connect(_on_joined_room)
	NetManager.join_failed.connect(_on_join_failed)
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_rejoin_button.pressed.connect(_on_rejoin_pressed)
	_settings_button.pressed.connect(func() -> void: navigate.emit(&"settings"))
	_credits_button.pressed.connect(func() -> void: navigate.emit(&"credits"))
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	_advanced_toggle.toggled.connect(func(on: bool) -> void: _advanced_box.visible = on)
	_code_edit.text_changed.connect(_on_code_changed)
	_code_edit.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_address_edit.text = DEFAULT_ADDRESS
	_port_edit.text = str(NetConfig.DEFAULT_PORT)
	var saved := SessionStore.load_session()
	_rejoin_button.visible = not saved.is_empty() and not String(saved.code).is_empty()
	if _rejoin_button.visible:
		_address_edit.text = saved.address
		_port_edit.text = str(saved.port)
	# An explicit settings override (M2-05) beats the last-session prefill;
	# the rejoin flow still uses the session's own address when pressed.
	var overrides := SettingsStore.load_settings()
	if not String(overrides.player_name).is_empty():
		_name_edit.text = overrides.player_name
	_name_edit.text_changed.connect(_save_player_name)
	var override_address: String = overrides.server_address
	var override_port: int = overrides.server_port
	if not override_address.is_empty():
		_address_edit.text = override_address
	if override_port > 0:
		_port_edit.text = str(override_port)
	_setup_update_flow()
	_apply_button_motion()
	_retry_button.pressed.connect(_start_probe)
	ButtonMotion.attach(_retry_button)
	_refresh_server_chip()
	_start_probe()
	_host_button.grab_focus()


## M16-03: the shared hover/press motion on every menu button. No-op under
## reduced motion (the helper checks); the themed color/shadow states remain.
func _apply_button_motion() -> void:
	for button: Button in [
		_host_button,
		_join_button,
		_rejoin_button,
		_settings_button,
		_credits_button,
		_quit_button,
		_update_button,
	]:
		ButtonMotion.attach(button)


## Self-update (#144): check quietly on menu load; the button only appears
## when a newer release exists, and every step after that is user-confirmed.
func _setup_update_flow() -> void:
	_update_checker = UpdateChecker.new()
	add_child(_update_checker)
	_update_checker.update_available.connect(_on_update_available)
	_updater = Updater.new()
	add_child(_updater)
	_updater.staged.connect(_on_update_staged)
	_updater.failed.connect(
		func(reason: String) -> void:
			_update_button.disabled = false
			_show_error(reason)
	)
	_update_button.pressed.connect(_on_update_pressed)
	_update_checker.check()


func _on_update_available(version: String, download_url: String) -> void:
	_update_version = version
	_update_url = download_url
	_update_button.text = "Update to v%s" % version
	_update_button.visible = true


func _on_update_pressed() -> void:
	if _update_url.is_empty():
		return
	_update_button.disabled = true
	_set_status("Downloading v%s ..." % _update_version)
	_updater.download_and_stage(_update_version, _update_url)


func _on_update_staged(version: String) -> void:
	_status_label.text = ""
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = (
		"v%s is ready. Restart now to finish updating?\n(You can keep playing and update later.)"
		% version
	)
	dialog.ok_button_text = "Restart and update"
	dialog.cancel_button_text = "Later"
	add_child(dialog)
	dialog.confirmed.connect(_updater.apply_and_restart)
	dialog.canceled.connect(
		func() -> void:
			_update_button.disabled = false
			dialog.queue_free()
	)
	dialog.popup_centered()


func _save_player_name(text: String) -> void:
	var settings := SettingsStore.load_settings()
	settings.player_name = text
	SettingsStore.save_settings(settings)


func _on_host_pressed() -> void:
	_begin(PendingRequest.HOST)


func _on_join_pressed() -> void:
	var code := RoomCodes.normalize(_code_edit.text)
	if not RoomCodes.is_valid(code):
		_show_error("Room codes are %d letters/digits." % NetConfig.ROOM_CODE_LENGTH)
		return
	_pending_code = code
	_begin(PendingRequest.JOIN)


func _on_rejoin_pressed() -> void:
	var saved := SessionStore.load_session()
	if saved.is_empty() or String(saved.code).is_empty():
		_rejoin_button.visible = false
		_show_error("No saved session to rejoin.")
		return
	_pending_code = saved.code
	_pending_token = saved.token
	_address_edit.text = saved.address
	_port_edit.text = str(saved.port)
	_begin(PendingRequest.REJOIN)


## Connects first if needed; the pending request fires on connected_to_server.
func _begin(request: PendingRequest) -> void:
	# The probe rides its own peer (#676) so it can't fight this connect; it is
	# cancelled anyway so a late result doesn't repaint the chip mid-flow.
	_cancel_probe()
	_pending = request
	_set_busy(true)
	if _is_connected():
		_dispatch_pending()
		return
	_set_status("Connecting to %s:%s ..." % [_address_edit.text, _port_edit.text])
	var err := NetManager.connect_to_server(_address_edit.text, int(_port_edit.text))
	if err != OK:
		_pending = PendingRequest.NONE
		_set_busy(false)
		_show_error("Could not start a connection (error %d)." % err)


func _dispatch_pending() -> void:
	match _pending:
		PendingRequest.HOST:
			NetManager.request_create_room(_display_name())
		PendingRequest.JOIN:
			NetManager.request_join_room(_pending_code, _display_name())
		PendingRequest.REJOIN:
			NetManager.request_rejoin_room(_pending_code, _pending_token)
	_pending = PendingRequest.NONE


func _on_connected_to_server() -> void:
	if _pending != PendingRequest.NONE:
		_dispatch_pending()


func _on_connection_failed() -> void:
	_pending = PendingRequest.NONE
	_set_busy(false)
	_show_error("Could not reach the server.")


func _on_joined_room(code: String, _slot: int, token: String) -> void:
	SessionStore.save_session(_address_edit.text, int(_port_edit.text), code, token)


func _on_join_failed(reason: int) -> void:
	_set_busy(false)
	_show_error(JoinFailureText.describe(reason))
	# A protocol mismatch usually means we're the stale side — surface the
	# update button if a newer release exists (#144).
	if reason == NetConfig.JoinResult.VERSION_MISMATCH:
		_update_checker.check()


func _on_code_changed(new_text: String) -> void:
	var normalized := RoomCodes.normalize(new_text)
	if normalized != new_text:
		var caret := _code_edit.caret_column
		_code_edit.text = normalized
		_code_edit.caret_column = mini(caret, normalized.length())


func _display_name() -> String:
	var display_name := _name_edit.text.strip_edges()
	return display_name if not display_name.is_empty() else "Player"


func _set_busy(busy: bool) -> void:
	_host_button.disabled = busy
	_join_button.disabled = busy
	_rejoin_button.disabled = busy
	_name_edit.editable = not busy
	_code_edit.editable = not busy
	if not busy:
		_status_label.text = ""


## Status line: gold for info/progress, red for errors (STYLE_GUIDE semantics —
## DANGER means something went wrong). StatusLabel is a HintLabel (accent) by
## default, so info needs no override.
func _set_status(text: String, is_error := false) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override(
		&"font_color", PartyTheme.DANGER if is_error else PartyTheme.ACCENT
	)


func _show_error(text: String) -> void:
	_set_status(text, true)


func _is_connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	# The engine substitutes OfflineMultiplayerPeer when none is set.
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# --- Server reachability probe (#607, transport isolated per #676) -----------


## Opens a throwaway connection to the configured server on the probe's OWN
## peer (never `multiplayer.multiplayer_peer`) — the chip reports
## reachable/unreachable before the player commits to Host/Join, and physically
## cannot disturb whoever owns the shared transport (the #676 regression: the
## first design stole and then closed the debug launcher's boot connection).
func _start_probe() -> void:
	if _probe_transport != null or _pending != PendingRequest.NONE or _is_connected():
		return
	_probe.mark_checking()
	_refresh_server_chip()
	_probe_transport = ServerReachabilityProbe.new()
	add_child(_probe_transport)
	_probe_transport.finished.connect(_on_probe_finished)
	_probe_transport.start(_address_edit.text, int(_port_edit.text))


func _on_probe_finished(reachable: bool, rtt_ms: int) -> void:
	if reachable:
		_probe.mark_online(rtt_ms)
	else:
		_probe.mark_unreachable()
	_clear_probe_transport()
	_refresh_server_chip()


## Aborts an in-flight probe without changing the last status — used when a
## real Host/Join begins, so a late result doesn't repaint the chip (#607).
func _cancel_probe() -> void:
	_clear_probe_transport()


func _clear_probe_transport() -> void:
	if _probe_transport == null:
		return
	_probe_transport.cancel()
	_probe_transport.queue_free()
	_probe_transport = null


func _refresh_server_chip() -> void:
	var address := _address_edit.text
	_server_chip.text = ServerProbe.chip_text(_probe.status, _probe.rtt_ms, address)
	_server_chip.add_theme_color_override(&"font_color", ServerProbe.chip_color(_probe.status))
	_retry_button.visible = ServerProbe.retry_visible(_probe.status)
