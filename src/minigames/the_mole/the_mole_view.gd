extends MinigameView3D
## The Mole client view (M10-13): iso-arena with the central machine (glow
## scaling with fuel progress, an unattributed red spark flash when
## sabotaged), loose fuel cells, and phase banners. The local player's
## secret role arrives via private_state (#254) — only this client ever
## renders "you are the MOLE". Voting: the action button cycles the current
## suspect; each cycle sends the vote, last one counts. Renders
## get_snapshot() only.

const MACHINE_COLOR := Color(0.35, 0.8, 0.5)
const SPARK_COLOR := Color(0.95, 0.3, 0.2)
const CELL_COLOR := Color(1.0, 0.85, 0.25)
const MOLE_COLOR := Color(0.95, 0.35, 0.25)
const MACHINE_HEIGHT := 1.6
const CELL_SIZE := 0.45

## Latest replicated state, straight from TheMole.get_snapshot().
var phase := TheMole.Phase.WORK
var phase_left := 0.0
var progress := 0
var target := TheMole.CELL_TARGET
var sparked := false
var players := {}
var cells: Array = []
var votes_in := 0
var reveal := {}

var _machine_material: StandardMaterial3D
# Pooled (#709): reused across snapshots, hiding surplus instead of freeing.
var _cell_mesh: BoxMesh
var _cell_nodes: Array[MeshInstance3D] = []
var _banner: Label
## Index into the votable slot list this client is currently aiming at.
var _vote_index := -1
var _my_vote := -1
# FX seeds: spark rising edge, delivery ticks, the one-shot reveal burst.
var _sparked_seen := false
var _progress_seen := -1
var _revealed := false


func _physics_process(_delta: float) -> void:
	if phase == TheMole.Phase.WORK:
		send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"action_primary"):
		return
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	if phase == TheMole.Phase.VOTE:
		_cycle_vote()
	else:
		NetManager.send_match_input({"act": true})


## SPACE/pad-A cycles the suspect and votes them — the last cycle counts.
## One button keeps it pad-only and kb-only clean (M12-05).
func _cycle_vote() -> void:
	var candidates := _votable_slots()
	if candidates.is_empty():
		return
	_vote_index = (_vote_index + 1) % candidates.size()
	_my_vote = candidates[_vote_index]
	NetManager.send_match_input({"vote": _my_vote})
	_update_banner()


func _votable_slots() -> Array:
	var out: Array = []
	for slot: int in players:
		if slot != my_slot:
			out.append(slot)
	out.sort()
	return out


## Suspicious cool blue-grey floor (#589).
func _floor_tint() -> Color:
	return Color(0.85, 0.88, 0.94)


func _arena_half() -> float:
	return TheMole.ARENA_HALF + 1.0


func _setup_3d() -> void:
	var pillar := CylinderMesh.new()
	pillar.top_radius = TheMole.MACHINE_RADIUS * 0.6
	pillar.bottom_radius = TheMole.MACHINE_RADIUS * 0.8
	pillar.height = MACHINE_HEIGHT
	_machine_material = StandardMaterial3D.new()
	_machine_material.albedo_color = MACHINE_COLOR
	_machine_material.emission_enabled = true
	_machine_material.emission = MACHINE_COLOR
	_machine_material.emission_energy_multiplier = 0.1
	pillar.material = _machine_material
	var machine := MeshInstance3D.new()
	machine.name = "Machine"
	machine.mesh = pillar
	machine.position = to_arena(TheMole.MACHINE_POS, MACHINE_HEIGHT / 2.0)
	arena.add_child(machine)
	_banner = make_banner(&"Phase", 26)
	_cell_mesh = BoxMesh.new()
	_cell_mesh.size = Vector3(CELL_SIZE, CELL_SIZE, CELL_SIZE)
	var cell_material := StandardMaterial3D.new()
	cell_material.albedo_color = CELL_COLOR
	cell_material.emission_enabled = true
	cell_material.emission = CELL_COLOR
	cell_material.emission_energy_multiplier = 0.3
	_cell_mesh.material = cell_material


