extends GutTest
## Shred Session client view (M14-04): renders the lane highway, falling notes,
## and scoreboard from replicated snapshots without simulating anything.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/shred_session/shred_session_view.tscn")

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	InputGlyphs.active_layout = InputGlyphs.Layout.GENERIC


func after_each() -> void:
	# InputGlyphs is a shared autoload — restore the default between tests.
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	InputGlyphs.active_layout = InputGlyphs.Layout.GENERIC


## players entry: [score, streak, last_judgment, last_lane, event_count]
func _snap(notes: Array, players: Dictionary, elapsed := 0.0) -> Dictionary:
	return {
		"elapsed": elapsed,
		"lanes": ShredSession.LANES,
		"song_end": 62.0,
		"notes": notes,
		"players": players,
	}


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"shred_session"),
		"res://src/minigames/shred_session/shred_session_view.tscn"
	)


func test_setup_builds_four_lanes_and_a_hit_line() -> void:
	for lane in ShredSession.LANES:
		assert_not_null(view.arena.get_node("Lane%d" % lane), "lane %d exists" % lane)
	assert_not_null(view.arena.get_node("HitLine"))


func test_notes_spawn_and_clear_with_the_snapshot() -> void:
	view.render(_snap([[3.0, 0], [3.5, 2]], {0: [0, 0, 0, -1, 0]}))
	assert_eq(view._note_nodes.size(), 2, "a node per advertised note")
	# The 3.0 note passes; only the later one remains.
	view.render(_snap([[3.5, 2]], {0: [0, 0, 0, -1, 0]}))
	assert_eq(view._note_nodes.size(), 1, "notes that leave the snapshot are dropped")


func test_note_sits_at_the_hit_line_when_the_clock_reaches_it() -> void:
	view.render(_snap([[4.0, 1]], {0: [0, 0, 0, -1, 0]}, 4.0))
	var entry: Dictionary = view._note_nodes.values()[0]
	assert_almost_eq(
		(entry.node as MeshInstance3D).position.z, view.HIT_Z, 0.01, "dt=0 places it on the line"
	)


func test_note_is_up_track_before_its_time() -> void:
	view.render(_snap([[6.0, 1]], {0: [0, 0, 0, -1, 0]}, 4.0))
	var entry: Dictionary = view._note_nodes.values()[0]
	assert_lt(
		(entry.node as MeshInstance3D).position.z, view.HIT_Z, "a future note is short of the line"
	)


func test_scoreboard_reflects_scores() -> void:
	view.render(_snap([], {0: [40, 3, 1, 1, 5], 1: [90, 0, 3, 2, 4]}))
	assert_string_contains((view._score_rows[1] as Label).text, "90")
	assert_string_contains((view._score_rows[0] as Label).text, "40")


func test_local_verdict_flashes_on_a_fresh_event() -> void:
	var label: Label = view.get_node("JudgmentLabel")
	view.render(_snap([], {0: [0, 0, 0, -1, 0]}))
	assert_false(label.visible, "no verdict yet")
	# Local player's event counter ticks with a PERFECT.
	view.render(_snap([], {0: [2, 1, ShredSession.Judgment.PERFECT, 1, 1]}))
	assert_true(label.visible, "the verdict flashes")
	assert_string_contains(label.text, "PERFECT")


func test_streak_banner_shows_once_the_multiplier_is_live() -> void:
	var streak: Label = view.get_node("StreakLabel")
	view.render(_snap([], {0: [16, ShredSession.STREAK_X2, 1, 0, 3]}))
	assert_true(streak.visible)
	assert_string_contains(streak.text, "×2")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view._note_nodes.size(), 0)


## #798: a clean hit vanishes its note right away instead of sliding through
## the line — the local player's own judgment event pops it early.
func test_a_perfect_hit_pops_its_note_immediately() -> void:
	view.render(_snap([[3.0, 1]], {0: [0, 0, 0, -1, 0]}, 3.0))
	assert_eq(view._note_nodes.size(), 1, "the note is up before the hit")
	view.render(_snap([[3.0, 1]], {0: [2, 1, ShredSession.Judgment.PERFECT, 1, 1]}, 3.0))
	assert_eq(view._note_nodes.size(), 0, "the perfect hit vanishes it early")


