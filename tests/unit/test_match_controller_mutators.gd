extends GutTest
## Mutator packs A/B (M9-04/M9-05): the seeded roll and never-repeat rule,
## snapshot exposure for late arrivals, and each pack's knob effects (double
## coins, golden round, short fuse, overdrive, mirror mode, robin hood). Split
## from test_match_controller.gd to stay under gdlint's public-method cap
## (same precedent as test_match_controller_finale_only.gd).

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


## Times out ranking slot 0 first and hands them 100 raw pickup coins, so cap
## behavior is observable in the awards.
class PickupGame:
	extends SlotOrderGame

	func _rank_players() -> Array:
		_pickup_coins = {0: 100}
		return super()


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
				"finale": false,
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
