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
				# Playlist-mechanics tests end at the podium; the finale flow
				# has its own suite below (#554).
				"finale": false,
			}
		)
	)
	controller.event_emitted.connect(func(event: Dictionary) -> void: events.append(event))
	return controller


## A controller with the finale enabled (#554): playlist rounds, then
## FINALE_SHOP -> FINALE_PLAY -> PODIUM, everything compressed.
func _make_finale_controller(room: Room, rounds := 1) -> MatchController:
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
				"shop_sec": 0.5,
			}
		)
	)
	controller.event_emitted.connect(func(event: Dictionary) -> void: events.append(event))
	return controller


func _run_to_finale_shop(controller: MatchController) -> void:
	controller.start()
	_run_until(
		controller, func() -> bool: return controller.state == MatchController.State.FINALE_SHOP
	)


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


## #572: when no explicit playlist is supplied, the controller must build one
## from the room's host-curated exclusion set — never drafting an excluded
## game even though it is otherwise eligible.
func test_build_playlist_path_honours_room_excluded_game_ids() -> void:
	MinigameCatalog.register(MinigameMeta.create({"id": &"other_game"}), SlotOrderGame)
	var room := _make_room(2)
	assert_true(room.set_excluded_game_ids(["other_game"]))
	var controller := (
		MatchController
		. new(
			room,
			{
				"seed": 7,
				"rounds": 4,
				"intro_sec": 0.1,
				"results_sec": 0.1,
				"leaderboard_sec": 0.1,
				"podium_sec": 0.1,
				"duration_override": 0.1,
				"finale": false,
			}
		)
	)
	for id: StringName in controller.playlist:
		assert_eq(id, &"slot_order", "excluded game must never be drafted")


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
	assert_eq(controller.state, MatchController.State.COUNTDOWN)
	var votes: Array = events.filter(
		func(event: Dictionary) -> bool: return event.type == "skip_votes"
	)
	assert_eq(votes.size(), 3)
	assert_eq(votes[0].votes, 1, "duplicate vote must not double-count")
	assert_eq(votes[-1].votes, 3)
	assert_eq(votes[-1].needed, 3)


## #819: a bot in the room never presses skip — the round should start once
## every HUMAN has, not wait on the bot too.
func test_bot_does_not_block_the_skip_vote() -> void:
	var room := _make_room(2)
	room.add_bot()
	var controller := _make_controller(room, 1)
	controller.start()
	controller.handle_skip(0)
	assert_eq(controller.state, MatchController.State.INTRO)
	controller.handle_skip(1)
	assert_eq(
		controller.state,
		MatchController.State.COUNTDOWN,
		"both humans skipped — the bot never counted"
	)
	var votes: Array = events.filter(
		func(event: Dictionary) -> bool: return event.type == "skip_votes"
	)
	assert_eq(votes[-1].needed, 2, "needed reflects the 2 humans, not the 3rd (bot) slot")


## The match controller hands each round's bot slots to the minigame (#819),
## so a per-game "wait for everyone" gate (Count Quick, The Mole) can skip
## waiting on them the same way.
func test_minigame_setup_receives_the_rooms_bot_slots() -> void:
	var room := _make_room(2)
	room.add_bot()
	var controller := _make_controller(room, 1)
	controller.start()
	controller.handle_skip(0)
	controller.handle_skip(1)
	assert_eq(controller.state, MatchController.State.COUNTDOWN)
	assert_eq(controller.game.bot_slots, [2], "the bot's slot reaches the minigame")


## #819: a disconnected human and a bot in the same room both drop out of
## "needed" — only the remaining connected humans have to skip.
func test_bot_and_disconnected_member_together_do_not_block_the_skip_vote() -> void:
	var room := _make_room(3)
	room.mark_disconnected(room.members[2], 0)
	room.add_bot()
	var controller := _make_controller(room, 1)
	controller.start()
	controller.handle_skip(0)
	assert_eq(controller.state, MatchController.State.INTRO)
	controller.handle_skip(1)
	assert_eq(
		controller.state,
		MatchController.State.COUNTDOWN,
		"the 2 remaining connected humans skipped — the disconnected member and the bot don't count"
	)
	var votes: Array = events.filter(
		func(event: Dictionary) -> bool: return event.type == "skip_votes"
	)
	assert_eq(votes[-1].needed, 2, "needed excludes both the disconnected human and the bot")


func test_skip_from_disconnected_member_is_ignored() -> void:
	var room := _make_room(3)
	room.mark_disconnected(room.members[2], 0)
	var controller := _make_controller(room, 1)
	controller.start()
	controller.handle_skip(2)
	assert_eq(controller.state, MatchController.State.INTRO)
	controller.handle_skip(0)
	controller.handle_skip(1)
	assert_eq(controller.state, MatchController.State.COUNTDOWN, "only connected players count")


