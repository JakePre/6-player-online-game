extends MinigameView3D
## Storm Court client view (#936): the finale dodgeball royale — a shrinking
## court disc with the #583 shrink-telegraph band, dodgeballs colored by
## state, sabotage strike telegraphs, hit/catch flashes off the sim's
## monotonic counters, and a lives HUD. Renders StormCourt.get_snapshot()
## only. Input: action_primary throws (or buffers a catch empty-handed),
## action_secondary spends a sabotage token on the nearest living rival —
## the same targeting idiom as the Gauntlet (#462).

const PLATFORM_COLOR := Color(0.30, 0.34, 0.44)
const PLATFORM_THICKNESS := 0.5
const SHRINK_TELEGRAPH_COLOR := Color(0.95, 0.4, 0.3, 0.55)
const BALL_LOOSE_COLOR := Color(0.9, 0.35, 0.3)
const BALL_FLYING_COLOR := Color(1.0, 0.85, 0.3)
const STRIKE_COLOR := Color(1.0, 0.45, 0.15, 0.6)
const STRIKE_POOL := 6
const CATCH_COLOR := Color(0.4, 1.0, 0.6)

var players := {}
var balls: Array = []
var strikes: Array = []
var radius := StormCourt.START_RADIUS

var _platform: MeshInstance3D
var _platform_mesh: CylinderMesh
var _telegraph: MeshInstance3D
var _telegraph_mesh: TorusMesh
var _ball_pool: Array[MeshInstance3D] = []
var _strike_pool: Array[MeshInstance3D] = []
var _status: Label
var _hit_seen := {}
var _catch_seen := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	if event.is_action_pressed(&"action_primary"):
		NetManager.send_match_input({"act": true})
	elif event.is_action_pressed(&"action_secondary"):
		NetManager.send_match_input({"sabotage": _sabotage_target()})


