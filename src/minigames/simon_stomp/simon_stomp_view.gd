extends MinigameView3D
## Simon Stomp client view (M4-05, on the M8-01 MinigameView3D tier): four
## colored stomp pads in a N/E/S/W diamond on the iso-arena floor. During SHOW
## the pads light up one at a time following the flashed sequence; during INPUT
## the player stomps with the four movement inputs. A Control-layer banner
## calls the phase ("WATCH" / "STOMP!" / round result) since reading it
## instantly matters. Cleared/busted players cheer or slump on their nameplates.

# Pads form a N/E/S/W diamond mapped to the four movement inputs, so the game
# needs no new input actions (project.godot input map is a shared file).
const PAD_COLORS: Array[Color] = [
	Color(0.85, 0.25, 0.25),  # 0 = North / up
	Color(0.25, 0.55, 0.9),  # 1 = East / right
	Color(0.95, 0.8, 0.25),  # 2 = South / down
	Color(0.35, 0.8, 0.4),  # 3 = West / left
]
const PAD_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_right",
	&"move_down",
	&"move_left",
]
const PAD_OFFSETS: Array[Vector2] = [
	Vector2(0, -1),
	Vector2(1, 0),
	Vector2(0, 1),
	Vector2(-1, 0),
]
const PAD_SIZE := 2.4
const PAD_GAP := 0.6
const DIM := 0.28
## Brighter flash (#588 — the original 1.4 read too subtly against the dim pad).
const LIT := 2.4
## How long a flashed pad stays lit within its SHOW_PER_PAD_SEC window.
const FLASH_HOLD := 0.42
## A lit pad hops for this long — a visible pop, not just a color change (#588).
const FLASH_BOUNCE_HEIGHT := 0.24
const FLASH_BOUNCE_SEC := 0.24
## Pad labels (#261): direction arrow + key + color name, always readable.
const PAD_LABELS: Array[String] = ["▲ W — Red", "▶ D — Amber", "▼ S — Green", "◀ A — Blue"]
## Distinct per-pad flash SFX (#588): a recognizable four-note identity instead
## of one shared "tick" for every pad, reusing the existing UI SFX set (no new
## audio assets).
const PAD_SFX: Array[StringName] = [&"tick", &"click", &"coin", &"confirm"]
## Your own stomp echoes on the pad this long (local feedback).
const PRESS_FLASH_SEC := 0.15
## Stomp-ripple FX (M13-16): a self-freeing ground ring that expands and fades.
## Beats ripple softly (watch the pattern); your own presses ripple harder.
const RIPPLE_SEC := 0.4
const RIPPLE_REACH := 2.6
const BEAT_RIPPLE_STRENGTH := 0.65
const PRESS_SHAKE := 3.0
## Audience layout (#795): alive players line up behind the pads facing the
## camera (the Shred Session rig-row convention); eliminated players move to
## a mirrored row on the far side, watching instead of loitering on the pads
## (rigs otherwise have no position/reveal logic here at all, so they'd sit
## invisible and stacked at the arena origin — right where the pad diamond is).
const ROW_Z := 4.5
const ROW_SPREAD := 4.0

var _phase: int = SimonStomp.Phase.SHOW
var _round := 0
var _rounds_total := SimonStomp.MAX_ROUNDS
var _sequence: Array = []
var _length := 0
var _alive := {}
var _cleared_count := {}
var _round_cleared := {}
var _round_failed := {}

var _pad_materials: Array[StandardMaterial3D] = []
var _pad_nodes: Array[MeshInstance3D] = []
var _phase_label: Label
var _round_label: Label
## Locally clocked SHOW timer: snapshots arrive at 30 Hz but the flash should
## animate every frame, so we drive it off _process and reset on entering SHOW.
var _show_timer := 0.0
var _pressed_pad := -1
var _pressed_until := 0.0
var _last_lit := -1
## When the current flash lit, so the bounce can decay smoothly (M13 pattern).
var _lit_at := -10.0
var _was_cleared := false
var _was_failed := false


## Rhythmic blue-violet floor for the stomp panels (#589).
func _floor_tint() -> Color:
	return Color(0.85, 0.88, 1.0)


func _arena_half() -> float:
	return 6.0


func _process(delta: float) -> void:
	if _phase == SimonStomp.Phase.SHOW:
		_show_timer += delta
		_update_pads()
	elif _phase == SimonStomp.Phase.INPUT:
		for pad in PAD_ACTIONS.size():
			if Input.is_action_just_pressed(PAD_ACTIONS[pad]):
				NetManager.send_match_input({"pad": pad})
				# Local stomp echo (#261): the pad you hit flashes and clicks.
				_pressed_pad = pad
				_pressed_until = Time.get_ticks_msec() / 1000.0 + PRESS_FLASH_SEC
				play_sfx(&"click")
				# Stomp ripple + a small kick — the press lands with weight (M13-16).
				_stomp_ripple(pad, PAD_COLORS[pad])
				request_shake(PRESS_SHAKE)
		_update_pads()


