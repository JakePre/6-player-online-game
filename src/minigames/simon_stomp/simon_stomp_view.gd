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
const LIT := 1.4
## How long a flashed pad stays lit within its SHOW_PER_PAD_SEC window.
const FLASH_HOLD := 0.42

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
var _phase_label: Label
var _round_label: Label
## Locally clocked SHOW timer: snapshots arrive at 30 Hz but the flash should
## animate every frame, so we drive it off _process and reset on entering SHOW.
var _show_timer := 0.0


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


func _setup_3d() -> void:
	_build_pads()
	_build_labels()


func _render_3d(game: Dictionary) -> void:
	var previous_phase := _phase
	_phase = game.get("phase", SimonStomp.Phase.SHOW)
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


func _build_labels() -> void:
	_phase_label = Label.new()
	_phase_label.name = "PhaseLabel"
	_phase_label.add_theme_font_size_override(&"font_size", 40)
	_phase_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phase_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_phase_label.position.y = 16.0
	add_child(_phase_label)

	_round_label = Label.new()
	_round_label.name = "RoundLabel"
	_round_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_round_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_round_label.position.y = 72.0
	add_child(_round_label)


func _update_labels() -> void:
	_phase_label.text = _phase_text()
	_round_label.text = "Round %d / %d  ·  Length %d" % [_round + 1, _rounds_total, _length]


## During SHOW, light the pad whose flash window we're inside; the framework
## replays the sequence at SHOW_PER_PAD_SEC per step and we hold each lit for
## FLASH_HOLD. Outside SHOW every pad sits dimmed.
func _update_pads() -> void:
	var lit_pad := -1
	if _phase == SimonStomp.Phase.SHOW and not _sequence.is_empty():
		var step := SimonStomp.SHOW_PER_PAD_SEC
		var idx := int(_show_timer / step)
		if idx < _sequence.size() and fmod(_show_timer, step) <= FLASH_HOLD:
			lit_pad = int(_sequence[idx])
	for pad in _pad_materials.size():
		var base := PAD_COLORS[pad]
		var energy := LIT if pad == lit_pad else DIM
		_pad_materials[pad].albedo_color = base
		_pad_materials[pad].emission = base
		_pad_materials[pad].emission_energy_multiplier = energy


## Alive players idle; a player who cleared this round cheers, a busted one
## slumps ("hit"). Nameplates show each player's cleared-round tally.
func _update_rigs() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var caption := "%s  %d" % [player_name(slot), int(_cleared_count.get(slot, 0))]
		var desired: StringName = &"idle"
		if not _alive.get(slot, true):
			desired = &"hit"
			caption += "  (out)"
		elif _round_cleared.get(slot, false):
			desired = &"cheer"
		elif _round_failed.get(slot, false):
			desired = &"hit"
		if rig.current_action() != desired:
			rig.play(desired)
		rig.display_name = caption


func _phase_text() -> String:
	match _phase:
		SimonStomp.Phase.SHOW:
			return "WATCH..."
		SimonStomp.Phase.INPUT:
			return "STOMP!"
		_:
			return "Round over"
