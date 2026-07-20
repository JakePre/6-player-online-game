extends MinigameView3D
## Quick Draw client view (M8-08): renders the standoff in the shared 2.5D
## iso-arena (M8-01, MinigameView3D) — rigs lined up in a row, a signal lamp
## that flips red (WAIT) to green (DRAW!), the round winner cheering and
## false-starters flinching, with win tallies on the nameplates. The WAIT /
## DRAW! call-out and round counter stay as Control-layer labels over the
## viewport since reading them instantly is the game. Presentation-tier swap
## only: state storage and the render contract are unchanged from the 2D
## pass (M4-06).
##
## GFX enhancements (#1151): western backdrop via scatter_rim_props (cacti,
## rocks, barrels, fences), sand-packed floor texture, desert mood, holster
## props on rigs, duelist ground name labels, bullet trail on DRAW, rolling
## tumbleweed during WAIT phase.

const WAITING_COLOR := Color(0.7, 0.15, 0.15)
const LIVE_COLOR := Color(0.2, 0.75, 0.3)
const ROUND_OVER_COLOR := Color(0.35, 0.38, 0.45)
## Base half-extent for the 6-player row (M15); scales for larger lobbies so
## the wider, deeper row formation (M15-07 LaneLayout) still fits the floor
## and camera.
const BASE_ARENA_HALF := 6.0
const ROW_SPACING := 2.0
## Depth between duel rows when the line-up wraps (M15-07): crowds past one
## row's worth stand in staggered ranks instead of overflowing the arena.
const ROW_GAP := 1.7
const LAMP_RADIUS := 0.45
const LAMP_HEIGHT := 3.2
## FX pass (#302): the go-signal flare and the winner fanfare.
const FLASH_SEC := 0.28
const LAMP_FLARE_SEC := 0.35
const BURST_SEC := 0.55
const CONFETTI_COLORS: Array[Color] = [
	Color(1.0, 0.85, 0.2), Color(0.95, 0.3, 0.35), Color(0.35, 0.7, 1.0), Color(0.4, 0.9, 0.5)
]
## Western backdrop rim props (#1151): cacti, rocks, barrels, and fences
## scattered around the arena perimeter via the shared scatter_rim_props helper.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_nature_kit/cactus_short.glb"),
	preload("res://assets/environment/kenney_nature_kit/cactus_tall.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_smallA.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_smallB.glb"),
	preload("res://assets/environment/kenney_platformer_kit/barrel.glb"),
]
const RIM_PROP_COUNT := 16
const RIM_PROP_SEED := 0xDEAD
## Sand-packed western floor (#1151).
const SAND_FLOOR := preload("res://assets/generated/textures/sand-packed.png")
## Holster prop size (#1151): small box at the rig's hip.
const HOLSTER_SIZE := Vector3(0.15, 0.25, 0.08)
const HOLSTER_COLOR := Color(0.35, 0.25, 0.15)
## Tumbleweed (#1151): torus ring that rolls during WAIT.
const TUMBLEWEED_RADIUS := 0.3
const TUMBLEWEED_TUBE := 0.06
const TUMBLEWEED_SPEED := 0.6
## Bullet trail (#1151): gold tracer duration and width.
const TRAIL_DURATION := 0.25
const TRAIL_COLOR := Color(1.0, 0.85, 0.15)

var _phase: int = QuickDraw.Phase.WAITING
var _round := 0
var _rounds_total := QuickDraw.ROUNDS_TO_PLAY
var _wins := {}
var _false_started := {}
var _winner := -1

var _lamp_material: StandardMaterial3D
var _signal_label: Label
var _round_label: Label
## FX state (#302): screen flash overlay, one-shot transition guards, and a
## brief lamp-flare clock.
var _flash_rect: ColorRect
var _prev_phase: int = QuickDraw.Phase.WAITING
var _fanfare_round := -1
var _lamp_flare_until := 0.0
## Ground name labels (#1151): Label3D per slot at floor level.
var _ground_labels: Dictionary  # slot -> Label3D
## Tumbleweed (#1151): the rolling torus and its animation state.
var _tumbleweed: MeshInstance3D
var _tumbleweed_pos := 0.0
var _tumbleweed_forward := true


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"action_primary"):
		NetManager.send_match_input({"press": true})
	_update_lamp()
	_update_tumbleweed(delta)


## Sandy high-noon floor (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.9, 0.72)


## formula-twin — must mirror QuickDraw._setup (scaled _play_half). The sim
## derives _play_half = MinigameScaling.arena_half(BASE_ARENA_HALF, slots.size());
## this view re-derives the same value. If the scaling formula changes in the
## sim but not here, the rendered floor/camera will mismatch the sim's arena.
func _arena_half() -> float:
	return MinigameScaling.arena_half(BASE_ARENA_HALF, names.size())


