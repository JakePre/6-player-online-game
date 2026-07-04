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
