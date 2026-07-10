extends GutTest
## Faulty Wiring client view (M10-16): renders replicated snapshots in the
## dark iso-arena — node glow, unattributed cut sparks, the private-role
## prompt, and the reveal banner — without simulating anything locally.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/faulty_wiring/faulty_wiring_view.tscn")

var view: MinigameView3D
var _saved_show_names := false


func before_each() -> void:
	_saved_show_names = MinigameView.show_names
	MinigameView.show_names = true  # #580: names off by default; this suite tests the name itself
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob", 2: "Cleo", 3: "Dan"}, 0)


func after_each() -> void:
	MinigameView.show_names = _saved_show_names


func _node(x: float, y: float, progress: float, pulse: int) -> Array:
	return [x, y, progress, pulse]


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"faulty_wiring"),
		"res://src/minigames/faulty_wiring/faulty_wiring_view.tscn"
	)


func test_setup_builds_four_dark_nodes() -> void:
	assert_not_null(view.arena.get_node("Node0"))
	assert_not_null(view.arena.get_node("Node3"))
	# The base daylight rig is dimmed so the room reads as dark.
	assert_lt((view.arena.get_node("KeyLight") as DirectionalLight3D).light_energy, 0.5)


func test_nodes_glow_from_red_to_green_with_repair() -> void:
	var pos := FaultyWiring.NODE_POSITIONS
	(
		view
		. render(
			{
				"phase": FaultyWiring.Phase.WORK,
				"players": {},
				"nodes":
				[
					_node(pos[0].x, pos[0].y, 0.0, 0),
					_node(pos[1].x, pos[1].y, 1.0, 0),
					_node(pos[2].x, pos[2].y, 0.0, 0),
					_node(pos[3].x, pos[3].y, 0.0, 0),
				],
			}
		)
	)
	var broken: OmniLight3D = view.arena.get_node("NodeLight0")
	var fixed: OmniLight3D = view.arena.get_node("NodeLight1")
	assert_gt(fixed.light_energy, broken.light_energy, "a repaired node shines brighter")
	assert_gt(fixed.light_color.g, broken.light_color.g, "and reads greener")


func test_a_fresh_cut_spark_bursts_unattributed() -> void:
	var pos := FaultyWiring.NODE_POSITIONS
	view.render(
		{
			"phase": FaultyWiring.Phase.WORK,
			"players": {},
			"nodes": [_node(pos[0].x, pos[0].y, 0.5, 0)]
		}
	)
	var before: int = view.arena.get_child_count()
	# Same node, spark pulse bumped: a cut just landed.
	view.render(
		{
			"phase": FaultyWiring.Phase.WORK,
			"players": {},
			"nodes": [_node(pos[0].x, pos[0].y, 0.0, 1)]
		}
	)
	assert_gt(view.arena.get_child_count(), before, "the cut throws a spark burst")


func test_only_the_local_saboteur_sees_the_role_prompt() -> void:
	view.private_state = {"role": "saboteur", "cut_cd": 0.0}
	view.render({"phase": FaultyWiring.Phase.WORK, "players": {}, "nodes": []})
	assert_string_contains(view.get_node("BannerLayer/RoleLabel").text, "SABOTEUR")
	# A crew client carries no private role, so the prompt stays empty.
	view.private_state = {}
	view.render({"phase": FaultyWiring.Phase.WORK, "players": {}, "nodes": []})
	assert_eq(view.get_node("BannerLayer/RoleLabel").text, "", "crew never see a role prompt")


## Regression for #576: the owner reported the saboteur's own role text
## unreadable at the bottom of the screen — the default grow direction let a
## long line grow downward until it clipped past the viewport's bottom edge.
## The label now routes through the shared make_banner() (#831), which carries
## the fix; this pins the behavior either way.
func test_role_prompt_stays_within_the_viewport() -> void:
	view.private_state = {"role": "saboteur", "cut_cd": 0.0}
	view.render({"phase": FaultyWiring.Phase.WORK, "players": {}, "nodes": []})
	await get_tree().process_frame
	var label: Label = view.get_node("BannerLayer/RoleLabel")
	assert_string_contains(label.text, "SPACE to cut a wire")
	assert_true(
		label.position.y + label.size.y <= view.size.y + 1.0,
		"the role prompt grows upward off its anchor, not downward past the screen edge"
	)


