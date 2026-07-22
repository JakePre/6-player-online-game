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
## Metal-deck floor texture (IMG-057, #1155): game-show stage floor replacing
## the flat tint, tiled for a production-studio feel.
const FLOOR_TEXTURE := preload("res://assets/generated/textures/metal-deck.png")
const FLOOR_TEXTURE_TILES := 5.0
## Game-show rim props (#1155): crates, barrels, and poles scattered around
## the arena perimeter via the shared scatter_rim_props helper.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_platformer_kit/barrel.glb"),
	preload("res://assets/environment/kenney_platformer_kit/crate.glb"),
	preload("res://assets/environment/kenney_platformer_kit/poles.glb"),
	preload("res://assets/environment/kenney_platformer_kit/plant.glb"),
]
const RIM_PROP_COUNT := 14
const RIM_PROP_SEED := 0x1155
## Backdrop panel dimensions (#1155): a vertical board behind the pads with
## the game title, game-show style.
const BACKDROP_W := 4.0
const BACKDROP_H := 2.8
const BACKDROP_Z := -5.0
## Follow-spotlight (#1155): tracks the currently lit pad during SHOW.
const SPOTLIGHT_HEIGHT := 8.0
const SPOTLIGHT_ANGLE := 15.0

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
var _pad_rims: Array[MeshInstance3D] = []
var _phase_label: Label
var _round_label: Label
## Big pre-flash countdown (#1044): mirrors the match-level countdown's punch-in
## digit (#182) so a mid-game round transition is as unmissable as round 1's.
var _countdown_label: Label
var _countdown_digit := 0
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
## Follow-spotlight node (#1155): tracks the currently lit pad.
var _spotlight: SpotLight3D
## Game-show backdrop panel (#1155).
var _backdrop: Node3D
## Sequence position indicator (#1155): shows the current flash step.
var _sequence_label: Label3D


## Rhythmic blue-violet floor for the stomp panels (#589).
func _floor_tint() -> Color:
	return Color(0.85, 0.88, 1.0)


## Game-show dark studio mood (#1155): deep blue-violet backdrop behind the
## brightly lit pads, making the flashing pads pop against the stage.
func _mood() -> Color:
	return Color(0.12, 0.08, 0.18).lerp(Color(0.25, 0.18, 0.35), 0.3)


## Metal-deck game-show floor (#1155): textured plane replacing the default
## tinted tile, tiled for a production-studio feel.
func _build_floor() -> void:
	var floor_node := _dresser.build_floor(_floor_tile_scene(), _floor_tint(), _arena_half())
	if floor_node != null:
		var mat := floor_node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_texture = FLOOR_TEXTURE
			mat.uv1_scale = Vector3(FLOOR_TEXTURE_TILES, FLOOR_TEXTURE_TILES, 1.0)


func _arena_half() -> float:
	return 6.0


func _process(delta: float) -> void:
	if _phase == SimonStomp.Phase.SHOW:
		_show_timer += delta
		_update_pads()
		_update_countdown()
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
	_build_backdrop()
	_build_spotlight()
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)


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
		# Pad group: parent node for the pad + rim so they move together.
		var group := Node3D.new()
		group.name = "PadGroup%d" % pad
		group.position = to_arena(_pad_position(pad), 0.0)
		arena.add_child(group)
		# Main pad panel: slightly thicker for a physical platform feel (#1155).
		var mesh := BoxMesh.new()
		mesh.size = Vector3(PAD_SIZE, 0.25, PAD_SIZE)
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		mesh.material = material
		_pad_materials.append(material)
		var node := MeshInstance3D.new()
		node.name = "Pad%d" % pad
		node.mesh = mesh
		node.position.y = 0.125
		group.add_child(node)
		_pad_nodes.append(node)
		# Beveled TorusMesh rim around the pad edge (#1155): a frame that
		# makes the pad read as a physical platform, not a flat panel.
		var rim_size := PAD_SIZE + 0.12
		var rim := TorusMesh.new()
		rim.inner_radius = rim_size / 2.0 - 0.06
		rim.outer_radius = rim_size / 2.0
		rim.material = material  # same material, tinted by the emission
		var rim_node := MeshInstance3D.new()
		rim_node.name = "PadRim%d" % pad
		rim_node.mesh = rim
		rim_node.rotation.x = PI / 2.0
		rim_node.position.y = 0.125
		group.add_child(rim_node)
		_pad_rims.append(rim_node)
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


