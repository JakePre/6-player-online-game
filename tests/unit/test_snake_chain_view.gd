extends GutTest
## Snake Chain client view (M10-11): renders replicated snapshots without
## simulating anything locally.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/snake_chain/snake_chain_view.tscn")

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"snake_chain"),
		"res://src/minigames/snake_chain/snake_chain_view.tscn"
	)


func test_render_places_trail_segments_from_the_pool() -> void:
	(
		view
		. render(
			{
				"players": {0: [1.0, 1.0, 3, 0.0, 0]},
				"trails": {0: [[0.5, 0.5], [0.0, 0.0]]},
				"pellets": [[2.0, 2.0]],
				"teams": [],
			}
		)
	)
	assert_eq(view.trails[0].size(), 2)
	var visible_segments := 0
	for node: MeshInstance3D in view._segment_pools[0]:
		if node.visible:
			visible_segments += 1
	assert_eq(visible_segments, 2, "one glowing segment per trail point")
	assert_string_contains(view.rig_for_slot(0).display_name, "3")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.pellets, [])


## #950: holding action_primary sends a boost; releasing stops it (Tail Burn).
func test_boost_input_maps_to_a_held_boost_action() -> void:
	var press := InputEventAction.new()
	press.action = &"action_primary"
	press.pressed = true
	assert_true(view.input_sends_for_event(press).has({"boost": true}), "hold -> boost on")
	var release := InputEventAction.new()
	release.action = &"action_primary"
	release.pressed = false
	assert_true(view.input_sends_for_event(release).has({"boost": false}), "release -> boost off")


## #950: a boosting head trails a color spark (the Tail Burn FX).
func test_a_boosting_head_trails_a_spark() -> void:
	var base := view.arena.get_child_count()
	var snap := {
		"players": {0: [1.0, 0.0, 3, 0.0, 1]}, "trails": {0: []}, "pellets": [], "teams": []
	}
	# Render twice so the staggered per-slot cadence fires at least once.
	view.render(snap)
	view.render(snap)
	assert_gt(view.arena.get_child_count(), base, "a boosting head spawns a trail spark")


## ADR 003: a 12-player view sizes its pellet pool to the scaled supply (plus
## the crash-spill headroom), so the extra pellets can actually render.
func test_large_lobby_pellet_pool_scales() -> void:
	var names := {}
	for slot in 12:
		names[slot] = "P%d" % (slot + 1)
	var big: MinigameView3D = VIEW_SCENE.instantiate()
	add_child_autofree(big)
	big.setup(names, 0)
	var expected := SnakeChain.max_pellets_for(12) + SnakeChain.SPILL_HEADROOM
	assert_eq(big._pellet_pool.size(), expected)
	assert_gt(big._pellet_pool.size(), SnakeChain.MAX_ACTIVE_PELLETS + SnakeChain.SPILL_HEADROOM)
