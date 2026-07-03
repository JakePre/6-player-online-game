extends GutTest
## Match state machine (SPEC $4): INTRO -> PLAY -> RESULTS -> (LEADERBOARD
## every 5 rounds) -> PODIUM, coin awards on RoomMember.score, rejoiners
## sitting out the round in progress.

const TICK := 1.0 / 30.0
const MAX_TICKS := 10_000


## Ranks players by slot ascending (slot 0 first, no ties) so awards are
## predictable; ends only by timeout (duration_override keeps rounds short).
class SlotOrderGame:
	extends MinigameBase

	var inputs := []

	func _handle_input(slot: int, data: Dictionary) -> void:
		inputs.append([slot, data])

	func _rank_players() -> Array:
		var ordered := slots.duplicate()
		ordered.sort()
		var placements: Array = []
		for slot: int in ordered:
			placements.append([slot])
		return placements


var events: Array = []


func before_each() -> void:
	MinigameCatalog.clear()
	var meta := MinigameMeta.create({"id": &"slot_order", "duration_sec": 60.0})
	MinigameCatalog.register(meta, SlotOrderGame)
	events = []


func after_all() -> void:
	MinigameCatalog.clear()


func _make_room(player_count: int) -> Room:
	var room := Room.new()
	room.code = "TEST42"
	for i in player_count:
		room.add_member(100 + i, "P%d" % i, "token%d" % i)
	return room


func _make_controller(room: Room, rounds: int) -> MatchController:
	var playlist: Array = []
	for _i in rounds:
		playlist.append(&"slot_order")
	var controller := (
		MatchController
		. new(
			room,
			{
				"seed": 7,
				"playlist": playlist,
				"intro_sec": 0.1,
				"results_sec": 0.1,
				"leaderboard_sec": 0.1,
				"podium_sec": 0.1,
				"duration_override": 0.1,
			}
		)
	)
	controller.event_emitted.connect(func(event: Dictionary) -> void: events.append(event))
	return controller


func _run_until(controller: MatchController, predicate: Callable) -> void:
	for _i in MAX_TICKS:
		if predicate.call():
			return
		controller.tick(TICK)
	fail_test("controller never reached the expected state")


func _event_types() -> Array:
	return events.map(func(event: Dictionary) -> String: return event.type)


## Regression: config.get("playlist", MinigameCatalog.build_playlist(...))
## would evaluate build_playlist eagerly even when "playlist" is supplied
## (GDScript doesn't lazily evaluate Dictionary.get defaults), and every
## registered minigame requires >=2 players, so a solo debug session (see
## debug_launcher.gd) would hit build_playlist's eligibility assert despite
## never needing it to run at all.
func test_explicit_playlist_skips_build_playlist_for_a_single_player() -> void:
	var room := _make_room(1)
	var controller := _make_controller(room, 1)
	controller.start()
	assert_eq(controller.state, MatchController.State.INTRO)
	assert_eq(events[1].minigame.id, "slot_order")


func test_start_resets_scores_and_enters_intro() -> void:
	var room := _make_room(3)
	room.members[0].score = 99
	var controller := _make_controller(room, 2)
	controller.start()
	assert_eq(room.state, Room.State.IN_MATCH)
	assert_eq(room.members[0].score, 0)
	assert_eq(controller.state, MatchController.State.INTRO)
	assert_eq(_event_types(), ["match_started", "round_intro"])
	assert_eq(events[1].minigame.id, "slot_order")


func test_full_match_reaches_done_and_returns_room_to_lobby() -> void:
	var room := _make_room(2)
	var controller := _make_controller(room, 2)
	controller.start()
	_run_until(controller, func() -> bool: return controller.is_done())
	assert_eq(room.state, Room.State.LOBBY)
	var types := _event_types()
	assert_eq(types.count("round_intro"), 2)
	assert_eq(types.count("round_results"), 2)
	assert_eq(types.count("match_ended"), 1)


func test_awards_accumulate_on_member_scores() -> void:
	var room := _make_room(3)
	var controller := _make_controller(room, 2)
	controller.start()
	_run_until(controller, func() -> bool: return controller.is_done())
	# SlotOrderGame always ranks slot 0/1/2 -> 30/20/15 per round, two rounds.
	assert_eq(room.members[0].score, 60)
	assert_eq(room.members[1].score, 40)
	assert_eq(room.members[2].score, 30)


func test_match_ended_standings_sorted_by_score() -> void:
	var room := _make_room(3)
	var controller := _make_controller(room, 1)
	controller.start()
	_run_until(controller, func() -> bool: return controller.is_done())
	var ended: Dictionary = events[_event_types().find("match_ended")]
	var slots: Array = ended.standings.map(func(row: Dictionary) -> int: return row.slot)
	assert_eq(slots, [0, 1, 2])


