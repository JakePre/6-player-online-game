extends GutTest
## Musical Platforms client view (M10-02): renders replicated snapshots in
## the shared iso-arena without simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load(
		"res://src/minigames/musical_platforms/musical_platforms_view.tscn"
	)
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"musical_platforms"),
		"res://src/minigames/musical_platforms/musical_platforms_view.tscn"
	)


func test_phase_label_flips_with_the_music() -> void:
	view.render({"players": {}, "phase": MusicalPlatforms.Phase.MUSIC, "platforms": []})
	var label: Label = view.get_node("PhaseLabel")
	assert_eq(label.text, view.MUSIC_TEXT)
	view.render({"players": {}, "phase": MusicalPlatforms.Phase.STOP, "platforms": []})
	assert_eq(label.text, view.STOP_TEXT)


func test_platforms_show_free_and_claimed_colors() -> void:
	view.render(
		{
			"players": {},
			"phase": MusicalPlatforms.Phase.STOP,
			"platforms": [[2.0, -3.0, -1], [4.0, 1.0, 1]],
			"fallen": []
		}
	)
	var free_node: MeshInstance3D = view.arena.get_node("Platform0")
	var claimed: MeshInstance3D = view.arena.get_node("Platform1")
	assert_true(free_node.visible)
	assert_almost_eq(free_node.position.x, 2.0, 0.001)
	var free_color: Color = (
		((free_node.mesh as CylinderMesh).material as StandardMaterial3D).albedo_color
	)
	assert_eq(free_color, view.PLATFORM_FREE_COLOR)
	var claimed_color: Color = (
		((claimed.mesh as CylinderMesh).material as StandardMaterial3D).albedo_color
	)
	assert_eq(Color(claimed_color, 1.0), Color(PlayerPalette.color_for_slot(1), 1.0))
	assert_false(view.arena.get_node("Platform2").visible)
	view.render({"players": {}, "phase": MusicalPlatforms.Phase.MUSIC, "platforms": []})
	assert_false(free_node.visible, "platforms clear when the music restarts")


func test_downed_player_collapses_and_shake_fires_once_seeded() -> void:
	watch_signals(view)
	view.render(
		{"players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "phase": 0, "platforms": [], "fallen": []}
	)
	assert_signal_not_emitted(view, "shake_requested")
	view.render({"players": {0: [0.0, 0.0]}, "phase": 0, "platforms": [], "fallen": [[1]]})
	assert_signal_emitted(view, "shake_requested")
	assert_eq(view.rig_for_slot(1).current_action(), &"ko")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.platforms.size(), 0)
	assert_eq(view.phase, MusicalPlatforms.Phase.MUSIC)


## M13-08: fresh waves dust in, claims sparkle in the claimant's color, downs
## puff — with rejoin seeding on the first render.
func test_wave_drop_in_dusts_after_seeding() -> void:
	view.render(
		{
			"players": {},
			"phase": MusicalPlatforms.Phase.STOP,
			"platforms": [[2.0, 0.0, -1], [4.0, 0.0, -1]],
			"fallen": []
		}
	)
	var before: int = view.arena.get_child_count()
	view.render(
		{"players": {}, "phase": MusicalPlatforms.Phase.MUSIC, "platforms": [], "fallen": []}
	)
	view.render(
		{
			"players": {},
			"phase": MusicalPlatforms.Phase.STOP,
			"platforms": [[1.0, 1.0, -1], [3.0, 3.0, -1]],
			"fallen": []
		}
	)
	assert_eq(view.arena.get_child_count(), before + 2, "second wave dusts both platforms")


func test_claim_sparkles_in_the_claimants_color() -> void:
	view.render(
		{
			"players": {},
			"phase": MusicalPlatforms.Phase.STOP,
			"platforms": [[2.0, 0.0, -1]],
			"fallen": []
		}
	)
	var before: int = view.arena.get_child_count()
	view.render(
		{
			"players": {},
			"phase": MusicalPlatforms.Phase.STOP,
			"platforms": [[2.0, 0.0, 1]],
			"fallen": []
		}
	)
	assert_eq(view.arena.get_child_count(), before + 1, "claim flips fire one sparkle")
	var fx: CPUParticles3D = view.arena.get_child(before)
	assert_eq(Color(fx.color, 1.0), Color(PlayerPalette.color_for_slot(1), 1.0))
