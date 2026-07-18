class_name StageShell
extends RefCounted
## The party-stadium shell (#939): one shared 3D environment every
## MinigameView3D arena sits inside, replacing the bare grey void with a
## framed "game show" backdrop. Primitive-first (owner-approved concept): a
## warm gradient sky dome, a distant low bleacher ring, silhouette crowd
## billboards, and slow emissive spotlight cones — all tinted from the game's
## mood color. Pure presentation: no snapshot/sim impact, zero per-game code
## (MinigameView3D mounts it with hook defaults that cover every game).
##
## Occlusion-safe by construction: the dome is far behind, and the ring +
## crowd sit low (top below rig-head height) and outside the arena, so nothing
## here ever draws in front of the players. Sized off the arena extent so it
## clears every game's ARENA_HALF including M15 head-count scaling.

## Multipliers on the arena extent: the dome wraps far behind, the ring frames
## just outside the play field, the crowd rides the ring.
const DOME_RADIUS_MULT := 4.5
const RING_RADIUS_MULT := 1.7
const RING_HEIGHT := 1.0
## The ring top sits at this world-y — below a standing rig's head (~2u) so it
## never occludes gameplay from the front.
const RING_TOP_Y := 0.4
const CROWD_COUNT := 28
const CROWD_SIZE := Vector2(0.7, 1.0)
const SPOTLIGHT_COUNT := 3
const SPOTLIGHT_SWEEP_SPEED := 0.35

var _root: Node3D
var _spotlights: Array[Node3D] = []
var _crowd: Array[Node3D] = []
var _sweep := 0.0


## Build the shell under `arena`, framing an arena of half-extent `extent`,
## themed from `mood` (a warm-dark base color). Idempotent per instance.
func build(arena: Node3D, extent: float, mood: Color) -> void:
	if _root != null:
		return
	_root = Node3D.new()
	_root.name = "StageShell"
	arena.add_child(_root)
	_build_dome(extent, mood)
	_build_ring(extent, mood)
	_build_crowd(extent, mood)
	_build_spotlights(extent, mood)


## Slow spotlight sweep + gentle crowd sway. The caller gates this on
## ArenaFX.reduced_motion (M12-03): under reduced motion it is never called,
## so the shell holds a calm static pose.
func update(delta: float) -> void:
	_sweep += delta * SPOTLIGHT_SWEEP_SPEED
	for i in _spotlights.size():
		_spotlights[i].rotation.y = sin(_sweep + float(i) * 2.1) * 0.5
	for i in _crowd.size():
		var bob := sin(_sweep * 2.0 + float(i) * 0.7) * 0.05
		_crowd[i].position.y = RING_TOP_Y + bob


func root() -> Node3D:
	return _root


## The sky: a big inverted sphere in a warm dark tone, with a brighter horizon
## band cylinder for a cheap gradient read. Unshaded + cull-disabled so we see
## its inner face behind the arena.
func _build_dome(extent: float, mood: Color) -> void:
	var radius := extent * DOME_RADIUS_MULT
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	sphere.material = _unshaded(_dome_top(mood), true)
	var dome := MeshInstance3D.new()
	dome.name = "SkyDome"
	dome.mesh = sphere
	_root.add_child(dome)
	# A brighter horizon band just above the ground line for the gradient read.
	var band := CylinderMesh.new()
	band.top_radius = radius * 0.98
	band.bottom_radius = radius * 0.98
	band.height = extent * 1.5
	band.material = _unshaded(_dome_horizon(mood), true)
	var band_node := MeshInstance3D.new()
	band_node.name = "HorizonBand"
	band_node.mesh = band
	band_node.position.y = extent * 0.4
	_root.add_child(band_node)


## The bleacher wall: a short cylinder ring just outside the arena, its top
## kept at RING_TOP_Y so it frames from behind without occluding the players.
func _build_ring(extent: float, mood: Color) -> void:
	var radius := extent * RING_RADIUS_MULT
	var wall := CylinderMesh.new()
	wall.top_radius = radius
	wall.bottom_radius = radius
	wall.height = RING_HEIGHT
	wall.material = _unshaded(mood.darkened(0.55), true)
	var node := MeshInstance3D.new()
	node.name = "BleacherRing"
	node.mesh = wall
	node.position.y = RING_TOP_Y - RING_HEIGHT / 2.0
	_root.add_child(node)


## Silhouette crowd: flat dark billboard quads spaced around the ring, a few
## carrying a PlayerPalette-colored dot so the audience reads as fans.
func _build_crowd(extent: float, mood: Color) -> void:
	var radius := extent * RING_RADIUS_MULT
	var dark := mood.darkened(0.75)
	for i in CROWD_COUNT:
		var angle := TAU * float(i) / float(CROWD_COUNT)
		var quad := QuadMesh.new()
		quad.size = CROWD_SIZE
		var tinted := i % 5 == 0
		var color := PlayerPalette.color_for_slot(i % 6) if tinted else dark
		quad.material = _unshaded(color, false)
		var billboard := MeshInstance3D.new()
		billboard.name = "Fan%d" % i
		billboard.mesh = quad
		billboard.position = Vector3(cos(angle) * radius, RING_TOP_Y, sin(angle) * radius)
		var mat := quad.material as StandardMaterial3D
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_root.add_child(billboard)
		_crowd.append(billboard)


## Slow emissive spotlight cones angled in from above the ring.
func _build_spotlights(extent: float, mood: Color) -> void:
	for i in SPOTLIGHT_COUNT:
		var angle := TAU * float(i) / float(SPOTLIGHT_COUNT)
		var pivot := Node3D.new()
		pivot.name = "Spotlight%d" % i
		pivot.position = Vector3(cos(angle) * extent * 1.2, extent * 2.2, sin(angle) * extent * 1.2)
		# Point the cone down-and-inward toward the arena center.
		pivot.look_at_from_position(pivot.position, Vector3.ZERO, Vector3.UP)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = extent * 0.35
		cone.height = extent * 2.0
		var glow := mood.lerp(Color(1.0, 0.95, 0.8), 0.6)
		glow.a = 0.12
		var mat := _unshaded(glow, false)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		cone.material = mat
		var beam := MeshInstance3D.new()
		beam.name = "Beam"
		beam.mesh = cone
		# The cone's local +Y is its length; lay it along the pivot's forward.
		beam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		beam.position = Vector3(0.0, 0.0, -cone.height / 2.0)
		pivot.add_child(beam)
		_root.add_child(pivot)
		_spotlights.append(pivot)


## A warm-dark top tone for the dome, derived from the mood.
func _dome_top(mood: Color) -> Color:
	return mood.darkened(0.72)


## A slightly warmer/brighter horizon tone.
func _dome_horizon(mood: Color) -> Color:
	return mood.darkened(0.5).lerp(Color(0.9, 0.6, 0.4), 0.25)


func _unshaded(color: Color, double_sided: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if double_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
