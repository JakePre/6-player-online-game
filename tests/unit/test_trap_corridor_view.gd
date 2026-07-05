extends GutTest
## Trap Corridor client view (M4-15): renders replicated snapshots without
## simulating anything locally; remembers only its own trap placements.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/trap_corridor/trap_corridor_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"trap_corridor"),
		"res://src/minigames/trap_corridor/trap_corridor_view.tscn"
	)


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"phase": TrapCorridor.Phase.RUNNING,
				"phase_left": 9.5,
				"trapper": 1,
				"players": {0: [2.0, 0.5]},
				"revealed": [17],
				"caught": [],
				"scores": {0: 3, 1: 2},
				"traps_left": 2,
			}
		)
	)
	assert_eq(view.phase, TrapCorridor.Phase.RUNNING)
	assert_eq(view.trapper, 1)
	assert_eq(view.revealed, [17])
	assert_eq(view.scores, {0: 3, 1: 2})
	view.render({"phase": TrapCorridor.Phase.TRAPPING, "players": {}})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_new_trap_phase_clears_local_trap_memory() -> void:
	view.my_traps = [12, 13]
	view.render({"phase": TrapCorridor.Phase.RUNNING})
	assert_eq(view.my_traps, [12, 13], "kept during the run")
	view.render({"phase": TrapCorridor.Phase.TRAPPING})
	assert_eq(view.my_traps, [], "cleared when the next trapper starts")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.revealed, [])


## M13-26: a trap newly appearing in `revealed` spawns a spring burst; the
## first snapshot seeds silently.
func test_new_reveal_spawns_spring_burst() -> void:
	view.render({"revealed": [17]})
	assert_eq(view._springs.size(), 0, "first sighting seeds silently")
	view.render({"revealed": [17, 22]})
	assert_eq(view._springs.size(), 1, "only the new reveal bursts")
	assert_eq(int(view._springs[0].index), 22)


func test_spring_bursts_expire() -> void:
	view.render({"revealed": []})
	view.render({"revealed": [8]})
	assert_eq(view._springs.size(), 1)
	view._process(view.SPRING_DURATION + 0.05)
	assert_eq(view._springs.size(), 0, "bursts free themselves after their lifetime")


func test_sub_round_reset_allows_same_tile_to_burst_again() -> void:
	view.render({"revealed": []})
	view.render({"revealed": [8]})
	view._springs.clear()
	view.render({"phase": TrapCorridor.Phase.TRAPPING, "revealed": []})
	view.render({"phase": TrapCorridor.Phase.RUNNING, "revealed": [8]})
	assert_eq(view._springs.size(), 1, "a reset revealed list re-arms the diff")


func test_arm_pulse_advances_only_while_trapping_as_trapper() -> void:
	view.render({"phase": TrapCorridor.Phase.TRAPPING, "trapper": 0})
	view.my_traps = [12]
	view._process(0.5)
	assert_gt(view._arm_clock, 0.0, "trapper with armed tiles pulses")
	var clock: float = view._arm_clock
	view.render({"phase": TrapCorridor.Phase.RUNNING, "trapper": 0})
	view._process(0.5)
	assert_eq(view._arm_clock, clock, "no pulse outside the trapping phase")


# --- M12-05: keyboard/gamepad input parity for trap placement ----------------


## Feeds an action event through the view's _unhandled_input, exactly as the
## engine would for a keypress or pad button (parity path — no mouse).
func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	view._unhandled_input(event)


func _trapping_as_local(trapper_slot: int, budget: int) -> void:
	view.phase = TrapCorridor.Phase.TRAPPING
	view.trapper = trapper_slot
	view.traps_left = budget


func test_move_actions_step_the_placement_cursor() -> void:
	_trapping_as_local(0, 6)  # local slot 0 is the trapper
	view._cursor_col = 3
	view._cursor_row = 2
	_press(&"move_left")
	assert_eq(view._cursor_col, 2, "move_left steps one column")
	_press(&"move_up")
	assert_eq(view._cursor_row, 1, "move_up steps one row")
	_press(&"move_right")
	_press(&"move_down")
	assert_eq(view._cursor_col, 3)
	assert_eq(view._cursor_row, 2, "the four directions all drive the cursor")


func test_cursor_never_leaves_the_placeable_tiles() -> void:
	_trapping_as_local(0, 6)
	for _i in 20:
		view._move_cursor(-1, -1)
	assert_eq(view._cursor_col, 1, "start column stays safe")
	assert_eq(view._cursor_row, 0)
	for _i in 20:
		view._move_cursor(1, 1)
	assert_eq(view._cursor_col, TrapCorridor.COLS - 2, "finish column stays safe")
	assert_eq(view._cursor_row, TrapCorridor.ROWS - 1)


func test_action_primary_arms_the_cursor_tile() -> void:
	_trapping_as_local(0, 2)
	view._cursor_col = 4
	view._cursor_row = 0
	_press(&"action_primary")
	assert_true(4 * TrapCorridor.ROWS + 0 in view.my_traps, "the cursor arms its tile, mouse-free")


func test_placement_respects_the_trap_budget() -> void:
	_trapping_as_local(0, 0)  # no traps left
	view._place_trap(2, 1)
	assert_eq(view.my_traps, [], "an empty budget arms nothing")


func test_only_the_trapper_drives_the_cursor() -> void:
	_trapping_as_local(1, 2)  # local slot 0 is NOT the trapper
	var col_before: int = view._cursor_col
	_press(&"move_right")
	_press(&"action_primary")
	assert_eq(view._cursor_col, col_before, "a non-trapper cannot move the cursor")
	assert_eq(view.my_traps, [], "a non-trapper arms nothing")
