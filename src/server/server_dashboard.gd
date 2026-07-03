class_name ServerDashboard
extends Control
## Double-clickable server app (#145 part 1): a small status window wrapped
## around the real dedicated server. Mounts the untouched ServerHost as a
## child (so ticking, heartbeats, and ServerUpdater behave exactly like the
## headless build) and renders what operators care about: status, live room
## and player counts, an activity log, and a Stop button. Ships as the
## "Windows Server" preset via the server_app feature (#166); dev-testable
## anywhere with `-- --server-ui`.

const SERVER_HOST_SCRIPT := "res://src/server/server_host.gd"
const MAX_LOG_LINES := 200
const STATS_REFRESH_SEC := 1.0

## Tests disable this to exercise the UI without binding a real port.
var autostart := true

@onready var _status_label: Label = %StatusLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _log: RichTextLabel = %Log
@onready var _stop_button: Button = %StopButton
@onready var _update_button: Button = %UpdateButton


func _ready() -> void:
	get_window().title = "Party Rush Server v%s" % AppVersion.VERSION
	_stop_button.pressed.connect(func() -> void: get_tree().quit())
	NetManager.peer_joined_room.connect(
		func(room: Room, member: RoomMember) -> void:
			log_line("%s joined room %s" % [member.display_name, room.code])
	)
	NetManager.peer_left_room.connect(
		func(room: Room) -> void: log_line("a player left room %s" % room.code)
	)
	NetManager.match_started.connect(
		func(room: Room) -> void: log_line("match started in room %s" % room.code)
	)
	var stats := Timer.new()
	stats.wait_time = STATS_REFRESH_SEC
	stats.timeout.connect(_refresh_stats)
	add_child(stats)
	stats.start()
	if autostart:
		var host: Node = (load(SERVER_HOST_SCRIPT) as GDScript).new()
		host.name = "ServerHost"
		add_child(host)
		_wire_updater(host.get_node_or_null("ServerUpdater"))
	_refresh_status()


## Client-style update UX (#172, mirrors main_menu's #144 flow): the button
## appears when a newer release exists; one click downloads and applies with
## ServerUpdater's never-under-live-rooms restart. Headless opt-in behavior
## is untouched — this is just eyes and a button on the same machinery.
func _wire_updater(updater: ServerUpdater) -> void:
	if updater == null:
		return
	updater.update_available.connect(
		func(version: String) -> void:
			log_line("update available: v%s" % version)
			_update_button.text = "Update to v%s & restart" % version
			_update_button.visible = true
	)
	updater.update_staged.connect(
		func(version: String) -> void: log_line("v%s downloaded — restarting when idle" % version)
	)
	updater.update_waiting.connect(
		func(version: String, live_rooms: int) -> void:
			log_line("v%s waits for %d live room(s) to finish" % [version, live_rooms])
	)
	updater.update_failed.connect(
		func(reason: String) -> void:
			_update_button.disabled = false
			log_line("update failed: %s" % reason)
	)
	_update_button.pressed.connect(
		func() -> void:
			_update_button.disabled = true
			log_line("downloading update...")
			updater.request_update()
	)


func _refresh_status() -> void:
	if NetManager.is_server:
		_status_label.text = (
			"RUNNING — protocol %d, build v%s" % [NetConfig.PROTOCOL_VERSION, AppVersion.VERSION]
		)
		_status_label.modulate = Color(0.5, 1.0, 0.55)
		log_line("server ready (protocol %d)" % NetConfig.PROTOCOL_VERSION)
	else:
		_status_label.text = "NOT RUNNING — see the log; is the port already in use?"
		_status_label.modulate = Color(1.0, 0.45, 0.4)


func _refresh_stats() -> void:
	if not NetManager.is_server:
		return
	var manager: RoomManager = NetManager.room_manager
	var players := NetManager.multiplayer.get_peers().size()
	_stats_label.text = "Rooms: %d    Players online: %d" % [manager.rooms.size(), players]


## Appends a timestamped line to the activity log, keeping it bounded.
func log_line(text: String) -> void:
	var stamp := Time.get_time_string_from_system()
	_log.append_text("[%s] %s\n" % [stamp, text])
	if _log.get_paragraph_count() > MAX_LOG_LINES:
		_log.remove_paragraph(0)
