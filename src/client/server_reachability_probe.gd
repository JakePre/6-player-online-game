class_name ServerReachabilityProbe
extends Node
## One-shot server reachability probe (#607): opens a throwaway
## ENetMultiplayerPeer client to (address, port), polls it independently of the
## SceneMultiplayer, and emits `finished(reachable, rtt_ms)` when it connects,
## fails, or times out.
##
## The probe's peer is NEVER assigned to `multiplayer.multiplayer_peer`, so it
## can't disturb whoever else owns that shared peer — this is a
## look-before-you-leap check, not the actual session. It uses the same ENet
## transport the real connect uses, so "reachable" here means "reachable then".
## This isolation is load-bearing (#676): the first probe design drove the
## shared peer and silently killed the debug launcher's boot-time connection.

signal finished(reachable: bool, rtt_ms: int)

## ENet's own connect retries take several seconds to give up on a dead host, so
## the probe caps its own patience below that to keep the menu responsive.
const TIMEOUT_SEC := 4.0

var _peer: ENetMultiplayerPeer
var _elapsed := 0.0
var _start_ms := 0
var _done := false


## Kick off the probe. Emits `finished(false, -1)` synchronously if the client
## can't even be created (bad address/port); otherwise resolves on a later frame.
func start(address: String, port: int) -> void:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_emit(false, -1)
		return
	_start_ms = Time.get_ticks_msec()
	set_process(true)


func _process(delta: float) -> void:
	if _done or _peer == null:
		return
	_peer.poll()
	match _peer.get_connection_status():
		MultiplayerPeer.CONNECTION_CONNECTED:
			_emit(true, Time.get_ticks_msec() - _start_ms)
		MultiplayerPeer.CONNECTION_DISCONNECTED:
			_emit(false, -1)
		_:
			_elapsed += delta
			if _elapsed >= TIMEOUT_SEC:
				_emit(false, -1)


## Abandon an in-flight probe without emitting (e.g. the chip is re-probing or
## being freed). Safe to call more than once, or before start().
func cancel() -> void:
	_done = true
	set_process(false)
	_close()


func _emit(reachable: bool, rtt_ms: int) -> void:
	if _done:
		return
	_done = true
	set_process(false)
	_close()
	finished.emit(reachable, rtt_ms)


func _close() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
