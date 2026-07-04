extends MinigameView3D
## Beat Bounce client view (M4-09, reworked #259): a Simon-Says-on-a-clock.
## Four labelled bounce pads sit in a N/E/S/W diamond under a central beat
## lamp whose shrinking ring telegraphs the next beat and whose metronome ticks
## every beat — the "hit now" cue. During WATCH the demonstrated pad flashes on
## each beat; during REPEAT the pads dim and the local player stomps the four
## movement inputs, each press echoing with a click, a cleared step chiming and
## a strike buzzing. A Control banner calls WATCH / REPEAT with the round and a
## row of sequence-length dots. Rigs bounce, flinch, and KO with the state.

const PAD_COLORS: Array[Color] = [
	Color(0.85, 0.25, 0.25),  # 0 = North / up
	Color(0.25, 0.55, 0.9),  # 1 = East / right
	Color(0.95, 0.8, 0.25),  # 2 = South / down
	Color(0.35, 0.8, 0.4),  # 3 = West / left
]
const PAD_ACTIONS: Array[StringName] = [&"move_up", &"move_right", &"move_down", &"move_left"]
const PAD_OFFSETS: Array[Vector2] = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
const PAD_ARROWS: Array[String] = ["▲", "▶", "▼", "◀"]
const PAD_SPREAD := 2.2
const PAD_SIZE := 1.7
const DIM := 0.3
const LIT := 1.7
const PRESS_ECHO_SEC := 0.14

const RIG_RING_RADIUS := 5.2
const LAMP_HEIGHT := 3.0
const LAMP_RADIUS := 0.45
const TELEGRAPH_MAX_SCALE := 3.0
const PULSE_COLOR := Color(0.95, 0.85, 0.3)
const IDLE_COLOR := Color(0.35, 0.3, 0.5)
const PULSE_SEC := 0.15

## FX pass (M13-18, pairs with #264): beat-synced particle pops so the rhythm
## reads in juice, not just the lamp. Heights lift each effect to roughly where
## the eye already is (pad face vs rig chest).
const STRIKE_FX_COLOR := Color(0.95, 0.3, 0.25)
const PAD_FX_HEIGHT := 0.6
const RIG_FX_HEIGHT := 1.0

var _phase: int = BeatBounce.Phase.WATCH
var _round := 0
var _seq_len := 0
var _flash := -1
var _beat := 0
var _next_in := 0.0
var _interval := BeatBounce.START_INTERVAL_SEC
var _strikes := {}
var _alive := {}
var _progress := {}

var _pad_nodes: Array[MeshInstance3D] = []
var _pad_materials: Array[StandardMaterial3D] = []
var _phase_label: Label
var _round_label: Label
var _dots_label: Label
var _lamp_material: StandardMaterial3D
var _telegraph: MeshInstance3D

var _snapshot_at := 0.0
var _ticked_beat := -1
var _pressed_pad := -1
var _pressed_until := 0.0
var _my_last_strikes := 0
var _my_last_progress := 0
var _was_repeat := false
var _flinched := {}  # slot -> strike count already flinched at
var _sparked_progress := {}  # slot -> progress count already FX'd at


func _arena_half() -> float:
	return 7.0


func _setup_3d() -> void:
	_ring_up_rigs()
	_build_pads()
	_build_lamp()
	_build_telegraph()
	_build_labels()


func _process(_delta: float) -> void:
	if _phase == BeatBounce.Phase.REPEAT:
		for pad in PAD_ACTIONS.size():
			if Input.is_action_just_pressed(PAD_ACTIONS[pad]):
				NetManager.send_match_input({"pad": pad})
				_pressed_pad = pad
				_pressed_until = _now_sec() + PRESS_ECHO_SEC
				play_sfx(&"click")
				fx_dust(PAD_OFFSETS[pad] * PAD_SPREAD)  # stomp puff under the foot
	_animate_beat()
	_update_pads()


