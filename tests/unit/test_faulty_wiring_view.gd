extends GutTest
## Faulty Wiring client view (M10-16): renders replicated snapshots in the
## dark iso-arena — node glow, unattributed cut sparks, the private-role
## prompt, and the reveal banner — without simulating anything locally.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/faulty_wiring/faulty_wiring_view.tscn")

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob", 2: "Cleo", 3: "Dan"}, 0)


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
	assert_string_contains(view.get_node("RoleLabel").text, "SABOTEUR")
	# A crew client carries no private role, so the prompt stays empty.
	view.private_state = {}
	view.render({"phase": FaultyWiring.Phase.WORK, "players": {}, "nodes": []})
	assert_eq(view.get_node("RoleLabel").text, "", "crew never see a role prompt")


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
	assert_string_contains(view.get_node("Banner").text, "RESTORED")
	assert_string_contains(view.get_node("RoleLabel").text, "Cleo")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.nodes.size(), 0)
	assert_not_null(view.arena.get_node("Node0"))
