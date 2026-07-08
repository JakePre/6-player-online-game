extends SideScrollView
## Loadout Duel client view (M14-01): renders the replicated arena over the
## M14-00 side-scroll base — the shared stage, weapon daises, in-flight
## projectiles, held-weapon and shield markers, KO'd ducks, and the
## round/score chrome. Simulates nothing locally.
##
## Input: A/D run + W/Space jump go through the base's move axis; J fires,
## K throws (action_primary / action_secondary).

const KIND_COLORS := {
	LoadoutDuel.Kind.BLASTER: Color(0.5, 0.8, 1.0),
	LoadoutDuel.Kind.SCATTER: Color(1.0, 0.7, 0.35),
	LoadoutDuel.Kind.BOOMER: Color(1.0, 0.45, 0.35),
	LoadoutDuel.Kind.HAMMER: Color(0.75, 0.6, 0.95),
	LoadoutDuel.Kind.SHIELD: Color(0.4, 0.85, 0.55),
}
const KO_MODULATE := Color(0.4, 0.4, 0.45, 0.75)

var players := {}
var shots: Array = []
var dais_states: Array = []
var phase: int = LoadoutDuel.Phase.COUNTDOWN
var sub_round := 0

var _fx_layer: Control
var _hud: Label
var _alive_seen := {}
## Last-seen shot count, for the fire edge (#728) — shots only grow between a
## fire and its resolution, so a size increase is a fresh shot.
var _shots_seen := 0
var _seen_snapshot := false


func _ready() -> void:
	super()
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
	setup_stage(
		LoadoutDuel.solid_platforms(), LoadoutDuel.one_way_platforms(), LoadoutDuel.stage_bounds()
	)


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
		NetManager.send_match_input({"fire": true})
	elif event.is_action_pressed(&"action_secondary"):
		NetManager.send_match_input({"throw": true})


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	shots = game.get("shots", [])
	dais_states = game.get("daises", [])
	phase = int(game.get("phase", LoadoutDuel.Phase.COUNTDOWN))
	sub_round = int(game.get("sub_round", 0))
	# Signature cue (#728, docs/AUDIO_GUIDE.md — Brawlers): any fresh shot
	# (blaster, scatter, or a thrown boomer/hammer) reads as `laser`.
	if _seen_snapshot and shots.size() > _shots_seen:
		play_sfx(&"laser")
	_shots_seen = shots.size()
	render_side_scroll(players)
	for slot: int in players:
		_render_fighter(slot, players[slot])
	_update_hud(game.get("scores", {}))
	if _fx_layer != null:
		_fx_layer.queue_redraw()
	_seen_snapshot = true


func _render_fighter(slot: int, state: Array) -> void:
	if state.size() < LoadoutDuel.PS_COUNT:
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	var flags := int(state[LoadoutDuel.PS_FLAGS])
	var alive := flags & 1 > 0
	rig.modulate = Color.WHITE if alive else KO_MODULATE
	# KO edge: shake + the shared elimination cue for everyone, seeded so a
	# rejoiner stays quiet.
	var was_alive: bool = _alive_seen.get(slot, true)
	if _seen_snapshot and was_alive and not alive:
		request_shake(7.0)
		play_sfx(&"ko")
	_alive_seen[slot] = alive


func _update_hud(scores: Dictionary) -> void:
	if _hud == null:
		return
	var banner := ""
	match phase:
		LoadoutDuel.Phase.COUNTDOWN:
			banner = "Round %d — Ready…" % (sub_round + 1)
		LoadoutDuel.Phase.FIGHT:
			banner = "Round %d — FIGHT!" % (sub_round + 1)
		LoadoutDuel.Phase.ROUND_OVER:
			banner = "Round %d over" % (sub_round + 1)
	var parts: Array = []
	for slot: int in scores:
		parts.append("%s %d" % [player_name(slot), int(scores[slot])])
	_hud.text = "%s    %s" % [banner, "  ·  ".join(parts)]


## Daises (colored pads with an icon, dimmed while cooling), then projectiles
## and per-fighter held/shield markers — all in world→screen space.
func _draw_fx() -> void:
	for dais in dais_states:
		var kind := int(dais[LoadoutDuel.DS_KIND])
		var at := world_to_screen(
			Vector2(float(dais[LoadoutDuel.DS_X]), float(dais[LoadoutDuel.DS_Y]))
		)
		var color: Color = KIND_COLORS.get(kind, PartyTheme.BG_RAISED)
		if kind == LoadoutDuel.Kind.NONE:
			color = PartyTheme.BG_RAISED
		var radius := 10.0 * _world_scale() / 20.0 + 6.0
		_fx_layer.draw_circle(
			at, radius, Color(color, 0.9 if kind != LoadoutDuel.Kind.NONE else 0.4)
		)
	for shot in shots:
		var at := world_to_screen(
			Vector2(float(shot[LoadoutDuel.SH_X]), float(shot[LoadoutDuel.SH_Y]))
		)
		var shot_kind := int(shot[LoadoutDuel.SH_KIND])
		if shot_kind == LoadoutDuel.Shot.THROWN:
			_fx_layer.draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), PartyTheme.TEXT)
		elif shot_kind == LoadoutDuel.Shot.LOB:
			_fx_layer.draw_circle(at, 7.0, KIND_COLORS[LoadoutDuel.Kind.BOOMER])
		else:
			_fx_layer.draw_circle(at, 4.0, PartyTheme.ACCENT_BRIGHT)
	for slot: int in players:
		_draw_fighter_markers(players[slot])


func _draw_fighter_markers(state: Array) -> void:
	if state.size() < LoadoutDuel.PS_COUNT or int(state[LoadoutDuel.PS_FLAGS]) & 1 == 0:
		return
	var center := world_to_screen(
		Vector2(float(state[LoadoutDuel.PS_X]), float(state[LoadoutDuel.PS_Y]))
	)
	var facing := int(state[LoadoutDuel.PS_FACING])
	var held := int(state[LoadoutDuel.PS_HELD])
	if held != LoadoutDuel.Kind.NONE:
		var muzzle := center + Vector2(float(facing) * 18.0, -2.0)
		_fx_layer.draw_circle(muzzle, 5.0, KIND_COLORS.get(held, PartyTheme.TEXT))
	if int(state[LoadoutDuel.PS_FLAGS]) & 2 > 0:
		_fx_layer.draw_arc(center, 22.0, 0.0, TAU, 20, KIND_COLORS[LoadoutDuel.Kind.SHIELD], 3.0)
