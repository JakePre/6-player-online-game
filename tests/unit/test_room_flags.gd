extends GutTest
## Boolean host lobby toggles (#1070) — split from test_room.gd to stay under
## the public-method lint cap: the playtest-mode flag and the generic
## set_lobby_flag dispatch NetManager's single set-flag RPC routes through.


func _room_with(count: int) -> Room:
	var room := Room.new()
	room.code = "TESTAA"
	for i in count:
		room.add_member(100 + i, "P%d" % i, "token%d" % i)
	return room


func test_playtest_mode_toggle_defaults_off_replicates_and_is_lobby_only() -> void:
	var room := _room_with(2)
	assert_false(room.playtest_mode, "off by default")
	assert_false(room.to_state_dict().playtest_mode, "off in the broadcast")
	assert_true(room.set_playtest_mode(true), "the host can turn it on in the lobby")
	assert_true(room.to_state_dict().playtest_mode, "the toggle rides the room state")
	room.state = Room.State.IN_MATCH
	assert_false(room.set_playtest_mode(false), "rejected mid-match")
	assert_true(room.playtest_mode)


## The generic boolean-toggle dispatch (#1070): known flags route to their
## setters, anything else is rejected so a hostile flag name changes nothing.
func test_set_lobby_flag_dispatches_known_flags_and_rejects_unknown() -> void:
	var room := _room_with(2)
	assert_true(room.set_lobby_flag("debug_all_games", true))
	assert_true(room.debug_all_games)
	assert_true(room.set_lobby_flag("playtest_mode", true))
	assert_true(room.playtest_mode)
	assert_false(room.set_lobby_flag("no_such_flag", true), "unknown flag rejected")
	assert_false(room.set_lobby_flag("code", true), "field names that aren't flags rejected")
