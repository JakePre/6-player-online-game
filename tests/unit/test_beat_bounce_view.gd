extends GutTest
## Beat Bounce client view (reworked #259): labelled pads, phase banner, and
## the demonstrated flash — rendered from snapshots without local simulation.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/beat_bounce/beat_bounce_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func _snapshot(phase: int, flash: int, seq_len: int) -> Dictionary:
	return {
		"phase": phase,
		"round": 0,
		"seq_len": seq_len,
		"pad_count": BeatBounce.PAD_COUNT,
		"beat": 1,
		"step": 0,
		"flash": flash,
		"next_in": 0.3,
		"interval": 0.9,
		"strikes": {0: 0, 1: 0},
		"alive": {0: true, 1: true},
		"progress": {0: 0, 1: 0},
	}


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"beat_bounce"),
		"res://src/minigames/beat_bounce/beat_bounce_view.tscn"
	)


func test_four_labelled_pads_and_a_beat_lamp_exist() -> void:
	assert_not_null(view.arena.get_node("BeatLamp"))
	for pad in 4:
		var node := view.arena.get_node("Pad%d" % pad) as MeshInstance3D
		assert_not_null(node)
		var tag := node.get_node("PadLabel%d" % pad) as Label3D
		assert_eq(tag.text, view.PAD_ARROWS[pad], "pad shows its direction arrow")


func test_banner_reads_watch_then_repeat_with_length_dots() -> void:
	view.render(_snapshot(BeatBounce.Phase.WATCH, 1, 3))
	assert_eq(view.get_node("PhaseLabel").text, "WATCH...")
	assert_eq(view.get_node("DotsLabel").text, "●●●", "one dot per sequence step")
	view.render(_snapshot(BeatBounce.Phase.REPEAT, -1, 3))
	assert_eq(view.get_node("PhaseLabel").text, "REPEAT!")


func test_flashed_pad_lights_during_watch_only() -> void:
	view.render(_snapshot(BeatBounce.Phase.WATCH, 2, 3))
	view._update_pads()
	assert_gt(
		view._pad_materials[2].emission_energy_multiplier,
		view._pad_materials[0].emission_energy_multiplier,
		"the demonstrated pad glows brighter"
	)
	# During REPEAT the sequence is hidden, so no flash may light a pad.
	view.render(_snapshot(BeatBounce.Phase.REPEAT, -1, 3))
	view._update_pads()
	for pad in 4:
		assert_almost_eq(
			view._pad_materials[pad].emission_energy_multiplier, view.DIM, 0.001, "all pads dim"
		)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_not_null(view.arena.get_node("Pad0"))
