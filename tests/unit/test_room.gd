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


func _ready_all(room: Room) -> void:
	for member in room.members:
		member.ready = true


func test_round_count_defaults_to_standard() -> void:
	var room := _room_with(2)
	assert_eq(room.round_count, NetConfig.DEFAULT_ROUND_COUNT)


func test_round_count_accepts_only_presets() -> void:
	var room := _room_with(2)
	for count in NetConfig.ROUND_COUNT_OPTIONS:
		assert_true(room.set_round_count(count), "preset %d accepted" % count)
		assert_eq(room.round_count, count)
	assert_false(room.set_round_count(9))
	assert_eq(room.round_count, 15, "invalid value leaves setting untouched")


func test_round_count_locked_once_match_started() -> void:
	var room := _room_with(2)
	room.state = Room.State.IN_MATCH
	assert_false(room.set_round_count(8))


func _register_test_mutators() -> void:
	MutatorCatalog.clear()
	MutatorCatalog.register(Mutator.create({"id": &"double", "name": "Double Coins"}))
	MutatorCatalog.register(Mutator.create({"id": &"blackout", "name": "Blackout"}))


func test_mutator_pool_defaults_empty_and_replicates() -> void:
	var room := _room_with(2)
	assert_eq(room.mutator_pool, [] as Array[StringName])
	assert_eq(room.to_state_dict().mutator_pool, [])


func test_mutator_pool_keeps_only_known_ids_deduped() -> void:
	_register_test_mutators()
	var room := _room_with(2)
	assert_true(room.set_mutator_pool(["double", "bogus", "double", "blackout"]))
	assert_eq(room.mutator_pool, [&"double", &"blackout"] as Array[StringName])
	assert_eq(room.to_state_dict().mutator_pool, [&"double", &"blackout"])
	assert_true(room.set_mutator_pool([]), "clearing the pool is allowed")
	assert_eq(room.mutator_pool, [] as Array[StringName])
	MutatorCatalog.clear()


func test_mutator_pool_locked_once_match_started() -> void:
	_register_test_mutators()
	var room := _room_with(2)
	room.state = Room.State.IN_MATCH
	assert_false(room.set_mutator_pool(["double"]))
	assert_eq(room.mutator_pool, [] as Array[StringName])
	MutatorCatalog.clear()


func test_cannot_start_alone() -> void:
	var room := _room_with(1)
	_ready_all(room)
	assert_false(room.can_start())


func test_cannot_start_until_everyone_ready() -> void:
	var room := _room_with(3)
	room.members[0].ready = true
	room.members[1].ready = true
	assert_false(room.can_start())
	room.members[2].ready = true
	assert_true(room.can_start())


func test_disconnected_member_does_not_block_start() -> void:
	var room := _room_with(3)
	_ready_all(room)
	room.members[2].ready = false
	room.mark_disconnected(room.members[2], 1000)
	assert_true(room.can_start())


func test_cannot_start_twice() -> void:
	var room := _room_with(2)
	_ready_all(room)
	assert_true(room.start_match())
	assert_eq(room.state, Room.State.IN_MATCH)
	assert_false(room.can_start())
	assert_false(room.start_match())


func test_start_consumes_ready_flags() -> void:
	var room := _room_with(2)
	_ready_all(room)
	assert_true(room.start_match())
	for member in room.members:
		assert_false(member.ready)


func test_force_start_bypasses_player_count_and_ready_gate() -> void:
	var room := _room_with(1)
	assert_false(room.can_start(), "sanity: a solo room could never normally start")
	assert_true(room.force_start_match())
	assert_eq(room.state, Room.State.IN_MATCH)


func test_force_start_still_consumes_ready_flags() -> void:
	var room := _room_with(1)
	room.members[0].ready = true
	assert_true(room.force_start_match())
	assert_false(room.members[0].ready)


func test_force_start_refuses_a_room_already_in_match() -> void:
	var room := _room_with(1)
	assert_true(room.force_start_match())
	assert_false(room.force_start_match())


func test_state_dict_exposes_ready_and_round_count() -> void:
	var room := _room_with(2)
	room.members[0].ready = true
	var state := room.to_state_dict()
	assert_eq(state.round_count, NetConfig.DEFAULT_ROUND_COUNT)
	assert_true(state.members[0].ready)
	assert_false(state.members[1].ready)


func test_member_defaults_to_roster_default_character() -> void:
	var room := _room_with(1)
	assert_eq(room.members[0].character_id, CharacterRoster.DEFAULT_ID)


func test_state_dict_exposes_character_id() -> void:
	var room := _room_with(2)
	room.members[0].character_id = &"mage"
	var state := room.to_state_dict()
	assert_eq(state.members[0].character_id, &"mage")
	assert_eq(state.members[1].character_id, CharacterRoster.DEFAULT_ID)


func test_duplicate_character_picks_allowed() -> void:
	var room := _room_with(2)
	room.members[0].character_id = &"knight"
	room.members[1].character_id = &"knight"
	assert_eq(room.members[0].character_id, room.members[1].character_id)


func test_expiry_clock() -> void:
	var room := _room_with(2)
	room.state = Room.State.IN_MATCH
	assert_false(room.is_expired(999999999), "connected room never expires")
	room.mark_disconnected(room.members[0], 1000)
	assert_false(room.is_expired(999999999), "one member still connected")
	room.mark_disconnected(room.members[1], 2000)
	assert_false(room.is_expired(2000 + NetConfig.ROOM_EXPIRY_MS - 1))
	assert_true(room.is_expired(2000 + NetConfig.ROOM_EXPIRY_MS))
