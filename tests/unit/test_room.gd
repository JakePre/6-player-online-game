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


## #581: the chosen colour replicates in the member dict, defaulting to -1.
func test_member_dict_carries_the_chosen_color_index() -> void:
	var room := _room_with(2)
	assert_eq(room.members[0].to_dict().color_index, -1, "no pick defaults to -1")
	room.members[1].color_index = 5
	assert_eq(room.members[1].to_dict().color_index, 5, "a pick replicates")


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


func _register_test_minigames() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register(MinigameMeta.create({"id": &"game_a"}), MinigameBase)
	MinigameCatalog.register(MinigameMeta.create({"id": &"game_b"}), MinigameBase)


func test_excluded_game_ids_defaults_empty_and_replicates() -> void:
	var room := _room_with(2)
	assert_eq(room.excluded_game_ids, [] as Array[StringName])
	assert_eq(room.to_state_dict().excluded_game_ids, [])


func test_excluded_game_ids_keeps_only_known_ids_deduped() -> void:
	_register_test_minigames()
	var room := _room_with(2)
	assert_true(room.set_excluded_game_ids(["game_a", "bogus", "game_a"]))
	assert_eq(room.excluded_game_ids, [&"game_a"] as Array[StringName])
	assert_eq(room.to_state_dict().excluded_game_ids, [&"game_a"])
	assert_true(room.set_excluded_game_ids([]), "clearing the set is allowed")
	assert_eq(room.excluded_game_ids, [] as Array[StringName])
	MinigameCatalog.clear()


func test_excluded_game_ids_rejects_set_that_leaves_nothing_eligible() -> void:
	_register_test_minigames()
	var room := _room_with(2)
	assert_false(room.set_excluded_game_ids(["game_a", "game_b"]))
	assert_eq(room.excluded_game_ids, [] as Array[StringName], "rejected call leaves set untouched")
	assert_true(room.set_excluded_game_ids(["game_a"]), "excluding only one of two is still fine")
	MinigameCatalog.clear()


## Regression (#816): a solo host (1 connected member) could never exclude any
## game, because no game is eligible at 1 player (min_players >= 2) so every
## exclusion was silently rejected — the client toggle flipped but the server
## never stored it, and the next broadcast (a player joining) reverted it,
## reading as "joining reset the room settings". The guard now floors the
## eligibility check at MIN_PLAYERS_TO_START, the lowest count a match can run.
func test_excluded_game_ids_accepts_while_host_is_alone() -> void:
	_register_test_minigames()
	var room := _room_with(1)
	assert_eq(room.connected_count(), 1)
	assert_true(
		room.set_excluded_game_ids(["game_a"]),
		"a solo host can exclude a game — validated at the 2-player start floor, not count 1"
	)
	assert_eq(room.excluded_game_ids, [&"game_a"] as Array[StringName])
	# The exclusion survives a player joining (the reported symptom).
	room.add_member(200, "Joiner", "jtoken")
	assert_eq(
		room.to_state_dict().excluded_game_ids, [&"game_a"], "the exclusion persists across a join"
	)
	# The starve guard still holds even at the floor: excluding everything fails.
	assert_false(
		room.set_excluded_game_ids(["game_a", "game_b"]), "excluding every game is still rejected"
	)
	assert_eq(
		room.excluded_game_ids, [&"game_a"] as Array[StringName], "the rejected set is untouched"
	)
	MinigameCatalog.clear()


func test_excluded_game_ids_locked_once_match_started() -> void:
	_register_test_minigames()
	var room := _room_with(2)
	room.state = Room.State.IN_MATCH
	assert_false(room.set_excluded_game_ids(["game_a"]))
	assert_eq(room.excluded_game_ids, [] as Array[StringName])
	MinigameCatalog.clear()


# --- Debug "play all games" toggle (#812) ------------------------------------


func test_debug_all_games_toggle_defaults_off_replicates_and_is_lobby_only() -> void:
	var room := _room_with(2)
	assert_false(room.debug_all_games, "off by default")
	assert_false(room.to_state_dict().debug_all_games, "off in the broadcast")
	assert_true(room.set_debug_all_games(true), "the host can turn it on in the lobby")
	assert_true(room.to_state_dict().debug_all_games, "the toggle rides the room state")
	assert_true(room.set_debug_all_games(false), "and back off")
	assert_false(room.debug_all_games)
	# Locked once the match is under way, like every other lobby setting.
	room.state = Room.State.IN_MATCH
	assert_false(room.set_debug_all_games(true), "rejected mid-match")
	assert_false(room.debug_all_games)


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


func test_find_by_slot() -> void:
	var room := Room.new()
	var alice := room.add_member(100, "Alice", "t1")
	room.add_member(200, "Bob", "t2")
	assert_eq(room.find_by_slot(alice.slot), alice)
	assert_null(room.find_by_slot(99), "unknown slot")


# --- Practice bots (#577) ---


func test_add_bot_takes_a_real_slot_and_auto_readies() -> void:
	var room := _room_with(1)
	var bot := room.add_bot()
	assert_not_null(bot)
	assert_true(bot.is_bot)
	assert_true(bot.ready, "bots never block can_start")
	assert_true(bot.connected)
	assert_eq(bot.peer_id, 0, "no backing peer")
	assert_eq(bot.slot, 1, "lowest free slot")
	assert_string_contains(bot.display_name, "Bot")
	assert_eq(room.bot_count(), 1)


func test_bots_count_toward_full_and_can_start() -> void:
	var room := _room_with(1)  # one human host
	assert_false(room.can_start(), "a lone unready human cannot start")
	room.members[0].ready = true
	room.add_bot()
	assert_true(room.can_start(), "host + a ready bot reaches MIN_PLAYERS")


func test_bot_is_never_host() -> void:
	var room := Room.new()
	room.code = "TESTAA"
	var human := room.add_member(100, "Alice", "t1")
	var bot := room.add_bot()
	assert_eq(room.host(), human)
	# Even if the only real member disconnects, a bot does not inherit host.
	human.connected = false
	assert_null(room.host(), "no human left → no host, never the bot")
	assert_false(bot.is_bot == false)


func test_remove_last_bot_removes_the_newest_bot_only() -> void:
	var room := _room_with(1)
	var bot_a := room.add_bot()
	var bot_b := room.add_bot()
	var removed := room.remove_last_bot()
	assert_eq(removed, bot_b, "the newest bot goes first")
	assert_eq(room.bot_count(), 1)
	assert_true(room.members.has(bot_a), "the older bot stays")
	assert_true(room.members.has(room.members[0]), "the human stays")


func test_remove_last_bot_is_null_when_no_bots() -> void:
	var room := _room_with(2)
	assert_null(room.remove_last_bot())


func test_add_bot_refused_when_full_or_mid_match() -> void:
	var room := _room_with(1)
	room.state = Room.State.IN_MATCH
	assert_null(room.add_bot(), "no adding bots mid-match")
	room.state = Room.State.LOBBY
	while not room.is_full():
		room.add_bot()
	assert_null(room.add_bot(), "no adding past the cap")
	assert_eq(room.members.size(), NetConfig.MAX_PLAYERS_PER_ROOM)


func test_bot_flag_replicates_in_state_dict() -> void:
	var room := _room_with(1)
	room.add_bot()
	var dicts: Array = room.to_state_dict().members
	assert_true(dicts[0].is_bot == false, "the human is not a bot")
	assert_true(dicts[1].is_bot, "the bot flag rides the snapshot")
