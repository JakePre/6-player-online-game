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
	if _swings.is_empty():
		return
	var alive: Array[Dictionary] = []
	for swing in _swings:
		swing.age = float(swing.age) + delta
		if float(swing.age) < SWING_LIFE:
			alive.append(swing)
	_swings = alive
	_fx_layer.queue_redraw()


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
	if state.size() < 6:
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	var alive := int(state[3]) == 1
	rig.modulate = Color.WHITE if alive else KO_MODULATE
	var plate: Label = rig.get_node("Plate")
	var percent := int(state[4])
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
	_percent_seen[slot] = percent
	var attack := int(state[5])
	if attack > 0:
		(
			_swings
			. append(
				{
					"pos": Vector2(float(state[0]), float(state[1])),
					"facing": int(state[2]),
					"color": SMASH_COLOR if attack == 2 else SWING_COLOR,
					"age": 0.0,
				}
			)
		)
	# KO edge: shake + the shared elimination cue for everyone (the whole
	# stage sees a duck fly off), seeded so a rejoiner stays quiet.
	var was_alive: bool = _alive_seen.get(slot, true)
	if _seen_snapshot and was_alive and not alive:
		request_shake(8.0)
		play_sfx(&"ko")
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
