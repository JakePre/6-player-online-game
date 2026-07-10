extends SideScrollView
## Knock-Off client view (M14-03): renders the replicated brawl over the
## M14-00 side-scroll base — the small stage, each fighter's damage percent
## on their nameplate (reddening as it climbs), attack-swing flashes, and
## KO'd ducks greyed out. Simulates nothing locally.
##
## Input: A/D run + W/Space jump through the base move axis; J jabs, K smashes.

const KO_MODULATE := Color(0.4, 0.4, 0.45, 0.7)
const SWING_COLOR := Color(1.0, 0.95, 0.6)
const SMASH_COLOR := Color(1.0, 0.55, 0.3)
const SWING_LIFE := 0.18

## #789: the sim frees a KO'd body the instant it rings out (see
## test_falling_off_the_stage_is_a_ko), so every snapshot after death reports
## (0, 0) — without a client-side tumble the corpse would teleport to stage
## center and sit there grey for the rest of the round. The tumble drifts
## from the last real pose instead and owns the rig until it fades out.
const KO_TUMBLE_SEC := 0.7
const KO_SPIN_SPEED := 9.0
const KO_DRIFT := Vector2(3.5, -3.0)

## Brief rig poses layered on top of the base pose/interpolation: a lunge on
## your own swing, a red flinch flash when a hit lands.
const SWING_POSE_SEC := 0.15
const HIT_POSE_SEC := 0.22
const HIT_FLASH_COLOR := Color(1.0, 0.35, 0.3)

var players := {}
var phase: int = KnockOff.Phase.COUNTDOWN

var _fx_layer: Control
var _hud: Label
## Transient swing arcs: {pos, facing, color, age}.
var _swings: Array[Dictionary] = []
var _alive_seen := {}
## slot -> last-seen damage percent, for the hit/hit_heavy edge (#728).
var _percent_seen := {}
var _seen_snapshot := false
## slot -> pose the instant they were last seen alive, so a KO tumble has
## somewhere real to drift from instead of the wire's post-death (0, 0).
var _last_alive_pos := {}
var _last_alive_facing := {}
## slot -> {origin, dir, age}, active while a KO'd rig is tumbling off.
var _tumbles := {}
## slot -> {facing, age}, active while an attack lunge is playing.
var _swing_pose := {}
## slot -> {age}, active while a landed-hit flash is playing.
var _hit_pose := {}


func _ready() -> void:
	super()
	set_process(true)
	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.draw.connect(_draw_fx)
	add_child(_fx_layer)
	_hud = Label.new()
	_hud.theme_type_variation = PartyTheme.HEADER_VARIATION
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)


func _setup() -> void:
	setup_stage(KnockOff.solid_platforms(), KnockOff.one_way_platforms(), KnockOff.stage_bounds())


func _physics_process(_delta: float) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	NetManager.send_match_input({"mx": Input.get_axis(&"move_left", &"move_right")})


func _unhandled_input(event: InputEvent) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	if event.is_action_pressed(&"move_up"):
		NetManager.send_match_input({"jump": true})
	elif event.is_action_pressed(&"action_primary"):
		NetManager.send_match_input({"jab": true})
	elif event.is_action_pressed(&"action_secondary"):
		NetManager.send_match_input({"smash": true})


func _process(delta: float) -> void:
	if not _swings.is_empty():
		var alive: Array[Dictionary] = []
		for swing in _swings:
			swing.age = float(swing.age) + delta
			if float(swing.age) < SWING_LIFE:
				alive.append(swing)
		_swings = alive
		_fx_layer.queue_redraw()
	if not _tumbles.is_empty():
		_advance_tumbles(delta)
	if not _swing_pose.is_empty():
		_advance_swing_pose(delta)
	if not _hit_pose.is_empty():
		_advance_hit_pose(delta)


## Drifts a KO'd rig away from its last real pose, spinning and fading it
## out — then hides it for good, instead of leaving a grey corpse pinned to
## the wire's post-death (0, 0).
func _advance_tumbles(delta: float) -> void:
	var done: Array[int] = []
	for slot: int in _tumbles:
		var tumble: Dictionary = _tumbles[slot]
		tumble.age = float(tumble.age) + delta
		var rig := rig_for_slot(slot)
		if rig == null:
			done.append(slot)
			continue
		var t: float = float(tumble.age)
		var origin: Vector2 = tumble.origin
		var dir: float = float(tumble.dir)
		rig.position = world_to_screen(origin + Vector2(KO_DRIFT.x * dir, KO_DRIFT.y) * t)
		rig.rotation = dir * KO_SPIN_SPEED * t
		var fade := clampf(1.0 - t / KO_TUMBLE_SEC, 0.0, 1.0)
		rig.modulate = Color(KO_MODULATE.r, KO_MODULATE.g, KO_MODULATE.b, KO_MODULATE.a * fade)
		if t >= KO_TUMBLE_SEC:
			rig.visible = false
			done.append(slot)
	for slot: int in done:
		_tumbles.erase(slot)


## A quick squash-lunge on the attacker's own body, on top of the arc flash.
func _advance_swing_pose(delta: float) -> void:
	var done: Array[int] = []
	for slot: int in _swing_pose:
		var pose: Dictionary = _swing_pose[slot]
		pose.age = float(pose.age) + delta
		var t: float = clampf(float(pose.age) / SWING_POSE_SEC, 0.0, 1.0)
		var rig := rig_for_slot(slot)
		if rig != null:
			var body: Panel = rig.get_node("Body")
			body.pivot_offset = body.size / 2.0
			var lunge := sin(t * PI) * 0.18
			body.scale = Vector2(1.0 + lunge, 1.0 - lunge * 0.6)
		if t >= 1.0:
			if rig != null:
				(rig.get_node("Body") as Panel).scale = Vector2.ONE
			done.append(slot)
	for slot: int in done:
		_swing_pose.erase(slot)


