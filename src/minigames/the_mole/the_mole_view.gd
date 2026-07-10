extends MinigameView3D
## The Mole client view (M10-13): iso-arena with the central machine (glow
## scaling with fuel progress, an unattributed red spark flash when
## sabotaged), loose fuel cells, and phase banners. The local player's
## secret role arrives via private_state (#254) — only this client ever
## renders "you are the MOLE".
##
## Voting (#801): the action button cycles the suspect you're accusing, shown
## by a floating marker over that player in the arena; a check over each rig
## tracks who has voted (participation only — never who they voted for). The
## reveal then draws the full accusation web (arrows from every voter to their
## target, green when they pinned the mole) and names the mole. Renders
## get_snapshot() only.

const MACHINE_COLOR := Color(0.35, 0.8, 0.5)
const SPARK_COLOR := Color(0.95, 0.3, 0.2)
const CELL_COLOR := Color(1.0, 0.85, 0.25)
const MOLE_COLOR := Color(0.95, 0.35, 0.25)
const MACHINE_HEIGHT := 1.6
const CELL_SIZE := 0.45
## Vote-aim marker (#801): a floating chevron over the suspect you're accusing.
const AIM_COLOR := Color(1.0, 0.85, 0.3)
const AIM_HEIGHT := 2.6
## Reveal accusation arrows (#801): a beam from each voter to whom they accused,
## green when they fingered the actual mole, dim otherwise.
const VOTE_CORRECT_COLOR := Color(0.4, 0.9, 0.45)
const VOTE_WRONG_COLOR := Color(0.5, 0.5, 0.55, 0.7)
const ARROW_HEIGHT := 0.12

## Latest replicated state, straight from TheMole.get_snapshot().
var phase := TheMole.Phase.WORK
var phase_left := 0.0
var progress := 0
var target := TheMole.CELL_TARGET
var sparked := false
var players := {}
var cells: Array = []
var votes_in := 0
var voted: Array = []
var reveal := {}

var _machine_material: StandardMaterial3D
# Pooled (#709): reused across snapshots, hiding surplus instead of freeing.
var _cell_mesh: BoxMesh
var _cell_nodes: Array[MeshInstance3D] = []
var _banner: Label
## Index into the votable slot list this client is currently aiming at.
var _vote_index := -1
var _my_vote := -1
## Floating chevron over the suspect the local player is accusing (#801).
var _aim_marker: MeshInstance3D
## Accusation-arrow nodes built once at the reveal, freed on the next round.
var _vote_arrows: Array[MeshInstance3D] = []
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
	_build_aim_marker()


## A downward chevron (an inverted cone) that floats over the accused suspect
## during voting, so cycling the vote is visible in the arena, not just text.
func _build_aim_marker() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.35
	mesh.bottom_radius = 0.0
	mesh.height = 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = AIM_COLOR
	material.emission_enabled = true
	material.emission = AIM_COLOR
	material.emission_energy_multiplier = 0.6
	mesh.material = material
	_aim_marker = MeshInstance3D.new()
	_aim_marker.name = "VoteAim"
	_aim_marker.mesh = mesh
	_aim_marker.visible = false
	arena.add_child(_aim_marker)


func _render_3d(game: Dictionary) -> void:
	phase = game.get("phase", TheMole.Phase.WORK)
	phase_left = float(game.get("phase_left", 0.0))
	progress = int(game.get("progress", 0))
	target = int(game.get("target", TheMole.CELL_TARGET))
	sparked = bool(game.get("sparked", false))
	players = game.get("players", {})
	cells = game.get("cells", [])
	votes_in = int(game.get("votes_in", 0))
	voted = game.get("voted", [])
	reveal = game.get("reveal", {})
	_update_players()
	_update_cells()
	_update_machine()
	_update_vote_aim()
	_update_reveal_fx()
	_update_banner()


func _update_players() -> void:
	var mole_slot := int(reveal.get("mole", -1))
	var reveal_votes: Dictionary = reveal.get("votes", {})
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[TheMole.PS_X], state[TheMole.PS_Y]))
		# Per-phase nameplate + tint so the vote/reveal reads at a glance (#801).
		match phase:
			TheMole.Phase.VOTE:
				var mark := "  ✓ voted" if slot in voted else ""
				rig.display_name = player_name(slot) + mark
				rig.player_color = PlayerPalette.color_for_slot(slot)
			TheMole.Phase.REVEAL:
				if slot == mole_slot:
					rig.display_name = "%s  ◄ THE MOLE" % player_name(slot)
					rig.player_color = MOLE_COLOR
				else:
					var correct := int(reveal_votes.get(slot, -1)) == mole_slot
					rig.display_name = player_name(slot) + ("  ✓ called it" if correct else "")
					rig.player_color = (
						VOTE_CORRECT_COLOR if correct else PlayerPalette.color_for_slot(slot)
					)
			_:
				rig.display_name = player_name(slot)
				rig.player_color = PlayerPalette.color_for_slot(slot)


func _update_cells() -> void:
	sync_pool(_cell_nodes, cells.size(), _make_cell, _place_cell)


func _make_cell() -> Node3D:
	var node := MeshInstance3D.new()
	node.mesh = _cell_mesh
	return node


