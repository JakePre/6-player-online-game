extends GutTest
## Reconnect overlay behaviour (M6-03): drive it with stubbed network calls
## and the same NetManager signals the live client receives.

const SESSION := {"address": "127.0.0.1", "port": 7777, "code": "ABCDEF", "token": "tok-1"}

var overlay: Control
var connect_calls: Array = []
var rejoin_calls: Array = []
var saved_sessions: Array = []
var connect_result: int = OK


func before_each() -> void:
	connect_calls = []
	rejoin_calls = []
	saved_sessions = []
	connect_result = OK
	overlay = (load("res://src/client/reconnect_overlay.tscn") as PackedScene).instantiate()
	add_child_autofree(overlay)
	overlay.connect_func = func(address: String, port: int) -> int:
		connect_calls.append([address, port])
		return connect_result
	overlay.disconnect_func = func() -> void: pass
	overlay.rejoin_func = func(code: String, token: String) -> void:
		rejoin_calls.append([code, token])
	overlay.save_session_func = func(
		address: String, port: int, code: String, token: String
	) -> void:
		saved_sessions.append([address, port, code, token])
	watch_signals(overlay)


func test_hidden_and_inert_until_begun() -> void:
	assert_false(overlay.visible)
	NetManager.connected_to_server.emit()
	NetManager.joined_room.emit("ABCDEF", 2, "tok-2")
	assert_eq(rejoin_calls.size(), 0)
	assert_eq(saved_sessions.size(), 0)
	assert_false(overlay.visible)


func test_begin_shows_and_dials_the_saved_server() -> void:
	overlay.begin(SESSION)
	assert_true(overlay.visible)
	assert_eq(connect_calls, [["127.0.0.1", 7777]])


func test_rejoin_requested_once_connected() -> void:
	overlay.begin(SESSION)
	NetManager.connected_to_server.emit()
	assert_eq(rejoin_calls, [["ABCDEF", "tok-1"]])


func test_successful_rejoin_saves_new_token_and_closes() -> void:
	overlay.begin(SESSION)
	NetManager.connected_to_server.emit()
	NetManager.joined_room.emit("ABCDEF", 2, "tok-2")
	assert_eq(saved_sessions, [["127.0.0.1", 7777, "ABCDEF", "tok-2"]])
	assert_false(overlay.visible)
	assert_signal_emitted_with_parameters(overlay, "closed", [true])


func test_failed_connection_schedules_a_retry() -> void:
	overlay.begin(SESSION)
	NetManager.connection_failed.emit()
	assert_true(overlay.visible)
	assert_false(overlay.get_node("%RetryTimer").is_stopped())
	assert_true(overlay.get_node("%RetryButton").visible)


func test_retry_timer_dials_again() -> void:
	overlay.begin(SESSION)
	NetManager.connection_failed.emit()
	overlay.get_node("%RetryTimer").timeout.emit()
	assert_eq(connect_calls.size(), 2)


func test_gives_up_after_exhausting_retries() -> void:
	overlay.begin(SESSION)
	var max_attempts: int = overlay.RETRY_DELAYS_SEC.size()
	for i in range(max_attempts - 1):
		NetManager.connection_failed.emit()
		overlay.get_node("%RetryTimer").timeout.emit()
	NetManager.connection_failed.emit()
	assert_eq(connect_calls.size(), max_attempts)
	assert_true(overlay.get_node("%RetryTimer").is_stopped())
	assert_string_contains(overlay.get_node("%Detail").text, "Could not reconnect")
	assert_true(overlay.visible)


func test_manual_retry_after_giving_up_starts_over() -> void:
	overlay.begin(SESSION)
	for i in range(overlay.RETRY_DELAYS_SEC.size() - 1):
		NetManager.connection_failed.emit()
		overlay.get_node("%RetryTimer").timeout.emit()
	NetManager.connection_failed.emit()
	connect_calls.clear()
	overlay.get_node("%RetryButton").pressed.emit()
	assert_eq(connect_calls.size(), 1)
	NetManager.connection_failed.emit()
	# A fresh cycle waits again instead of instantly giving up.
	assert_false(overlay.get_node("%RetryTimer").is_stopped())


## M16-10: giving up reads as an error (DANGER); a fresh attempt clears it back
## to the theme's default DimLabel color.
func test_giving_up_colors_the_detail_as_an_error() -> void:
	overlay.begin(SESSION)
	for i in range(overlay.RETRY_DELAYS_SEC.size() - 1):
		NetManager.connection_failed.emit()
		overlay.get_node("%RetryTimer").timeout.emit()
	NetManager.connection_failed.emit()
	var detail: Label = overlay.get_node("%Detail")
	assert_eq(detail.get_theme_color(&"font_color"), PartyTheme.DANGER)
	overlay.get_node("%RetryButton").pressed.emit()
	assert_false(
		detail.has_theme_color_override(&"font_color"), "a new attempt clears the error tint"
	)


func test_refused_rejoin_is_terminal() -> void:
	overlay.begin(SESSION)
	NetManager.connected_to_server.emit()
	NetManager.join_failed.emit(NetConfig.JoinResult.NOT_FOUND)
	assert_true(overlay.get_node("%RetryTimer").is_stopped())
	assert_eq(
		overlay.get_node("%Detail").text, JoinFailureText.describe(NetConfig.JoinResult.NOT_FOUND)
	)
	assert_true(overlay.visible)


func test_leave_button_closes_without_rejoin() -> void:
	overlay.begin(SESSION)
	overlay.get_node("%LeaveButton").pressed.emit()
	assert_false(overlay.visible)
	assert_signal_emitted_with_parameters(overlay, "closed", [false])
