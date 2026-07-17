extends MinigameView3D
## Putt Panic client view (M14-08): renders the shared green — cup, static
## blocks, the sliding bar, and every player's ball — plus a local aim line
## and power meter. The local player aims with the stick/WASD, holds to charge,
## releases to putt (only while their ball is at rest). Renders get_snapshot().

const BLOCK_COLOR := Color(0.3, 0.5, 0.32)
const BAR_COLOR := Color(0.85, 0.5, 0.3)
const CUP_COLOR := Color(0.05, 0.05, 0.06)
const CUP_RING_COLOR := Color(0.95, 0.85, 0.3)
const AIM_COLOR := Color(1.0, 1.0, 1.0, 0.7)
## Seconds of held charge for a full-power putt.
const CHARGE_SEC := 1.1
## Real flagstick model (#793/#911, MDL-008): base-pivoted, planted right at
## the cup — a real mini-golf hole always has one, and the sim never had a
## flag before this, only the flat hole + ring.
const FLAGSTICK_SCENE := preload("res://assets/generated/models/golf-flagstick.glb")
## Course-pool names (#1071), keyed by PuttPanic.Course — shown as a status
## line so playtesters can tell which archetype the round seeded.
const COURSE_NAMES := {
	PuttPanic.Course.OPEN_GREEN: "Open Green",
	PuttPanic.Course.WINDMILL: "Windmill",
	PuttPanic.Course.PILLAR_RING: "Pillar Ring",
	PuttPanic.Course.BUMPER_FIELD: "Bumper Field",
}

var players := {}

var _balls := {}  # slot -> MeshInstance3D
var _bar: MeshInstance3D
var _aim_line: MeshInstance3D
var _power_bar: ProgressBar
var _charge := 0.0
var _charging := false
var _sunk_seen := {}
## The course is seeded per round (#793), so it's built from the first snapshot
## that carries it (like KotH's pillars) rather than from consts. _cup caches the
## replicated cup for the hole-out burst.
var _course_built := false
var _cup := Vector2.ZERO


## A real putting green (#813): the Kenney grass block replaces the grey
## platform and carries its own color, so the old pastel-green tint (#589)
## approximating one is gone.
func _floor_tile_scene() -> PackedScene:
	return preload("res://assets/environment/kenney_platformer_kit/block-grass.glb")


func _arena_half() -> float:
	return PuttPanic.ARENA_HALF + 1.0


func _setup_3d() -> void:
	# The cup/blocks/bar are seeded per round (#793) and built from the first
	# snapshot; balls and the aim UI are course-independent, so build them now.
	_build_balls()
	_build_aim_and_meter()


func _process(delta: float) -> void:
	var state: Array = players.get(my_slot, [])
	var can_putt := (
		state.size() >= PuttPanic.PS_COUNT
		and int(state[PuttPanic.PS_SUNK]) == 0
		and int(state[PuttPanic.PS_AT_REST]) == 1
	)
	if not can_putt:
		_charging = false
		_charge = 0.0
		_update_aim_visual(false)
		return
	var aim := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if aim.length() > 0.1:
		NetManager.send_match_input({"ax": aim.x, "ay": aim.y})
	if Input.is_action_just_pressed(&"action_primary"):
		_charging = true
		_charge = 0.0
	if _charging:
		_charge = minf(1.0, _charge + delta / CHARGE_SEC)
	if _charging and Input.is_action_just_released(&"action_primary"):
		NetManager.send_match_input({"putt": true, "power": _charge})
		_charging = false
		_charge = 0.0
	_update_aim_visual(true)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	if not _course_built and game.has("cup"):
		_build_course(game)
	var bar: Array = game.get("bar", [])
	if _bar != null and bar.size() >= 2:
		_bar.position = to_arena(Vector2(float(bar[0]), float(bar[1])), 0.35)
	for slot: int in players:
		var state: Array = players[slot]
		var ball: MeshInstance3D = _balls.get(slot)
		if ball == null:
			continue
		ball.position = to_arena(
			Vector2(float(state[PuttPanic.PS_X]), float(state[PuttPanic.PS_Y])),
			PuttPanic.BALL_RADIUS
		)
		var just_sunk := int(state[PuttPanic.PS_SUNK]) == 1
		if just_sunk and not bool(_sunk_seen.get(slot, false)):
			fx_burst(_cup, CUP_RING_COLOR, 0.6)
			# Signature cue (#728, docs/AUDIO_GUIDE.md — Water): a sunk putt is
			# a target hit, not currency — `bell`'s literal meaning.
			play_sfx(&"bell")
		_sunk_seen[slot] = just_sunk
		var rig := rig_for_slot(slot)
		if rig != null:
			update_rig(slot, Vector2(float(state[PuttPanic.PS_X]), -8.5))  # rigs watch from the tee edge
			rig.display_name = "%s  %d" % [player_name(slot), int(state[PuttPanic.PS_STROKES])]