## Western desert floor (#1151): sand-packed texture instead of default tiles.
func _build_floor() -> void:
	var half := _arena_half()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(half * 2.0, half * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = SAND_FLOOR
	material.albedo_color = Color(1.0, 0.9, 0.72)
	material.metallic = 0.0
	material.roughness = 0.85
	mesh.material = material
	var floor_node := MeshInstance3D.new()
	floor_node.name = "SandFloor"
	floor_node.mesh = mesh
	floor_node.position.y = -0.01
	arena.add_child(floor_node)


## Warm desert mood (#1151): golden-hour atmosphere for the backdrop.
func _mood() -> Color:
	return Color(0.18, 0.12, 0.06).lerp(Color(0.45, 0.35, 0.2), 0.3)


func _setup_3d() -> void:
	_line_up_rigs()
	_build_lamp()
	_build_labels()
	_build_flash()
	_build_holsters()
	_build_ground_labels()
	_build_tumbleweed()
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)


func _render_3d(game: Dictionary) -> void:
	_phase = game.get("phase", QuickDraw.Phase.WAITING)
	_round = game.get("round", 0)
	_rounds_total = game.get("rounds_total", QuickDraw.ROUNDS_TO_PLAY)
	_wins = game.get("wins", {})
	_false_started = game.get("false_started", {})
	_winner = game.get("winner", -1)
	_fire_transition_fx()
	_update_labels()
	_update_lamp()
	_update_rigs()
	_update_ground_labels()


## One-shot FX on the phase edges (#302): a punchy flash the instant it goes
## live, and a fanfare when the round resolves.
func _fire_transition_fx() -> void:
	if _phase != _prev_phase:
		if _phase == QuickDraw.Phase.LIVE:
			_draw_flash()
		elif _phase == QuickDraw.Phase.ROUND_OVER:
			_resolve_fx()
		_prev_phase = _phase


## The go signal: screen flash, lamp flare, a sharp cue and a jolt — the
## moment the whole game hinges on. Plus a dust burst (#1151) and bullet trail
## from the winner's position to center.
func _draw_flash() -> void:
	_lamp_flare_until = _now() + LAMP_FLARE_SEC
	# Signature cue (#728): the go-signal snap, not a UI accept.
	play_sfx(&"laser")
	request_shake(9.0)
	if _flash_rect != null and not ArenaFX.reduced_motion:
		_flash_rect.color = Color(0.7, 1.0, 0.75, 0.55)
		var tween := _flash_rect.create_tween()
		tween.tween_property(_flash_rect, "color:a", 0.0, FLASH_SEC)
	# Dust burst at center (#1151): the draw moment kicks up sand.
	if not ArenaFX.reduced_motion:
		fx_dust(Vector2.ZERO)
		# Secondary dust ring: a ring of small dust puffs around center.
		for i in 6:
			var angle := TAU * i / 6.0
			var offset := Vector2(cos(angle), sin(angle)) * 0.5
			fx_dust(offset)


## Round result: fanfare + confetti over the winner, or an error sting on a
## false-start-only bust. Guarded to fire once per round.
func _resolve_fx() -> void:
	if _fanfare_round == _round:
		return
	_fanfare_round = _round
	if _winner != -1:
		# `round_win`/`round_lose` are chrome's per-match-round stingers
		# (docs/AUDIO_GUIDE.md) — a duel here is a sub-round inside one
		# minigame session, so reusing them would double-fire the same jingle
		# for a different meaning (the #591 collision class). `bell` is this
		# batch's bright-positive signature cue instead.
		play_sfx(&"bell")
		var rig := rig_for_slot(_winner)
		if rig != null:
			_confetti_burst(rig.position)
		# Bullet trail (#1151): gold streak from winner to center on DRAW.
		if rig != null and not ArenaFX.reduced_motion:
			_bullet_trail(rig.position, Vector3(0.0, 1.0, 0.0))
	elif not _false_started.is_empty():
		play_sfx(&"error")


