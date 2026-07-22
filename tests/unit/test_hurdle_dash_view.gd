extends GutTest
## Hurdle Dash client view (M4-07): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/hurdle_dash/hurdle_dash_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"hurdle_dash"),
		"res://src/minigames/hurdle_dash/hurdle_dash_view.tscn"
	)


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"players": {0: [5.0, 1, 0.0, false]},
				"hurdles": [5.0, 12.0],
				"course_len": 40.0,
			}
		)
	)
	assert_eq(view.players.size(), 1)
	assert_eq(view.hurdles, [5.0, 12.0])
	view.render({"players": {}, "hurdles": [], "course_len": 40.0})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.hurdles, [])


## M13-30: a stun timer starting means a hurdle clip — one spark burst; the
## first snapshot seeds silently and an ongoing stun doesn't re-spark.
func test_hurdle_clip_fires_spark() -> void:
	view.render({"players": {0: [5.0, 0, 0.8, false]}, "hurdles": []})
	assert_eq(view._sparks.size(), 0, "first sighting seeds silently")
	view.render({"players": {0: [5.0, 0, 0.0, false]}, "hurdles": []})
	view.render({"players": {0: [5.0, 0, 0.8, false]}, "hurdles": []})
	assert_eq(view._sparks.size(), 1, "stun starting = one spark")
	assert_eq(int(view._sparks[0].slot), 0)
	view.render({"players": {0: [5.0, 0, 0.6, false]}, "hurdles": []})
	assert_eq(view._sparks.size(), 1, "an ongoing stun doesn't re-spark")


func test_sparks_expire() -> void:
	view.render({"players": {0: [5.0, 0, 0.0, false]}, "hurdles": []})
	view.render({"players": {0: [5.0, 0, 0.8, false]}, "hurdles": []})
	assert_eq(view._sparks.size(), 1)
	view._process(view.SPARK_DURATION + 0.05)
	assert_eq(view._sparks.size(), 0, "sparks free themselves after their lifetime")


func test_speed_tracks_progress_delta() -> void:
	view.render({"players": {0: [2.0, 0, 0.0, false]}, "hurdles": []})
	assert_eq(float(view._speeds[0]), 0.0, "first sighting has no delta")
	view.render({"players": {0: [3.5, 0, 0.0, false]}, "hurdles": []})
	assert_almost_eq(float(view._speeds[0]), 1.5, 0.001)
	view.render({"players": {0: [3.5, 0, 0.0, false]}, "hurdles": []})
	assert_eq(float(view._speeds[0]), 0.0, "standing still has no speed lines")


## #1141 GFX: landing after a jump puffs dust; the airborne edge is seeded so
## a rejoiner already mid-air on their first snapshot doesn't fire it.
func test_landing_spawns_dust_that_expires() -> void:
	view.render({"players": {0: [5.0, 1, 0.0, false]}, "hurdles": []})
	assert_eq(view._dust.size(), 0, "first sighting seeds silently")
	view.render({"players": {0: [5.0, 0, 0.0, false]}, "hurdles": []})
	assert_eq(view._dust.size(), 1, "airborne -> grounded puffs dust")
	assert_eq(int(view._dust[0].slot), 0)
	view._process(view.DUST_DURATION + 0.05)
	assert_true(view._dust.is_empty(), "dust puffs expire")


## #1141 GFX: while airborne the runner leaves a trail of fading points;
## it stops growing once grounded and fades out over TRAIL_LIFE_SEC.
func test_airborne_leaves_a_trail_that_fades() -> void:
	view.render({"players": {0: [5.0, 1, 0.0, false]}, "hurdles": []})
	view.render({"players": {0: [5.5, 1, 0.0, false]}, "hurdles": []})
	assert_eq(view._trails[0].size(), 2, "each airborne snapshot adds a trail point")
	view.render({"players": {0: [6.0, 0, 0.0, false]}, "hurdles": []})
	assert_eq(view._trails[0].size(), 2, "landing stops adding new points")
	view._process(view.TRAIL_LIFE_SEC + 0.05)
	assert_true(view._trails[0].is_empty(), "trail points fade out")
