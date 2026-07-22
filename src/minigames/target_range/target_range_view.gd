extends MinigameView3D
## Target Range client view (M4-08, on the M8-01 MinigameView3D tier):
## shooting-gallery targets drift across the far band of the iso arena while
## the shooters stand on a firing line at the near edge. Each player has a
## colored crosshair ring; the local one is predicted from raw input (mouse
## projection onto the floor plane, or stick/WASD nudging) so aiming feels
## instant, and fades while the fire cooldown runs. Scores ride the
## nameplates like Quick Draw's win tallies.

const FIRING_LINE := 6.0
## Depth between shooter ranks when the firing line wraps (M15-07).
const RANK_STEP := 1.5
const AIM_SPEED := 12.0
const CROSSHAIR_HEIGHT := 0.15
const COOLDOWN_ALPHA := 0.25
## FX pass (M13-17): a fired-shot tracer streak and a burst when a target breaks.
const TRACER_SEC := 0.12
const TRACER_THICKNESS := 0.05

const KIND_COLORS := {
	TargetRange.Kind.STANDARD: Color(0.85, 0.3, 0.25),
	TargetRange.Kind.SMALL: Color(0.3, 0.6, 0.95),
	TargetRange.Kind.GOLD: Color(0.95, 0.8, 0.2),
}
## GFX enhancements (#1158): sand-packed floor texture, desert backdrop wall,
## target stands, hit marker decals, and desert rim props.
const SAND_FLOOR := preload("res://assets/generated/textures/sand-packed.png")
const BACKDROP_WALL_TEXTURE := preload("res://assets/generated/textures/castle-stone.png")
const BACKDROP_WALL_HEIGHT := 6.0
const BACKDROP_WALL_Y := -7.0
const TARGET_POLE_RADIUS := 0.04
const HIT_MARKER_FADE_SEC := 0.25
## Desert backdrop rim props (#1158): cacti, rocks, and barrels
## scattered around the arena perimeter.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_nature_kit/cactus_short.glb"),
	preload("res://assets/environment/kenney_nature_kit/cactus_tall.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_smallA.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_smallB.glb"),
	preload("res://assets/environment/kenney_platformer_kit/barrel.glb"),
]
const RIM_PROP_COUNT := 16
const RIM_PROP_SEED := 0xBEEF

var _aim := Vector2.ZERO
var _scores := {}
var _cooldown := 0.0
## This match's scaled gallery half-width (equals the const at <=6 players),
## derived from the head count with the sim's own helper so aim clamps and the
## shot-vs-drift check match the server's wider arena (M15 → 24).
var _half := TargetRange.ARENA_HALF

var _target_nodes := {}  # id (int) -> MeshInstance3D
var _target_colors := {}  # id (int) -> Color (kind tint, for the break burst)
var _crosshairs := {}  # slot (int) -> MeshInstance3D
var _aim_beams := {}  # slot (int) -> MeshInstance3D (#214 aim lines)


## Desert shooting range floor (#1158): sand-packed texture instead of default tiles.
func _build_floor() -> void:
	var half := _arena_half()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(half * 2.0, half * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = SAND_FLOOR
	material.albedo_color = Color(1.0, 0.9, 0.74)
	material.metallic = 0.0
	material.roughness = 0.85
	mesh.material = material
	var floor_node := MeshInstance3D.new()
	floor_node.name = "SandFloor"
	floor_node.mesh = mesh
	floor_node.position.y = -0.01
	arena.add_child(floor_node)


## Warm desert shooting range mood (#1158).
func _mood() -> Color:
	return Color(0.18, 0.12, 0.06).lerp(Color(0.8, 0.7, 0.5), 0.25)


## Tall stone backdrop wall at the far end of the gallery (#1158), so the
## shooting range has a visual end behind the drifting targets.
func _build_backdrop_wall() -> void:
	var half := _half
	var mesh := BoxMesh.new()
	mesh.size = Vector3(half * 2.0, BACKDROP_WALL_HEIGHT, 0.3)
	var material := StandardMaterial3D.new()
	material.albedo_texture = BACKDROP_WALL_TEXTURE
	material.albedo_color = Color(1.0, 0.9, 0.74)
	material.metallic = 0.0
	material.roughness = 0.9
	material.uv1_scale = Vector3(half * 2.0 / 3.0, BACKDROP_WALL_HEIGHT / 3.0, 1.0)
	mesh.material = material
	var wall := MeshInstance3D.new()
	wall.name = "BackdropWall"
	wall.mesh = mesh
	wall.position = Vector3(0.0, BACKDROP_WALL_HEIGHT / 2.0, BACKDROP_WALL_Y)
	arena.add_child(wall)


## Desert range floor (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.9, 0.74)


func _arena_half() -> float:
	return TargetRange.arena_half_for(names.size())


func _setup_3d() -> void:
	_half = TargetRange.arena_half_for(names.size())
	_line_up_rigs()
	for slot: int in names:
		_crosshairs[slot] = _build_crosshair(slot)
	_build_backdrop_wall()
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)