func _place_cell(node: Node3D, index: int) -> void:
	var cell: Array = cells[index]
	node.position = to_arena(
		Vector2(float(cell[TheMole.CL_X]), float(cell[TheMole.CL_Y])), CELL_SIZE / 2.0
	)


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
		# The unattributed sabotage tell is exposure/suspicion — the
		# vocabulary's own alarm meaning (#728), not a generic hurt cue.
		play_sfx(&"alarm")
	_sparked_seen = sparked
	# Delivery sparkle: progress ticking up (seeded on first sight).
	if _progress_seen >= 0 and progress > _progress_seen:
		fx_sparkle(TheMole.MACHINE_POS, CELL_COLOR, 1.2)
		play_sfx(&"coin")
	_progress_seen = progress


## Floats the aim chevron over the suspect the local player is accusing, so
## cycling the vote is visible in the arena; hidden outside voting (#801).
func _update_vote_aim() -> void:
	if _aim_marker == null:
		return
	var state: Array = players.get(_my_vote, [])
	if phase != TheMole.Phase.VOTE or _my_vote < 0 or state.size() < 2:
		_aim_marker.visible = false
		return
	_aim_marker.visible = true
	_aim_marker.position = to_arena(
		Vector2(float(state[TheMole.PS_X]), float(state[TheMole.PS_Y])), AIM_HEIGHT
	)


## The reveal sequence (#801): a burst on the mole, the accusation web (an arrow
## from every voter to whom they accused, green when they nailed the mole), and
## an outcome cue. Built once on the first reveal snapshot.
func _update_reveal_fx() -> void:
	if _revealed or reveal.is_empty():
		return
	_revealed = true
	_aim_marker.visible = false
	var mole_slot := int(reveal.get("mole", -1))
	var state: Array = players.get(mole_slot, [])
	if state.size() >= 2:
		fx_burst(Vector2(float(state[TheMole.PS_X]), float(state[TheMole.PS_Y])), MOLE_COLOR)
	_build_vote_arrows(reveal.get("votes", {}), mole_slot)
	# The outcome cue: `bell` (checkpoint/justice) when the crew caught the mole,
	# `error` when it slipped through (#728).
	var caught := bool(reveal.get("caught", false))
	play_sfx(&"bell" if caught else &"error")
	if caught:
		request_shake(5.0)


func _build_vote_arrows(vote_map: Dictionary, mole_slot: int) -> void:
	for voter_v: Variant in vote_map:
		var voter := int(voter_v)
		var target := int(vote_map[voter])
		var vstate: Array = players.get(voter, [])
		var tstate: Array = players.get(target, [])
		if vstate.size() < 2 or tstate.size() < 2:
			continue
		var from := Vector2(float(vstate[TheMole.PS_X]), float(vstate[TheMole.PS_Y]))
		var to := Vector2(float(tstate[TheMole.PS_X]), float(tstate[TheMole.PS_Y]))
		_vote_arrows.append(_make_vote_arrow(voter, from, to, target == mole_slot))


func _make_vote_arrow(voter: int, from: Vector2, to: Vector2, correct: bool) -> MeshInstance3D:
	var length := maxf(from.distance_to(to), 0.1)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.14, 0.05, length)
	var color := VOTE_CORRECT_COLOR if correct else VOTE_WRONG_COLOR
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.6 if correct else 0.2
	mesh.material = material
	var node := MeshInstance3D.new()
	# Unique per voter so sibling names never collide (Godot would auto-rename a
	# duplicate to an @-prefixed form the arena counter wouldn't recognize).
	node.name = "VoteArrow%d" % voter
	node.mesh = mesh
	node.position = to_arena((from + to) * 0.5, ARROW_HEIGHT)
	# The box's long (local +Z) axis points from -> to across the X/Z floor.
	node.rotation.y = atan2(to.x - from.x, to.y - from.y)
	arena.add_child(node)
	return node


## Crew members (not the mole) who accused the mole — the count that decided
## caught vs escaped.
func _accusers_of_mole(mole_slot: int) -> int:
	var vote_map: Dictionary = reveal.get("votes", {})
	var n := 0
	for voter_v: Variant in vote_map:
		var voter := int(voter_v)
		if voter != mole_slot and int(vote_map[voter]) == mole_slot:
			n += 1
	return n


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
			var aim := (
				"SPACE to accuse"
				if _my_vote < 0
				else "accusing %s (SPACE to change)" % player_name(_my_vote)
			)
			_banner.text = (
				"WHO IS THE MOLE?  ·  %s  ·  %d voted  ·  %0.0fs" % [aim, votes_in, phase_left]
			)
			_banner.modulate = Color.WHITE
		TheMole.Phase.REVEAL:
			var mole_slot := int(reveal.get("mole", -1))
			var caught := bool(reveal.get("caught", false))
			var against := _accusers_of_mole(mole_slot)
			var outcome := (
				"CAUGHT by %d!" % against if caught else "ESCAPED — only %d saw it" % against
			)
			var job := (
				"The machine was fueled." if reveal.get("success", false) else "The machine died."
			)
			_banner.text = "%s was THE MOLE — %s  %s" % [player_name(mole_slot), outcome, job]
			_banner.modulate = VOTE_CORRECT_COLOR if caught else MOLE_COLOR
