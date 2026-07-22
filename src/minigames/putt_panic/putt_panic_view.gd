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
## GFX enhancements (#1149): rim scenery — trees and bushes ring the putting
## green via the shared scatter_rim_props helper, giving a garden-course feel.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_nature_kit/tree_pineRoundA.glb"),
	preload("res://assets/environment/kenney_nature_kit/tree_pineRoundB.glb"),
	preload("res://assets/environment/kenney_nature_kit/tree_pineTallA.glb"),
	preload("res://assets/environment/kenney_nature_kit/plant_bushSmall.glb"),
	preload("res://assets/environment/kenney_nature_kit/plant_bush.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_smallA.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_smallB.glb"),
]
const RIM_PROP_COUNT := 24
const RIM_PROP_SEED := 1149
## Scoreboard constants (#1149): 3D labels floating above the green showing
## strokes per player, so the tally reads from the arena itself.
const SCOREBOARD_HEIGHT := 3.5
const SCOREBOARD_PIXEL_SIZE := 0.003
const SCOREBOARD_FONT_SIZE := 28
## Ball trail (#1149): a small fading disc behind each moving ball so the
## stroke reads as motion, not a teleport.
const TRAIL_DECAY_SEC := 0.4
const TRAIL_DISC_RADIUS := 0.15
const TRAIL_DISC_HEIGHT := 0.01
## Course-specific decoration colors (#1149).
const SAND_TRAP_COLOR := Color(0.76, 0.7, 0.5)
const WATER_HAZARD_COLOR := Color(0.2, 0.35, 0.7, 0.6)
const BUMPER_BODY_COLOR := Color(0.85, 0.3, 0.3)
const BUMPER_RING_COLOR := Color(0.95, 0.85, 0.3)
const WINDMILL_TOWER_COLOR := Color(0.55, 0.5, 0.45)
const WINDMILL_BLADE_COLOR := Color(0.7, 0.65, 0.6)
const CASTLE_STONE := preload("res://assets/generated/textures/castle-stone.png")

var players := {}

var _balls := {}  # slot -> MeshInstance3D
var _bar: MeshInstance3D
var _aim_line: MeshInstance3D
var _power_bar: ProgressBar
var _charge := 0.0
var _charging := false
## Locally-predicted aim direction (#1043): the aim LINE used to read the
## replicated PS_AIM_X/Y, which lags a network round-trip behind the stick —
## so the power meter (100% local) filled instantly while the aim line
## visibly caught up a beat later. That mismatch read as "commit your aim,
## THEN charge" even though the sim always accepted both at once. Tracking
## the local input directly makes aim and charge feel like one motion.
var _local_aim := Vector2.ZERO
var _sunk_seen := {}
## The course is seeded per round (#793), so it's built from the first snapshot
## that carries it (like KotH's pillars) rather than from consts. _cup caches the
## replicated cup for the hole-out burst.
var _course_built := false
var _cup := Vector2.ZERO
## GFX (#1149): scoreboard label nodes, one per slot.
var _scoreboard_labels: Array[Label3D] = []
## GFX (#1149): windmill arm node for rotating blades.
var _windmill_arm: Node3D
## GFX (#1149): ball trail — a fading disc behind each ball.
var _trail := {}  # slot -> MeshInstance3D
var _trail_age := {}  # slot -> float
var _last_ball_pos := {}  # slot -> Vector2


## A real putting green (#813): the Kenney grass block replaces the grey
## platform and carries its own color, so the old pastel-green tint (#589)
## approximating one is gone.
func _floor_tile_scene() -> PackedScene:
	return preload("res://assets/environment/kenney_platformer_kit/block-grass.glb")


## Sunny grassy mood (#1149): warm golden-hour atmosphere for the putting
## green, making the grass feel like a real golf course in good weather.
func _mood() -> Color:
	return Color(0.2, 0.15, 0.1).lerp(Color(0.35, 0.28, 0.15), 0.3)


func _arena_half() -> float:
	return PuttPanic.ARENA_HALF + 1.0