func _render_3d(game: Dictionary) -> void:
	phase = game.get("phase", TheMole.Phase.WORK)
	phase_left = float(game.get("phase_left", 0.0))
	progress = int(game.get("progress", 0))
	target = int(game.get("target", TheMole.CELL_TARGET))
	sparked = bool(game.get("sparked", false))
	players = game.get("players", {})
	cells = game.get("cells", [])
	votes_in = int(game.get("votes_in", 0))
	reveal = game.get("reveal", {})
	_update_players()
	_update_cells()
	_update_machine()
	_update_reveal_fx()
	_update_banner()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		if rig_for_slot(slot) == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))


func _update_cells() -> void:
	sync_pool(_cell_nodes, cells.size(), _make_cell, _place_cell)


func _make_cell() -> Node3D:
	var node := MeshInstance3D.new()
	node.mesh = _cell_mesh
	return node


func _place_cell(node: Node3D, index: int) -> void:
	var cell: Array = cells[index]
	node.position = to_arena(Vector2(float(cell[0]), float(cell[1])), CELL_SIZE / 2.0)


func _update_machine() -> void:
	var fill := float(progress) / maxf(float(target), 1.0)
	if sparked:
		_machine_material.albedo_color = SPARK_COLOR
		_machine_material.emission = SPARK_COLOR
		_machine_material.emission_energy_multiplier = 1.5
	else:
		_machine_material.albedo_color = MACHINE_COLOR
		_machine_material.emission = MACHINE_COLOR
		_machine_material.emission_energy_multiplier = 0.1 + fill * 1.0
	# The unattributed tell (rising edge): sabotage bursts red at the machine
	# with no name attached — whoever's nearby is a suspect.
	if sparked and not _sparked_seen:
		fx_burst(TheMole.MACHINE_POS, SPARK_COLOR)
		play_sfx(&"error")
	_sparked_seen = sparked
	# Delivery sparkle: progress ticking up (seeded on first sight).
	if _progress_seen >= 0 and progress > _progress_seen:
		fx_sparkle(TheMole.MACHINE_POS, CELL_COLOR, 1.2)
		play_sfx(&"coin")
	_progress_seen = progress


func _update_reveal_fx() -> void:
	if _revealed or reveal.is_empty():
		return
	_revealed = true
	var mole_slot := int(reveal.get("mole", -1))
	var state: Array = players.get(mole_slot, [])
	if state.size() >= 2:
		fx_burst(Vector2(float(state[0]), float(state[1])), MOLE_COLOR)


func _update_banner() -> void:
	if _banner == null:
		return
	match phase:
		TheMole.Phase.WORK:
			if private_state.get("role", "") == "mole":
				_banner.text = (
					"You are the MOLE — sabotage near the machine (SPACE)  ·  %d/%d"
					% [progress, target]
				)
				_banner.modulate = MOLE_COLOR
			else:
				_banner.text = "Fuel the machine — %d/%d (%0.0fs)" % [progress, target, phase_left]
				_banner.modulate = CELL_COLOR
		TheMole.Phase.VOTE:
			var aim := "SPACE cycles your vote" if _my_vote < 0 else player_name(_my_vote)
			_banner.text = (
				"WHO IS THE MOLE?  Voting: %s  (%d in, %0.0fs)" % [aim, votes_in, phase_left]
			)
			_banner.modulate = Color.WHITE
		TheMole.Phase.REVEAL:
			var mole_slot := int(reveal.get("mole", -1))
			var outcome := "CAUGHT!" if bool(reveal.get("caught", false)) else "they escaped!"
			var job := (
				"The machine was fueled." if reveal.get("success", false) else ("The machine died.")
			)
			_banner.text = "%s was the mole — %s %s" % [player_name(mole_slot), outcome, job]
			_banner.modulate = MOLE_COLOR
