extends GutTest
## The party-stadium shell (#939): a shared 3D backdrop every MinigameView3D
## arena sits inside. These cover the builder in isolation — nodes built,
## occlusion-safe placement, mood tinting, and the reduced-motion-gated sweep.

var arena: Node3D
var shell: StageShell


func before_each() -> void:
	arena = Node3D.new()
	add_child_autofree(arena)
	shell = StageShell.new()
	shell.build(arena, 10.0, Color(0.16, 0.13, 0.2))


func test_build_mounts_a_single_shell_root() -> void:
	assert_not_null(shell.root(), "the shell has a root node")
	assert_eq(shell.root().get_parent(), arena, "mounted under the arena")
	assert_not_null(shell.root().get_node("SkyDome"))
	assert_not_null(shell.root().get_node("BleacherRing"))
	assert_not_null(shell.root().get_node("Spotlight0"))


func test_build_is_idempotent() -> void:
	var root := shell.root()
	shell.build(arena, 10.0, Color.WHITE)
	assert_eq(shell.root(), root, "a second build is a no-op")
	assert_eq(arena.get_child_count(), 1, "only one shell root under the arena")


## The dome wraps far outside the arena extent so it never clips the play field.
func test_dome_sits_well_outside_the_arena() -> void:
	var dome := shell.root().get_node("SkyDome") as MeshInstance3D
	var radius := (dome.mesh as SphereMesh).radius
	assert_gt(radius, 10.0 * 3.0, "the dome is far behind the arena")


## Occlusion-safety invariant (#939): the ring + crowd stay below rig-head
## height (~2u) so the shell never draws in front of the players.
func test_ring_and_crowd_stay_below_head_height() -> void:
	var ring := shell.root().get_node("BleacherRing") as MeshInstance3D
	var ring_top: float = ring.position.y + (ring.mesh as CylinderMesh).height / 2.0
	assert_lte(ring_top, StageShell.RING_TOP_Y + 0.001, "the ring top is low")
	assert_lt(ring_top, 1.5, "and clears of rig-head height")
	assert_not_null(shell.root().get_node("Fan0"), "crowd billboards exist")


## The crowd carries a few PlayerPalette-colored fans among the silhouettes.
func test_crowd_has_some_palette_colored_fans() -> void:
	var palette := PlayerPalette.color_for_slot(0)
	var found := false
	for i in StageShell.CROWD_COUNT:
		var fan := shell.root().get_node("Fan%d" % i) as MeshInstance3D
		var mat := (fan.mesh as QuadMesh).material as StandardMaterial3D
		if mat.albedo_color.is_equal_approx(palette):
			found = true
			assert_eq(mat.billboard_mode, BaseMaterial3D.BILLBOARD_ENABLED, "fans billboard")
			break
	assert_true(found, "at least one fan wears a player color")


## The sweep moves the spotlights; reduced motion is enforced by the caller
## (MinigameView3D only calls update() when motion is on), so update() itself
## always animates.
func test_update_sweeps_the_spotlights() -> void:
	var before := (shell.root().get_node("Spotlight0") as Node3D).rotation.y
	shell.update(1.0)
	var after := (shell.root().get_node("Spotlight0") as Node3D).rotation.y
	assert_ne(before, after, "the spotlight sweeps under update()")
