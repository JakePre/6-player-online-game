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


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"action_primary"):
		NetManager.send_match_input({"press": true})
	_update_lamp()


func _arena_half() -> float:
	return MinigameScaling.arena_half(BASE_ARENA_HALF, names.size())


func _setup_3d() -> void:
	_line_up_rigs()
	_build_lamp()
	_build_labels()
	_build_flash()


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
## moment the whole game hinges on.
func _draw_flash() -> void:
	_lamp_flare_until = _now() + LAMP_FLARE_SEC
	play_sfx(&"confirm")
	request_shake(9.0)
	if _flash_rect != null:
		_flash_rect.color = Color(0.7, 1.0, 0.75, 0.55)
		var tween := _flash_rect.create_tween()
		tween.tween_property(_flash_rect, "color:a", 0.0, FLASH_SEC)


## Round result: fanfare + confetti over the winner, or an error sting on a
## false-start-only bust. Guarded to fire once per round.
func _resolve_fx() -> void:
	if _fanfare_round == _round:
		return
	_fanfare_round = _round
	if _winner != -1:
		play_sfx(&"round_win")
		var rig := rig_for_slot(_winner)
		if rig != null:
			_confetti_burst(rig.position)
	elif not _false_started.is_empty():
		play_sfx(&"error")


## A fountain of colored cubes over the winner — cheap, deterministic confetti
## sized to read at iso distance.
func _confetti_burst(origin: Vector3) -> void:
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
