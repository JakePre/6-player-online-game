extends SideScrollView
## Tumble Run client view (M14-09): renders the vertical climb over the
## M14-00 side-scroll base — the laddered stage with crumble ledges shown
## only while solid, falling boulders, stunned/summited climbers, a summit
## marker, and the climb standings. Simulates nothing locally.
##
## Input: A/D run + W/Space jump through the base move axis. No attacks.

## Declarative button input (#947): jump is momentary; the move axis stays a
## hand-rolled _process send (a continuous vector, not a button).
const INPUT_ACTIONS := {&"move_up": "jump"}

const BOULDER_COLOR := Color(0.42, 0.29, 0.22)
## Hazard read (#925): boulders wear a hot warning glow + a dark rim so they
## never blur into the cool, soft backdrop clouds behind the stage.
const BOULDER_GLOW := Color(1.0, 0.45, 0.2, 0.35)
const BOULDER_RIM := Color(0.12, 0.08, 0.06)
const SUMMIT_COLOR := Color(0.96, 0.79, 0.2)
const CRUMBLE_COLOR := Color(0.7, 0.45, 0.3)
const STUN_MODULATE := Color(1.0, 0.7, 0.5, 0.85)
const SUMMIT_MODULATE := Color(1.0, 1.0, 0.7)
const BOULDER_CRACK_COLOR := Color(0.25, 0.18, 0.14)
## Rope ladder rung lines on stable ledges.
const RUNG_COLOR := Color(0.5, 0.35, 0.2)
## Summit flag colors.
const FLAG_POLE_COLOR := Color(0.7, 0.7, 0.7)
const FLAG_COLOR := Color(0.96, 0.79, 0.2)

var players := {}
var crumble: Array = []
var standings: Array = []
var boulders: Array = []
var clock := 0.0

var _fx_layer: Control
var _hud: Label
## Parallel to TumbleRun.ledges(): the panel node for each crumble ledge,
## kept only for those that actually crumble (rest are static base platforms).
var _crumble_nodes := {}
var _summit_seen := {}
## slot -> was stunned last render, for the boulder-hit cue (#728).
var _stun_seen := {}
var _seen_snapshot := false
## True once any climber reaches the summit — gates the flag animation.
var _any_summited := false


func _ready() -> void:
	super()
	_ensure_chrome()


## Chrome (fx layer + HUD) is built lazily + idempotently because _setup()
## runs before _ready() in the production mount order and creates crumble
## panels into _fx_layer (#575). Building only in _ready() left it null.
func _ensure_chrome() -> void:
	if _fx_layer != null:
		return
	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.draw.connect(_draw_fx)
	add_child(_fx_layer)
	# HUD below the match chrome via the shared helper (#925 clip fix).
	_hud = make_sidescroll_hud()
	resized.connect(_layout_crumble)


func _setup() -> void:
	# The base draws solids + one-way from the sim's static layout; the
	# always-solid floor and summit go through it, plus the full ledge
	# ladder. Crumble ledges get their own toggleable panels on top.
	# Order matters: setup_stage() builds the base layers (bottom), then
	# _ensure_chrome() puts the fx layer + HUD on top of them.
	var base_solids := TumbleRun.solid_platforms()
	setup_stage(base_solids, TumbleRun.ledges(), TumbleRun.stage_bounds())
	_ensure_chrome()
	for index in TumbleRun._crumble_indices():
		var node := _make_crumble_panel()
		_crumble_nodes[index] = node
	_layout_crumble()


func _make_crumble_panel() -> Panel:
	var node := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CRUMBLE_COLOR
	style.set_corner_radius_all(PartyTheme.RADIUS_SM)
	node.add_theme_stylebox_override(&"panel", style)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(node)
	return node


func _layout_crumble() -> void:
	var rects := TumbleRun.ledges()
	for index: int in _crumble_nodes:
		var rect: Rect2 = rects[index]
		var top_left := world_to_screen(Vector2(rect.position.x, rect.position.y + rect.size.y))
		var node: Panel = _crumble_nodes[index]
		node.position = top_left
		node.size = rect.size * _world_scale()


func _physics_process(_delta: float) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	NetManager.send_match_input({"mx": Input.get_axis(&"move_left", &"move_right")})


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	crumble = game.get("crumble", [])
	standings = game.get("standings", [])
	boulders = game.get("boulders", [])
	clock = float(game.get("clock", 0.0))
	render_side_scroll(players)
	for slot: int in players:
		_render_climber(slot, players[slot])
	# A crumble ledge shows only while the sim says it's solid.
	for index: int in _crumble_nodes:
		var solid: bool = index < crumble.size() and bool(crumble[index])
		_crumble_nodes[index].visible = solid
	_update_hud()
	# Track summit flag: any player with the summit bit set.
	_any_summited = false
	for slot: int in players:
		var state: Array = players[slot]
		if state.size() >= TumbleRun.PS_COUNT and int(state[TumbleRun.PS_FLAGS]) & 2 > 0:
			_any_summited = true
			break
	_fx_layer.queue_redraw()
	_seen_snapshot = true


