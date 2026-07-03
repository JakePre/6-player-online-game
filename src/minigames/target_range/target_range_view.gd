extends MinigameView3D
## Target Range client view (M4-08, on the M8-01 MinigameView3D tier):
## shooting-gallery targets drift across the far band of the iso arena while
## the shooters stand on a firing line at the near edge. Each player has a
## colored crosshair ring; the local one is predicted from raw input (mouse
## projection onto the floor plane, or stick/WASD nudging) so aiming feels
## instant, and fades while the fire cooldown runs. Scores ride the
## nameplates like Quick Draw's win tallies.

const FIRING_LINE := 6.0
const AIM_SPEED := 12.0
const CROSSHAIR_HEIGHT := 0.15
const COOLDOWN_ALPHA := 0.25

const KIND_COLORS := {
	TargetRange.Kind.STANDARD: Color(0.85, 0.3, 0.25),
	TargetRange.Kind.SMALL: Color(0.3, 0.6, 0.95),
	TargetRange.Kind.GOLD: Color(0.95, 0.8, 0.2),
}

var _aim := Vector2.ZERO
var _scores := {}
var _cooldown := 0.0

var _target_nodes := {}  # id (int) -> MeshInstance3D
var _crosshairs := {}  # slot (int) -> MeshInstance3D
var _aim_beams := {}  # slot (int) -> MeshInstance3D (#214 aim lines)


func _arena_half() -> float:
	return TargetRange.ARENA_HALF


func _setup_3d() -> void:
	_line_up_rigs()
	for slot: int in names:
		_crosshairs[slot] = _build_crosshair(slot)


func _physics_process(delta: float) -> void:
	var nudge := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if nudge != Vector2.ZERO:
		_aim += nudge * AIM_SPEED * delta
		_aim = _aim.clamp(
			Vector2(-TargetRange.ARENA_HALF, -TargetRange.ARENA_HALF),
			Vector2(TargetRange.ARENA_HALF, TargetRange.ARENA_HALF)
		)
	NetManager.send_match_input({"ax": _aim.x, "ay": _aim.y})


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"action_primary"):
		NetManager.send_match_input({"fire": true})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_aim_at_mouse()
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_aim_at_mouse()
		NetManager.send_match_input({"ax": _aim.x, "ay": _aim.y, "fire": true})


func _render_3d(game: Dictionary) -> void:
	var previous: int = _scores.get(my_slot, 0)
	_scores = game.get("scores", {})
	_cooldown = float(game.get("cd", {}).get(my_slot, 0.0))
	if int(_scores.get(my_slot, 0)) > previous:
		play_sfx(&"coin")
	_update_targets(game.get("targets", []))
	_update_crosshairs(game.get("aims", {}))
	_update_rigs()


## Shooters stand on a fixed firing line facing the gallery; there is no
## body movement in this game, so rigs are placed once.
func _line_up_rigs() -> void:
	var sorted: Array = names.keys()
	sorted.sort()
	for i in sorted.size():
		var rig := rig_for_slot(sorted[i])
		if rig == null:
			continue
		rig.position = to_arena(Vector2((i - (sorted.size() - 1) / 2.0) * 2.0, FIRING_LINE))
		rig.rotation.y = PI  # face the target band


## Projects the mouse ray onto the arena floor plane (y = 0). The container
## stretches 1:1 over this Control, so local mouse coords are viewport coords.
func _aim_at_mouse() -> void:
	var camera := arena.get_node("IsoCameraRig/Camera3D") as Camera3D
	var mouse := get_local_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if absf(direction.y) < 0.0001:
		return
	var hit := origin - direction * (origin.y / direction.y)
	_aim = Vector2(hit.x, hit.z).clamp(
		Vector2(-TargetRange.ARENA_HALF, -TargetRange.ARENA_HALF),
		Vector2(TargetRange.ARENA_HALF, TargetRange.ARENA_HALF)
	)


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
			(_target_nodes[id] as MeshInstance3D).queue_free()
			_target_nodes.erase(id)


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
