extends MinigameView3D
## Ro-Sham-Bo Royale client view (M14-05): three pads (Rock/Paper/Scissors) in
## the iso-arena — run to one to throw. REVEAL shows every alive player's
## pick and who's out; sudden death (final two, tied) calls out the shape to
## counter. Eliminated players stop moving and instead cycle a vote for the
## eventual champion with move_left/move_right, confirmed with action_primary
## (M12-05 parity: no mouse needed). Renders get_snapshot() only.

const SHAPE_NAMES := ["ROCK", "PAPER", "SCISSORS"]
const PAD_COLORS := [Color(0.55, 0.55, 0.6), Color(0.88, 0.84, 0.6), Color(0.75, 0.32, 0.28)]
const PAD_DISC_HEIGHT := 0.05

## Latest replicated state, straight from RoShamBo.get_snapshot().
var players := {}
var eliminated_order: Array = []
var sudden_death := false
var target_shape := -1
var phase_left := 0.0
var last_result := {}
var phase: int = RoShamBo.Phase.THROW

var _pad_nodes: Array[Node3D] = []
var _banner: Label
# FX/SFX seeds: eliminated-groups seen so far, so a fresh elimination only
# bursts/pings once; local vote cursor for eliminated spectators.
var _eliminated_seen := 0
var _vote_cursor := 0
var _voted := false


func _physics_process(_delta: float) -> void:
	if _am_alive():
		send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if _am_alive() or _voted or event.is_echo():
		return
	var candidates := _alive_candidates()
	if candidates.is_empty():
		return
	if event.is_action_pressed(&"move_left"):
		_vote_cursor = (_vote_cursor - 1 + candidates.size()) % candidates.size()
	elif event.is_action_pressed(&"move_right"):
		_vote_cursor = (_vote_cursor + 1) % candidates.size()
	elif event.is_action_pressed(&"action_primary"):
		NetManager.send_match_input({"vote": candidates[_vote_cursor]})
		_voted = true


## Playful bright-yellow game-show floor (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.97, 0.78)


func _arena_half() -> float:
	return RoShamBo.ARENA_HALF


func _setup_3d() -> void:
	for i in 3:
		var pad := Node3D.new()
		pad.name = "Pad%d" % i
		var disc := MeshInstance3D.new()
		disc.name = "Disc"
		var mesh := CylinderMesh.new()
		mesh.top_radius = RoShamBo.PAD_RADIUS
		mesh.bottom_radius = RoShamBo.PAD_RADIUS
		mesh.height = PAD_DISC_HEIGHT
		var material := StandardMaterial3D.new()
		material.albedo_color = PAD_COLORS[i]
		mesh.material = material
		disc.mesh = mesh
		pad.add_child(disc)
		var label := Label3D.new()
		label.name = "Label"
		label.text = SHAPE_NAMES[i]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.006
		label.position.y = 1.0
		pad.position = to_arena(RoShamBo.pad_position(i), PAD_DISC_HEIGHT / 2.0)
		pad.add_child(label)
		arena.add_child(pad)
		_pad_nodes.append(pad)
	_banner = make_banner(&"Phase", 26)


func _render_3d(game: Dictionary) -> void:
	phase = int(game.get("phase", RoShamBo.Phase.THROW))
	players = game.get("players", {})
	eliminated_order = game.get("eliminated_order", [])
	sudden_death = bool(game.get("sudden_death", false))
	target_shape = int(game.get("target_shape", -1))
	phase_left = float(game.get("phase_left", 0.0))
	last_result = game.get("last_result", {})
	_update_players()
	_update_banner()
	_handle_elimination_fx()


func _update_players() -> void:
	var throws: Dictionary = last_result.get("throws", {})
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var alive := int(state[2]) == 1
		update_rig(slot, Vector2(state[0], state[1]))
		rig.visible = alive
		var caption := player_name(slot)
		if not alive:
			caption += "  [OUT]"
		elif phase == RoShamBo.Phase.REVEAL and throws.has(slot):
			caption += "  " + SHAPE_NAMES[int(throws[slot])]
		elif int(state[3]) == 1:
			caption += "  [LOCKED]"
		rig.display_name = caption


func _update_banner() -> void:
	if _banner == null:
		return
	if phase == RoShamBo.Phase.THROW:
		if sudden_death:
			_banner.text = (
				"SUDDEN DEATH! Throw %s (%0.1fs)"
				% [SHAPE_NAMES[_counter(target_shape)], phase_left]
			)
		else:
			_banner.text = "Run to Rock / Paper / Scissors! (%0.1fs)" % phase_left
	else:
		if bool(last_result.get("wash", false)):
			_banner.text = "TIE — no one's out"
		else:
			_banner.text = "OUT!"


## Fresh eliminations burst + ping once per reveal (M12-02 convention: the
## eliminated hear the loss, everyone still in hears a quieter confirm).
func _handle_elimination_fx() -> void:
	if eliminated_order.size() <= _eliminated_seen:
		return
	for i in range(_eliminated_seen, eliminated_order.size()):
		var group: Array = eliminated_order[i]
		for slot: int in group:
			var state: Array = players.get(slot, [0.0, 0.0, 0, 0])
			fx_burst(Vector2(state[0], state[1]), Color(0.8, 0.2, 0.2))
		if my_slot in group:
			play_sfx(&"error")
		elif my_slot in players:
			play_sfx(&"confirm")
	_eliminated_seen = eliminated_order.size()


func _am_alive() -> bool:
	var state: Array = players.get(my_slot, [0.0, 0.0, 1, 0])
	return int(state[2]) == 1


## Currently-alive slots other than me, in a stable order for the vote cursor.
func _alive_candidates() -> Array:
	var candidates: Array = []
	for slot: int in players:
		if slot == my_slot:
			continue
		var state: Array = players[slot]
		if int(state[2]) == 1:
			candidates.append(slot)
	candidates.sort()
	return candidates


func _counter(shape: int) -> int:
	match shape:
		RoShamBo.Shape.ROCK:
			return RoShamBo.Shape.PAPER
		RoShamBo.Shape.PAPER:
			return RoShamBo.Shape.SCISSORS
		_:
			return RoShamBo.Shape.ROCK
