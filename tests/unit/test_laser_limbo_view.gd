extends GutTest
## Laser Limbo client view (M10-06): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView


func _player(x: float, y: float, live_count: int, air: int, duck: int) -> Array:
	return [x, y, live_count, air, duck]


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/laser_limbo/laser_limbo_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"laser_limbo"),
		"res://src/minigames/laser_limbo/laser_limbo_view.tscn"
	)


func test_wall_kinds_show_their_segments() -> void:
	(
		view
		. render(
			{
				"players": {},
				"walls":
				[
					[2.0, 1, LaserLimbo.WallKind.LOW, 0.0],
					[-3.0, -1, LaserLimbo.WallKind.HIGH, 0.0],
					[0.0, 1, LaserLimbo.WallKind.GAP, 2.0],
				],
				"fallen": []
			}
		)
	)
	var low_wall: Node3D = view.arena.get_node("Wall0")
	var high_wall: Node3D = view.arena.get_node("Wall1")
	var gap_wall: Node3D = view.arena.get_node("Wall2")
	assert_true(low_wall.visible)
	assert_almost_eq(low_wall.position.x, 2.0, 0.001)
	assert_true(low_wall.get_node("Low").visible)
	assert_false(low_wall.get_node("High").visible)
	assert_true(high_wall.get_node("High").visible)
	assert_true(gap_wall.get_node("GapNear").visible)
	assert_true(gap_wall.get_node("GapFar").visible)
	assert_false(view.arena.get_node("Wall3").visible, "pool beyond snapshot hidden")


func test_jump_and_duck_read_on_the_rig() -> void:
	view.render(
		{"players": {0: _player(0.0, 0.0, 3, 1, 0), 1: _player(1.0, 1.0, 3, 0, 1)}, "walls": []}
	)
	assert_almost_eq(view.rig_for_slot(0).position.y, view.JUMP_HEIGHT, 0.001, "jumper is up")
	assert_almost_eq(view.rig_for_slot(1).scale.y, view.DUCK_SCALE, 0.001, "ducker squashes")
	assert_string_contains(view.rig_for_slot(0).display_name, "+++", "lives ride the nameplate")


func test_losing_a_life_flinches_and_shakes() -> void:
	watch_signals(view)
	view.render({"players": {0: _player(0.0, 0.0, 3, 0, 0)}, "walls": [], "fallen": []})
	assert_signal_not_emitted(view, "shake_requested")
	view.render({"players": {0: _player(0.0, 0.0, 2, 0, 0)}, "walls": [], "fallen": []})
	assert_signal_emitted(view, "shake_requested")
	assert_eq(view.rig_for_slot(0).current_action(), &"hit")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.walls.size(), 0)


## M13-13: beams shimmer across snapshots, hits burst electric.
func test_beams_shimmer_across_snapshots() -> void:
	view.render({"players": {}, "walls": [[0.0, 1, LaserLimbo.WallKind.LOW, 0.0]], "fallen": []})
	var glow_a: float = view._beam_material.emission_energy_multiplier
	view.render({"players": {}, "walls": [[0.5, 1, LaserLimbo.WallKind.LOW, 0.0]], "fallen": []})
	assert_ne(view._beam_material.emission_energy_multiplier, glow_a, "the hum advances")


func test_life_loss_bursts_at_the_player() -> void:
	view.render({"players": {0: _player(0.0, 0.0, 3, 0, 0)}, "walls": [], "fallen": []})
	var before: int = view.arena.get_child_count()
	view.render({"players": {0: _player(0.0, 0.0, 2, 0, 0)}, "walls": [], "fallen": []})
	assert_eq(view.arena.get_child_count(), before + 1, "the laser bite bursts")