func test_leaderboard_every_five_rounds_but_not_at_match_end() -> void:
	var room := _make_room(2)
	var controller := _make_controller(room, 10)
	controller.start()
	_run_until(controller, func() -> bool: return controller.is_done())
	var types := _event_types()
	# After round 5 only; round 10 goes straight to the podium.
	assert_eq(types.count("leaderboard"), 1)
	var leaderboard_at := types.find("leaderboard")
	assert_eq(types[leaderboard_at - 1], "round_results")
	assert_eq(types.slice(0, leaderboard_at).count("round_results"), 5)


func test_input_routed_only_during_play() -> void:
	var room := _make_room(2)
	var controller := _make_controller(room, 1)
	controller.start()
	controller.handle_input(0, {"mx": 1.0})  # Still in INTRO: dropped.
	_run_until(controller, func() -> bool: return controller.state == MatchController.State.PLAY)
	var game := controller.game as SlotOrderGame
	controller.handle_input(0, {"mx": 1.0})
	assert_eq(game.inputs, [[0, {"mx": 1.0}]])


func test_disconnected_member_sits_out_round() -> void:
	var room := _make_room(3)
	var member := room.members[2]
	room.mark_disconnected(member, 0)
	var controller := _make_controller(room, 1)
	controller.start()
	_run_until(controller, func() -> bool: return controller.state == MatchController.State.PLAY)
	controller.handle_input(member.slot, {"mx": 1.0})
	var game := controller.game as SlotOrderGame
	assert_eq(game.slots, [0, 1])
	assert_eq(game.inputs.size(), 0)
	_run_until(controller, func() -> bool: return controller.is_done())
	# Absent players earn nothing but keep their slot and score.
	assert_eq(member.score, 0)
	assert_eq(room.members.size(), 3)


func test_snapshot_shape_per_state() -> void:
	var room := _make_room(2)
	var controller := _make_controller(room, 1)
	controller.start()
	var intro := controller.get_snapshot()
	assert_eq(intro.state, MatchController.State.INTRO)
	assert_false(intro.has("game"))
	_run_until(controller, func() -> bool: return controller.state == MatchController.State.PLAY)
	var play := controller.get_snapshot()
	assert_true(play.has("game"))
	assert_between(float(play.time_left), 0.0, 0.1)


func test_unanimous_skip_starts_the_round_early() -> void:
	var room := _make_room(3)
	var controller := _make_controller(room, 1)
	controller.start()
	controller.handle_skip(0)
	controller.handle_skip(0)  # Duplicate votes count once.
	assert_eq(controller.state, MatchController.State.INTRO)
	controller.handle_skip(1)
	controller.handle_skip(2)
	assert_eq(controller.state, MatchController.State.PLAY)
	var votes: Array = events.filter(
		func(event: Dictionary) -> bool: return event.type == "skip_votes"
	)
	assert_eq(votes.size(), 3)
	assert_eq(votes[0].votes, 1, "duplicate vote must not double-count")
	assert_eq(votes[-1].votes, 3)
	assert_eq(votes[-1].needed, 3)


func test_skip_from_disconnected_member_is_ignored() -> void:
	var room := _make_room(3)
	room.mark_disconnected(room.members[2], 0)
	var controller := _make_controller(room, 1)
	controller.start()
	controller.handle_skip(2)
	assert_eq(controller.state, MatchController.State.INTRO)
	controller.handle_skip(0)
	controller.handle_skip(1)
	assert_eq(controller.state, MatchController.State.PLAY, "only connected players count")


func test_skip_votes_reset_each_round() -> void:
	var room := _make_room(2)
	var controller := _make_controller(room, 2)
	controller.start()
	controller.handle_skip(0)
	controller.handle_skip(1)
	assert_eq(controller.state, MatchController.State.PLAY)
	_run_until(
		controller,
		func() -> bool:
			return controller.round_index == 1 and controller.state == MatchController.State.INTRO
	)
	controller.handle_skip(0)
	assert_eq(controller.state, MatchController.State.INTRO, "one vote of two must not skip")


func test_skip_outside_intro_is_ignored() -> void:
	var room := _make_room(2)
	var controller := _make_controller(room, 1)
	controller.start()
	controller.handle_skip(0)
	controller.handle_skip(1)
	assert_eq(controller.state, MatchController.State.PLAY)
	var event_count := events.size()
	controller.handle_skip(0)
	assert_eq(events.size(), event_count, "skips during play emit nothing")


