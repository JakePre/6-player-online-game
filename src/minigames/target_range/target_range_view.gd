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


func _arena_half() -> float:
	return TargetRange.arena_half_for(names.size())


func _setup_3d() -> void:
	_half = TargetRange.arena_half_for(names.size())
	_line_up_rigs()
	for slot: int in names:
		_crosshairs[slot] = _build_crosshair(slot)


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
		play_sfx(&"coin")
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
		var id := int(entry[0])
		seen[id] = true
		var node: MeshInstance3D = _target_nodes.get(id)
		if node == null:
			node = _build_target(id, float(entry[3]), int(entry[4]))
		node.position = Vector3(float(entry[1]), float(entry[3]), float(entry[2]))
	for id: int in _target_nodes.keys():
		if not seen.has(id):
			var node := _target_nodes[id] as MeshInstance3D
			# On-screen removal means it was shot; a target recycled off the far
			# edge (sim drift) leaves from beyond the arena and pops nothing.
			if absf(node.position.x) <= _half:
				var tint: Color = _target_colors.get(id, KIND_COLORS[TargetRange.Kind.STANDARD])
				fx_burst(Vector2(node.position.x, node.position.z), tint, node.position.y)
			node.queue_free()
			_target_nodes.erase(id)
			_target_colors.erase(id)


func _update_crosshairs(aim_list: Dictionary) -> void:
	for slot: int in _crosshairs:
		var ring: MeshInstance3D = _crosshairs[slot]
		# The local crosshair follows raw input for instant feel; remote ones
		# follow the replicated aim.
		var aim := _aim
		if slot != my_slot:
			var wire: Array = aim_list.get(slot, [0.0, 0.0])
			aim = Vector2(float(wire[0]), float(wire[1]))
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
	play_sfx(&"click")
	fx_burst(Vector2(rig.position.x, rig.position.z), player_color(my_slot), 0.9)
	var from := rig.position + Vector3(0.0, 0.9, 0.0)
	var to := to_arena(_aim, CROSSHAIR_HEIGHT)
	var length := from.distance_to(to)
	if length < 0.1:
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
