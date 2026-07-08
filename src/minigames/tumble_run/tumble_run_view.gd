extends SideScrollView
## Tumble Run client view (M14-09): renders the vertical climb over the
## M14-00 side-scroll base — the laddered stage with crumble ledges shown
## only while solid, falling boulders, stunned/summited climbers, a summit
## marker, and the climb standings. Simulates nothing locally.
##
## Input: A/D run + W/Space jump through the base move axis. No attacks.

const BOULDER_COLOR := Color(0.4, 0.34, 0.3)
const SUMMIT_COLOR := Color(0.96, 0.79, 0.2)
const CRUMBLE_COLOR := Color(0.7, 0.45, 0.3)
const STUN_MODULATE := Color(1.0, 0.7, 0.5, 0.85)
const SUMMIT_MODULATE := Color(1.0, 1.0, 0.7)
const BOULDER_POOL := 10

var players := {}
var crumble: Array = []
var standings: Array = []
var boulders: Array = []

var _fx_layer: Control
var _hud: Label
## Parallel to TumbleRun.ledges(): the panel node for each crumble ledge,
## kept only for those that actually crumble (rest are static base platforms).
var _crumble_nodes := {}
var _summit_seen := {}
## slot -> was stunned last render, for the boulder-hit cue (#728).
var _stun_seen := {}
var _seen_snapshot := false


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
	_hud = Label.new()
	_hud.theme_type_variation = PartyTheme.HEADER_VARIATION
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
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


func _unhandled_input(event: InputEvent) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	if event.is_action_pressed(&"move_up"):
		NetManager.send_match_input({"jump": true})


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	crumble = game.get("crumble", [])
	standings = game.get("standings", [])
	boulders = game.get("boulders", [])
	render_side_scroll(players)
	for slot: int in players:
		_render_climber(slot, players[slot])
	# A crumble ledge shows only while the sim says it's solid.
	for index: int in _crumble_nodes:
		var solid: bool = index < crumble.size() and bool(crumble[index])
		_crumble_nodes[index].visible = solid
	_update_hud()
	_fx_layer.queue_redraw()
	_seen_snapshot = true


func _render_climber(slot: int, state: Array) -> void:
	if state.size() < 4:
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	var flags := int(state[3])
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
	_hud.text = "Climb to the top!    Leader: %s" % leader


func _draw_fx() -> void:
	# Summit line across the top of the stage.
	var left := world_to_screen(Vector2(_world.position.x, TumbleRun.GOAL_HEIGHT))
	var right := world_to_screen(Vector2(_world.end.x, TumbleRun.GOAL_HEIGHT))
	_fx_layer.draw_line(left, right, Color(SUMMIT_COLOR, 0.6), 3.0)
	for boulder: Array in boulders:
		var at := world_to_screen(Vector2(float(boulder[0]), float(boulder[1])))
		_fx_layer.draw_circle(at, TumbleRun.BOULDER_RADIUS * _world_scale(), BOULDER_COLOR)