func test_play_snapshot_carries_minigame_id_for_late_mounts() -> void:
	var room := _make_room(2)
	var controller := _make_controller(room, 1)
	controller.start()
	var intro := controller.get_snapshot()
	assert_false(intro.has("minigame"), "id is only replicated while playing")
	_run_until(controller, func() -> bool: return controller.state == MatchController.State.PLAY)
	var playing := controller.get_snapshot()
	assert_eq(playing.minigame, "slot_order")
	assert_true(playing.has("game"))


## Two fixed teams (evens vs odds, evens win) with team_mode set, so results
## must route to Economy.award_for_teams (SPEC $5) instead of the FFA table.
class TeamGame:
	extends MinigameBase

	func _setup() -> void:
		team_mode = true

	func _rank_players() -> Array:
		var evens := slots.filter(func(slot: int) -> bool: return slot % 2 == 0)
		var odds := slots.filter(func(slot: int) -> bool: return slot % 2 == 1)
		return [evens, odds]


func test_team_mode_results_award_team_tables() -> void:
	MinigameCatalog.register(MinigameMeta.create({"id": &"team_game"}), TeamGame)
	var room := _make_room(4)
	var controller := (
		MatchController
		. new(
			room,
			{
				"seed": 7,
				"playlist": [&"team_game"],
				"intro_sec": 0.1,
				"results_sec": 0.1,
				"podium_sec": 0.1,
				"duration_override": 0.1,
			}
		)
	)
	controller.event_emitted.connect(func(event: Dictionary) -> void: events.append(event))
	controller.start()
	_run_until(
		controller,
		func() -> bool:
			return events.any(
				func(event: Dictionary) -> bool: return String(event.type) == "round_results"
			)
	)
	var results := {}
	for event: Dictionary in events:
		if String(event.type) == "round_results":
			results = event
			break
	# Winning team members (slots 0/2) get 20 each, losers (1/3) get 5.
	assert_eq(results.awards, {0: 20, 2: 20, 1: 5, 3: 5})


func _register_mutators_and_pool(room: Room, ids: Array) -> void:
	MutatorCatalog.clear()
	for id: StringName in ids:
		MutatorCatalog.register(Mutator.create({"id": id, "name": String(id), "blurb": "b"}))
	assert_true(room.set_mutator_pool(ids))


func test_no_mutator_rolls_without_a_pool() -> void:
	var room := _make_room(2)
	var controller := _make_controller(room, 3)
	controller.start()
	_run_until(controller, func() -> bool: return controller.is_done())
	for event: Dictionary in events:
		if event.type == "round_intro":
			assert_false(event.has("mutator"), "empty pool never mutates")


func test_mutator_rolls_are_seeded_announced_and_never_repeat() -> void:
	var room := _make_room(2)
	_register_mutators_and_pool(room, [&"alpha", &"beta"])
	var controller := _make_controller(room, 30)
	controller.start()
	_run_until(controller, func() -> bool: return controller.is_done())
	var previous_id := ""
	var repeats := 0
	var count := 0
	for event: Dictionary in events:
		if event.type != "round_intro":
			continue
		var id: String = event.get("mutator", {}).get("id", "")
		if not id.is_empty():
			count += 1
			assert_true(id in ["alpha", "beta"], "rolled from the enabled pool")
			if id == previous_id:
				repeats += 1
		previous_id = id
	assert_eq(repeats, 0, "never the same mutator twice in a row")
	assert_between(count, 5, 20, "~40% of 30 rounds with the seeded rng")
	MutatorCatalog.clear()


func test_snapshot_carries_mutator_for_late_arrivals() -> void:
	var room := _make_room(2)
	_register_mutators_and_pool(room, [&"alpha"])
	var controller := _make_controller(room, 1)
	controller.start()
	controller.current_mutator = MutatorCatalog.mutator_of(&"alpha")
	assert_eq(controller.get_snapshot().mutator.id, "alpha")
	_run_until(controller, func() -> bool: return controller.is_done())
	assert_false(controller.get_snapshot().has("mutator"), "no mutator once the match is over")
	MutatorCatalog.clear()


## Times out ranking slot 0 first and hands them 100 raw pickup coins, so cap
## behavior is observable in the awards.
class PickupGame:
	extends SlotOrderGame

	func _rank_players() -> Array:
		_pickup_coins = {0: 100}
		return super()


## Pins the round's mutator directly instead of fishing for the 40% roll.
func _controller_with_mutator(room: Room, id: StringName) -> MatchController:
	MutatorCatalog.clear()
	MutatorCatalog.register_builtins()
	assert_true(room.set_mutator_pool([String(id)]))
	var controller := _make_controller(room, 1)
	controller.start()
	controller.current_mutator = MutatorCatalog.mutator_of(id)
	return controller


