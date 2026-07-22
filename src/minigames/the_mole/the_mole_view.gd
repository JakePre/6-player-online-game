extends MinigameView3D
## The Mole client view (M10-13): iso-arena with the central machine (glow
## scaling with fuel progress, an unattributed red spark flash when
## sabotaged), loose fuel cells, and phase banners. The local player's
## secret role arrives via private_state (#254) — only this client ever
## renders "you are the MOLE".
##
## Visual enhancements (#1160): machine detail (gears, pipes, display screen),
## Kenney crate fuel cells, metal-deck textured floor, progress light ring,
## voting pedestals, rim props, dark industrial mood, and floor edge barriers.
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
## Blackout (#958): the lights-out vignette — a radial dark whose transparent
## center follows the local rig, so you see only your own patch. The mole never
## renders it (they keep full vision, private-side). Reduced-motion unaffected:
## it's darkness, not movement, and colorblind-safe (value, not hue).
const BLACKOUT_CLEAR := Color(0.0, 0.0, 0.02, 0.0)
const BLACKOUT_EDGE := Color(0.0, 0.0, 0.02, 0.9)
## Fractions of the vignette texture radius (the texture spans ~2.2x the
## viewport so the dark reaches every corner with the hole anywhere): transparent
## out to _INNER, fully dark by _OUTER. Kept small so only a tight patch around
## your own rig stays lit — the rest goes black.
const BLACKOUT_HOLE_INNER := 0.06
const BLACKOUT_HOLE_OUTER := 0.15
## Preloads for visual enhancements (#1160): metal-deck floor texture,
## Kenney crate model for fuel cells, and rim props for arena dressing.
const FLOOR_TEXTURE := preload("res://assets/generated/textures/metal-deck.png")
const CRATE_SCENE := preload("res://assets/environment/kenney_platformer_kit/crate.glb")
const FLOOR_TILES := 5.0
## Machine detail constants (#1160).
const GEAR_COUNT := 4
const GEAR_RADIUS := 0.35
const GEAR_INNER := 0.2
const GEAR_HEIGHT := 0.08
const PIPE_COUNT := 4
const PIPE_RADIUS := 0.06
const SCREEN_COLOR := Color(0.15, 0.9, 0.3)
## Progress light ring (#1160): ring of small lights around the machine base.
const PROGRESS_LIGHT_COUNT := 12
const PROGRESS_LIGHT_RADIUS := 0.15
const PROGRESS_LIGHT_RING_RADIUS := 2.0
## Voting pedestal (#1160): small disc that elevates slightly during VOTE.
const PEDESTAL_HEIGHT := 0.08
const PEDESTAL_RADIUS := 0.5
const PEDESTAL_ELEVATION := 0.3
## Rim scenery (#1160): industrial props ring the arena edge.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_platformer_kit/barrel.glb"),
	preload("res://assets/environment/kenney_platformer_kit/pipe.glb"),
	preload("res://assets/environment/kenney_platformer_kit/rocks.glb"),
]
const RIM_PROP_COUNT := 16
const RIM_PROP_SEED := 0x1160
## Floor edge barrier (#1160): thin walls around the arena perimeter.
const EDGE_HEIGHT := 0.4
const EDGE_THICKNESS := 0.15
const EDGE_COLOR := Color(0.25, 0.28, 0.32)

## Latest replicated state, straight from TheMole.get_snapshot().
var phase := TheMole.Phase.WORK
var phase_left := 0.0
var progress := 0
var target := TheMole.CELL_TARGET
var sparked := false
var blackout := false
var players := {}
var cells: Array = []
var votes_in := 0
var voted: Array = []
var reveal := {}
## The lights-out vignette (#958); null until _setup_3d builds it.
var _blackout_overlay: TextureRect

var _machine_material: StandardMaterial3D
var _screen_material: StandardMaterial3D
var _machine_node: Node3D
# Pooled (#709): reused across snapshots, hiding surplus instead of freeing.
var _cell_nodes: Array[Node3D] = []
var _progress_lights: Array[MeshInstance3D] = []
var _pedestal_nodes: Array[MeshInstance3D] = []
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
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	# Blackout (#958): the mole's distinct second button, WORK phase only. The sim
	# gates it to the mole too, but gating the send keeps a crew press silent.
	if event.is_action_pressed(&"action_secondary"):
		if phase == TheMole.Phase.WORK and private_state.get("role", "") == "mole":
			NetManager.send_match_input({"blackout": true})
		return
	if not event.is_action_pressed(&"action_primary"):
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


