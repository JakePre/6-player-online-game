extends GutTest
## Ro-Sham-Bo Royale client view (M14-05): renders replicated snapshots
## without simulating anything locally.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/ro_sham_bo/ro_sham_bo_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"ro_sham_bo"),
		"res://src/minigames/ro_sham_bo/ro_sham_bo_view.tscn"
	)
	MinigameCatalog.clear()


## Pad geometry is fixed and derived locally (RoShamBo.pad_position) — never
## sent over the wire, so it's placed at setup and needs no snapshot data.
func test_setup_places_three_pads_at_the_sim_geometry() -> void:
	var rock: Node3D = view.arena.get_node("Pad0")
	var expected := view.to_arena(RoShamBo.pad_position(RoShamBo.Shape.ROCK), 0.025)
	assert_eq(rock.name, "Pad0")
	assert_almost_eq(rock.position.x, expected.x, 0.001)
	assert_almost_eq(rock.position.z, expected.z, 0.001)
	assert_eq(view.arena.get_node("Pad2").name, "Pad2")


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"phase": RoShamBo.Phase.THROW,
				"players": {0: [1.0, 2.0, 1, 0], 1: [3.0, -1.0, 1, 1]},
				"eliminated_order": [],
				"sudden_death": false,
				"target_shape": -1,
				"phase_left": 2.5,
			}
		)
	)
	assert_eq(view.players.size(), 2)
	assert_eq(view.phase, RoShamBo.Phase.THROW)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)


func test_locked_player_shows_it_before_reveal() -> void:
	(
		view
		. render(
			{
				"phase": RoShamBo.Phase.THROW,
				"players": {0: [0.0, 0.0, 1, 1], 1: [1.0, 1.0, 1, 0]},
				"eliminated_order": [],
			}
		)
	)
	assert_string_contains(view.rig_for_slot(0).display_name, "LOCKED")
	assert_false("LOCKED" in view.rig_for_slot(1).display_name)


func test_eliminated_player_is_tagged_out_and_hidden() -> void:
	(
		view
		. render(
			{
				"phase": RoShamBo.Phase.REVEAL,
				"players": {0: [0.0, 0.0, 0, 1], 1: [1.0, 1.0, 1, 1]},
				"eliminated_order": [[0]],
				"last_result": {"throws": {0: 0, 1: 1}, "eliminated": [0], "wash": false},
			}
		)
	)
	assert_string_contains(view.rig_for_slot(0).display_name, "OUT")
	assert_false(view.rig_for_slot(0).visible)
	assert_true(view.rig_for_slot(1).visible)


func test_reveal_shows_the_thrown_shape() -> void:
	(
		view
		. render(
			{
				"phase": RoShamBo.Phase.REVEAL,
				"players": {0: [0.0, 0.0, 1, 1], 1: [1.0, 1.0, 1, 1]},
				"eliminated_order": [],
				"last_result": {"throws": {0: 0, 1: 1}, "eliminated": [], "wash": true},
			}
		)
	)
	assert_string_contains(view.rig_for_slot(0).display_name, "ROCK")
	assert_string_contains(view.rig_for_slot(1).display_name, "PAPER")


## M13-style FX seeding: the first elimination group seen fires FX/SFX
## exactly once, not on every subsequent render of the same state.
func test_new_elimination_fires_burst_once() -> void:
	(
		view
		. render(
			{
				"phase": RoShamBo.Phase.REVEAL,
				"players": {0: [0.0, 0.0, 0, 1], 1: [1.0, 1.0, 1, 1]},
				"eliminated_order": [[0]],
				"last_result": {"throws": {0: 0, 1: 1}, "eliminated": [0], "wash": false},
			}
		)
	)
	var before: int = view.arena.get_child_count()
	(
		view
		. render(
			{
				"phase": RoShamBo.Phase.REVEAL,
				"players": {0: [0.0, 0.0, 0, 1], 1: [1.0, 1.0, 1, 1]},
				"eliminated_order": [[0]],
				"last_result": {"throws": {0: 0, 1: 1}, "eliminated": [0], "wash": false},
			}
		)
	)
	assert_eq(
		view.arena.get_child_count(), before, "re-rendering the same result bursts nothing new"
	)