## Game-show backdrop panel (#1155): a vertical board behind the pads with
## the game title, game-show style.
func _build_backdrop() -> void:
	var panel := Node3D.new()
	panel.name = "Backdrop"
	# Main board
	var board := BoxMesh.new()
	board.size = Vector3(BACKDROP_W, BACKDROP_H, 0.08)
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.15, 0.1, 0.22)
	board_mat.metallic = 0.0
	board_mat.roughness = 0.5
	board.material = board_mat
	var board_node := MeshInstance3D.new()
	board_node.name = "BackdropBoard"
	board_node.mesh = board
	board_node.position.y = BACKDROP_H / 2.0
	panel.add_child(board_node)
	# Glowing border strip at top
	var trim := BoxMesh.new()
	trim.size = Vector3(BACKDROP_W + 0.2, 0.06, 0.12)
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.85, 0.5, 0.15)
	trim_mat.emission_enabled = true
	trim_mat.emission = Color(0.85, 0.5, 0.15)
	trim_mat.emission_energy_multiplier = 0.8
	trim.material = trim_mat
	var trim_node := MeshInstance3D.new()
	trim_node.name = "BackdropTrim"
	trim_node.mesh = trim
	trim_node.position.y = BACKDROP_H + 0.04
	panel.add_child(trim_node)
	# Title label: "SIMON STOMP" in game-show style
	var title := Label3D.new()
	title.name = "BackdropTitle"
	title.text = "SIMON STOMP"
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.no_depth_test = true
	title.fixed_size = true
	title.pixel_size = 0.004
	title.font_size = 60
	title.outline_size = 8
	title.modulate = Color(0.95, 0.85, 0.6)
	title.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	title.position = Vector3(0.0, BACKDROP_H * 0.65, 0.05)
	panel.add_child(title)
	# Sequence position indicator (#1155): shows the current flash step on
	# the backdrop panel so players can track the pattern length.
	var seq := Label3D.new()
	seq.name = "SequenceLabel"
	seq.text = ""
	seq.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	seq.no_depth_test = true
	seq.fixed_size = true
	seq.pixel_size = 0.0025
	seq.font_size = 36
	seq.outline_size = 6
	seq.modulate = Color(0.8, 0.75, 0.9)
	seq.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	seq.position = Vector3(0.0, BACKDROP_H * 0.25, 0.05)
	panel.add_child(seq)
	_sequence_label = seq
	# Position behind the pads
	panel.position = to_arena(Vector2(0.0, BACKDROP_Z))
	arena.add_child(panel)
	_backdrop = panel


## Follow-spotlight (#1155): a spotlight angled at the arena floor, tracking
## the currently lit pad during SHOW. Hidden during INPUT.
func _build_spotlight() -> void:
	var spot := SpotLight3D.new()
	spot.name = "FollowSpot"
	spot.spot_angle = SPOTLIGHT_ANGLE
	spot.spot_attenuation = 0.5
	spot.light_color = Color(1.0, 0.95, 0.85)
	spot.light_energy = 3.0
	spot.light_indirect_energy = 0.3
	spot.shadow_enabled = false
	spot.position = to_arena(Vector2(0.0, 0.0), SPOTLIGHT_HEIGHT)
	spot.rotation.x = deg_to_rad(-90.0)
	arena.add_child(spot)
	_spotlight = spot