func test_skip_votes_reset_each_round() -> void:
	var room := _make_room(2)
	var controller := _make_controller(room, 2)
	controller.start()
	controller.handle_skip(0)
	controller.handle_skip(1)
	assert_eq(controller.state, MatchController.State.COUNTDOWN)
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
	assert_eq(controller.state, MatchController.State.COUNTDOWN)
	var event_count := events.size()
	controller.handle_skip(0)
	assert_eq(events.size(), event_count, "skips outside the intro emit nothing")


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


## #182: the 3-2-1 countdown sits between intro and play — the game is
## already set up (snapshots show starting positions) but neither ticks nor
## accepts input until PLAY.
func test_countdown_shows_the_arena_but_blocks_play() -> void:
	var room := _make_room(2)
	var controller := _make_controller(room, 1)
	controller.start()
	controller.handle_skip(0)
	controller.handle_skip(1)
	assert_eq(controller.state, MatchController.State.COUNTDOWN)
	assert_true(events.any(func(event: Dictionary) -> bool: return event.type == "round_countdown"))
	var snapshot := controller.get_snapshot()
	assert_true(snapshot.has("minigame"), "countdown snapshots carry the arena")
	assert_true(snapshot.has("game"))
	assert_between(
		float(snapshot.time_left),
		0.0,
		MatchController.COUNTDOWN_STEP_SEC * MatchController.COUNTDOWN_STEPS
	)
	var before: float = controller.game.elapsed
	controller.handle_input(0, {"mx": 1.0})
	controller.tick(0.1)
	assert_eq(controller.game.elapsed, before, "the sim must not advance during countdown")
	_run_until(controller, func() -> bool: return controller.state == MatchController.State.PLAY)
	assert_true(events.any(func(event: Dictionary) -> bool: return event.type == "round_started"))


## #369: the playtest harness compresses every phase to finish a full match in
## seconds; the countdown gate needs its own debug knob or a 12-round match
## overruns the bot's phase timeout.
func test_countdown_step_sec_debug_override_compresses_the_gate() -> void:
	var room := _make_room(2)
	var controller := MatchController.new(
		room, {"seed": 7, "playlist": [&"slot_order"], "countdown_step_sec": 0.05}
	)
	controller.event_emitted.connect(func(event: Dictionary) -> void: events.append(event))
	controller.start()
	controller.handle_skip(0)
	controller.handle_skip(1)
	assert_eq(controller.state, MatchController.State.COUNTDOWN)
	assert_between(
		float(controller.get_snapshot().time_left), 0.0, 0.05 * MatchController.COUNTDOWN_STEPS
	)


# --- Finale flow (SPEC $6, #554) ----------------------------------------------


func test_playlist_exhausted_enters_finale_shop() -> void:
	var room := _make_room(2)
	var controller := _make_finale_controller(room)
	_run_to_finale_shop(controller)
	var types := _event_types()
	assert_has(types, "finale_shop")
	assert_does_not_have(types, "match_ended", "the finale must precede the podium")
	var snapshot := controller.get_snapshot()
	assert_true(snapshot.has("shop"), "shop state replicates")
	assert_between(float(snapshot.time_left), 0.0, 0.5)


func test_shop_purchases_flow_through_match_input() -> void:
	# SlotOrderGame awards 30/20/15 per round: two rounds -> 60/40/30 coins.
	var room := _make_room(3)
	var controller := _make_finale_controller(room, 2)
	_run_to_finale_shop(controller)
	controller.handle_input(0, {"shop": {"action": "buy", "item": "shield"}})
	controller.handle_input(0, {"shop": {"action": "buy", "item": "nonsense"}})
	controller.handle_input(2, {"shop": {"action": "buy", "item": "shield"}})  # 30c < 40c
	var players: Dictionary = controller.get_snapshot().shop.players
	assert_eq(int(players[0].coins), 20, "shield costs 40 of the 60 earned")
	assert_eq(int(players[0]["items"].get(&"shield", 0)), 1)
	assert_eq(int(players[2].coins), 30, "an unaffordable buy is refused")
	assert_true(players[2]["items"].is_empty())


func test_all_confirmed_closes_shop_early_and_applies_loadouts() -> void:
	# Four rounds of 30 first-place coins buy slot 0 the 100c extra life.
	var room := _make_room(2)
	var controller := _make_finale_controller(room, 4)
	_run_to_finale_shop(controller)
	controller.handle_input(0, {"shop": {"action": "buy", "item": "extra_life"}})
	controller.handle_input(0, {"shop": {"action": "confirm"}})
	controller.handle_input(1, {"shop": {"action": "confirm"}})
	controller.tick(TICK)
	assert_eq(controller.state, MatchController.State.FINALE_PLAY, "all confirmed -> early close")
	assert_has(_event_types(), "finale_started")
	var gauntlet := controller.game as Gauntlet
	assert_not_null(gauntlet, "the finale runs The Gauntlet directly")
	assert_eq(int(gauntlet.lives[0]), 2, "the bought extra life landed")
	assert_eq(int(gauntlet.lives[1]), 1)
	var snapshot := controller.get_snapshot()
	assert_eq(String(snapshot.minigame), "gauntlet", "late arrivals can mount the finale view")
	assert_true(snapshot.has("game"))