func _physics_process(delta: float) -> void:
	var nudge := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if nudge != Vector2.ZERO:
		_aim += nudge * AIM_SPEED * delta
		_aim = _aim.clamp(Vector2(-_half, -_half), Vector2(_half, _half))
	NetManager.send_match_input({"ax": _aim.x, "ay": _aim.y})


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"action_primary"):
		NetManager.send_match_input({"fire": true})
		_fire_shot()


## Mouse aim/fire is handled in _input, not _unhandled_input (#579): the view
## roots (and the match screen's PlayArea) are default MOUSE_FILTER_STOP Controls
## that swallow mouse motion as GUI input before it ever reaches unhandled input,
## so aiming with the mouse did nothing. _input runs before GUI picking, so the
## events always arrive. Non-mouse events fall through untouched.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_aim_at_mouse()
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_aim_at_mouse()
		NetManager.send_match_input({"ax": _aim.x, "ay": _aim.y, "fire": true})
		_fire_shot()


func _render_3d(game: Dictionary) -> void:
	var previous: int = _scores.get(my_slot, 0)
	_scores = game.get("scores", {})
	_cooldown = float(game.get("cd", {}).get(my_slot, 0.0))
	if int(_scores.get(my_slot, 0)) > previous:
		# Signature cue (#728 Aim & targets batch): a bright target hit, not
		# currency — matches the docs/AUDIO_GUIDE.md `bell` meaning exactly.
		play_sfx(&"bell")
	_update_targets(game.get("targets", []))
	_update_crosshairs(game.get("aims", {}))
	_update_rigs()


## Shooters stand on the firing line facing the gallery; there is no body
## movement in this game, so rigs are placed once. Crowds wrap into extra
## ranks stepping toward the gallery (M15-07) — the front rank keeps the
## classic line, and even three ranks (24 shooters) stay well short of the
## target band (BAND_NEAR is -1; the third rank stands at y = 3).
func _line_up_rigs() -> void:
	var sorted: Array = names.keys()
	sorted.sort()
	var offsets := LaneLayout.row_positions(sorted.size(), 2.0, RANK_STEP)
	for i in sorted.size():
		var rig := rig_for_slot(sorted[i])
		if rig == null:
			continue
		rig.position = to_arena(Vector2(offsets[i].x, FIRING_LINE - offsets[i].y))
		rig.rotation.y = PI  # face the target band


## Aims at the current mouse position. The SubViewportContainer stretches the
## arena viewport 1:1 over this full-rect Control, so the Control-local mouse
## position is also the arena viewport's.
func _aim_at_mouse() -> void:
	_aim = _screen_to_floor(get_local_mouse_position())


## Projects a viewport point through the iso camera onto the arena floor plane
## (y = 0), clamped to the gallery. Pure of mouse state so it is unit-testable.
func _screen_to_floor(point: Vector2) -> Vector2:
	var camera := arena.get_node("IsoCameraRig/Camera3D") as Camera3D
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	if absf(direction.y) < 0.0001:
		return _aim
	var hit := origin - direction * (origin.y / direction.y)
	return Vector2(hit.x, hit.z).clamp(Vector2(-_half, -_half), Vector2(_half, _half))


