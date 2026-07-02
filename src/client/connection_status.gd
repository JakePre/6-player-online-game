extends PanelContainer
## Always-visible connection status indicator (SPEC $11): offline, connecting,
## or online with round-trip time. Reads the transport state directly each
## frame so it stays honest even if a signal is missed.

const PING_INTERVAL_SEC := 2.0

var _last_rtt_ms := -1

@onready var _label: Label = $Label


func _ready() -> void:
	NetManager.pong_received.connect(func(rtt_ms: int) -> void: _last_rtt_ms = rtt_ms)
	NetManager.server_disconnected.connect(func() -> void: _last_rtt_ms = -1)
	NetManager.connection_failed.connect(func() -> void: _last_rtt_ms = -1)
	var timer := Timer.new()
	timer.wait_time = PING_INTERVAL_SEC
	timer.timeout.connect(_on_ping_timer)
	add_child(timer)
	timer.start()


func _process(_delta: float) -> void:
	_label.text = _status_text()


func _on_ping_timer() -> void:
	if _connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		NetManager.send_ping()


func _status_text() -> String:
	match _connection_status():
		MultiplayerPeer.CONNECTION_CONNECTING:
			return "Connecting..."
		MultiplayerPeer.CONNECTION_CONNECTED:
			if _last_rtt_ms >= 0:
				return "Online  %d ms" % _last_rtt_ms
			return "Online"
		_:
			return "Offline"


func _connection_status() -> MultiplayerPeer.ConnectionStatus:
	var peer := multiplayer.multiplayer_peer
	# The engine substitutes OfflineMultiplayerPeer when none is set, and that
	# one always reports CONNECTED.
	if peer == null or peer is OfflineMultiplayerPeer:
		return MultiplayerPeer.CONNECTION_DISCONNECTED
	return peer.get_connection_status()