## A GOOD hit gets the same early-vanish treatment as a PERFECT.
func test_a_good_hit_pops_its_note_immediately() -> void:
	view.render(_snap([[3.0, 2]], {0: [0, 0, 0, -1, 0]}, 3.0))
	view.render(_snap([[3.0, 2]], {0: [1, 1, ShredSession.Judgment.GOOD, 2, 1]}, 3.0))
	assert_eq(view._note_nodes.size(), 0, "a good hit vanishes it early too")


## A miss keeps rolling through the line — the miss itself is the feedback,
## and the server's own snapshot still carries the note for other players.
func test_a_miss_does_not_pop_its_note() -> void:
	view.render(_snap([[3.0, 0]], {0: [0, 0, 0, -1, 0]}, 3.0))
	view.render(_snap([[3.0, 0]], {0: [0, 0, ShredSession.Judgment.MISS, 0, 1]}, 3.0))
	assert_eq(view._note_nodes.size(), 1, "a missed note keeps sliding — still in the snapshot")


## A hit only ever pops the note near the hit line — a far-future note in the
## same lane is untouched.
func test_pop_never_targets_a_note_far_from_the_hit_line() -> void:
	view.render(_snap([[10.0, 1]], {0: [0, 0, 0, -1, 0]}, 3.0))
	view.render(_snap([[10.0, 1]], {0: [2, 1, ShredSession.Judgment.PERFECT, 1, 1]}, 3.0))
	assert_eq(view._note_nodes.size(), 1, "a note way up-track is out of the judging window")


func test_lane_headers_are_enlarged_and_moved_off_the_bottom_edge() -> void:
	# #798: the original -24px placement went unnoticed; moved up and enlarged.
	# A bottom-anchored Control's `position` resolves through the parent
	# viewport size at layout time, so this checks `offset_top` — the literal
	# value the layout math is built from — rather than the post-anchor pixel
	# position, which the CI render clip verifies visually.
	var row: Control = view.get_node("LaneHeaders")
	assert_almost_eq(row.offset_top, -220.0, 0.01, "moved well above the old -24px placement")
	var chip: VBoxContainer = row.get_child(0)
	var arrow: Label = chip.get_child(0)
	assert_gt(arrow.get_theme_font_size(&"font_size"), 22, "bigger than the old header size")


func test_flat_lane_headers_replace_the_iso_projected_glyphs() -> void:
	# #585: the ambiguous iso Label3D targets are gone; a flat screen-space
	# header row carries lane identity instead.
	assert_null(view.arena.get_node_or_null("LaneTarget0"), "no iso lane glyphs")
	assert_not_null(view.get_node_or_null("LaneHeaders"), "flat header row exists")
	assert_eq(view._lane_glyph_labels.size(), ShredSession.LANES, "one glyph label per lane")


func test_lane_headers_show_the_device_aware_bound_input() -> void:
	# On keyboard each header mirrors InputGlyphs' bound-key label; the action
	# lane is Space.
	for lane in ShredSession.LANES:
		assert_eq(
			view._lane_glyph_labels[lane].text,
			InputGlyphs.glyph_for(view.LANE_ACTIONS[lane]),
			"lane %d header mirrors the glyph helper" % lane
		)
	assert_eq(view._lane_glyph_labels[3].text, "Space", "action lane shows the keyboard key")


func test_lane_glyphs_refresh_when_the_device_changes() -> void:
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	InputGlyphs.active_layout = InputGlyphs.Layout.XBOX
	InputGlyphs.device_changed.emit(InputGlyphs.Device.GAMEPAD)
	# action_primary is a pad button (A); movement lanes are stick axes with no
	# button glyph, so those sub-labels clear and the arrow alone instructs.
	assert_eq(view._lane_glyph_labels[3].text, "A", "action lane shows the pad button")
	assert_eq(view._lane_glyph_labels[0].text, "", "a stick-axis lane has no button glyph")


func test_each_lane_has_a_distinct_drum_on_the_sfx_bus() -> void:
	assert_eq(view._lane_players.size(), ShredSession.LANES, "one player per lane")
	var paths := {}
	for player: AudioStreamPlayer in view._lane_players:
		assert_not_null(player.stream, "lane player is loaded")
		assert_eq(player.bus, &"SFX", "drums route through the SFX bus")
		paths[player.stream.resource_path] = true
	assert_eq(paths.size(), ShredSession.LANES, "each lane's drum is distinct")