## Track the follow-spotlight to the currently lit pad (#1155). During SHOW
## the spotlight sweeps to the lit pad; during INPUT it stays centered on the
## arena to light the whole stage.
func _update_spotlight(lit_pad: int) -> void:
	if _spotlight == null:
		return
	if lit_pad >= 0 and _phase == SimonStomp.Phase.SHOW:
		var target := _pad_position(lit_pad)
		_spotlight.position.x = lerpf(_spotlight.position.x, target.x, 0.15)
		_spotlight.position.z = lerpf(_spotlight.position.z, target.y, 0.15)
	elif _phase == SimonStomp.Phase.INPUT:
		_spotlight.position.x = lerpf(_spotlight.position.x, 0.0, 0.1)
		_spotlight.position.z = lerpf(_spotlight.position.z, 0.0, 0.1)


func _build_labels() -> void:
	_phase_label = make_status_label(&"PhaseLabel")
	_round_label = make_status_label(&"RoundLabel", PartyTheme.SIZE_OVERLAY_BODY)
	# #924: gap below the primary line, relative to the chrome-cleared baseline.
	_round_label.position.y = MinigameView3D.CHROME_CLEARANCE_Y + 56.0
	_build_countdown_label()


## Dead-center, huge, and hidden except during the SHOW lead-in (#1044) — the
## match-level countdown's look (#182), reused here so a mid-game round
## transition reads exactly as loud as the very first one.
func _build_countdown_label() -> void:
	_countdown_label = Label.new()
	_countdown_label.name = "CountdownLabel"
	_countdown_label.add_theme_font_size_override(&"font_size", 132)
	_countdown_label.add_theme_constant_override(&"outline_size", 10)
	_countdown_label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_label.visible = false
	_attach_overlay_label(_countdown_label)


func _update_labels() -> void:
	_phase_label.text = _phase_text()
	_round_label.text = "Round %d / %d  ·  Length %d" % [_round + 1, _rounds_total, _length]


## #930: these banners live on the never-hidden BannerLayer (gameplay-critical
## text must survive over the arena), so a match ending mid-SHOW otherwise
## leaves "Round 2/8 · Length 3" floating over the results overlay. Clear
## them once the match itself is over.
func _celebrate(placements: Array) -> void:
	_phase_label.text = ""
	_round_label.text = ""
	_countdown_label.visible = false
	super(placements)


## Ticks a big numeral down through the SHOW lead-in (#1044), same digit math
## and punch-in as the match-level countdown (#182): 3, 2, 1, then the first
## pad flash takes over and this hides.
func _update_countdown() -> void:
	if _phase != SimonStomp.Phase.SHOW or _show_timer >= SimonStomp.SHOW_LEAD_IN_SEC:
		_countdown_label.visible = false
		_countdown_digit = 0
		return
	_countdown_label.visible = true
	var remaining := SimonStomp.SHOW_LEAD_IN_SEC - _show_timer
	var digit := clampi(
		int(ceilf(remaining / SimonStomp.SHOW_LEAD_IN_STEP_SEC)), 1, SimonStomp.SHOW_LEAD_IN_STEPS
	)
	if digit != _countdown_digit:
		_countdown_digit = digit
		_countdown_label.text = str(digit)
		_pop_countdown()
		play_sfx(&"tick")


## Punch-in scale pop (#1044), the same overshoot tween the match-level
## countdown uses (#182). Reduced-motion shows the digit at rest instead.
func _pop_countdown() -> void:
	if ArenaFX.reduced_motion:
		return
	_countdown_label.pivot_offset = _countdown_label.size / 2.0
	_countdown_label.scale = Vector2(1.35, 1.35)
	var tween := create_tween()
	tween.set_trans(PartyTheme.TRANS_OVERSHOOT).set_ease(PartyTheme.EASE_DEFAULT)
	tween.tween_property(_countdown_label, "scale", Vector2.ONE, PartyTheme.DUR_MED)


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
	# Follow-spotlight tracks the lit pad (#1155).
	_update_spotlight(lit_pad)
	# Sequence position indicator (#1155): show current step of the flash pattern.
	if lit_pad >= 0 and _sequence_label != null:
		var flash_step := int(maxf(0.0, flash_time) / SimonStomp.SHOW_PER_PAD_SEC)
		_sequence_label.text = "Step %d / %d" % [min(flash_step + 1, _length), _length]


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