## A brief red flash on a landed hit — the flinch a KO'd tumble doesn't cover.
func _advance_hit_pose(delta: float) -> void:
	var done: Array[int] = []
	for slot: int in _hit_pose:
		var pose: Dictionary = _hit_pose[slot]
		pose.age = float(pose.age) + delta
		var t: float = clampf(float(pose.age) / HIT_POSE_SEC, 0.0, 1.0)
		var rig := rig_for_slot(slot)
		if rig != null:
			rig.modulate = Color.WHITE.lerp(HIT_FLASH_COLOR, 1.0 - t)
		if t >= 1.0:
			if rig != null:
				rig.modulate = Color.WHITE
			done.append(slot)
	for slot: int in done:
		_hit_pose.erase(slot)


func _start_tumble(slot: int) -> void:
	var origin: Vector2 = _last_alive_pos.get(slot, Vector2.ZERO)
	var facing: int = int(_last_alive_facing.get(slot, 1))
	var dir := signf(origin.x) if not is_zero_approx(origin.x) else float(facing)
	_tumbles[slot] = {"origin": origin, "dir": dir, "age": 0.0}


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	phase = int(game.get("phase", KnockOff.Phase.COUNTDOWN))
	render_side_scroll(players)
	for slot: int in players:
		_render_fighter(slot, players[slot])
	_update_hud()
	_fx_layer.queue_redraw()
	_seen_snapshot = true


func _render_fighter(slot: int, state: Array) -> void:
	if state.size() < KnockOff.PS_COUNT:
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	var alive := int(state[KnockOff.PS_ALIVE]) == 1
	if alive:
		if not _hit_pose.has(slot):
			rig.modulate = Color.WHITE
		if not _swing_pose.has(slot):
			(rig.get_node("Body") as Panel).scale = Vector2.ONE
		rig.rotation = 0.0
		rig.visible = true
		_last_alive_pos[slot] = Vector2(float(state[KnockOff.PS_X]), float(state[KnockOff.PS_Y]))
		_last_alive_facing[slot] = int(state[KnockOff.PS_FACING])
	else:
		# The tumble (once started) owns position/rotation/modulate from here.
		_samples.erase(slot)
		if not _tumbles.has(slot):
			rig.modulate = KO_MODULATE
	var plate: Label = rig.get_node("Plate")
	var percent := int(state[KnockOff.PS_PERCENT])
	plate.text = "%s  %d%%" % [player_name(slot), percent]
	# Nameplate reddens with damage — the at-a-glance danger read.
	plate.add_theme_color_override(
		&"font_color",
		PlayerPalette.color_for_slot(slot).lerp(SMASH_COLOR, clampf(percent / 130.0, 0.0, 1.0))
	)
	# Signature cues (#728, docs/AUDIO_GUIDE.md — Brawlers): a landed jab is
	# `hit`, a landed smash (double the damage, KnockOff.SMASH_DAMAGE vs
	# JAB_DAMAGE) is `hit_heavy` — the percent delta tells them apart since
	# the snapshot carries no separate "landed" flag.
	var prev_percent: int = _percent_seen.get(slot, percent)
	if _seen_snapshot and percent > prev_percent:
		play_sfx(&"hit_heavy" if percent - prev_percent >= 12 else &"hit")
		_hit_pose[slot] = {"age": 0.0}
	_percent_seen[slot] = percent
	var attack := int(state[KnockOff.PS_ATTACK])
	if attack > 0:
		(
			_swings
			. append(
				{
					"pos": Vector2(float(state[KnockOff.PS_X]), float(state[KnockOff.PS_Y])),
					"facing": int(state[KnockOff.PS_FACING]),
					"color": SMASH_COLOR if attack == 2 else SWING_COLOR,
					"age": 0.0,
				}
			)
		)
		_swing_pose[slot] = {"facing": int(state[KnockOff.PS_FACING]), "age": 0.0}
	# KO edge: shake + the shared elimination cue for everyone (the whole
	# stage sees a duck fly off), seeded so a rejoiner stays quiet.
	var was_alive: bool = _alive_seen.get(slot, true)
	if _seen_snapshot and was_alive and not alive:
		request_shake(8.0)
		play_sfx(&"ko")
		_start_tumble(slot)
	_alive_seen[slot] = alive


func _update_hud() -> void:
	if _hud == null:
		return
	var standing := 0
	for slot: int in players:
		if int(players[slot][3]) == 1:
			standing += 1
	match phase:
		KnockOff.Phase.COUNTDOWN:
			_hud.text = "Get ready…"
		KnockOff.Phase.FIGHT:
			_hud.text = "%d left — knock 'em off!" % standing
		_:
			_hud.text = "K.O.!"


func _draw_fx() -> void:
	for swing in _swings:
		var center := world_to_screen(swing.pos)
		var reach := _attack_arc_px()
		var facing: float = signf(float(swing.facing))
		var fade := 1.0 - float(swing.age) / SWING_LIFE
		var color: Color = swing.color
		color.a = fade
		var from := -0.5 * facing
		var to := 0.6 * facing
		_fx_layer.draw_arc(center + Vector2(facing * 6.0, 0.0), reach, from, to, 10, color, 4.0)


func _attack_arc_px() -> float:
	return KnockOff.ATTACK_RANGE * _world_scale()