func _update_targets(target_list: Array) -> void:
	var seen := {}
	for entry: Array in target_list:
		var id := int(entry[TargetRange.TL_ID])
		seen[id] = true
		var node: MeshInstance3D = _target_nodes.get(id)
		if node == null:
			node = _build_target(
				id, float(entry[TargetRange.TL_RADIUS]), int(entry[TargetRange.TL_KIND])
			)
		node.position = Vector3(
			float(entry[TargetRange.TL_X]),
			float(entry[TargetRange.TL_RADIUS]),
			float(entry[TargetRange.TL_Y])
		)
	for id: int in _target_nodes.keys():
		if not seen.has(id):
			var node := _target_nodes[id] as MeshInstance3D
			# On-screen removal means it was shot; a target recycled off the far
			# edge (sim drift) leaves from beyond the arena and pops nothing.
			if absf(node.position.x) <= _half:
				var tint: Color = _target_colors.get(id, KIND_COLORS[TargetRange.Kind.STANDARD])
				fx_burst(Vector2(node.position.x, node.position.z), tint, node.position.y)
				_spawn_hit_marker(Vector2(node.position.x, node.position.z), node.position.y)
			node.queue_free()
			_target_nodes.erase(id)


## Crosshair-pattern hit marker decal at the impact point (#1158): two thin
## white BoxMesh strips crossing at right angles, visible briefly, then fading
## out and freeing themselves. Fire-and-forget.
func _spawn_hit_marker(world_pos: Vector2, height: float) -> void:
	if ArenaFX.reduced_motion:
		return
	var arm_length := 0.15
	var arm_width := 0.03
	var cross := Node3D.new()
	cross.name = "HitMarker"
	cross.position = to_arena(world_pos, height + 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for angle: float in [0.0, PI / 2.0]:
		var arm := BoxMesh.new()
		arm.size = Vector3(arm_length, arm_width, arm_width)
		if angle > 0.0:
			arm.size = Vector3(arm_width, arm_width, arm_length)
		arm.material = mat
		var arm_node := MeshInstance3D.new()
		arm_node.name = "Arm%d" % int(angle * 2.0 / PI)
		arm_node.mesh = arm
		arm_node.rotation.y = angle
		cross.add_child(arm_node)
	arena.add_child(cross)
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, HIT_MARKER_FADE_SEC)
	tween.tween_callback(cross.queue_free)


func _update_crosshairs(aim_list: Dictionary) -> void:
	for slot: int in _crosshairs:
		var ring: MeshInstance3D = _crosshairs[slot]
		# The local crosshair follows raw input for instant feel; remote ones
		# follow the replicated aim.
		var aim := _aim
		if slot != my_slot:
			var wire: Array = aim_list.get(slot, [0.0, 0.0])
			aim = Vector2(float(wire[TargetRange.AM_X]), float(wire[TargetRange.AM_Y]))
		ring.position = to_arena(aim, CROSSHAIR_HEIGHT)
		_update_aim_beam(slot, ring)
		if slot == my_slot:
			var material := ring.mesh.surface_get_material(0) as StandardMaterial3D
			material.albedo_color.a = COOLDOWN_ALPHA if _cooldown > 0.0 else 1.0


func _update_rigs() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		# Rigs are pooled hidden (#601); this stationary view places them once in
		# _line_up_rigs and never calls update_rig, so without this reveal the
		# shooters never appear at all (#790). Reveal only the round's actual
		# participants (the snapshot's scores keys), so a disconnected member's
		# rig stays hidden — the same snapshot-driven reveal Quick Draw uses (#780).
		if _scores.has(slot):
			reveal_rig(slot)
		rig.display_name = "%s  %d" % [player_name(slot), int(_scores.get(slot, 0))]