## Dark industrial mood for the party-stadium shell (#1160): pushes the
## dusk base toward a blue-grey industrial underground feel, matching the
## metal-deck floor and the secret-facility theme.
func _mood() -> Color:
	return Color(0.12, 0.14, 0.18)


func _arena_half() -> float:
	return TheMole.ARENA_HALF + 1.0


func _setup_3d() -> void:
	_build_machine()
	_build_machine_detail()
	_build_progress_lights()
	_banner = make_banner(&"Phase", 26)
	_build_aim_marker()
	_build_blackout_overlay()
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)
	_build_floor_edge()
	_build_pedestal_pool()


## Metal-deck floor texture (#1160): replaces the flat tint with an
## industrial underground facility feel.
func _build_floor() -> void:
	var half := _arena_half()
	var surface_mesh := PlaneMesh.new()
	surface_mesh.size = Vector2(half * 2.0, half * 2.0)
	var surface_material := StandardMaterial3D.new()
	surface_material.albedo_texture = FLOOR_TEXTURE
	surface_material.uv1_scale = Vector3(FLOOR_TILES, FLOOR_TILES, 1.0)
	surface_mesh.material = surface_material
	var surface := MeshInstance3D.new()
	surface.name = "Floor"
	surface.mesh = surface_mesh
	surface.position = to_arena(Vector2.ZERO, 0.01)
	arena.add_child(surface)


func _build_machine() -> void:
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
	_machine_node = MeshInstance3D.new()
	_machine_node.name = "Machine"
	_machine_node.mesh = pillar
	_machine_node.position = to_arena(TheMole.MACHINE_POS, MACHINE_HEIGHT / 2.0)
	arena.add_child(_machine_node)


## Machine detail (#1160): gears, pipes, and a display screen on the
## central machine for an industrial underground facility feel.
func _build_machine_detail() -> void:
	# Gears (TorusMesh segments) around the machine at varying heights.
	var gear_mat := StandardMaterial3D.new()
	gear_mat.albedo_color = Color(0.5, 0.5, 0.55)
	gear_mat.metallic = 0.6
	gear_mat.roughness = 0.4
	for i in GEAR_COUNT:
		var gear := TorusMesh.new()
		gear.inner_radius = GEAR_INNER
		gear.outer_radius = GEAR_RADIUS
		gear.material = gear_mat
		var node := MeshInstance3D.new()
		node.name = "Gear%d" % i
		node.mesh = gear
		var angle := TAU * i / GEAR_COUNT
		var radius := TheMole.MACHINE_RADIUS * 0.8
		node.position = to_arena(
			TheMole.MACHINE_POS + Vector2(cos(angle), sin(angle)) * radius,
			MACHINE_HEIGHT * (0.2 + 0.6 * i / GEAR_COUNT)
		)
		node.rotation.x = PI / 2.0
		arena.add_child(node)
	# Pipes (CylinderMesh) running up the machine sides.
	var pipe_mat := StandardMaterial3D.new()
	pipe_mat.albedo_color = Color(0.35, 0.38, 0.42)
	pipe_mat.metallic = 0.5
	pipe_mat.roughness = 0.5
	for i in PIPE_COUNT:
		var pipe := CylinderMesh.new()
		pipe.top_radius = PIPE_RADIUS
		pipe.bottom_radius = PIPE_RADIUS * 1.3
		pipe.height = MACHINE_HEIGHT * 0.85
		pipe.material = pipe_mat
		var node := MeshInstance3D.new()
		node.name = "Pipe%d" % i
		node.mesh = pipe
		var angle := TAU * i / PIPE_COUNT + TAU / 8.0
		var radius := TheMole.MACHINE_RADIUS * 0.5
		node.position = to_arena(
			TheMole.MACHINE_POS + Vector2(cos(angle), sin(angle)) * radius, MACHINE_HEIGHT * 0.5
		)
		arena.add_child(node)
	# Display screen (BoxMesh) on the machine face with emissive green.
	_screen_material = StandardMaterial3D.new()
	_screen_material.albedo_color = SCREEN_COLOR
	_screen_material.emission_enabled = true
	_screen_material.emission = SCREEN_COLOR
	_screen_material.emission_energy_multiplier = 0.3
	var screen := BoxMesh.new()
	screen.size = Vector3(0.6, 0.4, 0.05)
	screen.material = _screen_material
	var screen_node := MeshInstance3D.new()
	screen_node.name = "DisplayScreen"
	screen_node.mesh = screen
	screen_node.position = to_arena(
		TheMole.MACHINE_POS + Vector2(0.0, TheMole.MACHINE_RADIUS * 0.5), MACHINE_HEIGHT * 0.65
	)
	arena.add_child(screen_node)


