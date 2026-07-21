extends MinigameView3D
## Dodgeball client view (#791): renders the court in the shared 2.5D iso-arena.
## Team halves are tinted and split by a center line (team mode); players carry,
## aim, and hurl balls. Hits KO-tumble the target with a burst; a catch flashes
## "CAUGHT!" and reflects — the round's clip moment. Renders get_snapshot()
## only; the sim owns all outcomes.
##
## GFX enhancements (#1135): wood-court floor texture (IMG-054), painted
## boundary lines, translucent backstop walls, 3D scoreboard above center court,
## ball shadows under flying balls, and gym-scene rim props.
## Real dodgeball model (#791/#911, MDL-003): a two-tone rubber ball replacing
## the flat sphere. Base-pivoted (probed AABB: y 0..0.4, matching the
## generated-models convention), so positioning needs no radius offset — a
## LOOSE ball sits right on the floor.
## Declarative button input (#947): pick up / aim-throw a ball.
const INPUT_ACTIONS := {&"action_primary": "act"}
const BALL_SCENE := preload("res://assets/generated/models/dodgeball.glb")
## Still used for the KO burst FX color, matching the model's dominant red.
const BALL_COLOR := Color(0.9, 0.32, 0.28)
const BALL_CARRY_HEIGHT := 1.3
const FLYING_HEIGHT := 1.0
## Team-half tints + center line (team mode); mirrors Tug of War's side tints.
const TEAM_A_COLOR := Color(0.35, 0.72, 1.0)
const TEAM_B_COLOR := Color(1.0, 0.55, 0.2)
const SIDE_TINT_ALPHA := 0.2
const CENTER_LINE_COLOR := Color(0.95, 0.95, 1.0)
const ELIMINATED_COLOR := Color(0.42, 0.42, 0.46)
const EVENT_HOLD_SEC := 0.9
## Court surface — IMG-054 hardwood gym floor (#1135).
const COURT_TEXTURE := preload("res://assets/generated/textures/wood-court.png")
const COURT_TEXTURE_TILES := 4.0
## Boundary line constants (#1135): thin white emissive strips around the
## court perimeter, matching Basket Brawl's court-line pattern.
const COURT_LINE_COLOR := Color(0.95, 0.95, 0.92)
const COURT_LINE_WIDTH := 0.12
const COURT_LINE_HEIGHT := 0.02
## Backstop wall constants (#1135): translucent wall at each Z-end so balls
## don't fly into the void — matching Laser Limbo's BACK_WALL pattern.
const BACK_WALL_COLOR := Color(0.14, 0.1, 0.22, 0.35)
const BACK_WALL_HEIGHT := 2.6
## Ball shadow constants (#1135): a dark transparent disc under each flying ball.
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const SHADOW_RADIUS := 0.2
const SHADOW_HEIGHT := 0.01
## Scoreboard constants (#1135): 3D labels above center court in team mode.
const SCOREBOARD_HEIGHT := 2.8
const SCOREBOARD_PIXEL_SIZE := 0.003
const SCOREBOARD_FONT_SIZE := 28
## Rim props (#1135): low-detail buildings around the arena perimeter to read
## as a gymnasium, matching Bomb Courier's rim-building pattern.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-a.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-b.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-c.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-d.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-e.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-f.glb"),
]
const RIM_PROP_COUNT := 20
const RIM_PROP_SEED := 0xDB0
## Latest replicated state, straight from Dodgeball.get_snapshot().
var players := {}
var ball_states: Array = []
var teams: Array = []
var half := Dodgeball.ARENA_HALF

var _ball_pool: Array[Node3D] = []
var _objective_label: Label
var _event_label: Label
var _event_until := 0.0
var _center_line: MeshInstance3D
var _side_tints: Array[MeshInstance3D] = []
var _downed := {}
## Rejoin-quiet rising edge on the fallen count (#941): the first snapshot
## seeds and never shakes/flashes.
var _edges := EdgeTracker.new()
# Ball index -> holder from the previous snapshot, for catch detection: a ball
# going FLYING (no holder) -> HELD (a live holder) is a catch.
var _ball_holder_seen := {}
var _ball_state_seen := {}
## Court surface + boundary lines (#1135).
var _court_surface: MeshInstance3D
var _boundary_lines: Array[MeshInstance3D] = []
## Backstop walls (#1135): translucent PlaneMesh walls at each Z-end.
var _backstop_walls: Array[MeshInstance3D] = []
## Scoreboard labels (#1135): team name + alive count, shown in team mode.
var _scoreboard_labels: Array[Label3D] = []
## Ball shadows (#1135): small dark disc pool under flying balls.
var _shadow_pool: Array[MeshInstance3D] = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Warm hardwood-gym floor (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.9, 0.78)


