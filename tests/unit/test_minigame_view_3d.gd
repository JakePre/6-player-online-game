extends GutTest
## MinigameView3D base behavior (#590): the arena background is transparent
## by default so the shared drifting-blob backdrop (M16-03's MenuBackdrop)
## shows through instead of the old flat grey. Any concrete 3D game view
## exercises the base — King of the Hill is a plain, already-tested fixture
## with no extra setup requirements (same choice test_minigame_view.gd made).

# Real in-repo tile dimensions (confirmed via mesh.get_aabb()), fed to the pure
# _floor_tiling() helper so the tiling math is checked deterministically — the
# headless RenderingServer doesn't retain MultiMesh instance transforms.
const PLATFORM_AABB := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 0.195, 1.0))
const GRASS_LOW_AABB := AABB(Vector3(-0.541, 0.0, -0.541), Vector3(1.082, 0.5, 1.082))

var view: MinigameView3D


## A tint-only game over the default white platform tile, so `albedo == tint`
## holds. Self-contained so the test never breaks when a real game changes its
## declared tint (or, per #813, swaps its tile mesh — which King of the Hill,
## the old fixture here, now does).
class _TintedView:
	extends MinigameView3D

	func _floor_tint() -> Color:
		return Color(0.5, 0.7, 0.9)


## Overrides the tile mesh (#813) to a thick grass block instead of the flat
## platform — a genuinely different footprint (~1.08) and height (0.5), so the
## measured-tiling path is exercised, not just a same-geometry material swap.
class _GrassTileView:
	extends MinigameView3D

	func _floor_tile_scene() -> PackedScene:
		return preload("res://assets/environment/kenney_platformer_kit/block-grass-low.glb")


## A bare MinigameView3D instance — every registered game now declares its own
## _floor_tint() (#589), so the true "un-overridden" fixture is the base class
## itself, not any particular game.
func _plain_view() -> MinigameView3D:
	return MinigameView3D.new()


func _add_view(v: MinigameView3D) -> MinigameView3D:
	add_child_autofree(v)
	v.setup({0: "Alice"}, 0)
	return v


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
	var other: MinigameView3D = _plain_view()
	add_child_autofree(other)
	other.setup({0: "Alice"}, 0)
	var theirs := (other.arena.get_node("Floor") as MultiMeshInstance3D).material_override
	assert_ne(mine, theirs, "each view owns its own floor material")


## A _floor_tint() override multiplies over the default tile's white native
## albedo, so the tinted material albedo equals the tint exactly.
func test_floor_tint_override_recolors_the_material() -> void:
	var tinted := _add_view(_TintedView.new())
	assert_eq(tinted._floor_tint(), Color(0.5, 0.7, 0.9), "the fixture declares its tint")
	var albedo := _floor_albedo(tinted)
	assert_almost_eq(albedo.r, 0.5, 0.01)
	assert_almost_eq(albedo.g, 0.7, 0.01)
	assert_almost_eq(albedo.b, 0.9, 0.01)


func test_untinted_game_keeps_the_neutral_white_floor() -> void:
	var plain := _add_view(_plain_view())
	assert_eq(plain._floor_tint(), Color.WHITE, "default tint is neutral")
	var albedo := _floor_albedo(plain)
	assert_almost_eq(albedo.r, 1.0, 0.01, "un-overridden floor stays the native white")
	assert_almost_eq(albedo.g, 1.0, 0.01)
	assert_almost_eq(albedo.b, 1.0, 0.01)


# --- Floor tile mesh (#813) ---------------------------------------------------


func _floor_mesh(v: MinigameView3D) -> Mesh:
	return (v.arena.get_node("Floor") as MultiMeshInstance3D).multimesh.mesh


func test_floor_tile_scene_defaults_to_the_platform_tile() -> void:
	var plain := _add_view(_plain_view())
	assert_eq(
		plain._floor_tile_scene(),
		MinigameView3D.FLOOR_TILE_SCENE,
		"un-overridden games tile from the shared platform mesh"
	)


## A game that overrides _floor_tile_scene() lays a different mesh than the
## default — the whole point of the hook.
func test_tile_override_swaps_the_floor_mesh() -> void:
	var plain := _add_view(_plain_view())
	var grass := _add_view(_GrassTileView.new())
	assert_ne(_floor_mesh(grass), _floor_mesh(plain), "the grass game tiles from a different mesh")


## Backward compatibility: the default platform tile tiles exactly as before the
## hook — span 1.0, dropped 0.195 so its top is on y=0, first tile at the edge.
func test_default_tile_tiling_is_unchanged() -> void:
	var t := MinigameView3D._floor_tiling(PLATFORM_AABB, 10.0)
	assert_almost_eq(float(t.span), 1.0, 0.001, "flat 1x1 footprint")
	assert_almost_eq(float(t.top_y), 0.195, 0.001, "dropped by the platform tile's thickness")
	assert_eq(int(t.count), 20, "20 tiles cover a 20-unit span")
	assert_almost_eq(
		float(t.start), -9.5, 0.001, "first tile centered a half-tile in from the edge"
	)


## The load-bearing invariant: a thicker tile (grass block, top 0.5) drops by
## its OWN height so its top still lands on y=0, and tiles at its own footprint.
func test_thicker_tile_drops_by_its_own_height() -> void:
	var t := MinigameView3D._floor_tiling(GRASS_LOW_AABB, 10.0)
	assert_almost_eq(float(t.span), 1.082, 0.001, "tiles at the grass block's true footprint")
	assert_almost_eq(float(t.top_y), 0.5, 0.001, "sinks by the block's full height, not 0.195")
	assert_eq(int(t.count), 19, "a wider tile needs fewer to span the arena")


## A degenerate measurement (a mesh that reports no footprint/height) falls back
## to the default tile's dimensions instead of dividing by zero into an infinite
## tile count.
func test_degenerate_tile_falls_back_to_default_dimensions() -> void:
	var t := MinigameView3D._floor_tiling(AABB(), 10.0)
	assert_almost_eq(float(t.span), MinigameView3D.FLOOR_TILE_SIZE, 0.001, "falls back to 1.0 span")
	assert_almost_eq(
		float(t.top_y), MinigameView3D.FLOOR_TILE_THICKNESS, 0.001, "falls back to the default drop"
	)


## End to end (mesh readback works headless even though transforms don't): a
## thick grass tile actually reports the 0.5 height the drop math relies on.
func test_grass_tile_mesh_reports_its_real_height() -> void:
	var grass := _add_view(_GrassTileView.new())
	var aabb := _floor_mesh(grass).get_aabb()
	assert_almost_eq(
		aabb.size.y, 0.5, 0.01, "the grass block is 0.5 tall, not the platform's 0.195"
	)
	assert_gt(aabb.size.x, 1.0, "and its footprint is wider than the flat platform tile")
