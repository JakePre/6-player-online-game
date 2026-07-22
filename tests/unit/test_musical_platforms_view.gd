extends GutTest
## Musical Platforms client view (M10-02, M15 12-cap): renders replicated
## snapshots in the shared iso-arena without simulating anything locally.

const VIEW_SCENE := preload("res://src/minigames/musical_platforms/musical_platforms_view.tscn")

var view: MinigameView


## The platform pool is sized to `names.size() - 1` at _setup_3d() (#457: it
## used to be a fixed 5, silently dropping platforms past that). Four named
## players here gives a pool of three (Platform0..2), matching the tests
## below that render up to three platforms.
func before_each() -> void:
	view = _new_view({0: "Alice", 1: "Bob", 2: "Carol", 3: "Dave"})


func _new_view(names: Dictionary) -> MinigameView:
	var instance: MinigameView = VIEW_SCENE.instantiate()
	add_child_autofree(instance)
	instance.setup(names, 0)
	return instance


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"musical_platforms"),
		"res://src/minigames/musical_platforms/musical_platforms_view.tscn"
	)


## M15: the view derives its floor/camera size from the lobby count with the
## same formula the sim uses, so the rendered arena matches the scaled one.
func test_arena_half_scales_with_lobby_size() -> void:
	assert_almost_eq(
		view._arena_half(), MusicalPlatforms.ARENA_HALF, 0.001, "<=6 players = base arena"
	)
	var names := {}
	for i in 12:
		names[i] = "P%d" % (i + 1)
	var big := _new_view(names)
	assert_gt(big._arena_half(), MusicalPlatforms.ARENA_HALF, "12 players get a bigger floor")


func test_phase_label_flips_with_the_music() -> void:
	view.render({"players": {}, "phase": MusicalPlatforms.Phase.MUSIC, "platforms": []})
	var label: Label = view.get_node("BannerLayer/PhaseLabel")
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


## #457: the pool used to be a fixed 5 regardless of lobby size, so an
## 11-platform scramble at 12 players silently dropped six of them. The pool
## now sizes to "players - 1" — the most a first scramble ever needs.
func test_platform_pool_scales_to_the_lobby_size() -> void:
	var names := {}
	for i in 12:
		names[i] = "P%d" % i
	var big := _new_view(names)
	big.render(
		{
			"players": {},
			"phase": MusicalPlatforms.Phase.STOP,
			"platforms": range(11).map(func(i: int) -> Array: return [float(i), 0.0, -1]),
			"fallen": []
		}
	)
	for i in 11:
		assert_true(big.arena.get_node("Platform%d" % i).visible, "platform %d renders" % i)
	assert_null(big.arena.get_node_or_null("Platform11"), "no extra pool nodes past the true max")


func test_downed_player_collapses_and_shake_fires_once_seeded() -> void:
	watch_signals(view)
	view.render(
		{"players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "phase": 0, "platforms": [], "fallen": []}
	)
	assert_signal_not_emitted(view, "shake_requested")
	view.render({"players": {0: [0.0, 0.0]}, "phase": 0, "platforms": [], "fallen": [[1]]})
	assert_signal_emitted(view, "shake_requested")
	assert_eq(view.rig_for_slot(1).current_action(), &"ko")


## #930: a downed rig sinks out of view instead of lying in the field mid-
## round (memory_match's #784 fall idiom).
func test_downed_player_sinks_and_hides() -> void:
	view.render(
		{"players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "phase": 0, "platforms": [], "fallen": []}
	)
	var rig: CharacterRig = view.rig_for_slot(1)
	var y_before := rig.position.y
	view.render({"players": {0: [0.0, 0.0]}, "phase": 0, "platforms": [], "fallen": [[1]]})
	view._process(0.2)
	assert_lt(rig.position.y, y_before, "the loser sinks")
	assert_true(rig.visible, "still sinking, not hidden yet")
	view._process(10.0)
	assert_false(rig.visible, "hides once fully sunk")


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


## #804: the music STOPPING is the whole game — the round loop pauses for the
## scramble phase and resumes when players roam again.
func test_music_pauses_for_the_scramble_and_resumes() -> void:
	AudioManager.play_music(&"round")
	AudioManager.set_music_paused(false)
	view.render(
		{"players": {}, "phase": MusicalPlatforms.Phase.STOP, "platforms": [], "fallen": []}
	)
	assert_true(AudioManager.music_paused, "music stops for the scramble")
	view.render(
		{"players": {}, "phase": MusicalPlatforms.Phase.MUSIC, "platforms": [], "fallen": []}
	)
	assert_false(AudioManager.music_paused, "music returns with the roam phase")


## #804: a winner emerging mid-scramble must not leave the shared loop paused
## for the next round — the results celebration resumes it.
func test_celebrate_resumes_the_music() -> void:
	view.render(
		{"players": {}, "phase": MusicalPlatforms.Phase.STOP, "platforms": [], "fallen": []}
	)
	assert_true(AudioManager.music_paused, "paused going into the results")
	view.celebrate([[0]])
	assert_false(AudioManager.music_paused, "the results resume the music")


## #1143 GFX: floating music notes drift up only during the MUSIC phase — the
## STOP scramble stays note-free so the phases still read distinctly.
func test_music_phase_spawns_floating_notes() -> void:
	view.render({"players": {}, "phase": MusicalPlatforms.Phase.MUSIC, "platforms": []})
	var before: int = view.arena.get_child_count()
	view._process(view.NOTE_INTERVAL_SEC + 0.01)
	assert_gt(view.arena.get_child_count(), before, "MUSIC phase spawns a floating note")


func test_stop_phase_spawns_no_notes() -> void:
	view.render({"players": {}, "phase": MusicalPlatforms.Phase.STOP, "platforms": []})
	var before: int = view.arena.get_child_count()
	view._process(view.NOTE_INTERVAL_SEC + 0.01)
	assert_eq(view.arena.get_child_count(), before, "STOP phase spawns no notes")


## #1143 GFX: an eliminated fighter leaves a flat ghost ring behind at their
## drop spot, marking the elimination for the rest of the round.
func test_downed_player_leaves_a_ghost_ring() -> void:
	view.render(
		{"players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "phase": 0, "platforms": [], "fallen": []}
	)
	view.render({"players": {0: [0.0, 0.0]}, "phase": 0, "platforms": [], "fallen": [[1]]})
	var found_ring := false
	for child in view.arena.get_children():
		if child.name == "GhostRing":
			found_ring = true
			break
	assert_true(found_ring, "a KO leaves a ghost ring behind")


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
