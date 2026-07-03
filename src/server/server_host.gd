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
	add_child(ServerUpdater.new())


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
