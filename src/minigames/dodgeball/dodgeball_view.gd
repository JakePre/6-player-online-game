extends MinigameView3D
## Dodgeball client view (#791): renders the court in the shared 2.5D iso-arena.
## Team halves are tinted and split by a center line (team mode); players carry,
## aim, and hurl balls. Hits KO-tumble the target with a burst; a catch flashes
## "CAUGHT!" and reflects — the round's clip moment. Renders get_snapshot()
## only; the sim owns all outcomes.

const BALL_COLOR := Color(0.9, 0.32, 0.28)
const BALL_RADIUS := 0.3
const BALL_CARRY_HEIGHT := 1.3
const FLYING_HEIGHT := 1.0
## Team-half tints + center line (team mode); mirrors Tug of War's side tints.
const TEAM_A_COLOR := Color(0.35, 0.72, 1.0)
const TEAM_B_COLOR := Color(1.0, 0.55, 0.2)
const SIDE_TINT_ALPHA := 0.2
const CENTER_LINE_COLOR := Color(0.95, 0.95, 1.0)
const ELIMINATED_COLOR := Color(0.42, 0.42, 0.46)
const EVENT_HOLD_SEC := 0.9

## Latest replicated state, straight from Dodgeball.get_snapshot().
var players := {}
var ball_states: Array = []
var teams: Array = []
var half := Dodgeball.ARENA_HALF

var _ball_pool: Array[MeshInstance3D] = []
var _ball_mesh: SphereMesh
var _objective_label: Label
var _event_label: Label
var _event_until := 0.0
var _center_line: MeshInstance3D
var _side_tints: Array[MeshInstance3D] = []
var _downed := {}
# -1 = unseeded, so a mid-match rejoin doesn't shake/flash on its first snapshot.
var _fallen_seen := -1
# Ball index -> holder from the previous snapshot, for catch detection: a ball
# going FLYING (no holder) -> HELD (a live holder) is a catch.
var _ball_holder_seen := {}
var _ball_state_seen := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_primary"):
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"act": true})


## Warm hardwood-gym floor (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.9, 0.78)


func _arena_half() -> float:
	return MinigameScaling.arena_half(Dodgeball.ARENA_HALF, names.size())


func _setup_3d() -> void:
	half = _arena_half()
	_build_court()
	_ball_mesh = SphereMesh.new()
	_ball_mesh.radius = BALL_RADIUS
	_ball_mesh.height = BALL_RADIUS * 2.0
	var ball_material := StandardMaterial3D.new()
	ball_material.albedo_color = BALL_COLOR
	ball_material.emission_enabled = true
	ball_material.emission = BALL_COLOR * 0.35
	_ball_mesh.material = ball_material
	_objective_label = make_status_label(&"ObjectiveLabel")
	_event_label = make_status_label(&"EventLabel")
	_event_label.position.y = 84.0
	_event_label.visible = false


## The center line + two translucent team-colored halves (team mode); in FFA
## the court is one open floor, so neither is drawn.
func _build_court() -> void:
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


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	ball_states = game.get("balls", [])
	teams = game.get("teams", [])
	half = float(game.get("half", half))
	var team_mode := bool(game.get("team_mode", false))
	_update_court(team_mode)
	_update_objective(team_mode, game)
	_update_players()
	_update_balls()
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
		var height := BALL_RADIUS + 0.05
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


func _ball_node(index: int) -> MeshInstance3D:
	while index >= _ball_pool.size():
		var node := MeshInstance3D.new()
		node.name = "Ball%d" % _ball_pool.size()
		node.mesh = _ball_mesh
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
	if _fallen_seen >= 0 and fallen_count > _fallen_seen:
		request_shake(8.0)
		play_sfx(&"ko")
	_fallen_seen = fallen_count


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
