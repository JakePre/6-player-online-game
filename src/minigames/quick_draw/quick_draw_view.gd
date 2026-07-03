extends MinigameView3D
## Quick Draw client view (M8-08): renders the standoff in the shared 2.5D
## iso-arena (M8-01, MinigameView3D) — rigs lined up in a row, a signal lamp
## that flips red (WAIT) to green (DRAW!), the round winner cheering and
## false-starters flinching, with win tallies on the nameplates. The WAIT /
## DRAW! call-out and round counter stay as Control-layer labels over the
## viewport since reading them instantly is the game. Presentation-tier swap
## only: state storage and the render contract are unchanged from the 2D
## pass (M4-06).

const WAITING_COLOR := Color(0.7, 0.15, 0.15)
const LIVE_COLOR := Color(0.2, 0.75, 0.3)
const ROUND_OVER_COLOR := Color(0.35, 0.38, 0.45)
const ROW_SPACING := 2.0
const LAMP_RADIUS := 0.45
const LAMP_HEIGHT := 3.2

var _phase: int = QuickDraw.Phase.WAITING
var _round := 0
var _rounds_total := QuickDraw.ROUNDS_TO_PLAY
var _wins := {}
var _false_started := {}
var _winner := -1

var _lamp_material: StandardMaterial3D
var _signal_label: Label
var _round_label: Label


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"action_primary"):
		NetManager.send_match_input({"press": true})


func _arena_half() -> float:
	return 6.0


func _setup_3d() -> void:
	_line_up_rigs()
	_build_lamp()
	_build_labels()


func _render_3d(game: Dictionary) -> void:
	_phase = game.get("phase", QuickDraw.Phase.WAITING)
	_round = game.get("round", 0)
	_rounds_total = game.get("rounds_total", QuickDraw.ROUNDS_TO_PLAY)
	_wins = game.get("wins", {})
	_false_started = game.get("false_started", {})
	_winner = game.get("winner", -1)
	_update_labels()
	_update_lamp()
	_update_rigs()


## Duelists stand in a fixed row facing the camera; there is no movement in
## this game, so rigs are placed once instead of via update_rig.
func _line_up_rigs() -> void:
	var slots: Array = names.keys()
	slots.sort()
	for i in slots.size():
		var rig := rig_for_slot(slots[i])
		if rig == null:
			continue
		rig.position = to_arena(Vector2((i - (slots.size() - 1) / 2.0) * ROW_SPACING, 0.0))
		rig.rotation.y = PI * 0.75  # face the iso camera


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
	_signal_label = Label.new()
	_signal_label.name = "SignalLabel"
	_signal_label.add_theme_font_size_override(&"font_size", 40)
	_signal_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_signal_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_signal_label.position.y = 16.0
	add_child(_signal_label)

	_round_label = Label.new()
	_round_label.name = "RoundLabel"
	_round_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_round_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_round_label.position.y = 72.0
	add_child(_round_label)


func _update_labels() -> void:
	_signal_label.text = _signal_text()
	_signal_label.add_theme_color_override(&"font_color", _signal_color())
	_round_label.text = "Round %d / %d" % [_round + 1, _rounds_total]


func _update_lamp() -> void:
	var color := _signal_color()
	_lamp_material.albedo_color = color
	_lamp_material.emission = color


## Winner cheers, false-starters flinch, everyone else idles. play() is
## guarded by current_action() so non-looping poses are not restarted every
## snapshot.
func _update_rigs() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
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