func _arena_half() -> float:
	return MinigameScaling.arena_half(Dodgeball.ARENA_HALF, names.size())


func _setup_3d() -> void:
	half = _arena_half()
	_build_court()
	_build_backstop_walls()
	_build_scoreboard()
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)
	_objective_label = make_status_label(&"ObjectiveLabel")
	_event_label = make_status_label(&"EventLabel")
	# #924: offset relative to the chrome-cleared baseline, not a bare pixel
	# value — keeps a fixed gap below the primary line regardless of the
	# baseline's position.
	_event_label.position.y = MinigameView3D.CHROME_CLEARANCE_Y + 68.0
	_event_label.visible = false


## The IMG-054 wood-court floor surface, painted boundary lines, center line,
## and two translucent team-colored halves (team mode).
func _build_court() -> void:
	# Court surface — IMG-054 wood-court texture (#1135).
	_court_surface = MeshInstance3D.new()
	_court_surface.name = "CourtSurface"
	var surface_mesh := PlaneMesh.new()
	surface_mesh.size = Vector2(half * 2.0, half * 2.0)
	var surface_material := StandardMaterial3D.new()
	surface_material.albedo_texture = COURT_TEXTURE
	surface_material.uv1_scale = Vector3(COURT_TEXTURE_TILES, COURT_TEXTURE_TILES, 1.0)
	surface_mesh.material = surface_material
	_court_surface.mesh = surface_mesh
	_court_surface.position = Vector3(0.0, 0.015, 0.0)
	arena.add_child(_court_surface)
	# Boundary lines — thin white BoxMesh strips around the court perimeter (#1135).
	_build_boundary_lines()
	# Center line (team mode).
	_center_line = MeshInstance3D.new()
	_center_line.name = "CenterLine"
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(0.3, 0.06, half * 2.0)
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = CENTER_LINE_COLOR
	line_material.emission_enabled = true
	line_material.emission = CENTER_LINE_COLOR
	line_material.emission_energy_multiplier = 0.4
	line_mesh.material = line_material
	_center_line.mesh = line_mesh
	_center_line.position = Vector3(0.0, 0.04, 0.0)
	_center_line.visible = false
	arena.add_child(_center_line)
	for team_index in 2:
		var tint := MeshInstance3D.new()
		tint.name = "SideTint%d" % team_index
		var tint_mesh := PlaneMesh.new()
		tint_mesh.size = Vector2(half, half * 2.0)
		var tint_material := StandardMaterial3D.new()
		tint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var color := TEAM_A_COLOR if team_index == 0 else TEAM_B_COLOR
		color.a = SIDE_TINT_ALPHA
		tint_material.albedo_color = color
		tint_mesh.material = tint_material
		tint.mesh = tint_mesh
		var side := -1.0 if team_index == 0 else 1.0
		tint.position = Vector3(side * half / 2.0, 0.02, 0.0)
		tint.visible = false
		arena.add_child(tint)
		_side_tints.append(tint)


