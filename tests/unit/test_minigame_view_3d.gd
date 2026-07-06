extends GutTest
## MinigameView3D base behavior (#590): the arena background is transparent
## by default so the shared drifting-blob backdrop (M16-03's MenuBackdrop)
## shows through instead of the old flat grey. Any concrete 3D game view
## exercises the base — King of the Hill is a plain, already-tested fixture
## with no extra setup requirements (same choice test_minigame_view.gd made).

## A plain, untinted base-floor 3D view — the default-tint fixture (#589).
const PLAIN_VIEW_SCENE := preload("res://src/minigames/simon_stomp/simon_stomp_view.tscn")

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


# --- Floor variation & tint (#589) -------------------------------------------


func _floor_albedo(v: MinigameView3D) -> Color:
	var mat := (v.arena.get_node("Floor") as MultiMeshInstance3D).material_override
	return (mat as StandardMaterial3D).albedo_color


## The floor material is a per-view duplicate (texture kept), not a shared
## resource — so tinting one game never bleeds into another.
func test_floor_material_is_a_per_view_duplicate() -> void:
	var mine := (view.arena.get_node("Floor") as MultiMeshInstance3D).material_override
	assert_true(mine is StandardMaterial3D, "the floor has a StandardMaterial3D override")
	var other: MinigameView3D = PLAIN_VIEW_SCENE.instantiate()
	add_child_autofree(other)
	other.setup({0: "Alice"}, 0)
	var theirs := (other.arena.get_node("Floor") as MultiMeshInstance3D).material_override
	assert_ne(mine, theirs, "each view owns its own floor material")


## King of the Hill overrides _floor_tint() (moss). The Kenney tile's native
## albedo is white, so the tinted material albedo equals the tint exactly.
func test_floor_tint_override_recolors_the_material() -> void:
	assert_eq(view._floor_tint(), Color(0.85, 0.96, 0.85), "KotH declares its moss tint")
	var albedo := _floor_albedo(view)
	assert_almost_eq(albedo.r, 0.85, 0.01)
	assert_almost_eq(albedo.g, 0.96, 0.01)
	assert_almost_eq(albedo.b, 0.85, 0.01)


func test_untinted_game_keeps_the_neutral_white_floor() -> void:
	var plain: MinigameView3D = PLAIN_VIEW_SCENE.instantiate()
	add_child_autofree(plain)
	plain.setup({0: "Alice"}, 0)
	assert_eq(plain._floor_tint(), Color.WHITE, "default tint is neutral")
	var albedo := _floor_albedo(plain)
	assert_almost_eq(albedo.r, 1.0, 0.01, "un-overridden floor stays the native white")
	assert_almost_eq(albedo.g, 1.0, 0.01)
	assert_almost_eq(albedo.b, 1.0, 0.01)