func _render_climber(slot: int, state: Array) -> void:
	if state.size() < TumbleRun.PS_COUNT:
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	var flags := int(state[TumbleRun.PS_FLAGS])
	var stunned := flags & 1 > 0
	var summited := flags & 2 > 0
	if summited:
		rig.modulate = SUMMIT_MODULATE
	elif stunned:
		rig.modulate = STUN_MODULATE
	else:
		rig.modulate = Color.WHITE
	# Summit edge: a sparkle-shake + local chime, seeded for rejoiners.
	if _seen_snapshot and summited and not _summit_seen.get(slot, false):
		request_shake(5.0)
		if slot == my_slot:
			# The reach-the-top checkpoint (#728), replacing generic UI confirm.
			play_sfx(&"bell")
	_summit_seen[slot] = summited
	# Boulder-hit edge: `thud`'s vocabulary entry names "boulder" directly.
	if _seen_snapshot and stunned and not _stun_seen.get(slot, false) and slot == my_slot:
		play_sfx(&"thud")
	_stun_seen[slot] = stunned


func _update_hud() -> void:
	if _hud == null:
		return
	var leader := ""
	if not standings.is_empty():
		leader = str(names.get(int(standings[0]), "P%d" % int(standings[0])))
	# #1065: your own finish is a headline, not a silent tint — and once the
	# first climber tops out, the finish window is a visible countdown.
	var my_state: Array = players.get(my_slot, [])
	var mine_done := (
		my_state.size() >= TumbleRun.PS_COUNT and int(my_state[TumbleRun.PS_FLAGS]) & 2 > 0
	)
	var line := "Climb to the top!"
	if mine_done:
		line = "FINISHED #%d!" % (standings.find(my_slot) + 1)
	elif clock > 0.0 and clock <= TumbleRun.FINISH_WINDOW_SEC:
		line = "Climb! %ds left" % int(ceilf(clock))
	_hud.text = "%s    Leader: %s" % [line, leader]


func _draw_fx() -> void:
	# Summit line across the top of the stage.
	var left := world_to_screen(Vector2(_world.position.x, TumbleRun.GOAL_HEIGHT))
	var right := world_to_screen(Vector2(_world.end.x, TumbleRun.GOAL_HEIGHT))
	_fx_layer.draw_line(left, right, Color(SUMMIT_COLOR, 0.6), 3.0)
	# Rope ladder rungs on non-crumble climbable ledges.
	_draw_ladder_rungs()
	for boulder: Array in boulders:
		var at := world_to_screen(
			Vector2(float(boulder[TumbleRun.BL_X]), float(boulder[TumbleRun.BL_Y]))
		)
		var r := TumbleRun.BOULDER_RADIUS * _world_scale()
		# Hot glow halo, dark rim, then the rock — a foreground danger read
		# that can't be confused with the backdrop's cool clouds (#925).
		_fx_layer.draw_circle(at, r * 1.5, BOULDER_GLOW)
		_fx_layer.draw_circle(at, r + 2.0, BOULDER_RIM)
		_fx_layer.draw_circle(at, r, BOULDER_COLOR)
		_draw_boulder_cracks(at, r)
	# Summit flag — animates when any climber reaches the goal.
	if _any_summited:
		_draw_summit_flag()


## Rock texture detail: 2–3 crack lines seeded from the boulder's screen
## position so they stay stable across frames.
func _draw_boulder_cracks(at: Vector2, r: float) -> void:
	var seed_val := int(at.x * 100.0) ^ int(at.y * 100.0)
	var crack_count := 2 + (seed_val % 2)
	for i in crack_count:
		var angle := fmod(float(seed_val * (i + 1) * 53) * 0.001, TAU)
		var crack_len := r * (0.3 + float(seed_val * (i + 2) * 29 % 100) * 0.005)
		var start_off := r * 0.2
		var s := at + Vector2(cos(angle), sin(angle)) * start_off
		var e := at + Vector2(cos(angle), sin(angle)) * (start_off + crack_len)
		_fx_layer.draw_line(s, e, BOULDER_CRACK_COLOR, 1.5)


## Small vertical rung marks on stable non-crumble ledges, selling them
## as rope ladders rather than bare textured rectangles.
func _draw_ladder_rungs() -> void:
	var crumble_set := {}
	for idx in TumbleRun._crumble_indices():
		crumble_set[idx] = true
	var ledges := TumbleRun.ledges()
	for i in ledges.size():
		if crumble_set.has(i):
			continue
		var rect: Rect2 = ledges[i]
		var rung_spacing := 0.48  # world units between rungs
		var rung_count := int(rect.size.x / rung_spacing)
		for j in rung_count:
			var x := rect.position.x + (float(j) + 0.5) * rung_spacing
			var top := world_to_screen(Vector2(x, rect.position.y + rect.size.y))
			var bot := world_to_screen(Vector2(x, rect.position.y))
			_fx_layer.draw_line(top, bot, RUNG_COLOR, 1.5)


## Summit flag pole and animated flag — draws only after first climber summits.
func _draw_summit_flag() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	# Pole at the center of the summit platform.
	var pole_base := world_to_screen(Vector2(0.0, TumbleRun.GOAL_HEIGHT + 0.5))
	var pole_top := world_to_screen(Vector2(0.0, TumbleRun.GOAL_HEIGHT + 1.8))
	_fx_layer.draw_line(pole_base, pole_top, FLAG_POLE_COLOR, 2.0)
	# Flag triangle with a sine-wave flutter.
	var wave := sin(t * 5.0) * 2.0
	var flag_pts := PackedVector2Array(
		[
			pole_top,
			Vector2(pole_top.x + 6.0 + wave, pole_top.y - 5.0),
			Vector2(pole_top.x + wave, pole_top.y),
		]
	)
	_fx_layer.draw_colored_polygon(flag_pts, FLAG_COLOR)