func _build_target(id: int, radius: float, kind: int) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var material := StandardMaterial3D.new()
	var color: Color = KIND_COLORS.get(kind, KIND_COLORS[TargetRange.Kind.STANDARD])
	_target_colors[id] = color
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.4
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "Target%d" % id
	node.mesh = mesh
	# Target stand pole (#1158): thin cylinder from floor to sphere center,
	# tinted the target kind color so it reads as one unit.
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = TARGET_POLE_RADIUS
	pole_mesh.bottom_radius = TARGET_POLE_RADIUS
	pole_mesh.height = radius
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = color.darkened(0.3)
	pole_mesh.material = pole_mat
	var pole := MeshInstance3D.new()
	pole.name = "Pole%d" % id
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, -radius / 2.0, 0.0)
	node.add_child(pole)
	# Worth is invisible from color alone (#214): float the point value over
	# every target, tinted to its kind.
	var value := Label3D.new()
	value.text = "+%d" % int(TargetRange.KIND_STATS[kind].value)
	value.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	value.no_depth_test = true
	value.fixed_size = true
	value.pixel_size = 0.002
	value.font_size = 40
	value.outline_size = 14
	value.modulate = color.lightened(0.35)
	value.position = Vector3(0.0, radius + 0.55, 0.0)
	node.add_child(value)
	arena.add_child(node)
	_target_nodes[id] = node
	return node


func _build_crosshair(slot: int) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	# Big enough to find at camera distance (#214); your own is largest.
	mesh.inner_radius = 0.42 if slot == my_slot else 0.36
	mesh.outer_radius = 0.62 if slot == my_slot else 0.52
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = player_color(slot)
	material.emission_enabled = true
	material.emission = player_color(slot)
	mesh.material = material
	var ring := MeshInstance3D.new()
	ring.name = "Crosshair%d" % slot
	ring.mesh = mesh
	ring.position = to_arena(Vector2.ZERO, CROSSHAIR_HEIGHT)
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.09
	dot_mesh.height = 0.18
	dot_mesh.material = material
	var dot := MeshInstance3D.new()
	dot.mesh = dot_mesh
	ring.add_child(dot)
	arena.add_child(ring)
	_aim_beams[slot] = _build_aim_beam(slot)
	return ring


## Thin player-colored beam from the shooter to their reticle, so whose aim
## is whose reads instantly (#214). The local player's is the most opaque.
func _build_aim_beam(slot: int) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.06, 1.0)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var color := player_color(slot)
	color.a = 0.7 if slot == my_slot else 0.3
	material.albedo_color = color
	mesh.material = material
	var beam := MeshInstance3D.new()
	beam.name = "AimBeam%d" % slot
	beam.mesh = mesh
	arena.add_child(beam)
	return beam


func _update_aim_beam(slot: int, ring: MeshInstance3D) -> void:
	var beam: MeshInstance3D = _aim_beams.get(slot)
	var rig := rig_for_slot(slot)
	if beam == null or rig == null:
		return
	var from := rig.position + Vector3(0.0, 0.9, 0.0)
	var to := ring.position
	var length := from.distance_to(to)
	if length < 0.1:
		beam.visible = false
		return
	beam.visible = true
	beam.look_at_from_position((from + to) / 2.0, to, Vector3.UP)
	beam.scale = Vector3(1.0, 1.0, length)


## A bright player-colored streak from the shooter to where they just fired,
## a fraction of a second long (M13-17). Fire-and-forget: it fades and frees
## itself, so this stays a one-file view change.
## Fire feedback so it's obvious a shot went off (#579): a sharp cue, a muzzle
## flash at the shooter, and the tracer streak to the aim point.
func _fire_shot() -> void:
	var rig := rig_for_slot(my_slot)
	if rig == null:
		return
	# Signature cue (#728): the gallery gunshot, not a UI click.
	play_sfx(&"laser")
	fx_burst(Vector2(rig.position.x, rig.position.z), player_color(my_slot), 0.9)
	var from := rig.position + Vector3(0.0, 0.9, 0.0)
	var to := to_arena(_aim, CROSSHAIR_HEIGHT)
	var length := from.distance_to(to)
	if length < 0.1 or ArenaFX.reduced_motion:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(TRACER_THICKNESS, TRACER_THICKNESS, length)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = player_color(my_slot)
	mesh.material = material
	var tracer := MeshInstance3D.new()
	tracer.name = "Tracer"
	tracer.mesh = mesh
	tracer.look_at_from_position((from + to) / 2.0, to, Vector3.UP)
	arena.add_child(tracer)
	var tween := tracer.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, TRACER_SEC)
	tween.tween_callback(tracer.queue_free)