func _render_3d(game: Dictionary) -> void:
	_phase = int(game.get("phase", BeatBounce.Phase.WATCH))
	_round = int(game.get("round", 0))
	_seq_len = int(game.get("seq_len", 0))
	_flash = int(game.get("flash", -1))
	_beat = int(game.get("beat", 0))
	_next_in = float(game.get("next_in", 0.0))
	_interval = maxf(float(game.get("interval", _interval)), 0.01)
	_strikes = game.get("strikes", {})
	_alive = game.get("alive", {})
	_progress = game.get("progress", {})
	_snapshot_at = _now_sec()
	# "Your turn" chime the moment REPEAT opens.
	var repeat_now := _phase == BeatBounce.Phase.REPEAT
	if repeat_now and not _was_repeat:
		play_sfx(&"coin")
	_was_repeat = repeat_now
	# Local hit / miss stings, from your own progress and strike deltas.
	var my_progress := int(_progress.get(my_slot, 0))
	if my_progress > _my_last_progress:
		play_sfx(&"confirm")
	_my_last_progress = my_progress
	var my_strikes := int(_strikes.get(my_slot, 0))
	if my_strikes > _my_last_strikes:
		play_sfx(&"error")
	_my_last_strikes = my_strikes
	_spark_cleared_steps()
	_update_labels()
	_update_rigs()


## Players ring the pad diamond, facing the center lamp.
func _ring_up_rigs() -> void:
	var sorted: Array = names.keys()
	sorted.sort()
	for i in sorted.size():
		var rig := rig_for_slot(sorted[i])
		if rig == null:
			continue
		var angle := TAU * i / sorted.size()
		var pos := Vector2(cos(angle), sin(angle)) * RIG_RING_RADIUS
		rig.position = to_arena(pos)
		rig.rotation.y = atan2(-pos.x, -pos.y)


func _build_pads() -> void:
	for pad in PAD_COLORS.size():
		var mesh := BoxMesh.new()
		mesh.size = Vector3(PAD_SIZE, 0.2, PAD_SIZE)
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		mesh.material = material
		_pad_materials.append(material)
		var node := MeshInstance3D.new()
		node.name = "Pad%d" % pad
		node.mesh = mesh
		node.position = to_arena(PAD_OFFSETS[pad] * PAD_SPREAD, 0.1)
		arena.add_child(node)
		_pad_nodes.append(node)
		var tag := Label3D.new()
		tag.name = "PadLabel%d" % pad
		tag.text = PAD_ARROWS[pad]
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.fixed_size = true
		tag.pixel_size = 0.004
		tag.font_size = 56
		tag.outline_size = 16
		tag.modulate = PAD_COLORS[pad]
		tag.position = Vector3(0.0, 1.0, 0.0)
		node.add_child(tag)


func _build_lamp() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = LAMP_RADIUS
	mesh.height = LAMP_RADIUS * 2.0
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.emission_enabled = true
	mesh.material = _lamp_material
	var lamp := MeshInstance3D.new()
	lamp.name = "BeatLamp"
	lamp.mesh = mesh
	lamp.position = Vector3(0.0, LAMP_HEIGHT, 0.0)
	arena.add_child(lamp)


func _build_telegraph() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = LAMP_RADIUS + 0.15
	mesh.outer_radius = LAMP_RADIUS + 0.3
	var material := StandardMaterial3D.new()
	material.albedo_color = PULSE_COLOR
	material.emission_enabled = true
	material.emission = PULSE_COLOR
	mesh.material = material
	_telegraph = MeshInstance3D.new()
	_telegraph.name = "Telegraph"
	_telegraph.mesh = mesh
	_telegraph.position = Vector3(0.0, LAMP_HEIGHT, 0.0)
	arena.add_child(_telegraph)


func _build_labels() -> void:
	_phase_label = Label.new()
	_phase_label.name = "PhaseLabel"
	_phase_label.add_theme_font_size_override(&"font_size", 48)
	_phase_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phase_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.position.y = 14.0
	add_child(_phase_label)

	_round_label = Label.new()
	_round_label.name = "RoundLabel"
	_round_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_round_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.position.y = 74.0
	add_child(_round_label)

	_dots_label = Label.new()
	_dots_label.name = "DotsLabel"
	_dots_label.add_theme_font_size_override(&"font_size", 28)
	_dots_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_dots_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dots_label.position.y = 102.0
	add_child(_dots_label)