func test_finale_placement_orders_match_ended_standings() -> void:
	# One round awards 30/20/15 — distinct coins, so FinaleRanking's tiebreaks
	# are deterministic when the compressed gauntlet times out with everyone
	# alive and tied on lives.
	var room := _make_room(3)
	var controller := _make_finale_controller(room)
	_run_to_finale_shop(controller)
	_run_until(controller, func() -> bool: return controller.state == MatchController.State.PODIUM)
	var ended: Dictionary = events[-1]
	assert_eq(String(ended.type), "match_ended")
	var standings: Array = ended.standings
	assert_eq(standings.size(), 3)
	for row: Dictionary in standings:
		assert_true(row.has("placement"), "finale standings carry explicit placements")
	# Timeout with everyone alive on equal lives: leftover coins break the tie.
	assert_eq(int(standings[0].slot), 0, "most leftover coins ranks first")
	assert_eq(int(standings[1].slot), 1)
	assert_eq(int(standings[2].slot), 2)
	assert_eq(int(standings[0].placement), 1)
	assert_eq(int(standings[1].placement), 2)
	assert_eq(int(standings[2].placement), 3)


func test_disconnected_member_ranks_below_finale_participants() -> void:
	var room := _make_room(3)
	room.members[2].score = 999
	room.members[2].connected = false
	var controller := _make_finale_controller(room)
	_run_to_finale_shop(controller)
	_run_until(controller, func() -> bool: return controller.state == MatchController.State.PODIUM)
	var standings: Array = events[-1].standings
	assert_eq(standings.size(), 3, "absentees still appear in the standings")
	assert_eq(int(standings[-1].slot), 2, "a no-show ranks below every participant")
	assert_eq(int(standings[-1].placement), 3)


func test_solo_room_skips_finale_to_podium() -> void:
	var room := _make_room(1)
	var controller := _make_finale_controller(room)
	controller.start()
	_run_until(controller, func() -> bool: return controller.state == MatchController.State.PODIUM)
	var types := _event_types()
	assert_does_not_have(types, "finale_shop", "a solo debug session keeps the old flow")
	assert_has(types, "match_ended")


func test_shop_times_out_into_finale_play() -> void:
	var room := _make_room(2)
	var controller := _make_finale_controller(room)
	_run_to_finale_shop(controller)
	_run_until(
		controller, func() -> bool: return controller.state == MatchController.State.FINALE_PLAY
	)
	assert_has(_event_types(), "finale_started", "an idle shop closes on its own clock")


func test_finale_ignores_input_from_non_participants() -> void:
	var room := _make_room(2)
	var controller := _make_finale_controller(room)
	_run_to_finale_shop(controller)
	controller.handle_input(99, {"shop": {"action": "confirm"}})
	var players: Dictionary = controller.get_snapshot().shop.players
	assert_false(bool(players.get(99, {}).get("confirmed", false)))
	assert_eq(players.size(), 2)


# --- Debug run: every game once, in order (#812) -----------------------------


## With debug_all_games on and no explicit playlist, the controller drafts the
## whole eligible roster in catalog order rather than a random round_count draw.
func test_debug_all_games_plays_the_whole_eligible_roster_in_order() -> void:
	# The real roster (before_each's lone stub can't prove "every game"). clear()
	# first so register_builtins' is-empty guard actually repopulates.
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	var room := _make_room(4)
	room.debug_all_games = true
	var controller: MatchController = MatchController.new(room, {"seed": 7, "finale": false})
	var expected: Array = MinigameCatalog.eligible_ids(4, [])
	assert_eq(controller.playlist, expected, "the debug run is eligible_ids in catalog order")
	assert_gt(controller.playlist.size(), 1, "the whole roster, not a single game")
	var seen := {}
	for id: StringName in controller.playlist:
		assert_false(seen.has(id), "%s is played exactly once" % id)
		seen[id] = true


## The debug run is a full audit, so the host's exclusion set does not apply —
## an "excluded" game is still reached.
func test_debug_all_games_ignores_host_exclusions() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	var room := _make_room(4)
	room.debug_all_games = true
	var victim: StringName = MinigameCatalog.eligible_ids(4, [])[0]
	room.excluded_game_ids = [victim] as Array[StringName]
	var controller: MatchController = MatchController.new(room, {"seed": 7, "finale": false})
	assert_true(victim in controller.playlist, "the 'excluded' game is still in the debug run")


## No mutator ever rolls during a debug run, even with the whole pool enabled.
func test_debug_run_never_rolls_a_mutator() -> void:
	MutatorCatalog.register_builtins()
	var room := _make_room(4)
	room.debug_all_games = true
	assert_true(room.set_mutator_pool(MutatorCatalog.registered_ids()), "enable every mutator")
	var controller: MatchController = MatchController.new(room, {"seed": 7, "finale": false})
	for _i in 50:
		assert_null(controller._roll_mutator(), "the debug audit is never perturbed by a mutator")
