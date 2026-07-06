extends Node
## Dedicated-server bootstrap (M1-01). Started by boot.gd when running with
## the "dedicated_server" feature or `-- --server`. Optional user args:
##   --port=7777

var _heartbeat_accum := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(NetManager._arg_value(args, "--port", str(NetConfig.DEFAULT_PORT)))
	var err := NetManager.start_server(port)
	if err != OK:
		printerr("[server] failed to listen on port %d (error %d)" % [port, err])
		get_tree().quit(1)
		return
	# Machine-readable startup line; the soak harness waits for it.
	print("SERVER READY port=%d protocol=%d" % [port, NetConfig.PROTOCOL_VERSION])
	# Diagnostics trail (M18-06): always on; --debug-log raises to the firehose.
	var level: int = (
		DiagnosticsLog.Level.DEBUG if "--debug-log" in args else DiagnosticsLog.Level.INFO
	)
	DiagnosticsLog.configure("server", level)
	DiagnosticsLog.event(
		&"app",
		&"boot",
		{"version": AppVersion.VERSION, "protocol": NetConfig.PROTOCOL_VERSION, "port": port}
	)
	var updater := ServerUpdater.new()
	updater.name = "ServerUpdater"  # the dashboard looks this child up (#172)
	add_child(updater)


func _process(delta: float) -> void:
	_heartbeat_accum += delta
	if _heartbeat_accum >= 60.0:
		_heartbeat_accum = 0.0
		var manager: RoomManager = NetManager.room_manager
		print(
			(
				"[server] heartbeat rooms=%d peers=%d"
				% [manager.rooms.size(), multiplayer.get_peers().size()]
			)
		)