func _setup_3d() -> void:
	_build_pads()
	_build_labels()


func _render_3d(game: Dictionary) -> void:
	var previous_phase := _phase
	_phase = game.get("phase", SimonStomp.Phase.SHOW)
	# Correct/bust stingers for the local player (#261).
	var cleared_now := bool(game.get("round_cleared", {}).get(my_slot, false))
	var failed_now := bool(game.get("round_failed", {}).get(my_slot, false))
	if cleared_now and not _was_cleared:
		# Clearing the round is a checkpoint (#728, docs/AUDIO_GUIDE.md).
		play_sfx(&"bell")
		_round_clear_pop()
	if failed_now and not _was_failed:
		play_sfx(&"error")
		_bust_puff()
	_was_cleared = cleared_now
	_was_failed = failed_now
	if _phase == SimonStomp.Phase.SHOW and previous_phase != SimonStomp.Phase.SHOW:
		_show_timer = 0.0
	_round = game.get("round", 0)
	_rounds_total = game.get("rounds_total", SimonStomp.MAX_ROUNDS)
	_sequence = game.get("sequence", [])
	_length = game.get("length", 0)
	_alive = game.get("alive", {})
	_cleared_count = game.get("cleared_count", {})
	_round_cleared = game.get("round_cleared", {})
	_round_failed = game.get("round_failed", {})
	_update_labels()
	_update_pads()
	_update_rigs()


## Pads sit in a N/E/S/W diamond centered on the floor, index order matching
## PAD_COLORS / PAD_ACTIONS.
func _pad_position(pad: int) -> Vector2:
	return PAD_OFFSETS[pad] * (PAD_SIZE + PAD_GAP)


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
		node.position = to_arena(_pad_position(pad), 0.1)
		arena.add_child(node)
		_pad_nodes.append(node)
		# Direction + key + color on every pad, through-wall readable (#261).
		var tag := Label3D.new()
		tag.name = "PadLabel%d" % pad
		tag.text = PAD_LABELS[pad]
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.fixed_size = true
		tag.pixel_size = 0.002
		tag.font_size = 40
		tag.outline_size = 16
		tag.modulate = PAD_COLORS[pad].lightened(0.35)
		tag.position = to_arena(_pad_position(pad), 1.1)
		arena.add_child(tag)


func _build_labels() -> void:
	_phase_label = make_status_label(&"PhaseLabel")
	_round_label = make_status_label(&"RoundLabel", PartyTheme.SIZE_OVERLAY_BODY)
	_round_label.position.y = 72.0


func _update_labels() -> void:
	_phase_label.text = _phase_text()
	_round_label.text = "Round %d / %d  ·  Length %d" % [_round + 1, _rounds_total, _length]


## During SHOW, light the pad whose flash window we're inside — after a lead-in
## beat so the very first flash doesn't land before eyes settle on the pads
## (#588). The framework replays the sequence at SHOW_PER_PAD_SEC per step and
## we hold each lit for FLASH_HOLD. Outside SHOW every pad sits dimmed.
func _update_pads() -> void:
	var lit_pad := -1
	var flash_time := _show_timer - SimonStomp.SHOW_LEAD_IN_SEC
	if _phase == SimonStomp.Phase.SHOW and not _sequence.is_empty() and flash_time >= 0.0:
		var step := SimonStomp.SHOW_PER_PAD_SEC
		var idx := int(flash_time / step)
		if idx < _sequence.size() and fmod(flash_time, step) <= FLASH_HOLD:
			lit_pad = int(_sequence[idx])
	var now := Time.get_ticks_msec() / 1000.0
	# A distinct note per pad every time the SHOW flash advances — the readable
	# four-note metronome (#588).
	if lit_pad != _last_lit and lit_pad != -1:
		play_sfx(PAD_SFX[lit_pad])
		# Each beat ripples the lit pad, so the pattern reads as motion (M13-16).
		_stomp_ripple(lit_pad, PAD_COLORS[lit_pad], BEAT_RIPPLE_STRENGTH)
		_lit_at = now
	_last_lit = lit_pad
	for pad in _pad_materials.size():
		var base := PAD_COLORS[pad]
		var energy := LIT if pad == lit_pad else DIM
		if pad == _pressed_pad and now < _pressed_until:
			energy = LIT  # Your own stomp echo (#261).
		_pad_materials[pad].albedo_color = base
		_pad_materials[pad].emission = base
		_pad_materials[pad].emission_energy_multiplier = energy
		_pad_nodes[pad].position.y = 0.1 + (_flash_bounce(now) if pad == lit_pad else 0.0)


