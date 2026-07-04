extends GutTest
## Fish Frenzy client view (#183): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/fish_frenzy/fish_frenzy_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"fish_frenzy"),
		"res://src/minigames/fish_frenzy/fish_frenzy_view.tscn"
	)


func test_setup_builds_catch_line_and_rigs() -> void:
	assert_not_null(view.arena.get_node("CatchLine"))
	assert_not_null(view.rig_for_slot(0))


func test_render_places_players_by_lane_and_shows_streaks() -> void:
	view.render({"players": {0: [2, 7, 6]}, "fish": [[0, 0.9]], "swim_sec": 1.8})
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.z, 2.4, 0.001, "lane 2 sits one spacing below center")
	assert_string_contains(rig.display_name, "7")
	assert_string_contains(rig.display_name, "6")
	assert_eq(view.fish.size(), 1)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.fish, [])


## M13-19: fish-shaped bodies that swim (wag driven by replicated progress),
## and a splash + sparkle at the line on every catch.
func test_fish_have_bodies_and_tails_that_wag() -> void:
	view.render({"players": {}, "fish": [[1, 0.9]], "swim_sec": 1.8})
	var fish_node: Node3D = view.arena.get_node("Fish0")
	assert_true(fish_node.visible)
	assert_not_null(fish_node.get_node("Body"))
	assert_not_null(fish_node.get_node("Tail"))
	var wag_a: float = fish_node.rotation.y
	view.render({"players": {}, "fish": [[1, 0.8]], "swim_sec": 1.8})
	var wag_b: float = fish_node.rotation.y
	assert_ne(wag_a, wag_b, "the wag advances with the replicated progress")
	view.render({"players": {}, "fish": [], "swim_sec": 1.8})
	assert_false(fish_node.visible)


func test_catch_fires_splash_and_sparkle_once_seeded() -> void:
	view.render({"players": {0: [1, 3, 0]}, "fish": [], "swim_sec": 1.8})
	var before: int = view.arena.get_child_count()
	view.render({"players": {0: [1, 3, 0]}, "fish": [], "swim_sec": 1.8})
	assert_eq(view.arena.get_child_count(), before, "no catch, no FX")
	view.render({"players": {0: [1, 4, 1]}, "fish": [], "swim_sec": 1.8})
	assert_eq(view.arena.get_child_count(), before + 2, "catch = splash + sparkle at the line")