func test_pack_a_registers_with_expected_knobs() -> void:
	MutatorCatalog.clear()
	MutatorCatalog.register_builtins()
	MutatorCatalog.register_builtins()
	for id: StringName in [&"double_coins", &"golden_round", &"overdrive", &"short_fuse"]:
		assert_true(MutatorCatalog.is_registered(id), "%s registered" % id)
	assert_eq(MutatorCatalog.mutator_of(&"double_coins").award_multiplier, 2.0)
	assert_eq(MutatorCatalog.mutator_of(&"golden_round").pickup_cap_scale, 2.0)
	assert_eq(MutatorCatalog.mutator_of(&"short_fuse").duration_scale, 0.6)
	assert_eq(MutatorCatalog.mutator_of(&"overdrive").speed_scale, 1.25)
	MutatorCatalog.clear()


func test_double_coins_doubles_round_awards() -> void:
	var room := _make_room(2)
	var controller := _controller_with_mutator(room, &"double_coins")
	_run_until(controller, func() -> bool: return controller.is_done())
	var results := events.filter(func(e: Dictionary) -> bool: return e.type == "round_results")
	assert_eq(results[0].awards, {0: 60, 1: 40}, "30/20 placement awards doubled")
	MutatorCatalog.clear()


func test_golden_round_raises_the_pickup_cap() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register(
		MinigameMeta.create({"id": &"slot_order", "duration_sec": 60.0}), PickupGame
	)
	var room := _make_room(2)
	var controller := _controller_with_mutator(room, &"golden_round")
	_run_until(controller, func() -> bool: return controller.is_done())
	var results := events.filter(func(e: Dictionary) -> bool: return e.type == "round_results")
	assert_eq(results[0].awards[0], 30 + 60, "100 raw pickups capped at the doubled 60")
	MutatorCatalog.clear()


func test_short_fuse_scales_the_round_duration() -> void:
	var room := _make_room(2)
	var controller := _controller_with_mutator(room, &"short_fuse")
	_run_until(controller, func() -> bool: return controller.state == MatchController.State.PLAY)
	assert_almost_eq(controller.game.duration_override, 0.06, 0.001, "0.1s override scaled by 0.6")
	MutatorCatalog.clear()


func test_overdrive_scales_the_sim_delta() -> void:
	var room := _make_room(2)
	var controller := _controller_with_mutator(room, &"overdrive")
	_run_until(controller, func() -> bool: return controller.state == MatchController.State.PLAY)
	var before: float = controller.game.elapsed
	controller.tick(TICK)
	assert_almost_eq(controller.game.elapsed - before, TICK * 1.25, 0.0001)
	MutatorCatalog.clear()


func test_pack_b_registers_with_expected_knobs() -> void:
	MutatorCatalog.clear()
	MutatorCatalog.register_builtins()
	assert_eq(MutatorCatalog.registered_ids().size(), 8, "packs A and B both registered")
	assert_eq(
		MutatorCatalog.mutator_of(&"mirror_mode").input_transform, Mutator.InputTransform.MIRROR
	)
	assert_true(MutatorCatalog.mutator_of(&"blackout").view_flags.has(&"blackout"))
	assert_true(MutatorCatalog.mutator_of(&"masquerade").view_flags.has(&"hide_nameplates"))
	assert_eq(MutatorCatalog.mutator_of(&"robin_hood").end_transfer_amount, 10)
	MutatorCatalog.clear()


func test_mirror_mode_flips_move_intent_server_side() -> void:
	var room := _make_room(2)
	var controller := _controller_with_mutator(room, &"mirror_mode")
	_run_until(controller, func() -> bool: return controller.state == MatchController.State.PLAY)
	controller.handle_input(0, {"mx": 1.0, "my": 0.5})
	var game: SlotOrderGame = controller.game
	assert_eq(game.inputs.size(), 1)
	assert_eq(game.inputs[0][1].mx, -1.0, "horizontal intent flipped before the sim sees it")
	assert_eq(game.inputs[0][1].my, 0.5)
	MutatorCatalog.clear()


func test_robin_hood_transfers_coins_in_the_broadcast_totals() -> void:
	var room := _make_room(2)
	var controller := _controller_with_mutator(room, &"robin_hood")
	_run_until(controller, func() -> bool: return controller.is_done())
	var results := events.filter(func(e: Dictionary) -> bool: return e.type == "round_results")
	# Placement awards 30/20, then last place takes 10 from first: 20/30.
	assert_eq(results[0].totals, {0: 20, 1: 30})
	MutatorCatalog.clear()