## Painted boundary lines around the court perimeter (#1135): thin white BoxMesh
## strips just outside the play area so the court reads as a real gym floor.
func _build_boundary_lines() -> void:
	var margin := 0.15
	var offset := half + margin
	for _bound: int in 4:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(COURT_LINE_WIDTH, COURT_LINE_HEIGHT, half * 2.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = COURT_LINE_COLOR
		material.emission_enabled = true
		material.emission = COURT_LINE_COLOR
		material.emission_energy_multiplier = 0.3
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		# Two vertical lines at ±X, two horizontal lines at ±Z.
		var side := -1.0 if _bound < 2 else 1.0
		if _bound % 2 == 0:
			# X-boundary vertical line (-X or +X edge).
			node.position = to_arena(Vector2(side * offset, 0.0), COURT_LINE_HEIGHT / 2.0 + 0.02)
		else:
			# Z-boundary horizontal line (-Z or +Z edge), rotated 90°.
			mesh.size = Vector3(half * 2.0, COURT_LINE_HEIGHT, COURT_LINE_WIDTH)
			node.position = to_arena(Vector2(0.0, side * offset), COURT_LINE_HEIGHT / 2.0 + 0.02)
		arena.add_child(node)
		_boundary_lines.append(node)


## Translucent backstop walls at each Z-end of the court (#1135): a dim
## vertical PlaneMesh so balls don't visually fly into the void, matching
## Laser Limbo's BACK_WALL pattern.
func _build_backstop_walls() -> void:
	var wall_mesh := PlaneMesh.new()
	wall_mesh.size = Vector2(half * 2.0, BACK_WALL_HEIGHT)
	var wall_material := StandardMaterial3D.new()
	wall_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_material.albedo_color = BACK_WALL_COLOR
	wall_mesh.material = wall_material
	for side: float in [-1.0, 1.0]:
		var wall := MeshInstance3D.new()
		wall.name = "BackstopWall%d" % (0 if side < 0.0 else 1)
		wall.mesh = wall_mesh
		# Position at the Z-end of the court, facing inward.
		wall.position = Vector3(0.0, BACK_WALL_HEIGHT / 2.0, side * half)
		wall.rotation.y = 0.0 if side < 0.0 else PI
		arena.add_child(wall)
		_backstop_walls.append(wall)


## 3D scoreboard above center court (#1135): two Label3D nodes showing team
## name + alive count in team mode, hidden in FFA.
func _build_scoreboard() -> void:
	for i in 2:
		var label := Label3D.new()
		label.name = "Scoreboard%d" % i
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = SCOREBOARD_PIXEL_SIZE
		label.font_size = SCOREBOARD_FONT_SIZE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.visible = false
		var side := -1.0 if i == 0 else 1.0
		label.position = Vector3(side * 2.0, SCOREBOARD_HEIGHT, 0.0)
		arena.add_child(label)
		_scoreboard_labels.append(label)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	ball_states = game.get("balls", [])
	teams = game.get("teams", [])
	half = float(game.get("half", half))
	var team_mode := bool(game.get("team_mode", false))
	_update_court(team_mode)
	_update_objective(team_mode, game)
	_update_scoreboard(team_mode)
	_update_players()
	_update_balls()
	_update_ball_shadows()
	_detect_catches()
	_shake_on_new_downs(game.get("fallen", []))
	if not _event_label.visible or Time.get_ticks_msec() / 1000.0 >= _event_until:
		_event_label.visible = false


func _update_court(team_mode: bool) -> void:
	_center_line.visible = team_mode
	for tint in _side_tints:
		tint.visible = team_mode


func _update_objective(team_mode: bool, game: Dictionary) -> void:
	if team_mode:
		_objective_label.text = "PEG THE OTHER TEAM OUT — catch to reflect!"
	else:
		var alive := (game.get("players", {}) as Dictionary).size()
		_objective_label.text = "LAST ONE STANDING — %d left!" % alive


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var pos := Vector2(float(state[Dodgeball.PS_X]), float(state[Dodgeball.PS_Y]))
		# Holders aim by facing while standing still, so drive the rig's heading
		# from the replicated facing rather than only from displacement.
		update_rig(slot, pos)
		if int(state[Dodgeball.PS_HOLDING]) == 1:
			var facing := Vector2(
				float(state[Dodgeball.PS_FACING_X]), float(state[Dodgeball.PS_FACING_Y])
			)
			if facing.length() > 0.01:
				rig.rotation.y = atan2(facing.x, facing.y)
		rig.display_name = player_name(slot)


func _update_balls() -> void:
	for i in ball_states.size():
		var ball: Array = ball_states[i]
		var node := _ball_node(i)
		node.visible = true
		var pos := Vector2(float(ball[Dodgeball.BL_X]), float(ball[Dodgeball.BL_Y]))
		var state := int(ball[Dodgeball.BL_STATE])
		var holder := int(ball[Dodgeball.BL_HOLDER])
		# LOOSE (resting/rolling): the base-pivoted model sits right on the floor.
		var height := 0.05
		if state == Dodgeball.BallState.HELD and players.has(holder):
			# Float the carried ball ahead of and above its holder, along their
			# aim, so "who's armed" and "which way" both read at a glance.
			var hstate: Array = players[holder]
			var facing := Vector2(
				float(hstate[Dodgeball.PS_FACING_X]), float(hstate[Dodgeball.PS_FACING_Y])
			)
			pos = (
				Vector2(float(hstate[Dodgeball.PS_X]), float(hstate[Dodgeball.PS_Y]))
				+ facing.normalized() * 0.5
			)
			height = BALL_CARRY_HEIGHT
		elif state == Dodgeball.BallState.FLYING:
			height = FLYING_HEIGHT
		node.position = to_arena(pos, height)
	for i in range(ball_states.size(), _ball_pool.size()):
		_ball_pool[i].visible = false


func _ball_node(index: int) -> Node3D:
	while index >= _ball_pool.size():
		var node := BALL_SCENE.instantiate() as Node3D
		node.name = "Ball%d" % _ball_pool.size()
		node.visible = false
		arena.add_child(node)
		_ball_pool.append(node)
	return _ball_pool[index]


## A ball flipping FLYING -> HELD with a live holder is a catch: flash "CAUGHT!"
## over the catcher and sparkle — the moment everyone came to see.
func _detect_catches() -> void:
	for i in ball_states.size():
		var ball: Array = ball_states[i]
		var state := int(ball[Dodgeball.BL_STATE])
		var holder := int(ball[Dodgeball.BL_HOLDER])
		var was_flying := int(_ball_state_seen.get(i, -1)) == Dodgeball.BallState.FLYING
		if was_flying and state == Dodgeball.BallState.HELD and players.has(holder):
			_flash_event("CAUGHT!", PartyTheme.ACCENT_BRIGHT)
			var pos := Vector2(float(ball[Dodgeball.BL_X]), float(ball[Dodgeball.BL_Y]))
			fx_sparkle(pos, PartyTheme.ACCENT_BRIGHT, 1.2)
			play_sfx(&"bell")
		_ball_state_seen[i] = state
		_ball_holder_seen[i] = holder


func _flash_event(text: String, color: Color) -> void:
	_event_label.text = text
	_event_label.add_theme_color_override(&"font_color", color)
	_event_label.visible = true
	_event_until = Time.get_ticks_msec() / 1000.0 + EVENT_HOLD_SEC


## KO-tumble the newly eliminated (new entries in `fallen`), bursting where they
## fell and shaking on the impact — the same seeded pattern Thin Ice uses.
func _shake_on_new_downs(fallen: Array) -> void:
	for group: Array in fallen:
		for slot: int in group:
			_down_rig(slot)
	var fallen_count := 0
	for group: Array in fallen:
		fallen_count += group.size()
	if _edges.rose(&"fallen", fallen_count):
		request_shake(8.0)
		play_sfx(&"ko")


func _down_rig(slot: int) -> void:
	if _downed.has(slot):
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	_downed[slot] = true
	rig.play(&"ko")
	rig.player_color = ELIMINATED_COLOR
	fx_burst(Vector2(rig.position.x, rig.position.z), BALL_COLOR, 0.7)


## Update the 3D team scoreboard (#1135): show teams + alive count in team mode.
func _update_scoreboard(team_mode: bool) -> void:
	for i in 2:
		var label: Label3D = _scoreboard_labels[i] if i < _scoreboard_labels.size() else null
		if label == null:
			continue
		if not team_mode or teams.size() < 2 or i >= teams.size():
			label.visible = false
			continue
		var team: Array = teams[i] if i < teams.size() else []
		var alive := 0
		for slot: int in team:
			if players.has(slot):
				alive += 1
		var team_name := "TEAM %s" % ["A", "B"][i]
		label.text = "%s  %d" % [team_name, alive]
		var color := TEAM_A_COLOR if i == 0 else TEAM_B_COLOR
		label.modulate = color
		label.visible = true


## Update ball shadows (#1135): a dark disc on the floor under each ball,
## visible only while flying or held (not while loose/on the ground).
func _update_ball_shadows() -> void:
	for i in ball_states.size():
		var ball: Array = ball_states[i]
		var state := int(ball[Dodgeball.BL_STATE])
		var shadow := _shadow_node(i)
		shadow.visible = state != Dodgeball.BallState.LOOSE
		if not shadow.visible:
			continue
		var pos := Vector2(float(ball[Dodgeball.BL_X]), float(ball[Dodgeball.BL_Y]))
		shadow.position = to_arena(pos, 0.02)
	for i in range(ball_states.size(), _shadow_pool.size()):
		_shadow_pool[i].visible = false


## Pooled dark disc under each ball (#1135).
func _shadow_node(index: int) -> MeshInstance3D:
	while index >= _shadow_pool.size():
		var mesh := CylinderMesh.new()
		mesh.top_radius = SHADOW_RADIUS
		mesh.bottom_radius = SHADOW_RADIUS
		mesh.height = SHADOW_HEIGHT
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = SHADOW_COLOR
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = material
		var node := MeshInstance3D.new()
		node.name = "Shadow%d" % _shadow_pool.size()
		node.mesh = mesh
		node.visible = false
		arena.add_child(node)
		_shadow_pool.append(node)
	return _shadow_pool[index]
