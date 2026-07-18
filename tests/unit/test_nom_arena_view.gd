extends GutTest
## Nom Arena client view (M14-10): renders blobs (as size-scaled discs), dots,
## and the seeded maze walls (#1027; ring removed, #1069) from replicated
## snapshots without simulating anything.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/nom_arena/nom_arena_view.tscn")

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


## players entry: [x, y, mass, lunging]
func _snapshot(players: Dictionary, dots := [], walls := []) -> Dictionary:
	return {"players": players, "dots": dots, "walls": walls}


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"nom_arena"),
		"res://src/minigames/nom_arena/nom_arena_view.tscn"
	)


func test_setup_hides_rigs_and_builds_blobs() -> void:
	assert_false(view.rig_for_slot(0).visible, "the blob is the avatar, not the rig")
	assert_not_null(view.arena.get_node("Blob0"))
	assert_false(view.arena.has_node("Boundary"), "the closing ring is gone (#1069)")


func test_blob_scales_with_mass_and_tracks_position() -> void:
	view.render(_snapshot({0: [2.0, -1.0, 16.0, 0]}))
	var blob: MeshInstance3D = view.arena.get_node("Blob0")
	assert_almost_eq(blob.position.x, 2.0, 0.001)
	assert_almost_eq(blob.position.z, -1.0, 0.001)
	var expected := sqrt(16.0) * NomArena.RADIUS_K
	assert_almost_eq(blob.scale.x, expected, 0.001, "disc radius follows sqrt(mass)")


## #1027: the maze builds once from the first snapshot that carries walls.
func test_walls_build_once_from_the_snapshot() -> void:
	var before := view.arena.get_child_count()
	view.render(_snapshot({}, [], [[3.0, 3.0, 0.5, 2.0], [-3.0, 3.0, 0.5, 2.0]]))
	assert_eq(view.arena.get_child_count(), before + 2, "one box per replicated wall")
	view.render(_snapshot({}, [], [[3.0, 3.0, 0.5, 2.0], [-3.0, 3.0, 0.5, 2.0]]))
	assert_eq(view.arena.get_child_count(), before + 2, "built once, not per snapshot")


func test_dots_render_from_the_pool() -> void:
	view.render(_snapshot({}, [[1.0, 2.0], [3.0, 4.0]]))
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


# --- Power Pellet (#954) --------------------------------------------------------


## The pellet model shows only when the snapshot carries one, at its position.
func test_power_pellet_appears_only_when_present() -> void:
	view.render(_snapshot({0: [0.0, 0.0, 8.0, 0, 0.0]}))
	assert_false((view.arena.get_node("PowerPellet") as Node3D).visible, "no pellet: hidden")
	var snap := _snapshot({0: [0.0, 0.0, 8.0, 0, 0.0]})
	snap["pellet"] = [3.0, -2.0]
	view.render(snap)
	var pellet: Node3D = view.arena.get_node("PowerPellet")
	assert_true(pellet.visible, "pellet on the field: shown")
	assert_almost_eq(pellet.position.x, 3.0, 0.001)
	assert_almost_eq(pellet.position.z, -2.0, 0.001)


## Frenzy dressing: the eater glows gold; every rival tints frightened-blue
## and gets the fear icon in its label (icon carries meaning for colorblind).
func test_frenzy_glows_eater_and_frightens_rivals() -> void:
	view.render(
		_snapshot({0: [0.0, 0.0, 12.0, 0, NomArena.FRENZY_SEC], 1: [2.0, 0.0, 12.0, 0, 0.0]})
	)
	var eater_mat := (
		((view.arena.get_node("Blob0") as MeshInstance3D).mesh as CylinderMesh).material
	)
	var rival_mat := (
		((view.arena.get_node("Blob1") as MeshInstance3D).mesh as CylinderMesh).material
	)
	assert_eq(
		(eater_mat as StandardMaterial3D).emission, view.FRENZY_GLOW_COLOR, "eater glows gold"
	)
	assert_eq(
		(rival_mat as StandardMaterial3D).albedo_color, view.FRIGHTENED_COLOR, "rival turns blue"
	)
	assert_string_contains(view._labels[1].text, view.FEAR_ICON, "rival wears the fear icon")
	assert_false(view._labels[0].text.contains(view.FEAR_ICON), "the eater is not afraid")


## Identity returns the instant frenzy ends — no lingering blue/gold.
func test_frenzy_dressing_clears_when_it_ends() -> void:
	view.render(
		_snapshot({0: [0.0, 0.0, 12.0, 0, NomArena.FRENZY_SEC], 1: [2.0, 0.0, 12.0, 0, 0.0]})
	)
	view.render(_snapshot({0: [0.0, 0.0, 12.0, 0, 0.0], 1: [2.0, 0.0, 12.0, 0, 0.0]}))
	var rival_mat := (
		((view.arena.get_node("Blob1") as MeshInstance3D).mesh as CylinderMesh).material
	)
	assert_eq(
		(rival_mat as StandardMaterial3D).albedo_color, view.player_color(1), "rival color restored"
	)
	assert_false(view._labels[1].text.contains(view.FEAR_ICON), "fear icon cleared")