func _update_labels() -> void:
	if _phase_label == null:
		return
	var watching := _phase == BeatBounce.Phase.WATCH
	_phase_label.text = "WATCH..." if watching else "REPEAT!"
	_phase_label.add_theme_color_override(
		&"font_color", PULSE_COLOR if watching else Color(0.4, 0.95, 0.5)
	)
	_round_label.text = "Round %d" % (_round + 1)
	_dots_label.text = "●".repeat(_seq_len)


## Pads: during WATCH the flashed demo pad lights and lifts; during REPEAT they
## sit dim except the local player's just-stomped pad, which echoes.
func _update_pads() -> void:
	var now := _now_sec()
	for pad in _pad_materials.size():
		var base := PAD_COLORS[pad]
		var lit := _phase == BeatBounce.Phase.WATCH and pad == _flash
		var echoing := (
			_phase == BeatBounce.Phase.REPEAT and pad == _pressed_pad and now < _pressed_until
		)
		var energy := LIT if (lit or echoing) else DIM
		_pad_materials[pad].albedo_color = base
		_pad_materials[pad].emission = base
		_pad_materials[pad].emission_energy_multiplier = energy
		_pad_nodes[pad].position.y = 0.1 + (0.3 if lit else 0.0)


## Lamp pulse + telegraph shrink extrapolate the beat clock from the last
## snapshot so the rhythm reads smoothly at any fps; one metronome tick per
## beat at the pulse onset (the audible "hit now" cue).
func _animate_beat() -> void:
	if _lamp_material == null:
		return
	var remaining := _next_in - (_now_sec() - _snapshot_at)
	var phase := clampf(remaining / _interval, 0.0, 1.0)
	var pulsing := remaining < PULSE_SEC or _interval - remaining < PULSE_SEC
	if pulsing and _beat != _ticked_beat:
		_ticked_beat = _beat
		play_sfx(&"tick")
		# The visual half of the metronome: on WATCH beats the demonstrated pad
		# pops a colored sparkle, so "hit now" reads even with the sound off.
		if _phase == BeatBounce.Phase.WATCH and _flash >= 0 and _flash < _pad_nodes.size():
			fx_sparkle(PAD_OFFSETS[_flash] * PAD_SPREAD, PAD_COLORS[_flash], PAD_FX_HEIGHT)
	var color := PULSE_COLOR if pulsing else IDLE_COLOR
	_lamp_material.albedo_color = color
	_lamp_material.emission = color
	var telegraph_scale := 1.0 + (TELEGRAPH_MAX_SCALE - 1.0) * phase
	_telegraph.scale = Vector3(telegraph_scale, 1.0, telegraph_scale)


## A player-colored sparkle lifts off a rig each time its owner clears a step,
## so a correct answer reads across the whole ring, not just on the pads. Baselines
## reset with progress, so a new round's first clear pops again.
func _spark_cleared_steps() -> void:
	for slot: int in _progress:
		var progress := int(_progress[slot])
		if progress > int(_sparked_progress.get(slot, 0)):
			var rig := rig_for_slot(slot)
			if rig != null:
				fx_sparkle(
					Vector2(rig.position.x, rig.position.z), player_color(slot), RIG_FX_HEIGHT
				)
		_sparked_progress[slot] = progress


## Bounce on a cleared step, KO on elimination, flinch on a fresh strike;
## play() is guarded so poses are not restarted every snapshot.
func _update_rigs() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var slot_strikes := int(_strikes.get(slot, 0))
		var caption := player_name(slot)
		if slot_strikes > 0:
			caption += "  %s" % "✕".repeat(slot_strikes)
		rig.display_name = caption
		var desired: StringName = &"idle"
		if not _alive.get(slot, true):
			desired = &"ko"
		elif slot_strikes > int(_flinched.get(slot, 0)):
			_flinched[slot] = slot_strikes
			fx_burst(Vector2(rig.position.x, rig.position.z), STRIKE_FX_COLOR, RIG_FX_HEIGHT)
			rig.play(&"hit")
			continue
		if rig.current_action() in [&"jump_start", &"hit"]:
			continue
		if rig.current_action() != desired:
			rig.play(desired)


func _now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0
