extends GutTest
## Bullet Waltz client view (M10-18): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/bullet_waltz/bullet_waltz_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"bullet_waltz"),
		"res://src/minigames/bullet_waltz/bullet_waltz_view.tscn"
	)


func test_setup_builds_turret_and_bullet_pool() -> void:
	assert_not_null(view.arena.get_node("Turret"))
	assert_not_null(view.rig_for_slot(0))


func test_bullets_show_from_the_pool_and_kos_hide_rigs() -> void:
	(
		view
		. render(
			{
				"players": {0: [1.0, 1.0, 2]},
				"bullets": [[0.5, 0.5], [2.0, -1.0]],
				"out": [[1]],
			}
		)
	)
	assert_eq(view.bullets.size(), 2)
	assert_false(view.rig_for_slot(1).visible, "KO'd players leave the floor")
	assert_true(view.rig_for_slot(0).visible)
	assert_string_contains(view.rig_for_slot(0).display_name, "2")
	view.render({"players": {0: [1.0, 1.0, 0]}, "bullets": [], "out": [[1]]})
	assert_eq(view.bullets.size(), 0, "each snapshot fully replaces the last")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.bullets, [])