## Build the seeded course from the first snapshot that carries it (#793): the
## cup, the two gate blocks, and the sliding bar — all replicated so the client
## draws exactly the layout the server generated.
func _build_course(game: Dictionary) -> void:
	_course_built = true
	var cup: Array = game.get("cup", [0.0, 6.5])
	_cup = Vector2(float(cup[0]), float(cup[1]))
	_build_cup(_cup)
	for block: Array in game.get("blocks", []):
		if block.size() < 4:
			continue
		var node := _box(Vector3(float(block[2]) * 2.0, 0.7, float(block[3]) * 2.0), BLOCK_COLOR)
		node.position = to_arena(Vector2(float(block[0]), float(block[1])), 0.35)
		arena.add_child(node)
	var bar: Array = game.get("bar", [0.0, 3.6, 1.6, 0.5])
	var bar_half_x := float(bar[2]) if bar.size() >= 4 else 1.6
	var bar_half_y := float(bar[3]) if bar.size() >= 4 else 0.5
	_bar = _box(Vector3(bar_half_x * 2.0, 0.7, bar_half_y * 2.0), BAR_COLOR)
	_bar.name = "Bar"
	_bar.position = to_arena(Vector2(float(bar[0]), float(bar[1])), 0.35)
	arena.add_child(_bar)
	# Which archetype this round seeded (#1071) — small, but it lets a
	# playtester name what they're looking at.
	if game.has("course"):
		var label := make_status_label(&"CourseLabel", PartyTheme.SIZE_OVERLAY_BODY)
		label.text = "Hole: %s" % COURSE_NAMES.get(int(game.course), "?")


func _build_cup(cup: Vector2) -> void:
	var hole := _disc(PuttPanic.CUP_RADIUS, CUP_COLOR, 0.02)
	hole.position = to_arena(cup, 0.02)
	arena.add_child(hole)
	var ring := _disc(PuttPanic.CUP_RADIUS * 1.3, CUP_RING_COLOR, 0.01, true)
	ring.position = to_arena(cup, 0.01)
	arena.add_child(ring)
	var flagstick := FLAGSTICK_SCENE.instantiate() as Node3D
	flagstick.name = "Flagstick"
	flagstick.position = to_arena(cup, 0.0)
	arena.add_child(flagstick)


func _disc(radius: float, color: Color, height: float, emissive := false) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.6
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node


func _build_balls() -> void:
	for slot: int in names:
		var mesh := SphereMesh.new()
		mesh.radius = PuttPanic.BALL_RADIUS
		mesh.height = PuttPanic.BALL_RADIUS * 2.0
		var material := StandardMaterial3D.new()
		material.albedo_color = player_color(slot)
		material.emission_enabled = true
		material.emission = player_color(slot)
		material.emission_energy_multiplier = 0.3
		mesh.material = material
		var node := MeshInstance3D.new()
		node.name = "Ball%d" % slot
		node.mesh = mesh
		arena.add_child(node)
		_balls[slot] = node


func _build_aim_and_meter() -> void:
	_aim_line = _box(Vector3(0.08, 0.08, 1.0), AIM_COLOR)
	_aim_line.name = "AimLine"
	_aim_line.visible = false
	arena.add_child(_aim_line)

	_power_bar = ProgressBar.new()
	_power_bar.name = "PowerBar"
	_power_bar.show_percentage = false
	_power_bar.custom_minimum_size = Vector2(220.0, 18.0)
	_power_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_power_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_power_bar.position.y = -46.0
	_power_bar.visible = false
	add_child(_power_bar)


## Points the aim line from the local ball along the aimed direction, its
## length growing with the current charge; the meter mirrors the charge.
func _update_aim_visual(active: bool) -> void:
	if _aim_line == null:
		return
	var state: Array = players.get(my_slot, [])
	if not active or state.size() < PuttPanic.PS_COUNT:
		_aim_line.visible = false
		_power_bar.visible = false
		return
	var ball := Vector2(float(state[PuttPanic.PS_X]), float(state[PuttPanic.PS_Y]))
	var aim := Vector2(float(state[PuttPanic.PS_AIM_X]), float(state[PuttPanic.PS_AIM_Y]))
	var length := 1.0 + _charge * 3.0
	_aim_line.visible = true
	_aim_line.mesh.size = Vector3(0.08, 0.08, length)
	_aim_line.position = to_arena(ball + aim * length * 0.5, 0.15)
	_aim_line.rotation.y = atan2(aim.x, aim.y)
	_power_bar.visible = true
	_power_bar.value = _charge * 100.0