## The lit pad's beat-synced hop (#588, M13-18 pattern): a small arc that decays
## over FLASH_BOUNCE_SEC after it lights, zero once it settles.
func _flash_bounce(now: float) -> float:
	var since := now - _lit_at
	if since < 0.0 or since >= FLASH_BOUNCE_SEC:
		return 0.0
	return FLASH_BOUNCE_HEIGHT * sin(PI * since / FLASH_BOUNCE_SEC)


## Alive players stand in a stage row facing the pads; a player who cleared
## this round cheers, a busted one slumps ("hit"). Eliminated players move to
## an audience row on the far side, idling — or cheering along, if anyone
## still in it clears the round (#795). Nameplates show each player's
## cleared-round tally.
func _update_rigs() -> void:
	var sorted_slots: Array = names.keys()
	sorted_slots.sort()
	var stage: Array = []
	var audience: Array = []
	for slot: int in sorted_slots:
		if bool(_alive.get(slot, true)):
			stage.append(slot)
		else:
			audience.append(slot)
	var anyone_cleared: bool = (_round_cleared.values() as Array).any(
		func(cleared: Variant) -> bool: return bool(cleared)
	)
	for i in stage.size():
		_place_rig(stage[i], i, stage.size(), -ROW_Z, 0.0, false, anyone_cleared)
	for i in audience.size():
		_place_rig(audience[i], i, audience.size(), ROW_Z, PI, true, anyone_cleared)


## `z`/`facing` pick the row and which way it looks; `is_audience` decides
## whether this slot poses off its own round result or the group's.
func _place_rig(
	slot: int,
	index: int,
	count: int,
	z: float,
	facing: float,
	is_audience: bool,
	anyone_cleared: bool
) -> void:
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	var x := lerpf(-ROW_SPREAD, ROW_SPREAD, 0.5 if count <= 1 else float(index) / (count - 1))
	rig.position = to_arena(Vector2(x, z))
	rig.rotation.y = facing
	reveal_rig(slot)
	var caption := "%s  %d" % [player_name(slot), int(_cleared_count.get(slot, 0))]
	var desired: StringName
	if is_audience:
		caption += "  (out)"
		desired = &"cheer" if anyone_cleared else &"idle"
	elif _round_cleared.get(slot, false):
		desired = &"cheer"
	elif _round_failed.get(slot, false):
		desired = &"hit"
	else:
		desired = &"idle"
	if rig.current_action() != desired:
		rig.play(desired)
	rig.display_name = caption


## An expanding, fading ground ring at `pad` — the stomp's shockwave. One-shot
## and self-freeing (M13-01 convention), so the FX pass stays a one-file view
## change. `strength` scales how far the ring travels (beats ripple gently).
func _stomp_ripple(pad: int, color: Color, strength: float = 1.0) -> void:
	if ArenaFX.reduced_motion:
		return
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.5
	mesh.outer_radius = 0.62
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	mesh.material = material
	var ring := MeshInstance3D.new()
	ring.name = "StompRipple"
	ring.mesh = mesh
	ring.rotation.x = PI / 2.0  # lay the ring flat on the floor
	ring.scale = Vector3.ONE * 0.4
	ring.position = to_arena(_pad_position(pad), 0.12)
	arena.add_child(ring)
	var reach := Vector3.ONE * RIPPLE_REACH * strength
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", reach, RIPPLE_SEC).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(material, "albedo_color:a", 0.0, RIPPLE_SEC)
	tween.chain().tween_callback(ring.queue_free)


## Cleared the round: ripple every pad and pop a sparkle burst over your rig.
func _round_clear_pop() -> void:
	for pad in PAD_COLORS.size():
		_stomp_ripple(pad, PAD_COLORS[pad])
	var rig := rig_for_slot(my_slot)
	if rig != null:
		fx_burst(Vector2(rig.position.x, rig.position.z), Color(0.4, 0.9, 0.5), 1.2)


## Busted out of the round: a dull dust puff where you stand.
func _bust_puff() -> void:
	var rig := rig_for_slot(my_slot)
	if rig != null:
		fx_dust(Vector2(rig.position.x, rig.position.z))


func _phase_text() -> String:
	match _phase:
		SimonStomp.Phase.SHOW:
			return "WATCH..."
		SimonStomp.Phase.INPUT:
			return "STOMP!"
		_:
			return "Round over"
