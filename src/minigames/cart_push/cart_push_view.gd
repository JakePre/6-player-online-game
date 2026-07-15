extends MinigameView3D
## Payload Race client view (#932, reworked from the shared-cart Cart Push
## #175, on the M8-01 MinigameView3D tier): two team-colored carts ride their
## own parallel rails from a shared start line toward the finish. Each cart's
## position reads its lane's monotonic progress, so the standings are legible at
## a glance. Wheel dust scales with how hard each cart is being pushed; shove
## windups play the interact pose (the telegraph) and staggered players flinch.
## A Control-layer banner tells the local player to mash beside their own cart.
##
## Primitive box carts for now (#932 PR1) — the MDL-013 mine-cart model, the
## per-lane progress bars, and the finish banners land in the polish follow-up.

const TEAM_COLORS: Array[Color] = [Color(0.9, 0.5, 0.2), Color(0.35, 0.6, 0.95)]
const RAIL_COLOR := Color(0.35, 0.3, 0.25)
const START_COLOR := Color(0.85, 0.85, 0.85)
const FINISH_COLOR := Color(0.95, 0.85, 0.2)
const CART_SIZE := Vector3(1.8, 1.0, 1.2)
## Wheel dust (M13-23): one puff per this many world units a cart rolls.
const DUST_STEP := 0.6

## Latest replicated state, straight from CartPush.get_snapshot().
var players := {}
var teams: Array = []
var progress: Array = [0.0, 0.0]

var _carts: Array[Node3D] = []
var _push_label: Label
var _my_team := -1
var _prev_prog: Array[float] = [0.0, 0.0]
var _dust_accum: Array[float] = [0.0, 0.0]
var _staggered := {}  # slot (int) -> bool, for one-shot shove-impact puffs


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"action_primary"):
		NetManager.send_match_input({"shove": true})


## Dusty mine floor (#589).
func _floor_tint() -> Color:
	return Color(0.95, 0.88, 0.74)


func _arena_half() -> float:
	return CartPush.ARENA_HALF


func _setup_3d() -> void:
	_build_rails()
	_build_start_finish()
	_build_carts()
	_build_labels()


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	teams = game.get("teams", [])
	progress = game.get("carts", [0.0, 0.0])
	for team_index in _carts.size():
		var prog := float(progress[team_index]) if team_index < progress.size() else 0.0
		_carts[team_index].position = to_arena(
			Vector2(-CartPush.TRACK_HALF + prog, _lane_y(team_index)), CART_SIZE.y * 0.5
		)
		_kick_wheel_dust(team_index, prog)
	_update_players()
	_update_labels()


func _lane_y(team_index: int) -> float:
	return -CartPush.LANE_Y if team_index == 0 else CartPush.LANE_Y


## A cart's wheels kick dust as it rolls: accumulate travel and drop one puff
## under the cart per DUST_STEP of movement (M13-23), so dust scales with how
## hard the cart is pushed rather than with the snapshot rate.
func _kick_wheel_dust(team_index: int, prog: float) -> void:
	_dust_accum[team_index] += absf(prog - _prev_prog[team_index])
	_prev_prog[team_index] = prog
	while _dust_accum[team_index] >= DUST_STEP:
		_dust_accum[team_index] -= DUST_STEP
		fx_dust(Vector2(-CartPush.TRACK_HALF + prog, _lane_y(team_index)))


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[CartPush.PS_X], state[CartPush.PS_Y]))
		var flags := int(state[CartPush.PS_FLAGS])
		var desired: StringName = &"idle"
		if flags & CartPush.FLAG_STAGGERED:
			desired = &"hit"
		elif flags & CartPush.FLAG_WINDUP:
			desired = &"interact"  # shove windup telegraph
		if desired != &"idle" and rig.current_action() != desired:
			rig.play(desired)
		# Shove landed (stagger rising edge): a dust puff kicks up (M13-23).
		var staggered := flags & CartPush.FLAG_STAGGERED == CartPush.FLAG_STAGGERED
		if staggered and not _staggered.get(slot, false):
			fx_dust(Vector2(state[CartPush.PS_X], state[CartPush.PS_Y]))
			if slot == my_slot:
				# A non-damaging shove (#728) — the vocabulary's own "shove"
				# example for bump.
				play_sfx(&"bump")
		_staggered[slot] = staggered
		rig.display_name = player_name(slot)


func _update_labels() -> void:
	if _my_team == -1 and not teams.is_empty():
		for team_index in teams.size():
			if my_slot in (teams[team_index] as Array):
				_my_team = team_index
	if _my_team != -1:
		_push_label.text = "MASH ◀▶ AT YOUR CART!"
		_push_label.add_theme_color_override(&"font_color", TEAM_COLORS[_my_team])


func _build_rails() -> void:
	for team_index in 2:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(CartPush.TRACK_LENGTH, 0.06, 0.4)
		var material := StandardMaterial3D.new()
		material.albedo_color = RAIL_COLOR
		mesh.material = material
		var rail := MeshInstance3D.new()
		rail.name = "Rail%d" % team_index
		rail.mesh = mesh
		rail.position = Vector3(0.0, 0.03, _lane_y(team_index))
		arena.add_child(rail)


func _build_start_finish() -> void:
	_build_line("StartLine", -CartPush.TRACK_HALF, START_COLOR)
	_build_line("FinishLine", CartPush.TRACK_HALF, FINISH_COLOR)


func _build_line(node_name: String, x: float, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.06, CartPush.LANE_Y * 2.0 + 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.4
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = Vector3(x, 0.05, 0.0)
	arena.add_child(node)


func _build_carts() -> void:
	_carts.clear()
	for team_index in 2:
		var cart := Node3D.new()
		cart.name = "Cart%d" % team_index
		var mesh := BoxMesh.new()
		mesh.size = CART_SIZE
		var material := StandardMaterial3D.new()
		material.albedo_color = TEAM_COLORS[team_index]
		mesh.material = material
		var body := MeshInstance3D.new()
		body.name = "Body"
		body.mesh = mesh
		cart.add_child(body)
		arena.add_child(cart)
		_carts.append(cart)


func _build_labels() -> void:
	_push_label = make_status_label(&"PushLabel")
