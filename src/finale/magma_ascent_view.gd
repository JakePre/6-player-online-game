extends SideScrollView
## Magma Ascent client view (#936): the rising-magma finale on the freshly
## dressed side-scroll base (#925). The stable tower ledges + floor + capstone
## ride the base's textured platforms; crumble ledges are toggleable overlay
## panels (so a gone ledge truly disappears); a hot magma plane rises from the
## bottom with a glowing crest, shielded climbers shimmer, eliminated ones drop
## out of sight. Renders MagmaAscent.get_snapshot() only. Input: A/D + jump,
## action_secondary spends a sabotage token on the nearest rival above.

const MAGMA_CORE := Color(0.85, 0.2, 0.08)
const MAGMA_CREST := Color(1.0, 0.62, 0.15)
const MAGMA_GLOW := Color(1.0, 0.5, 0.2, 0.30)
const CRUMBLE_COLOR := Color(0.72, 0.45, 0.28)
const SHIELD_MODULATE := Color(0.6, 0.85, 1.0, 0.85)

var players := {}
var crumble: Array = []
var magma_y := MagmaAscent.MAGMA_START_Y

var _fx_layer: Control
var _crumble_nodes := {}
var _hud: Label


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	if event.is_action_pressed(&"move_up"):
		NetManager.send_match_input({"jump": true})
	elif event.is_action_pressed(&"action_secondary"):
		NetManager.send_match_input({"sabotage": _sabotage_target()})


## Nearest living rival above us — the one whose ledge is worth crumbling.
func _sabotage_target() -> int:
	var my_state: Array = players.get(my_slot, [])
	if my_state.size() < MagmaAscent.PS_COUNT:
		return -1
	var my_y := float(my_state[MagmaAscent.PS_Y])
	var best := -1
	var best_gap := INF
	for slot: int in players:
		if slot == my_slot:
			continue
		var state: Array = players[slot]
		if int(state[MagmaAscent.PS_FLAGS]) & 2 > 0:
			continue  # eliminated
		var gap := float(state[MagmaAscent.PS_Y]) - my_y
		if gap > 0.0 and gap < best_gap:
			best_gap = gap
			best = slot
	return best


func _setup() -> void:
	# Only the always-present geometry goes to the base; crumble ledges are our
	# own overlay so a "gone" ledge actually vanishes (not double-drawn).
	var stable: Array[Rect2] = []
	var all := MagmaAscent.ledges()
	var crumble_set := MagmaAscent._crumble_indices()
	for i in all.size():
		if i not in crumble_set:
			stable.append(all[i])
	setup_stage(MagmaAscent.solid_platforms(), stable, MagmaAscent.STAGE_BOUNDS)
	_ensure_chrome()
	for index in crumble_set:
		_crumble_nodes[index] = _make_crumble_panel()
	_layout_crumble()


## The fx layer (magma plane) sits above the stage but below the HUD; built in
## _setup() to survive the production mount order (#575 idiom).
func _ensure_chrome() -> void:
	if _fx_layer != null:
		return
	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.draw.connect(_draw_magma)
	add_child(_fx_layer)
	_hud = make_sidescroll_hud()
	resized.connect(_layout_crumble)


func _make_crumble_panel() -> Panel:
	var node := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CRUMBLE_COLOR
	style.border_color = CRUMBLE_COLOR.darkened(0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(PartyTheme.RADIUS_SM)
	node.add_theme_stylebox_override(&"panel", style)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(node)
	return node


func _layout_crumble() -> void:
	var rects := MagmaAscent.ledges()
	for index: int in _crumble_nodes:
		var rect: Rect2 = rects[index]
		var top_left := world_to_screen(Vector2(rect.position.x, rect.position.y + rect.size.y))
		var node: Panel = _crumble_nodes[index]
		node.position = top_left
		node.size = rect.size * _world_scale()


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	crumble = game.get("crumble", [])
	magma_y = float(game.get("magma_y", MagmaAscent.MAGMA_START_Y))
	render_side_scroll(players)
	for slot: int in players:
		_style_climber(slot, players[slot])
	for index: int in _crumble_nodes:
		var solid: bool = index < crumble.size() and bool(crumble[index])
		_crumble_nodes[index].visible = solid
	_update_hud()
	_fx_layer.queue_redraw()


func _style_climber(slot: int, state: Array) -> void:
	var rig := rig_for_slot(slot)
	if rig == null or state.size() < MagmaAscent.PS_COUNT:
		return
	var flags := int(state[MagmaAscent.PS_FLAGS])
	# Eliminated climbers sink out of view; shielded ones shimmer cool.
	rig.visible = flags & 2 == 0
	rig.modulate = SHIELD_MODULATE if flags & 1 > 0 else Color.WHITE


func _update_hud() -> void:
	if _hud == null:
		return
	var alive := 0
	for slot: int in players:
		if int((players[slot] as Array)[MagmaAscent.PS_FLAGS]) & 2 == 0:
			alive += 1
	var my_state: Array = players.get(my_slot, [])
	var mine_out := (
		my_state.size() >= MagmaAscent.PS_COUNT and int(my_state[MagmaAscent.PS_FLAGS]) & 2 > 0
	)
	var line := (
		"Climb — the magma rises!" if not mine_out else "Eliminated — climb higher next time!"
	)
	_hud.text = "%s    Still climbing: %d" % [line, alive]


## The magma: a hot fill from the bottom of the screen up to the rising line,
## capped by a bright shimmering crest and a soft glow band — unmistakably the
## lethal floor, not backdrop decor.
func _draw_magma() -> void:
	var crest_y := world_to_screen(Vector2(0.0, magma_y)).y
	crest_y = clampf(crest_y, 0.0, size.y)
	if crest_y >= size.y:
		return
	_fx_layer.draw_rect(Rect2(0.0, crest_y, size.x, size.y - crest_y), MAGMA_CORE)
	_fx_layer.draw_rect(Rect2(0.0, crest_y - 10.0, size.x, 20.0), MAGMA_GLOW)
	_fx_layer.draw_rect(Rect2(0.0, crest_y, size.x, 4.0), MAGMA_CREST)
