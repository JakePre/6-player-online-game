extends GutTest
## Playtest mode (#1070): the State.PICK flow — a playtest match opens on the
## pick screen, only the host picks (and only real, eligible games), every
## round returns to the picker with the played history, the host ends the
## match on demand, and a humanless room can't wedge there.

const TICK := 1.0 / 30.0
const MAX_TICKS := 10_000


## Ranks by slot ascending; ends by timeout (duration_override keeps it short).
class SlotOrderGame:
	extends MinigameBase

	func _rank_players() -> Array:
		var ordered := slots.duplicate()
		ordered.sort()
		var placements: Array = []
		for slot: int in ordered:
			placements.append([slot])
		return placements


func before_each() -> void:
	MinigameCatalog.clear()
	var meta := MinigameMeta.create({"id": &"slot_order", "duration_sec": 60.0})
	MinigameCatalog.register(meta, SlotOrderGame)


func after_all() -> void:
	MinigameCatalog.clear()


func _make_room(player_count: int) -> Room:
	var room := Room.new()
	room.code = "TEST42"
	for i in player_count:
		room.add_member(100 + i, "P%d" % i, "token%d" % i)
	room.playtest_mode = true
	return room


## No "playlist" key on purpose: playtest mode builds its own empty one and
## grows it pick by pick.
func _make_controller(room: Room) -> MatchController:
	return (
		MatchController
		. new(
			room,
			{
				"seed": 7,
				"intro_sec": 0.1,
				"results_sec": 0.1,
				"podium_sec": 0.1,
				"duration_override": 0.1,
				"finale": false,
			}
		)
	)


func _run_until(controller: MatchController, predicate: Callable) -> void:
	for _i in MAX_TICKS:
		if predicate.call():
			return
		controller.tick(TICK)
	fail_test("controller never reached the expected state")


func test_playtest_match_opens_on_the_pick_screen() -> void:
	var controller := _make_controller(_make_room(2))
	controller.start()
	assert_eq(controller.state, MatchController.State.PICK, "no fixed playlist — pick first")
	var pick: Dictionary = controller.get_snapshot().pick
	assert_has(pick.eligible, "slot_order", "the live eligible catalog rides the snapshot")
	assert_eq(pick.played, [], "nothing played yet")


func test_only_the_host_picks_and_only_real_eligible_games() -> void:
	var controller := _make_controller(_make_room(2))
	controller.start()
	controller.handle_input(1, {"pick": "slot_order"})
	assert_eq(controller.state, MatchController.State.PICK, "a non-host pick changes nothing")
	controller.handle_input(0, {"pick": "no_such_game"})
	assert_eq(controller.state, MatchController.State.PICK, "an unknown id changes nothing")
	controller.handle_input(0, {"pick": "slot_order"})
	assert_eq(controller.state, MatchController.State.INTRO, "the host's pick starts the round")
	assert_eq(controller.playlist, [&"slot_order"], "the pick landed on the playlist")


func test_every_round_returns_to_the_picker_with_history() -> void:
	var controller := _make_controller(_make_room(2))
	controller.start()
	controller.handle_input(0, {"pick": "slot_order"})
	_run_until(controller, func() -> bool: return controller.state == MatchController.State.PICK)
	var pick: Dictionary = controller.get_snapshot().pick
	assert_eq(pick.played, ["slot_order"], "round one is on the history")
	controller.handle_input(0, {"pick": "slot_order"})
	assert_eq(controller.state, MatchController.State.INTRO, "repeat picks are fine")
	assert_eq(controller.round_index, 1, "round two")


func test_host_ends_the_match_from_the_picker() -> void:
	var controller := _make_controller(_make_room(2))
	controller.start()
	controller.handle_input(0, {"pick": "end"})
	assert_eq(controller.state, MatchController.State.PODIUM, "end-on-demand (finale off)")


func test_humanless_pick_screen_cannot_wedge_the_room() -> void:
	var room := _make_room(2)
	var controller := _make_controller(room)
	controller.start()
	for member in room.members:
		member.connected = false
	# With everyone gone no game is eligible either, so the self-pick escape
	# hatch resolves to the podium rather than waiting on a host forever.
	controller.tick(TICK)
	assert_eq(controller.state, MatchController.State.PODIUM, "no humans -> no wedge")


func test_normal_matches_never_visit_the_pick_screen() -> void:
	var room := _make_room(2)
	room.playtest_mode = false
	var controller := (
		MatchController
		. new(
			room,
			{
				"seed": 7,
				"rounds": 1,
				"intro_sec": 0.1,
				"results_sec": 0.1,
				"podium_sec": 0.1,
				"duration_override": 0.1,
				"finale": false,
			}
		)
	)
	controller.start()
	assert_eq(controller.state, MatchController.State.INTRO, "straight to the intro")
	_run_until(controller, func() -> bool: return controller.state == MatchController.State.PODIUM)
	assert_eq(controller.get_snapshot().get("pick", {}), {}, "no pick payload outside PICK")