## A fountain of colored cubes over the winner — cheap, deterministic confetti
## sized to read at iso distance.
func _confetti_burst(origin: Vector3) -> void:
	if ArenaFX.reduced_motion:
		return
	for i in 14:
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * 0.32
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var color: Color = CONFETTI_COLORS[i % CONFETTI_COLORS.size()]
		material.albedo_color = color
		mesh.material = material
		var shard := MeshInstance3D.new()
		shard.mesh = mesh
		# Start above the nameplate band (rigs cluster tight in this game) so
		# the fountain reads clear of the labels.
		shard.position = origin + Vector3(0.0, 3.2, 0.0)
		arena.add_child(shard)
		var angle := TAU * i / 14.0
		var reach := 0.8 + float(i % 3) * 0.5
		var rise := origin + Vector3(cos(angle) * reach, 4.8, sin(angle) * reach)
		var tween := shard.create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position", rise, BURST_SEC).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(shard, "rotation", Vector3(angle * 3.0, angle * 2.0, angle), BURST_SEC)
		tween.tween_property(material, "albedo_color:a", 0.0, BURST_SEC).set_delay(BURST_SEC * 0.4)
		tween.chain().tween_callback(shard.queue_free)


## Duelists stand in a row facing the camera; there is no movement in this
## game, so rigs are placed once instead of via update_rig. Crowds wrap into
## staggered ranks behind the front row (M15-07).
func _line_up_rigs() -> void:
	var slots: Array = names.keys()
	slots.sort()
	var offsets := LaneLayout.row_positions(slots.size(), ROW_SPACING, ROW_GAP)
	for i in slots.size():
		var rig := rig_for_slot(slots[i])
		if rig == null:
			continue
		rig.position = to_arena(offsets[i])
		rig.rotation.y = PI * 0.75  # face the iso camera


## Small holster prop on each rig's hip (#1151): a brown BoxMesh at about
## waist height, offset to the rig's side.
func _build_holsters() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var holster := MeshInstance3D.new()
		holster.name = "Holster_%d" % slot
		var mesh := BoxMesh.new()
		mesh.size = HOLSTER_SIZE
		var material := StandardMaterial3D.new()
		material.albedo_color = HOLSTER_COLOR
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = material
		holster.mesh = mesh
		# Offset to the rig's right hip side, at waist height.
		holster.position = Vector3(0.25, 0.75, -0.1)
		holster.rotation.z = 0.15  # slight cant for natural look
		rig.add_child(holster)


## Ground name labels (#1151): a Label3D per slot, billboarded, at ankle height
## so duelist names are readable on the arena floor.
func _build_ground_labels() -> void:
	for slot: int in names:
		var label := Label3D.new()
		label.name = "GroundName_%d" % slot
		label.text = player_name(slot)
		label.font_size = 18
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color(1.0, 0.95, 0.8, 0.85)
		label.outline_modulate = Color(0.1, 0.05, 0.02, 0.6)
		label.outline_size = 2
		label.fixed_size = false
		var rig := rig_for_slot(slot)
		if rig != null:
			label.position = rig.position + Vector3(0.0, 0.05, 0.0)
		arena.add_child(label)
		_ground_labels[slot] = label


## Update ground label positions to follow rigs and reflect current names.
func _update_ground_labels() -> void:
	for slot: int in names:
		var label: Label3D = _ground_labels.get(slot)
		if label == null:
			continue
		var rig := rig_for_slot(slot)
		if rig != null:
			label.position = rig.position + Vector3(0.0, 0.05, 0.0)
		label.text = player_name(slot)


## Tumbleweed (#1151): a torus that rolls back and forth across the arena floor
## during the WAIT phase, adding western atmosphere.
func _build_tumbleweed() -> void:
	if ArenaFX.reduced_motion:
		return
	var mesh := TorusMesh.new()
	mesh.inner_radius = TUMBLEWEED_RADIUS
	mesh.outer_radius = TUMBLEWEED_RADIUS + TUMBLEWEED_TUBE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.4, 0.25)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.metallic = 0.0
	material.roughness = 0.8
	mesh.material = material
	_tumbleweed = MeshInstance3D.new()
	_tumbleweed.name = "Tumbleweed"
	_tumbleweed.mesh = mesh
	_tumbleweed.position = Vector3(0.0, TUMBLEWEED_TUBE, 0.0)
	_tumbleweed_pos = 0.0
	_tumbleweed_forward = true
	arena.add_child(_tumbleweed)


## Animate the tumbleweed: rolls slowly across the arena during WAIT, resets
## to center on other phases, and hides when the game isn't waiting.
func _update_tumbleweed(delta: float) -> void:
	if _tumbleweed == null:
		return
	if _phase == QuickDraw.Phase.WAITING:
		_tumbleweed.visible = true
		var half := _arena_half()
		_tumbleweed_pos += delta * TUMBLEWEED_SPEED * (1.0 if _tumbleweed_forward else -1.0)
		if absf(_tumbleweed_pos) >= half * 0.7:
			_tumbleweed_forward = not _tumbleweed_forward
		_tumbleweed.position.x = clampf(_tumbleweed_pos, -half * 0.7, half * 0.7)
		# Rotate the torus around its local Z axis to simulate rolling.
		_tumbleweed.rotate_z(delta * TUMBLEWEED_SPEED * 6.0)
		# Slight side-to-side wobble for natural drift.
		_tumbleweed.position.z = sin(_now() * 0.5) * 0.3
	else:
		_tumbleweed.visible = false
		_tumbleweed_pos = 0.0
		_tumbleweed_forward = true