## Nearest living rival, the #462 targeting idiom — the sim validates tokens.
func _sabotage_target() -> int:
	var my_state: Array = players.get(my_slot, [])
	if my_state.size() < StormCourt.PS_COUNT:
		return -1
	var me := Vector2(float(my_state[StormCourt.PS_X]), float(my_state[StormCourt.PS_Y]))
	var best := -1
	var best_dist := INF
	for slot: int in players:
		if slot == my_slot:
			continue
		var state: Array = players[slot]
		var pos := Vector2(float(state[StormCourt.PS_X]), float(state[StormCourt.PS_Y]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = slot
	return best


func _arena_half() -> float:
	return StormCourt.start_radius_for(names.size()) + 2.0


func _setup_3d() -> void:
	radius = StormCourt.start_radius_for(names.size())
	_platform_mesh = CylinderMesh.new()
	_platform_mesh.height = PLATFORM_THICKNESS
	_platform_mesh.top_radius = radius
	_platform_mesh.bottom_radius = radius
	var material := StandardMaterial3D.new()
	material.albedo_color = PLATFORM_COLOR
	_platform_mesh.material = material
	_platform = MeshInstance3D.new()
	_platform.name = "Court"
	_platform.mesh = _platform_mesh
	_platform.position = Vector3(0.0, PLATFORM_THICKNESS / 2.0, 0.0)
	arena.add_child(_platform)
	_telegraph_mesh = TorusMesh.new()
	_telegraph_mesh.inner_radius = maxf(radius - 0.1, 0.05)
	_telegraph_mesh.outer_radius = radius
	var telegraph_mat := StandardMaterial3D.new()
	telegraph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	telegraph_mat.albedo_color = SHRINK_TELEGRAPH_COLOR
	_telegraph_mesh.material = telegraph_mat
	_telegraph = MeshInstance3D.new()
	_telegraph.name = "ShrinkTelegraph"
	_telegraph.mesh = _telegraph_mesh
	_telegraph.position = Vector3(0.0, PLATFORM_THICKNESS + 0.03, 0.0)
	_telegraph.visible = false
	arena.add_child(_telegraph)
	for _i in StormCourt.ball_count_for(names.size()):
		var mesh := SphereMesh.new()
		mesh.radius = StormCourt.BALL_RADIUS
		mesh.height = StormCourt.BALL_RADIUS * 2.0
		var ball_mat := StandardMaterial3D.new()
		ball_mat.albedo_color = BALL_LOOSE_COLOR
		ball_mat.emission_enabled = true
		ball_mat.emission = BALL_LOOSE_COLOR
		ball_mat.emission_energy_multiplier = 0.4
		mesh.material = ball_mat
		var node := MeshInstance3D.new()
		node.mesh = mesh
		arena.add_child(node)
		_ball_pool.append(node)
	for _i in STRIKE_POOL:
		var disc := CylinderMesh.new()
		disc.top_radius = StormCourt.SABOTAGE_RADIUS
		disc.bottom_radius = StormCourt.SABOTAGE_RADIUS
		disc.height = 0.04
		var strike_mat := StandardMaterial3D.new()
		strike_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		strike_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		strike_mat.albedo_color = STRIKE_COLOR
		disc.material = strike_mat
		var node := MeshInstance3D.new()
		node.mesh = disc
		node.visible = false
		arena.add_child(node)
		_strike_pool.append(node)
	_status = make_status_label(&"StormStatus")


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	balls = game.get("balls", [])
	strikes = game.get("strikes", [])
	radius = float(game.get("radius", radius))
	_update_court(float(game.get("shrink_in", StormCourt.SHRINK_STAGE_SEC)))
	_update_players()
	_update_balls()
	_update_strikes()
	_update_status()


func _update_court(shrink_in: float) -> void:
	_platform_mesh.top_radius = radius
	_platform_mesh.bottom_radius = radius
	# #583: light the doomed band before a stage lands (never below minimum).
	var warn := shrink_in <= StormCourt.SHRINK_WARN_SEC and radius > StormCourt.MIN_RADIUS + 0.01
	_telegraph.visible = warn
	if warn:
		var next_radius := maxf(StormCourt.MIN_RADIUS, radius - StormCourt.SHRINK_PER_STAGE)
		_telegraph_mesh.inner_radius = maxf(next_radius, 0.05)
		_telegraph_mesh.outer_radius = radius


func _update_players() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		if not players.has(slot):
			rig.visible = false
			continue
		rig.visible = true
		var state: Array = players[slot]
		var pos := Vector2(float(state[StormCourt.PS_X]), float(state[StormCourt.PS_Y]))
		update_rig(slot, pos)
		var hit := int(state[StormCourt.PS_HIT_SEQ])
		if hit > int(_hit_seen.get(slot, hit)):
			fx_burst(pos, Color(1.0, 0.5, 0.3), 0.8)
			play_sfx(&"hit_heavy" if slot == my_slot else &"hit")
		_hit_seen[slot] = hit
		var caught := int(state[StormCourt.PS_CATCH_SEQ])
		if caught > int(_catch_seen.get(slot, caught)):
			fx_sparkle(pos, CATCH_COLOR, 1.0)
			# The two-life swing (#936) deserves the bell.
			play_sfx(&"bell" if slot == my_slot else &"click")
		_catch_seen[slot] = caught


func _update_balls() -> void:
	for i in _ball_pool.size():
		var node := _ball_pool[i]
		if i >= balls.size():
			node.visible = false
			continue
		var ball: Array = balls[i]
		var state := int(ball[StormCourt.BL_STATE])
		var pos := Vector2(float(ball[StormCourt.BL_X]), float(ball[StormCourt.BL_Y]))
		node.visible = true
		var height := 0.35
		if state == StormCourt.BallState.HELD:
			height = 1.9
		elif state == StormCourt.BallState.FLYING:
			height = 0.9
		node.position = to_arena(pos, height)
		var material := (node.mesh as SphereMesh).material as StandardMaterial3D
		var color := BALL_FLYING_COLOR if state == StormCourt.BallState.FLYING else BALL_LOOSE_COLOR
		material.albedo_color = color
		material.emission = color


func _update_strikes() -> void:
	for i in _strike_pool.size():
		var node := _strike_pool[i]
		if i >= strikes.size():
			node.visible = false
			continue
		var strike: Array = strikes[i]
		node.visible = true
		node.position = to_arena(
			Vector2(float(strike[StormCourt.ST_X]), float(strike[StormCourt.ST_Y])),
			PLATFORM_THICKNESS + 0.05
		)


func _update_status() -> void:
	if _status == null:
		return
	var my_state: Array = players.get(my_slot, [])
	if my_state.size() >= StormCourt.PS_COUNT:
		_status.text = (
			"STORM COURT — lives: %d · standing: %d"
			% [int(my_state[StormCourt.PS_LIVES]), players.size()]
		)
	else:
		_status.text = "STORM COURT — eliminated · standing: %d" % players.size()
