extends GutTest
## Count Quick client view (M10-08): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/count_quick/count_quick_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"count_quick"),
		"res://src/minigames/count_quick/count_quick_view.tscn"
	)


## #1131 GFX: the swarm is Kenney critter models (not plain spheres), pads
## have a raised beveled rim, the floor wears stone pavers, and rocks ring
## the arena.
func test_gfx_critters_raised_pads_floor_and_rim_props() -> void:
	var critter: Node3D = view.arena.get_node("Swarm0")
	assert_gt(critter.get_child_count(), 0, "a critter GLB has real child geometry")
	var pad: Node3D = view.arena.get_node("Pad0")
	assert_not_null(pad.get_node("Rim"), "a beveled rim sells the raised pad")
	var disc: MeshInstance3D = pad.get_node("Disc")
	assert_almost_eq(disc.position.y, view.PAD_LIFT, 0.001, "the disc sits raised off the floor")
	var mat := (view.arena.get_node("Floor") as MultiMeshInstance3D).material_override
	assert_eq((mat as StandardMaterial3D).albedo_texture, view.FLOOR_TEXTURE)
	var props: Node = view.arena.get_node("RimProps")
	assert_eq(props.get_child_count(), view.RIM_PROP_COUNT)


func test_swarm_shows_during_flash_and_clears() -> void:
	view.render(
		{
			"players": {},
			"phase": CountQuick.Phase.FLASH,
			"swarm": [[1.0, 2.0], [3.0, -1.0]],
			"pads": []
		}
	)
	assert_true(view.arena.get_node("Swarm0").visible)
	assert_false(view.arena.get_node("Swarm2").visible)
	assert_eq(view.get_node("BannerLayer/PhaseLabel").text, view.FLASH_TEXT)
	view.render({"players": {}, "phase": CountQuick.Phase.ANSWER, "swarm": [], "pads": []})
	assert_false(view.arena.get_node("Swarm0").visible, "the swarm vanishes with the flash")
	assert_eq(view.get_node("BannerLayer/PhaseLabel").text, view.ANSWER_TEXT)


func test_pads_show_their_values() -> void:
	view.render(
		{
			"players": {},
			"phase": CountQuick.Phase.ANSWER,
			"swarm": [],
			"pads": [[-6.0, -6.0, 14], [6.0, -6.0, 12], [-6.0, 6.0, 16], [6.0, 6.0, 11]]
		}
	)
	var pad: Node3D = view.arena.get_node("Pad0")
	assert_true(pad.visible)
	assert_almost_eq(pad.position.x, -6.0, 0.001)
	assert_eq((pad.get_node("Value") as Label3D).text, "14")


## #799: the nameplate shows each player's current pick (the pad value under
## them), not a lock tag; off all pads (-1) shows no pick marker.
func test_current_pick_shows_on_the_nameplate() -> void:
	view.render(
		{
			"players": {0: [0.0, 0.0, 3, 14], 1: [1.0, 1.0, 2, -1]},
			"phase": 1,
			"swarm": [],
			"pads": []
		}
	)
	assert_string_contains(view.rig_for_slot(0).display_name, "▶ 14")
	assert_false("▶" in view.rig_for_slot(1).display_name, "off all pads shows no pick")
	assert_string_contains(view.rig_for_slot(0).display_name, "3")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.swarm.size(), 0)
	assert_eq(view.pads.size(), 0)


## M13-15: the swarm wiggles like living critters; picks flash.
func test_swarm_wiggles_across_snapshots() -> void:
	view.render({"players": {}, "phase": CountQuick.Phase.FLASH, "swarm": [[2.0, 2.0]], "pads": []})
	var node: Node3D = view.arena.get_node("Swarm0")
	var pos_a: Vector3 = node.position
	view.render({"players": {}, "phase": CountQuick.Phase.FLASH, "swarm": [[2.0, 2.0]], "pads": []})
	assert_ne(node.position, pos_a, "same replicated spot, living wiggle")


## #799: landing on a pad flashes; staying on the same pad doesn't re-flash;
## switching to a different pad flashes again (the pick changed).
func test_landing_on_a_pad_flashes_and_re_flashes_on_change() -> void:
	view.render({"players": {0: [0.0, 0.0, 0, -1]}, "phase": 1, "swarm": [], "pads": []})
	var before: int = view.arena.get_child_count()
	view.render({"players": {0: [0.0, 0.0, 0, 12]}, "phase": 1, "swarm": [], "pads": []})
	assert_eq(view.arena.get_child_count(), before + 1, "landing on a pad sparkles")
	view.render({"players": {0: [0.0, 0.0, 0, 12]}, "phase": 1, "swarm": [], "pads": []})
	assert_eq(view.arena.get_child_count(), before + 1, "staying on the same pad adds nothing")
	view.render({"players": {0: [0.0, 0.0, 0, 9]}, "phase": 1, "swarm": [], "pads": []})
	assert_eq(view.arena.get_child_count(), before + 2, "switching pads flashes the new pick")