## Progress light ring (#1160): ring of small SphereMeshes around the machine
## base that light up in sequence as fuel is delivered.
func _build_progress_lights() -> void:
	var light_mat := StandardMaterial3D.new()
	light_mat.albedo_color = CELL_COLOR
	light_mat.emission_enabled = true
	light_mat.emission = CELL_COLOR
	light_mat.emission_energy_multiplier = 0.0
	for i in PROGRESS_LIGHT_COUNT:
		var sphere := SphereMesh.new()
		sphere.radius = PROGRESS_LIGHT_RADIUS
		sphere.height = PROGRESS_LIGHT_RADIUS * 2.0
		sphere.material = light_mat.duplicate()
		var node := MeshInstance3D.new()
		node.name = "ProgressLight%d" % i
		node.mesh = sphere
		var angle := TAU * i / PROGRESS_LIGHT_COUNT
		node.position = to_arena(
			TheMole.MACHINE_POS + Vector2(cos(angle), sin(angle)) * PROGRESS_LIGHT_RING_RADIUS, 0.05
		)
		arena.add_child(node)
		_progress_lights.append(node)


## Floor edge barrier (#1160): thin walls around the arena perimeter so the
## play area reads as a contained industrial facility.
func _build_floor_edge() -> void:
	var half := _arena_half()
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = EDGE_COLOR
	var edge_segments := [
		[Vector2(-half, 0.0), Vector2(1.0, 0.0)],  # bottom
		[Vector2(half, 0.0), Vector2(-1.0, 0.0)],  # top
		[Vector2(0.0, -half), Vector2(0.0, 1.0)],  # left
		[Vector2(0.0, half), Vector2(0.0, -1.0)],  # right
	]
	for seg in edge_segments:
		var pos := seg[0] as Vector2
		var dir := seg[1] as Vector2
		var wall := BoxMesh.new()
		wall.size = Vector3(half * 2.0, EDGE_HEIGHT, EDGE_THICKNESS)
		wall.material = edge_mat
		var node := MeshInstance3D.new()
		node.name = "FloorEdge"
		node.mesh = wall
		node.position = to_arena(pos, EDGE_HEIGHT / 2.0)
		if dir.x == 0.0:
			node.rotation.y = PI / 2.0
		arena.add_child(node)


## Voting pedestal pool (#1160): pre-build colored discs for each player slot
## so VOTE phase can show them instantly. Hidden until _update_players().
func _build_pedestal_pool() -> void:
	for slot: int in names:
		var disc := CylinderMesh.new()
		disc.top_radius = PEDESTAL_RADIUS
		disc.bottom_radius = PEDESTAL_RADIUS
		disc.height = PEDESTAL_HEIGHT
		var mat := StandardMaterial3D.new()
		mat.albedo_color = PlayerPalette.color_for_slot(slot)
		mat.emission_enabled = true
		mat.emission = PlayerPalette.color_for_slot(slot)
		mat.emission_energy_multiplier = 0.2
		disc.material = mat
		var node := MeshInstance3D.new()
		node.name = "Pedestal%d" % slot
		node.mesh = disc
		arena.add_child(node)
		_pedestal_nodes.append(node)
		node.visible = false


## The lights-out vignette (#958): a radial dark whose transparent center is the
## lit patch. Lives inside the arena SubViewport so the camera unproject that
## re-centers it each frame lands in the same coordinate space.
func _build_blackout_overlay() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, BLACKOUT_HOLE_INNER, BLACKOUT_HOLE_OUTER, 1.0])
	grad.colors = PackedColorArray([BLACKOUT_CLEAR, BLACKOUT_CLEAR, BLACKOUT_EDGE, BLACKOUT_EDGE])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	_blackout_overlay = TextureRect.new()
	_blackout_overlay.name = "BlackoutOverlay"
	_blackout_overlay.texture = tex
	_blackout_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_blackout_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout_overlay.visible = false
	_viewport.add_child(_blackout_overlay)


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
	blackout = bool(game.get("blackout", false))
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
	_update_blackout()
	_update_banner()


