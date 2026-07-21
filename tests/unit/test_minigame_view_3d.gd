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


## #1119: the #939 party-stadium shell is disabled by default — its giant
## dome/band enclosed the shared orthographic camera and occluded the arena
## (invisible characters, missing floor). The hook is off and no shell mounts,
## until the shell is redesigned to frame without wrapping the ortho camera.
func test_stage_shell_is_disabled_by_default() -> void:
	assert_false(view.call(&"_stage_shell_enabled"), "the occluding shell is off (#1119)")
	assert_null(view.arena.get_node_or_null("StageShell"), "so nothing mounts to occlude")


## #939: the mood defaults from the game's floor tint, so every arena gets a
## coherent backdrop; it stays a warm-dark dusk base, never a bright wash.
func test_mood_defaults_from_the_floor_tint() -> void:
	var plain := _plain_view()
	var mood := plain.call(&"_mood") as Color
	assert_lt(mood.v, 0.5, "the mood is a dark dusk base, not a bright field")
	plain.free()


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
	assert_almost_eq(ArenaDresser._mesh_top(platform), 0.195, 0.01, "thin platform top")
	assert_almost_eq(ArenaDresser._mesh_top(grass), 1.0, 0.01, "full grass block top")


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


# --- Rim props (#813) --------------------------------------------------------


## A trivial packed Node3D, so the scatter tests don't depend on any particular
## kit mesh — the helper only cares that it gets an instantiable PackedScene.
func _stub_prop() -> PackedScene:
	var root := Node3D.new()
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


## scatter_rim_props builds a "RimProps" container under the arena holding one
## node per requested prop.
func test_scatter_rim_props_places_the_requested_count() -> void:
	var plain := _seeded_plain_view()
	var container := plain.scatter_rim_props([_stub_prop()], 12, 1)
	assert_eq(container.name, "RimProps")
	assert_eq(container.get_parent(), plain.arena, "props hang off the arena root")
	assert_eq(container.get_child_count(), 12, "one node per requested prop")


## Every prop is ground-seated (base at y=0) and sits outside the play area, so
## scenery can never overlap gameplay — the play half is _arena_half().
func test_rim_props_ring_outside_the_play_area_on_the_ground() -> void:
	var plain := _seeded_plain_view()
	var half := plain._arena_half()
	var container := plain.scatter_rim_props([_stub_prop()], 16, 5)
	for prop: Node3D in container.get_children():
		assert_almost_eq(prop.position.y, 0.0, 0.001, "props sit on the floor plane")
		var ground := Vector2(prop.position.x, prop.position.z).length()
		assert_gte(ground, half, "every prop sits past the play-area edge")


## The layout is seeded: the same seed reproduces the same placement (stable
## frame-to-frame and testable), a different seed moves it.
func test_rim_props_are_deterministic_for_a_seed() -> void:
	var plain := _seeded_plain_view()
	var scenes: Array[PackedScene] = [_stub_prop()]
	var a := plain.scatter_rim_props(scenes, 8, 42)
	var b := plain.scatter_rim_props(scenes, 8, 42)
	var c := plain.scatter_rim_props(scenes, 8, 99)
	assert_eq(
		(a.get_child(0) as Node3D).position,
		(b.get_child(0) as Node3D).position,
		"same seed = same layout"
	)
	assert_ne(
		(a.get_child(0) as Node3D).position,
		(c.get_child(0) as Node3D).position,
		"a different seed moves the ring"
	)


## Degenerate inputs are a no-op container, never a crash.
func test_scatter_rim_props_tolerates_empty_inputs() -> void:
	var plain := _seeded_plain_view()
	assert_eq(plain.scatter_rim_props([], 10, 0).get_child_count(), 0, "no scenes = no props")
	assert_eq(
		plain.scatter_rim_props([_stub_prop()], 0, 0).get_child_count(), 0, "zero count = no props"
	)


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


