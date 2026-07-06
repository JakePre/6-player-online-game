extends GutTest
## MinigameView3D base behavior (#590): the arena background is transparent
## by default so the shared drifting-blob backdrop (M16-03's MenuBackdrop)
## shows through instead of the old flat grey. Any concrete 3D game view
## exercises the base — King of the Hill is a plain, already-tested fixture
## with no extra setup requirements (same choice test_minigame_view.gd made).

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/king_of_the_hill/king_of_the_hill_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice"}, 0)


func test_backdrop_sits_behind_the_arena_viewport() -> void:
	var backdrop := view.get_node("Backdrop")
	assert_true(backdrop is MenuBackdrop)
	var container := view.get_node("Arena3DContainer")
	assert_lt(
		backdrop.get_index(), container.get_index(), "the backdrop draws behind the 3D viewport"
	)


func test_viewport_and_environment_are_transparent_by_default() -> void:
	var viewport := view.get_node("Arena3DContainer/Arena3DViewport") as SubViewport
	assert_true(viewport.transparent_bg, "the viewport lets the backdrop show through")
	var world_env := view.arena.get_node("Environment") as WorldEnvironment
	assert_eq(world_env.environment.background_mode, Environment.BG_CLEAR_COLOR)


## Ambient lighting is set independently of the background — #590 only
## changes what shows behind the arena, never how anything in it is lit.
func test_ambient_lighting_is_unaffected() -> void:
	var world_env := view.arena.get_node("Environment") as WorldEnvironment
	assert_eq(world_env.environment.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)
	assert_almost_eq(world_env.environment.ambient_light_energy, 0.6, 0.001)
