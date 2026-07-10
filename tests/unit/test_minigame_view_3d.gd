extends GutTest
## MinigameView3D base behavior (#590): the arena background is transparent
## by default so the shared drifting-blob backdrop (M16-03's MenuBackdrop)
## shows through instead of the old flat grey. Any concrete 3D game view
## exercises the base — King of the Hill is a plain, already-tested fixture
## with no extra setup requirements (same choice test_minigame_view.gd made).

const KOTH_SCENE: PackedScene = preload(
	"res://src/minigames/king_of_the_hill/king_of_the_hill_view.tscn"
)

var view: MinigameView3D


## A bare MinigameView3D instance — every registered game now declares its own
## _floor_tint() (#589), so the true "un-overridden" fixture is the base class
## itself, not any particular game.
func _plain_view() -> MinigameView3D:
	return MinigameView3D.new()


func before_each() -> void:
	view = KOTH_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice"}, 0)


func after_each() -> void:
	# The team-color funnel is static PlayerPalette state (#820) — restore it so
	# a team-snapshot test never bleeds into the next.
	PlayerPalette.clear_team_assignments()


## A mounted 2-player KotH view (rigs need the arena from _ready, so add before
## setup — the same order before_each uses).
func _two_player_view() -> MinigameView3D:
	var v: MinigameView3D = KOTH_SCENE.instantiate()
	add_child_autofree(v)
	v.setup({0: "Alice", 1: "Bob"}, 0)
	return v


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


## King of the Hill overrides _floor_tile_scene() (#813): its arena tiles with
## the Kenney grass block, not the default grey platform, so the fixture proves
## the mesh hook is honored.
func test_floor_tile_scene_override_swaps_the_mesh() -> void:
	var grass_mesh := (view.arena.get_node("Floor") as MultiMeshInstance3D).multimesh.mesh
	var plain_mesh := (
		(_seeded_plain_view().arena.get_node("Floor") as MultiMeshInstance3D).multimesh.mesh
	)
	assert_ne(grass_mesh, plain_mesh, "KotH's grass block is a different mesh than the platform")


## The reason a thick block works without a per-game offset (#813): the builder
## seats each tile at y = -_mesh_top(mesh), so the tile's top surface lands on
## the y=0 floor plane whatever its thickness. _mesh_top reads the mesh's own
## vertices (unlike get_aabb / multimesh transforms, which read 0 in a headless
## run until the RenderingServer has drawn them), so it is the placement math
## that is actually verifiable here.
func test_mesh_top_measures_each_tile_thickness() -> void:
	var platform: Mesh = _tile_mesh("res://assets/environment/kenney_platformer_kit/platform.glb")
	var grass: Mesh = _tile_mesh("res://assets/environment/kenney_platformer_kit/block-grass.glb")
	# The thin default platform vs the full grass block — very different tops, so
	# a fixed offset would sink or float one of them; the per-mesh measure seats
	# both. (These are the exact values _build_floor negates for the instance Y.)
	assert_almost_eq(MinigameView3D._mesh_top(platform), 0.195, 0.01, "thin platform top")
	assert_almost_eq(MinigameView3D._mesh_top(grass), 1.0, 0.01, "full grass block top")


func _tile_mesh(scene_path: String) -> Mesh:
	var tile := (load(scene_path) as PackedScene).instantiate()
	var mi := tile.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mesh := mi.mesh
	tile.free()
	return mesh


func _seeded_plain_view() -> MinigameView3D:
	var plain: MinigameView3D = _plain_view()
	add_child_autofree(plain)
	plain.setup({0: "Alice"}, 0)
	return plain


# --- Team colors (#820) ------------------------------------------------------


## A team-mode snapshot (carrying `teams`) recolors every rig to its team color,
## overriding personal picks — the identity funnel reaches the pooled rigs even
## though they baked player_color at build time (before any snapshot).
func test_team_snapshot_recolors_rigs_by_team() -> void:
	var two := _two_player_view()
	two.render({"teams": [[0], [1]]})
	assert_eq(two.rig_for_slot(0).player_color, PlayerPalette.TEAM_COLORS[0], "slot 0 on team 0")
	assert_eq(two.rig_for_slot(1).player_color, PlayerPalette.TEAM_COLORS[1], "slot 1 on team 1")


## Tug of War's team_a/team_b shape funnels through the same path as `teams`.
func test_tug_of_war_team_shape_is_understood() -> void:
	var two := _two_player_view()
	two.render({"team_a": [0], "team_b": [1]})
	assert_eq(two.rig_for_slot(0).player_color, PlayerPalette.TEAM_COLORS[0])
	assert_eq(two.rig_for_slot(1).player_color, PlayerPalette.TEAM_COLORS[1])


## A solo snapshot (no team key) leaves rigs on their personal colors.
func test_solo_snapshot_leaves_personal_colors() -> void:
	view.render({})
	assert_eq(view.rig_for_slot(0).player_color, PlayerPalette.color_for_slot(0))
	assert_false(PlayerPalette.has_team_assignments(), "no team round in force")


## Leaving the round (the view exits the tree) restores personal identity, so the
## lobby and standings that follow read personal picks — not the last team color.
func test_leaving_a_team_round_restores_personal_identity() -> void:
	var solo: MinigameView3D = KOTH_SCENE.instantiate()
	add_child(solo)
	solo.setup({0: "Alice", 1: "Bob"}, 0)
	solo.render({"teams": [[0], [1]]})
	assert_true(PlayerPalette.has_team_assignments(), "team round is in force while mounted")
	solo.free()
	assert_false(PlayerPalette.has_team_assignments(), "exiting the round restores personal colors")


func test_untinted_game_keeps_the_neutral_white_floor() -> void:
	var plain: MinigameView3D = _plain_view()
	add_child_autofree(plain)
	plain.setup({0: "Alice"}, 0)
	assert_eq(plain._floor_tint(), Color.WHITE, "default tint is neutral")
	var albedo := _floor_albedo(plain)
	assert_almost_eq(albedo.r, 1.0, 0.01, "un-overridden floor stays the native white")
	assert_almost_eq(albedo.g, 1.0, 0.01)
	assert_almost_eq(albedo.b, 1.0, 0.01)