## #945: the shared cooldown-ring chrome — builds an unshaded torus in the
## given color, seated just above the floor.
func test_make_cooldown_ring_builds_a_seated_unshaded_torus() -> void:
	var ring := view.make_cooldown_ring(Color.RED)
	assert_true(ring.mesh is TorusMesh, "a torus")
	assert_almost_eq(ring.position.y, 0.06, 0.001, "seated just above the floor")
	var mat := (ring.mesh as TorusMesh).material as StandardMaterial3D
	assert_eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(mat.albedo_color, Color.RED)
	ring.free()


## #945: update_cooldown_ring lazily builds under a rig, shrinks while cooling,
## and hides the instant it's ready — driven by a 0..1 fraction.
func test_update_cooldown_ring_builds_shrinks_and_hides() -> void:
	var rig := view.rig_for_slot(0)
	var rings := {}
	# Ready and no ring yet: nothing is built.
	view.update_cooldown_ring(rings, 0, rig, 0.0, Color.RED)
	assert_eq(rings.size(), 0, "no ring built while ready")
	# Just used: builds, shows, at full radius.
	view.update_cooldown_ring(rings, 0, rig, 1.0, Color.RED)
	var ring: MeshInstance3D = rings[0]
	assert_true(ring.visible, "shows while cooling")
	assert_almost_eq((ring.mesh as TorusMesh).outer_radius, 0.7, 0.001, "full at fraction 1")
	# Half-cooled: shrinks.
	view.update_cooldown_ring(rings, 0, rig, 0.5, Color.RED)
	assert_almost_eq(
		(ring.mesh as TorusMesh).outer_radius, 0.525, 0.001, "shrinks with the fraction"
	)
	# Ready again: hidden, ring kept for reuse.
	view.update_cooldown_ring(rings, 0, rig, 0.0, Color.RED)
	assert_false(ring.visible, "hidden the instant it's ready")


# --- Feedback animations framework hook (#1038) ------------------------------


func _particle_count(v: MinigameView3D) -> int:
	var n := 0
	for child in v.arena.get_children():
		if child is CPUParticles3D:
			n += 1
	return n


## play_hit plays the rig's hit reaction (Hit_A) pose-held and puffs an impact.
func test_play_hit_reacts_and_impacts() -> void:
	var v := _two_player_view()
	var before := _particle_count(v)
	v.play_hit(0)
	assert_eq(v.rig_for_slot(0).current_action(), &"hit", "the hit reaction plays")
	assert_true(v.rig_for_slot(0).is_pose_protected(), "and is pose-held so it reads")
	assert_gt(_particle_count(v), before, "an impact puff spawns")


func test_play_hit_is_a_noop_without_a_rig() -> void:
	# slot 5 has no pooled rig in a 2-player view — must not crash.
	view.play_hit(5)
	assert_true(true, "no rig -> no-op")


## A teleport-sized rig jump flashes a departure + arrival cue; the first
## sighting (spawn) and small moves stay silent.
func test_teleport_jump_flashes_arrival_and_departure() -> void:
	var v := _two_player_view()
	v.update_rig(0, Vector2(0.0, 0.0))  # first sighting: seeds, no FX
	var seeded := _particle_count(v)
	v.update_rig(0, Vector2(0.3, 0.0))  # a normal step: no teleport
	assert_eq(_particle_count(v), seeded, "a small move does not flash")
	v.update_rig(0, Vector2(9.0, 0.0))  # > TELEPORT_SNAP_DISTANCE: a warp
	assert_gt(_particle_count(v), seeded, "a teleport-sized jump flashes a cue")


func test_first_rig_sighting_never_flashes_a_teleport() -> void:
	var v := _two_player_view()
	var before := _particle_count(v)
	v.update_rig(1, Vector2(8.0, 8.0))  # far from origin, but first sight
	assert_eq(_particle_count(v), before, "spawning in place is not a teleport")