## Shows the lights-out vignette for everyone but the mole (who keeps full
## vision, private-side per #254), centered on the local rig so only your own
## patch stays lit. Public `blackout` never says who flipped the switch.
func _update_blackout() -> void:
	if _blackout_overlay == null:
		return
	var is_mole: bool = private_state.get("role", "") == "mole"
	var show := blackout and not is_mole
	_blackout_overlay.visible = show
	if not show:
		return
	# Cover the viewport even with the lit hole at a corner, then center on the rig.
	var viewport_size := Vector2(_viewport.size)
	var span := maxf(viewport_size.x, viewport_size.y) * 2.2
	_blackout_overlay.size = Vector2(span, span)
	var center := viewport_size * 0.5
	var cam: Camera3D = _camera_rig.camera() if _camera_rig != null else null
	var rig := rig_for_slot(my_slot)
	if cam != null and rig != null:
		center = cam.unproject_position(rig.global_position + Vector3(0.0, 1.0, 0.0))
	_blackout_overlay.position = center - _blackout_overlay.size * 0.5


func _update_players() -> void:
	_update_pedestals()
	var mole_slot := int(reveal.get("mole", -1))
	var reveal_votes: Dictionary = reveal.get("votes", {})
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[TheMole.PS_X], state[TheMole.PS_Y]))
		if phase == TheMole.Phase.VOTE or phase == TheMole.Phase.REVEAL:
			# #930: the jury circle only reads as a jury if everyone faces the
			# machine at the center — update_rig only turns rigs while moving,
			# and nobody moves once voting starts.
			rig.rotation.y = atan2(-float(state[TheMole.PS_X]), -float(state[TheMole.PS_Y]))
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


## Voting pedestals (#1160): during VOTE phase, each player stands on a small
## colored disc that elevates slightly, so the jury circle reads clearly.
## Hidden during other phases.
func _update_pedestals() -> void:
	var show := phase == TheMole.Phase.VOTE
	for i in _pedestal_nodes.size():
		var node: MeshInstance3D = _pedestal_nodes[i]
		if show and i < players.size():
			var slot: int = players.keys()[i]
			var state: Array = players[slot]
			node.visible = true
			node.position = to_arena(
				Vector2(float(state[TheMole.PS_X]), float(state[TheMole.PS_Y])), PEDESTAL_ELEVATION
			)
		else:
			node.visible = false


func _update_cells() -> void:
	sync_pool(_cell_nodes, cells.size(), _make_cell, _place_cell)


func _make_cell() -> Node3D:
	var node := CRATE_SCENE.instantiate() as Node3D
	node.scale = Vector3(CELL_SIZE, CELL_SIZE, CELL_SIZE) * 0.8
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
	# Display screen (#1160): emissive green intensity scales with progress.
	if _screen_material != null:
		_screen_material.emission_energy_multiplier = 0.2 + fill * 1.5
	# Progress light ring (#1160): lights up in sequence as fuel is delivered.
	var lit_count := int(fill * PROGRESS_LIGHT_COUNT)
	for i in PROGRESS_LIGHT_COUNT:
		if i < _progress_lights.size():
			var node: MeshInstance3D = _progress_lights[i]
			var mat := node.mesh.material as StandardMaterial3D
			if mat != null:
				if i < lit_count:
					mat.emission_energy_multiplier = 1.0
				else:
					mat.emission_energy_multiplier = 0.0


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
				if blackout:
					_banner.text = "Lights out! Reposition — the reveal retraces where you stand"
				else:
					var bl := (
						"  ·  Blackout ready (E)"
						if private_state.get("blackout_ready", false)
						else ""
					)
					_banner.text = (
						"You are the MOLE — sabotage near the machine (SPACE)%s  ·  %d/%d"
						% [bl, progress, target]
					)
				_banner.modulate = MOLE_COLOR
			elif blackout:
				_banner.text = "⚫ LIGHTS OUT — remember who's where!"
				_banner.modulate = Color(0.75, 0.75, 0.85)
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
