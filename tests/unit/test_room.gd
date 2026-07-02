extends GutTest


func _room_with(count: int) -> Room:
	var room := Room.new()
	room.code = "TESTAA"
	for i in count:
		room.add_member(100 + i, "P%d" % i, "token%d" % i)
	return room


func test_slots_assigned_lowest_first() -> void:
	var room := _room_with(3)
	assert_eq(room.members[0].slot, 0)
	assert_eq(room.members[1].slot, 1)
	assert_eq(room.members[2].slot, 2)


func test_freed_slot_is_reused() -> void:
	var room := _room_with(3)
	room.remove_member(room.members[1])
	var newcomer := room.add_member(200, "New", "tokenN")
	assert_eq(newcomer.slot, 1)


func test_full_room() -> void:
	var room := _room_with(NetConfig.MAX_PLAYERS_PER_ROOM)
	assert_true(room.is_full())


func test_disconnected_member_still_reserves_capacity() -> void:
	var room := _room_with(NetConfig.MAX_PLAYERS_PER_ROOM)
	room.mark_disconnected(room.members[0], 1000)
	assert_true(room.is_full())


func test_host_is_oldest_connected_member() -> void:
	var room := _room_with(3)
	assert_eq(room.host().slot, 0)
	room.mark_disconnected(room.members[0], 1000)
	assert_eq(room.host().slot, 1)


func test_state_dict_never_leaks_session_tokens() -> void:
	var room := _room_with(2)
	var state := room.to_state_dict()
	assert_eq(state.code, "TESTAA")
	assert_eq((state.members as Array).size(), 2)
	for member: Dictionary in state.members:
		assert_false(member.has("session_token"))
		assert_false(member.has("peer_id"))


func test_expiry_clock() -> void:
	var room := _room_with(2)
	room.state = Room.State.IN_MATCH
	assert_false(room.is_expired(999999999), "connected room never expires")
	room.mark_disconnected(room.members[0], 1000)
	assert_false(room.is_expired(999999999), "one member still connected")
	room.mark_disconnected(room.members[1], 2000)
	assert_false(room.is_expired(2000 + NetConfig.ROOM_EXPIRY_MS - 1))
	assert_true(room.is_expired(2000 + NetConfig.ROOM_EXPIRY_MS))