func test_reveal_names_the_saboteur_and_the_outcome() -> void:
	(
		view
		. render(
			{
				"phase": FaultyWiring.Phase.REVEAL,
				"players": {},
				"nodes": [],
				"saboteur": 2,
				"outcome": "crew",
			}
		)
	)
	assert_string_contains(view.get_node("BannerLayer/Banner").text, "RESTORED")
	assert_string_contains(view.get_node("BannerLayer/RoleLabel").text, "Cleo")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.nodes.size(), 0)
	assert_not_null(view.arena.get_node("Node0"))


# --- Visible wire runs (#802) ------------------------------------------------


func test_setup_builds_the_power_core_and_wire_runs() -> void:
	assert_not_null(view.arena.get_node("PowerCore"), "a central power core")
	for i in FaultyWiring.NODE_POSITIONS.size():
		assert_not_null(view.arena.get_node("Conduit%d" % i), "a base conduit to node %d" % i)
		assert_not_null(view.arena.get_node("WireFill%d" % i), "an energized fill for node %d" % i)


## The whole point of the fix: the energized run's length reads the repair
## value, so "which node needs work and how much" is spatially obvious. scale.z
## and position are stored transform values (readable headless, unlike AABBs).
func test_wire_fill_length_tracks_the_repair_value() -> void:
	var pos := FaultyWiring.NODE_POSITIONS
	(
		view
		. render(
			{
				"phase": FaultyWiring.Phase.WORK,
				"players": {},
				"nodes":
				[
					_node(pos[0].x, pos[0].y, 0.0, 0),
					_node(pos[1].x, pos[1].y, 1.0, 0),
					_node(pos[2].x, pos[2].y, 0.5, 0),
					_node(pos[3].x, pos[3].y, 0.25, 0),
				],
			}
		)
	)
	var run := pos[1].length()  # all four corner runs are equal
	assert_false(view._wire_fills[0].visible, "a 0% node lights no wire")
	assert_true(view._wire_fills[1].visible, "a repaired node lights its wire")
	assert_almost_eq(view._wire_fills[1].scale.z, run, 0.05, "a 100% wire reaches its node")
	assert_almost_eq(view._wire_fills[2].scale.z, run * 0.5, 0.05, "50% node = half-lit wire")
	assert_almost_eq(view._wire_fills[3].scale.z, run * 0.25, 0.05, "25% node = quarter-lit wire")
	# The live run is anchored at the core, so its centre sits half its length in.
	assert_almost_eq(
		view._wire_fills[1].position.length(),
		run * 0.5,
		0.1,
		"the full wire's centre is half a run from the core",
	)


## The far tip of the live run is the fault point a cut sparks at: on the node
## when fully repaired, back at the core when fully broken (#802).
func test_fault_point_is_the_tip_of_the_live_run() -> void:
	var pos := FaultyWiring.NODE_POSITIONS
	var full: Vector2 = view._fault_point(3, 1.0)
	assert_almost_eq(full.x, pos[3].x, 0.05, "a full wire's fault point sits on its node")
	assert_almost_eq(full.y, pos[3].y, 0.05)
	assert_almost_eq(
		view._fault_point(3, 0.0).length(), 0.0, 0.05, "a broken wire's fault point is at the core"
	)


## #590: the base arena background is transparent by default (so the
## drifting backdrop shows through), but a pitch-black room is the mechanic
## here — _darken() must opt back into a solid background color.
func test_darken_forces_a_solid_background() -> void:
	var world_env := view.arena.get_node("Environment") as WorldEnvironment
	assert_eq(world_env.environment.background_mode, Environment.BG_COLOR)
	assert_almost_eq(world_env.environment.background_color.v, 0.02, 0.01, "a near-black room")
