extends GutTest
## Laser Limbo client view (M10-06): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

const VIEW_SCENE := preload("res://src/minigames/laser_limbo/laser_limbo_view.tscn")

var view: MinigameView


func _player(x: float, y: float, live_count: int, air: int, duck: int) -> Array:
	return [x, y, live_count, air, duck]


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


## M15: the view derives arena and gap size from the lobby count with the same
## formula the sim uses, so rendered walls/gaps match the scaled play area.
func test_arena_and_gap_scale_with_lobby_size() -> void:
	assert_almost_eq(view._arena_half(), LaserLimbo.ARENA_HALF, 0.001, "2 players = base arena")
	assert_almost_eq(view._gap_half(), LaserLimbo.GAP_HALF_WIDTH, 0.001)
	var big: MinigameView3D = VIEW_SCENE.instantiate()
	add_child_autofree(big)
	var names := {}
	for i in 24:
		names[i] = "P%d" % (i + 1)
	big.setup(names, 0)
	assert_gt(big._arena_half(), LaserLimbo.ARENA_HALF, "24 players get a bigger floor")
	assert_gt(big._gap_half(), LaserLimbo.GAP_HALF_WIDTH, "and a wider rendered gap")


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
	var low_material: StandardMaterial3D = view._beam_materials[LaserLimbo.WallKind.LOW]
	view.render({"players": {}, "walls": [[0.0, 1, LaserLimbo.WallKind.LOW, 0.0]], "fallen": []})
	var glow_a: float = low_material.emission_energy_multiplier
	view.render({"players": {}, "walls": [[0.5, 1, LaserLimbo.WallKind.LOW, 0.0]], "fallen": []})
	assert_ne(low_material.emission_energy_multiplier, glow_a, "the hum advances")


## #779: each wall kind reads in its own color — the core "can't tell high vs
## low" fix — so a LOW (jump) and a HIGH (duck) beam are never the same hue.
func test_wall_kinds_are_color_coded() -> void:
	var low: StandardMaterial3D = view._beam_materials[LaserLimbo.WallKind.LOW]
	var high: StandardMaterial3D = view._beam_materials[LaserLimbo.WallKind.HIGH]
	var gap: StandardMaterial3D = view._beam_materials[LaserLimbo.WallKind.GAP]
	assert_ne(low.albedo_color, high.albedo_color, "jump and duck beams differ in hue")
	assert_ne(low.albedo_color, gap.albedo_color)
	assert_ne(high.albedo_color, gap.albedo_color)


## #779: a floor stripe under each beam carries the kind's color on the ground
## plane, where the iso camera can't foreshorten it away.
func test_beam_has_a_kind_colored_floor_stripe() -> void:
	view.render({"players": {}, "walls": [[1.0, 1, LaserLimbo.WallKind.HIGH, 0.0]], "fallen": []})
	var stripe: MeshInstance3D = view.arena.get_node("Wall0/FloorStripe")
	assert_almost_eq(
		stripe.position.y, view.FLOOR_STRIPE_THICKNESS / 2.0, 0.01, "flat on the floor"
	)
	assert_eq(
		(stripe.mesh as BoxMesh).material,
		view._beam_materials[LaserLimbo.WallKind.HIGH],
		"stripe wears the beam's kind color"
	)


## #928: a beam gets full-height emitter posts at both depth ends — the vertical
## ruler the eye reads its attach height against.
func test_beam_has_emitter_posts_as_a_height_ruler() -> void:
	view.render({"players": {}, "walls": [[1.0, 1, LaserLimbo.WallKind.LOW, 0.0]], "fallen": []})
	var wall: Node3D = view.arena.get_node("Wall0")
	var near: MeshInstance3D = wall.get_node("PostNear")
	var far: MeshInstance3D = wall.get_node("PostFar")
	assert_true(near.visible and far.visible, "a beam gets emitter posts at both ends")
	assert_almost_eq(
		(near.mesh as CylinderMesh).height, view.POST_HEIGHT, 0.001, "posts are full-height rulers"
	)
	assert_lt(near.position.z, 0.0, "posts sit at opposite depth ends")
	assert_gt(far.position.z, 0.0)


## #928: the jump and duck beams are elevated cylinders at clearly different
## heights — the core "can't tell high from low" fix.
func test_low_and_high_beams_sit_at_their_true_heights() -> void:
	(
		view
		. render(
			{
				"players": {},
				"walls":
				[
					[1.0, 1, LaserLimbo.WallKind.LOW, 0.0],
					[-1.0, 1, LaserLimbo.WallKind.HIGH, 0.0],
				],
				"fallen": []
			}
		)
	)
	var low: MeshInstance3D = view.arena.get_node("Wall0/Low")
	var high: MeshInstance3D = view.arena.get_node("Wall1/High")
	assert_almost_eq(low.position.y, view.LOW_BEAM_Y, 0.001, "the jump beam sits low")
	assert_almost_eq(high.position.y, view.HIGH_BEAM_Y, 0.001, "the duck beam sits high")
	assert_gt(high.position.y - low.position.y, 1.0, "a clear height gap between jump and duck")
	assert_true(low.mesh is CylinderMesh, "beams are cylinders, not flat floor bars")


## #928: the GAP wall's tall halves are their own vertical reference, so it
## skips the emitter posts.
func test_gap_wall_skips_emitter_posts() -> void:
	view.render({"players": {}, "walls": [[0.0, 1, LaserLimbo.WallKind.GAP, 2.0]], "fallen": []})
	var wall: Node3D = view.arena.get_node("Wall0")
	assert_false(wall.get_node("PostNear").visible, "the gap wall reads on its own — no posts")
	assert_false(wall.get_node("PostFar").visible)


## #779: a back wall gives beam height a fixed reference the camera can't flatten.
func test_back_wall_reference_exists() -> void:
	var back: MeshInstance3D = view.arena.get_node("BackWall")
	assert_not_null(back)
	assert_almost_eq((back.mesh as BoxMesh).size.y, view.BACK_WALL_HEIGHT, 0.001, "a tall backstop")


## #779: a jumping rig holds the jump pose, not a floating walk cycle.
func test_airborne_rig_holds_the_jump_pose() -> void:
	view.render({"players": {0: _player(2.0, 0.0, 3, 1, 0)}, "walls": [], "fallen": []})
	assert_eq(view.rig_for_slot(0).current_action(), &"jump_idle", "airborne holds the jump")


func test_life_loss_bursts_at_the_player() -> void:
	view.render({"players": {0: _player(0.0, 0.0, 3, 0, 0)}, "walls": [], "fallen": []})
	var before: int = view.arena.get_child_count()
	view.render({"players": {0: _player(0.0, 0.0, 2, 0, 0)}, "walls": [], "fallen": []})
	assert_eq(view.arena.get_child_count(), before + 1, "the laser bite bursts")