func _setup_3d() -> void:
	# The cup/blocks/bar are seeded per round (#793) and built from the first
	# snapshot; balls and the aim UI are course-independent, so build them now.
	_build_balls()
	_build_aim_and_meter()
	# Rim scenery (#1149): trees and bushes ring the putting green.
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)
	# Scoreboard (#1149): 3D floating strokes display above the green.
	_build_scoreboard()
	# Putting green decoration (#1149): flower patches on the grass.
	_build_green_decoration()


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
		_local_aim = aim.normalized()
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
		# Course-specific decorations (#1149): build once after the course is known.
		_build_course_decorations(game)
	var bar: Array = game.get("bar", [])
	if _bar != null and bar.size() >= 2:
		_bar.position = to_arena(Vector2(float(bar[0]), float(bar[1])), 0.35)
	# Windmill rotation (#1149): spin the blades every frame on Windmill course.
	if _windmill_arm != null:
		_windmill_arm.rotation.y += 2.0 * get_process_delta_time()
	for slot: int in players:
		var state: Array = players[slot]
		var ball: MeshInstance3D = _balls.get(slot)
		if ball == null:
			continue
		var ball_pos := Vector2(float(state[PuttPanic.PS_X]), float(state[PuttPanic.PS_Y]))
		ball.position = to_arena(ball_pos, PuttPanic.BALL_RADIUS)
		# Ball trail (#1149): drop a fading disc behind each moving ball.
		_update_trail(slot, ball_pos, state)
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
	# Scoreboard (#1149): update strokes per player every frame.
	_update_scoreboard()


## Build the seeded course from the first snapshot that carries it (#793): the
## cup, the two gate blocks, and the sliding bar — all replicated so the client
## draws exactly the layout the server generated.
func _build_course(game: Dictionary) -> void:
	_course_built = true
	var cup: Array = game.get("cup", [0.0, 6.5])
	_cup = Vector2(float(cup[0]), float(cup[1]))
	_build_cup(_cup)
	var course_type := int(game.get("course", PuttPanic.Course.OPEN_GREEN))
	for block: Array in game.get("blocks", []):
		if block.size() < 4:
			continue
		# Pillar Ring blocks get castle-stone texture (#1149); others keep the
		# grass-green block color.
		if course_type == PuttPanic.Course.PILLAR_RING:
			var node := _box_textured(
				Vector3(float(block[2]) * 2.0, 0.7, float(block[3]) * 2.0), CASTLE_STONE
			)
			node.position = to_arena(Vector2(float(block[0]), float(block[1])), 0.35)
			arena.add_child(node)
		else:
			var node := _box(
				Vector3(float(block[2]) * 2.0, 0.7, float(block[3]) * 2.0), BLOCK_COLOR
			)
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
	# Locally-predicted aim (#1043): before the player has touched the stick
	# this frame, fall back to the replicated direction (e.g. the sim's
	# toward-the-cup default) so the line never starts at zero-length.
	if _local_aim == Vector2.ZERO:
		_local_aim = Vector2(float(state[PuttPanic.PS_AIM_X]), float(state[PuttPanic.PS_AIM_Y]))
	var aim := _local_aim
	var length := 1.0 + _charge * 3.0
	_aim_line.visible = true
	_aim_line.mesh.size = Vector3(0.08, 0.08, length)
	_aim_line.position = to_arena(ball + aim * length * 0.5, 0.15)
	_aim_line.rotation.y = atan2(aim.x, aim.y)
	_power_bar.visible = true
	_power_bar.value = _charge * 100.0


