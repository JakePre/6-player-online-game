extends GutTest
## Magma Ascent client view (#936): renders replicated snapshots — the stable
## tower via the side-scroll base, toggleable crumble ledges, the rising magma
## plane, shielded shimmer and eliminated-climber hiding — without simulating.

const VIEW_SCENE: PackedScene = preload("res://src/finale/magma_ascent_view.tscn")

var view: SideScrollView


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(800.0, 450.0)
	view.setup({0: "Alice", 1: "Bob"}, 0)


## players entry: [x, y, facing, grounded, flags]
func _snapshot(
	players: Dictionary, magma_y := MagmaAscent.MAGMA_START_Y, crumble := []
) -> Dictionary:
	var crumble_state := crumble
	if crumble_state.is_empty():
		crumble_state = []
		for _i in MagmaAscent.LEDGE_COUNT:
			crumble_state.append(true)
	return {"players": players, "magma_y": magma_y, "crumble": crumble_state}


func test_view_scene_lives_at_the_registry_path() -> void:
	assert_eq(FinaleVariants.view_scene_path(&"magma_ascent"), VIEW_SCENE.resource_path)


func test_setup_builds_the_stage_and_crumble_overlays() -> void:
	# One overlay panel per crumble ledge; stable ledges + floor + capstone are
	# the base's platform nodes.
	assert_eq(view._crumble_nodes.size(), MagmaAscent._crumble_indices().size())
	assert_gt(view._platform_nodes.size(), 0, "base drew the stable stage")


func test_crumble_overlays_toggle_with_the_snapshot() -> void:
	var index: int = MagmaAscent._crumble_indices()[0]
	var gone := []
	for i in MagmaAscent.LEDGE_COUNT:
		gone.append(i != index)
	view.render(_snapshot({}, MagmaAscent.MAGMA_START_Y, gone))
	assert_false(view._crumble_nodes[index].visible, "a crumbled ledge hides")
	var solid := []
	for _i in MagmaAscent.LEDGE_COUNT:
		solid.append(true)
	view.render(_snapshot({}, MagmaAscent.MAGMA_START_Y, solid))
	assert_true(view._crumble_nodes[index].visible, "and returns when solid again")


func test_shielded_shimmers_and_eliminated_hides() -> void:
	view.render(_snapshot({0: [0.0, 2.0, 1, 1, 1], 1: [1.0, 2.0, 1, 1, 2]}))
	assert_eq(view.rig_for_slot(0).modulate, view.SHIELD_MODULATE, "shielded shimmers")
	assert_false(view.rig_for_slot(1).visible, "eliminated climber sinks out of view")


func test_magma_plane_draws_and_tracks_the_line() -> void:
	# Rendering a high magma line shouldn't error; the fx layer owns the draw.
	view.render(_snapshot({0: [0.0, 6.0, 1, 1, 0]}, 4.0))
	assert_not_null(view._fx_layer, "the magma fx layer exists")
	assert_almost_eq(view.magma_y, 4.0, 0.001, "tracks the replicated magma line")
