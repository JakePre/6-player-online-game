extends GutTest
## Nom Arena client view (M14-10): renders blobs (as size-scaled discs), dots,
## and the closing ring from replicated snapshots without simulating anything.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/nom_arena/nom_arena_view.tscn")

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


## players entry: [x, y, mass, lunging]
func _snapshot(players: Dictionary, boundary := NomArena.ARENA_HALF, dots := []) -> Dictionary:
	return {"players": players, "dots": dots, "boundary": boundary}


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"nom_arena"),
		"res://src/minigames/nom_arena/nom_arena_view.tscn"
	)


func test_setup_hides_rigs_and_builds_blobs_and_ring() -> void:
	assert_false(view.rig_for_slot(0).visible, "the blob is the avatar, not the rig")
	assert_not_null(view.arena.get_node("Blob0"))
	assert_not_null(view.arena.get_node("Boundary"))


func test_blob_scales_with_mass_and_tracks_position() -> void:
	view.render(_snapshot({0: [2.0, -1.0, 16.0, 0]}))
	var blob: MeshInstance3D = view.arena.get_node("Blob0")
	assert_almost_eq(blob.position.x, 2.0, 0.001)
	assert_almost_eq(blob.position.z, -1.0, 0.001)
	var expected := sqrt(16.0) * NomArena.RADIUS_K
	assert_almost_eq(blob.scale.x, expected, 0.001, "disc radius follows sqrt(mass)")


func test_boundary_ring_tracks_the_closing_radius() -> void:
	view.render(_snapshot({0: [0.0, 0.0, 8.0, 0]}, 6.0))
	assert_almost_eq((view.arena.get_node("Boundary") as MeshInstance3D).scale.x, 6.0, 0.001)


func test_dots_render_from_the_pool() -> void:
	view.render(_snapshot({}, NomArena.ARENA_HALF, [[1.0, 2.0], [3.0, 4.0]]))
	var visible_dots := 0
	for node: MeshInstance3D in view._dot_pool:
		if node.visible:
			visible_dots += 1
	assert_eq(visible_dots, 2)


func test_getting_eaten_puffs() -> void:
	view.render(_snapshot({0: [0.0, 0.0, 30.0, 0]}))
	var before := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			before += 1
	watch_signals(view)
	# A sharp mass drop = swallowed and respawned small.
	view.render(_snapshot({0: [5.0, 5.0, NomArena.MIN_MASS, 0]}))
	var after := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			after += 1
	assert_gt(after, before, "being eaten pops a puff")
	# Signature cue (#728): a debuff/stagger cue, heard by the swallowed blob.
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"powerdown"], "swallowed")


## Signature cue (#728): starting a lunge, heard only by the lunging player.
func test_lunge_onset_plays_dash() -> void:
	view.render(_snapshot({0: [0.0, 0.0, 20.0, 0]}))
	watch_signals(view)
	view.render(_snapshot({0: [0.0, 0.0, 20.0, 1]}))
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"dash"], "lunge onset")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