## A box with a tiled texture instead of a flat color (#1149): used for
## Pillar Ring blocks with castle-stone and similar textured elements.
func _box_textured(size: Vector3, texture: Texture2D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_repeat = true
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node


## 3D floating scoreboard above the green (#1149): one Label3D per player,
## showing strokes, so the tally reads from the arena itself.
func _build_scoreboard() -> void:
	for i in names.size():
		var label := Label3D.new()
		label.name = "Scoreboard%d" % i
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = SCOREBOARD_PIXEL_SIZE
		label.font_size = SCOREBOARD_FONT_SIZE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var angle := TAU * float(i) / float(names.size())
		label.position = Vector3(cos(angle) * 6.0, SCOREBOARD_HEIGHT, sin(angle) * 6.0)
		arena.add_child(label)
		_scoreboard_labels.append(label)


## Update the 3D scoreboard (#1149): show strokes per player every frame.
func _update_scoreboard() -> void:
	for i in names.size():
		var label: Label3D = _scoreboard_labels[i] if i < _scoreboard_labels.size() else null
		if label == null:
			continue
		var slot: int = names[i]
		var state: Array = players.get(slot, [])
		if state.size() < PuttPanic.PS_COUNT:
			label.visible = false
			continue
		var sunk := int(state[PuttPanic.PS_SUNK]) == 1
		var strokes := int(state[PuttPanic.PS_STROKES])
		label.text = "%s: %d%s" % [player_name(slot), strokes, " ✓" if sunk else ""]
		label.modulate = player_color(slot)
		label.visible = true


## Course-specific decorations (#1149): built once per round from the seeded
## course type. Windmill, bumper field, sand/water traps, and open green
## hazards each get their own visual dressings.
func _build_course_decorations(game: Dictionary) -> void:
	var course_type := int(game.get("course", PuttPanic.Course.OPEN_GREEN))
	match course_type:
		PuttPanic.Course.WINDMILL:
			_build_windmill()
		PuttPanic.Course.BUMPER_FIELD:
			# Build bumpers on top of the existing block positions.
			for block: Array in game.get("blocks", []):
				if block.size() < 4:
					continue
				_build_bumper(Vector2(float(block[0]), float(block[1])))
		PuttPanic.Course.OPEN_GREEN:
			# Sand traps and water hazards as decorative ellipses.
			_build_hazards(_cup)
		_:
			pass


## Windmill structure (#1149): a tall cylindrical tower with a rotating arm
## of torus/blade segments above the cup. The arm spins every frame in
## _render_3d, giving the Windmill course a signature moving obstacle look.
func _build_windmill() -> void:
	# Tower: a thin cylinder rising from the cup.
	var tower := CylinderMesh.new()
	tower.top_radius = 0.3
	tower.bottom_radius = 0.4
	tower.height = 2.0
	var tower_mat := StandardMaterial3D.new()
	tower_mat.albedo_color = WINDMILL_TOWER_COLOR
	tower.material = tower_mat
	var tower_node := MeshInstance3D.new()
	tower_node.mesh = tower
	tower_node.name = "WindmillTower"
	tower_node.position = to_arena(_cup, 1.0)
	arena.add_child(tower_node)
	# Rotating arm: a parent node we spin each frame.
	_windmill_arm = Node3D.new()
	_windmill_arm.name = "WindmillArm"
	_windmill_arm.position = to_arena(_cup, 2.0)
	arena.add_child(_windmill_arm)
	# Four blades as torus segments around the arm.
	var blade_count := 4
	for i in blade_count:
		var blade := TorusMesh.new()
		blade.inner_radius = 0.05
		blade.outer_radius = 0.12
		blade.ring = 8
		var blade_mat := StandardMaterial3D.new()
		blade_mat.albedo_color = WINDMILL_BLADE_COLOR
		blade.material = blade_mat
		var blade_node := MeshInstance3D.new()
		blade_node.mesh = blade
		var angle := TAU * float(i) / float(blade_count)
		blade_node.position = Vector3(cos(angle) * 1.2, 0.0, sin(angle) * 1.2)
		# Orient the torus ring so it faces outward as a blade.
		blade_node.rotation.z = PI / 2.0
		_windmill_arm.add_child(blade_node)


## Bumper model (#1149): a round mushroom-like body with a colored ring at
## the top, placed at the block position on Bumper Field courses.
func _build_bumper(pos: Vector2) -> void:
	# Body: a short wide cylinder.
	var body := CylinderMesh.new()
	body.top_radius = 0.5
	body.bottom_radius = 0.6
	body.height = 0.5
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = BUMPER_BODY_COLOR
	body.material = body_mat
	var body_node := MeshInstance3D.new()
	body_node.mesh = body
	body_node.name = "BumperBody"
	body_node.position = to_arena(pos, 0.25)
	arena.add_child(body_node)
	# Top ring: a thin torus sitting on top of the bumper body.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.25
	ring.outer_radius = 0.35
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = BUMPER_RING_COLOR
	ring_mat.emission_enabled = true
	ring_mat.emission = BUMPER_RING_COLOR
	ring_mat.emission_energy_multiplier = 0.4
	ring.material = ring_mat
	var ring_node := MeshInstance3D.new()
	ring_node.mesh = ring
	ring_node.name = "BumperRing"
	ring_node.position = to_arena(pos, 0.5)
	arena.add_child(ring_node)


## Decorative sand traps and water hazards (#1149): ellipses placed around
## the open green to give the course visual variety. Decorative only — no
## simulation support for terrain friction.
func _build_hazards(cup: Vector2) -> void:
	var hazard_positions := [
		Vector2(-3.0, -2.0),
		Vector2(3.0, 2.0),
		Vector2(-4.0, 3.0),
		Vector2(4.0, -3.0),
	]
	for i in hazard_positions.size():
		var is_sand := i % 2 == 0
		var pos: Vector2 = hazard_positions[i] + cup
		var ellipse := _disc(
			0.8 if is_sand else 0.6, SAND_TRAP_COLOR if is_sand else WATER_HAZARD_COLOR, 0.02
		)
		ellipse.name = "Hazard%d" % i
		ellipse.position = to_arena(pos, 0.01)
		# Scale the disc into an ellipse by stretching the mesh.
		ellipse.scale = Vector3(1.0, 1.0, 0.6) if is_sand else Vector3(1.0, 1.0, 0.5)
		arena.add_child(ellipse)


## Putting green decoration (#1149): small flower patches and bushes scattered
## on the green to make it feel like a real garden course.
func _build_green_decoration() -> void:
	var flower_positions := [
		Vector2(-5.0, 5.0),
		Vector2(5.0, -5.0),
		Vector2(-6.0, -4.0),
		Vector2(6.0, 4.0),
		Vector2(0.0, -7.0),
	]
	var flower_colors := [
		Color(0.9, 0.3, 0.3),
		Color(0.9, 0.7, 0.2),
		Color(0.8, 0.4, 0.9),
		Color(0.3, 0.6, 0.9),
		Color(0.9, 0.5, 0.7),
	]
	for i in flower_positions.size():
		var patch := _disc(0.4, flower_colors[i], 0.02)
		patch.name = "FlowerPatch%d" % i
		patch.position = to_arena(flower_positions[i], 0.005)
		arena.add_child(patch)


## Ball trail (#1149): a small fading disc left behind each moving ball so the
## stroke reads as a visible motion arc. The disc appears when the ball moves
## and fades over TRAIL_DECAY_SEC.
func _update_trail(slot: int, ball_pos: Vector2, state: Array) -> void:
	var at_rest := false
	if state.size() >= PuttPanic.PS_COUNT:
		at_rest = int(state[PuttPanic.PS_AT_REST]) == 1
	if at_rest:
		# Clear trail when ball stops.
		var trail: MeshInstance3D = _trail.get(slot)
		if trail != null:
			trail.queue_free()
			_trail.erase(slot)
		_trail_age.erase(slot)
		_last_ball_pos.erase(slot)
		return
	var last_pos: Vector2 = _last_ball_pos.get(slot, ball_pos)
	var moved := last_pos.distance_to(ball_pos) > 0.05
	if moved:
		# Drop a new trail disc.
		var disc := _disc(TRAIL_DISC_RADIUS, player_color(slot), TRAIL_DISC_HEIGHT, true)
		disc.name = "Trail%d" % slot
		disc.position = to_arena(last_pos, TRAIL_DISC_HEIGHT * 0.5)
		arena.add_child(disc)
		# Age out old trail nodes.
		var old: MeshInstance3D = _trail.get(slot)
		if old != null:
			old.queue_free()
		_trail[slot] = disc
		_trail_age[slot] = 0.0
	_last_ball_pos[slot] = ball_pos
	# Decay the existing trail disc.
	var age: float = _trail_age.get(slot, 0.0)
	age += get_process_delta_time()
	_trail_age[slot] = age
	if age >= TRAIL_DECAY_SEC:
		var trail: MeshInstance3D = _trail.get(slot)
		if trail != null:
			trail.queue_free()
			_trail.erase(slot)
		_trail_age.erase(slot)