## Gold bullet trail (#1151): a brief, bright tracer streak from `origin` toward
## `target`, self-freeing after TRAIL_DURATION seconds.
func _bullet_trail(origin: Vector3, target: Vector3) -> void:
	if ArenaFX.reduced_motion:
		return
	var mid := origin.lerp(target, 0.5)
	mid.y += 0.5  # slight arc
	var points := PackedVector3Array([origin, mid, target])
	var trail := MeshInstance3D.new()
	trail.name = "BulletTrail"
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = TRAIL_COLOR
	material.emission_enabled = true
	material.emission = TRAIL_COLOR
	material.emission_energy_multiplier = 3.0
	trail.mesh = mesh
	trail.material_override = material
	arena.add_child(trail)
	# Fade out and free.
	var tween := trail.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, TRAIL_DURATION)
	tween.parallel().tween_property(material, "emission_energy_multiplier", 0.0, TRAIL_DURATION)
	tween.chain().tween_callback(trail.queue_free)


func _build_lamp() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = LAMP_RADIUS
	mesh.height = LAMP_RADIUS * 2.0
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.emission_enabled = true
	mesh.material = _lamp_material
	var lamp := MeshInstance3D.new()
	lamp.name = "SignalLamp"
	lamp.mesh = mesh
	lamp.position = Vector3(0.0, LAMP_HEIGHT, 0.0)
	arena.add_child(lamp)


func _build_labels() -> void:
	_signal_label = make_status_label(&"SignalLabel")
	_round_label = make_status_label(&"RoundLabel", PartyTheme.SIZE_OVERLAY_BODY)
	# #924: gap below the primary line, relative to the chrome-cleared baseline.
	_round_label.position.y = MinigameView3D.CHROME_CLEARANCE_Y + 56.0


func _build_flash() -> void:
	_flash_rect = ColorRect.new()
	_flash_rect.name = "DrawFlash"
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)


func _update_labels() -> void:
	_signal_label.text = _signal_text()
	_signal_label.add_theme_color_override(&"font_color", _signal_color())
	_round_label.text = "Round %d / %d" % [_round + 1, _rounds_total]


## Lamp shows the phase color, flaring bright for a beat as the signal drops
## (#302) so the go-moment pops even without looking at the label.
func _update_lamp() -> void:
	if _lamp_material == null:
		return
	var color := _signal_color()
	_lamp_material.albedo_color = color
	_lamp_material.emission = color
	var flaring := _now() < _lamp_flare_until
	_lamp_material.emission_energy_multiplier = 4.0 if flaring else 1.0


## Winner cheers, false-starters flinch, everyone else idles. play() is
## guarded by current_action() so non-looping poses are not restarted every
## snapshot.
func _update_rigs() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		# Rigs are pooled hidden (#601); a stationary view that places them once
		# in _line_up_rigs never calls update_rig, so without this reveal the
		# duelists never appear at all (#780). Reveal only the round's actual
		# participants (the snapshot's wins keys), so a disconnected member's rig
		# stays hidden — the same snapshot-driven reveal Bullseye Bowl uses.
		if _wins.has(slot):
			reveal_rig(slot)
		var caption := "%s  %d" % [player_name(slot), int(_wins.get(slot, 0))]
		var desired: StringName = &"idle"
		if _phase == QuickDraw.Phase.ROUND_OVER:
			if slot == _winner:
				desired = &"cheer"
			elif _false_started.has(slot):
				desired = &"hit"
				caption += "  (false start!)"
		if rig.current_action() != desired:
			rig.play(desired)
		rig.display_name = caption


func _signal_text() -> String:
	match _phase:
		QuickDraw.Phase.WAITING:
			return "WAIT..."
		QuickDraw.Phase.LIVE:
			return "DRAW!"
		_:
			return "%s wins the round!" % player_name(_winner) if _winner != -1 else "No winner"


func _signal_color() -> Color:
	match _phase:
		QuickDraw.Phase.WAITING:
			return WAITING_COLOR
		QuickDraw.Phase.LIVE:
			return LIVE_COLOR
		_:
			return ROUND_OVER_COLOR


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
