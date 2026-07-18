extends MinigameView3D
## Kingslayer client view (#936): the asymmetric-hunt finale — a fixed royal
## court, a floating gold crown over the King, a King-HP headline, sabotage
## strike telegraphs, downed hunters hidden until their respawn lands, and
## hit/swing cues off the sim's monotonic counters. Renders
## Kingslayer.get_snapshot() only. Input: action_primary swings,
## action_secondary spends a sabotage token (hunters auto-target the King;
## the King targets the nearest hunter — the #462 idiom).

const COURT_COLOR := Color(0.36, 0.3, 0.42)
const COURT_THICKNESS := 0.5
const CROWN_COLOR := Color(0.98, 0.82, 0.2)
const STRIKE_COLOR := Color(1.0, 0.45, 0.15, 0.6)
const STRIKE_POOL := 6
const KING_HIT_COLOR := Color(1.0, 0.4, 0.3)

var players := {}
var strikes: Array = []
var king := -1

var _court: MeshInstance3D
var _crown: MeshInstance3D
var _strike_pool: Array[MeshInstance3D] = []
var _status: Label
var _hit_seen := {}
var _swing_seen := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	if event.is_action_pressed(&"action_primary"):
		NetManager.send_match_input({"swing": true})
	elif event.is_action_pressed(&"action_secondary"):
		NetManager.send_match_input({"sabotage": _sabotage_target()})


## Hunters always mean the King; the King means the nearest hunter (#462).
func _sabotage_target() -> int:
	if my_slot != king:
		return king
	var my_state: Array = players.get(my_slot, [])
	if my_state.size() < Kingslayer.PS_COUNT:
		return -1
	var me := Vector2(float(my_state[Kingslayer.PS_X]), float(my_state[Kingslayer.PS_Y]))
	var best := -1
	var best_dist := INF
	for slot: int in players:
		if slot == my_slot:
			continue
		var state: Array = players[slot]
		if float(state[Kingslayer.PS_RESPAWN]) > 0.0:
			continue
		var pos := Vector2(float(state[Kingslayer.PS_X]), float(state[Kingslayer.PS_Y]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = slot
	return best


func _arena_half() -> float:
	return Kingslayer.court_radius_for(names.size()) + 2.0


func _setup_3d() -> void:
	var radius := Kingslayer.court_radius_for(names.size())
	var court_mesh := CylinderMesh.new()
	court_mesh.height = COURT_THICKNESS
	court_mesh.top_radius = radius
	court_mesh.bottom_radius = radius
	var material := StandardMaterial3D.new()
	material.albedo_color = COURT_COLOR
	court_mesh.material = material
	_court = MeshInstance3D.new()
	_court.name = "Court"
	_court.mesh = court_mesh
	_court.position = Vector3(0.0, COURT_THICKNESS / 2.0, 0.0)
	arena.add_child(_court)
	# The crown (#936 "must feel like a crown"): a gold cone hovering over the
	# King's rig, spinning slowly in _process.
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.34
	crown_mesh.bottom_radius = 0.22
	crown_mesh.height = 0.3
	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color = CROWN_COLOR
	crown_mat.emission_enabled = true
	crown_mat.emission = CROWN_COLOR
	crown_mat.emission_energy_multiplier = 0.8
	crown_mesh.material = crown_mat
	_crown = MeshInstance3D.new()
	_crown.name = "Crown"
	_crown.mesh = crown_mesh
	_crown.visible = false
	arena.add_child(_crown)
	for _i in STRIKE_POOL:
		var disc := CylinderMesh.new()
		disc.top_radius = Kingslayer.SABOTAGE_RADIUS
		disc.bottom_radius = Kingslayer.SABOTAGE_RADIUS
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
	_status = make_status_label(&"KingslayerStatus")


func _process(_delta: float) -> void:
	if _crown != null and _crown.visible and not ArenaFX.reduced_motion:
		_crown.rotation.y = Time.get_ticks_msec() / 1000.0 * 1.6


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	strikes = game.get("strikes", [])
	king = int(game.get("king", -1))
	_update_players()
	_update_crown()
	_update_strikes()
	_update_status(int(game.get("king_max_hp", Kingslayer.KING_HP_BASE)))


func _update_players() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null or not players.has(slot):
			continue
		var state: Array = players[slot]
		# Downed hunters vanish until the respawn lands.
		rig.visible = float(state[Kingslayer.PS_RESPAWN]) <= 0.0
		if not rig.visible:
			continue
		var pos := Vector2(float(state[Kingslayer.PS_X]), float(state[Kingslayer.PS_Y]))
		update_rig(slot, pos)
		var hit := int(state[Kingslayer.PS_HIT_SEQ])
		if hit > int(_hit_seen.get(slot, hit)):
			fx_burst(pos, KING_HIT_COLOR if slot == king else Color(1.0, 0.8, 0.4), 0.8)
			play_sfx(&"hit_heavy" if slot == king else &"hit")
			if slot == king:
				request_shake(4.0)
		_hit_seen[slot] = hit
		var swing := int(state[Kingslayer.PS_SWING_SEQ])
		if swing > int(_swing_seen.get(slot, swing)):
			rig.play(&"attack")
			play_sfx(&"click")
		_swing_seen[slot] = swing


func _update_crown() -> void:
	var state: Array = players.get(king, [])
	if state.size() < Kingslayer.PS_COUNT:
		_crown.visible = false
		return
	_crown.visible = true
	var pos := Vector2(float(state[Kingslayer.PS_X]), float(state[Kingslayer.PS_Y]))
	_crown.position = to_arena(pos, 2.6)


func _update_strikes() -> void:
	for i in _strike_pool.size():
		var node := _strike_pool[i]
		if i >= strikes.size():
			node.visible = false
			continue
		var strike: Array = strikes[i]
		node.visible = true
		node.position = to_arena(
			Vector2(float(strike[Kingslayer.ST_X]), float(strike[Kingslayer.ST_Y])),
			COURT_THICKNESS + 0.05
		)


func _update_status(king_max_hp: int) -> void:
	if _status == null:
		return
	var king_state: Array = players.get(king, [])
	var king_hp := 0
	if king_state.size() >= Kingslayer.PS_COUNT:
		king_hp = int(king_state[Kingslayer.PS_HP])
	var role := "YOU ARE THE KING — survive!" if my_slot == king else "SLAY THE KING!"
	_status.text = (
		"%s    %s: %d/%d HP" % [role, str(names.get(king, "King")), king_hp, king_max_hp]
	)
