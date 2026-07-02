extends GutTest
## MinigameBase contract behaviour shared by every minigame.

const TICK := 1.0 / 30.0


class RecorderGame:
	extends MinigameBase

	var inputs := []

	func _handle_input(slot: int, data: Dictionary) -> void:
		inputs.append([slot, data])


func _make_game(duration: float) -> RecorderGame:
	var game := RecorderGame.new()
	game.meta = MinigameMeta.create({"id": &"recorder", "duration_sec": duration})
	var slots: Array[int] = [0, 2, 5]
	game.setup(slots, 42)
	return game


func test_times_out_with_everyone_tied() -> void:
	var game := _make_game(0.5)
	while not game.finished:
		game.tick(TICK)
	assert_eq(game.get_results().placements, [[0, 2, 5]])
	assert_between(game.elapsed, 0.5, 0.6)


func test_duration_override_replaces_meta_duration() -> void:
	var game := _make_game(60.0)
	game.duration_override = 0.1
	assert_eq(game.effective_duration(), 0.1)
	game.tick(0.2)
	assert_true(game.finished)


func test_input_from_unknown_slot_is_dropped() -> void:
	var game := _make_game(1.0)
	game.handle_input(3, {"mx": 1.0})
	assert_eq(game.inputs.size(), 0)
	game.handle_input(2, {"mx": 1.0})
	assert_eq(game.inputs, [[2, {"mx": 1.0}]])


func test_input_after_finish_is_dropped() -> void:
	var game := _make_game(1.0)
	game.finish([[0], [2], [5]])
	game.handle_input(0, {"mx": 1.0})
	assert_eq(game.inputs.size(), 0)
	assert_eq(game.get_results().placements, [[0], [2], [5]])


func test_early_finish_stops_the_clock() -> void:
	var game := _make_game(1.0)
	game.finish([[5], [0, 2]])
	var elapsed := game.elapsed
	game.tick(TICK)
	assert_eq(game.elapsed, elapsed)


func test_results_report_team_mode_off_by_default() -> void:
	var game := _make_game(0.5)
	game.finish([[0], [2], [5]])
	assert_false(game.get_results().team_mode)
	game.team_mode = true
	assert_true(game.get_results().team_mode)
