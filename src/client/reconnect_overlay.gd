extends Control
## Reconnect overlay (M6-03, SPEC $11): shown when the server connection drops
## while the player is in a room. Retries the saved session's rejoin flow
## (SPEC $9: connect + code + token) with a capped backoff; the player can
## retry immediately or give up back to the main menu. A refused rejoin (room
## expired, bad token, version mismatch) stops the automatic retries because
## repeating it cannot succeed.

signal closed(rejoined: bool)

enum State { IDLE, WAITING, CONNECTING, REJOINING, FAILED }

const RETRY_DELAYS_SEC: Array[float] = [2.0, 4.0, 8.0, 15.0, 30.0]

## Test seams; production values hit the NetManager/SessionStore singletons.
var connect_func := Callable(NetManager, "connect_to_server")
var disconnect_func := Callable(NetManager, "disconnect_from_server")
var rejoin_func := Callable(NetManager, "request_rejoin_room")
var save_session_func := Callable(SessionStore, "save_session")

var _state := State.IDLE
var _session: Dictionary = {}
var _attempt := 0

@onready var _detail: Label = %Detail
@onready var _retry_button: Button = %RetryButton
@onready var _leave_button: Button = %LeaveButton
@onready var _retry_timer: Timer = %RetryTimer


func _ready() -> void:
	NetManager.connected_to_server.connect(_on_connected_to_server)
	NetManager.connection_failed.connect(_on_connection_failed)
	NetManager.joined_room.connect(_on_joined_room)
	NetManager.join_failed.connect(_on_join_failed)
	_retry_timer.timeout.connect(_start_attempt)
	_retry_button.pressed.connect(_on_retry_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)
	set_process(false)


func _process(_delta: float) -> void:
	if _state == State.WAITING:
		_update_detail()


## Session is SessionStore's {address, port, code, token} shape.
func begin(session: Dictionary) -> void:
	_session = session
	_attempt = 0
	visible = true
	set_process(true)
	_start_attempt()


func _start_attempt() -> void:
	_attempt += 1
	_state = State.CONNECTING
	_retry_button.visible = false
	_update_detail()
	# Drop any half-dead peer before dialing again.
	disconnect_func.call()
	if connect_func.call(String(_session.address), int(_session.port)) != OK:
		_on_connection_failed()


func _on_connected_to_server() -> void:
	if _state != State.CONNECTING:
		return
	_state = State.REJOINING
	_update_detail()
	rejoin_func.call(String(_session.code), String(_session.token))


func _on_connection_failed() -> void:
	if _state != State.CONNECTING:
		return
	if _attempt >= RETRY_DELAYS_SEC.size():
		_fail("Could not reconnect after %d attempts." % _attempt)
		return
	_state = State.WAITING
	_retry_button.visible = true
	_retry_timer.start(RETRY_DELAYS_SEC[_attempt - 1])
	_update_detail()


func _on_joined_room(code: String, _slot: int, token: String) -> void:
	if _state == State.IDLE or not visible:
		return
	# The server may reissue the token on rejoin; keep the saved session fresh.
	save_session_func.call(String(_session.address), int(_session.port), code, token)
	_close(true)


func _on_join_failed(reason: int) -> void:
	if _state != State.REJOINING:
		return
	_fail(JoinFailureText.describe(reason))


func _on_retry_pressed() -> void:
	_retry_timer.stop()
	if _state == State.FAILED:
		_attempt = 0
	_start_attempt()


func _on_leave_pressed() -> void:
	_close(false)


func _fail(text: String) -> void:
	_state = State.FAILED
	_retry_timer.stop()
	_retry_button.visible = true
	_detail.text = text


func _close(rejoined: bool) -> void:
	_state = State.IDLE
	_retry_timer.stop()
	visible = false
	set_process(false)
	closed.emit(rejoined)


func _update_detail() -> void:
	match _state:
		State.CONNECTING:
			_detail.text = (
				"Reconnecting... (attempt %d of %d)" % [_attempt, RETRY_DELAYS_SEC.size()]
			)
		State.REJOINING:
			_detail.text = "Rejoining your room..."
		State.WAITING:
			_detail.text = (
				"Retrying in %d s... (attempt %d of %d)"
				% [ceili(_retry_timer.time_left), _attempt, RETRY_DELAYS_SEC.size()]
			)
		_:
			pass
