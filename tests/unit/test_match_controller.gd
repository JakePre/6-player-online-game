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
