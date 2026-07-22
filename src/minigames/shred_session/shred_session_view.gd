extends MinigameView3D
## Shred Session client view (M14-04): a four-lane note highway. Notes stream
## down the lanes toward a hit line at the front; the local player strums the
## four lane inputs as each note crosses. Everything is driven by the replicated
## `elapsed` clock (extrapolated between snapshots for smoothness) — the view
## simulates nothing and scores nothing. Per-player scores ride a scoreboard;
## the local player's verdict flashes big, its lane lighting up. Audio is
## decorative: the round loop is the vibe, the replicated clock is the truth.

## #1033: ordered to match the physical A, W, D, Space key layout (was Left,
## Right, Up, Action) — LANE_X (the screen positions) is untouched, so the
## highway automatically reads left-to-right as Left/Up/Right/Action.
const LANE_ACTIONS: Array[StringName] = [&"move_left", &"move_up", &"move_right", &"action_primary"]
## Flat direction glyph per lane, shown on the screen-space HUD header (#585) —
## unambiguous where the old iso-projected Label3D arrows were hard to read.
const LANE_LABELS: Array[String] = ["◀", "▲", "▶", "●"]
## Per-lane drum one-shot (#585): a distinct hit per lane replaces the single
## reused "alarm" tone. Procedurally generated originals (CC0), played on the
## SFX bus so the mixer/settings still apply.
const LANE_DRUMS: Array[String] = [
	"res://assets/audio/shred_drums/kick.wav",
	"res://assets/audio/shred_drums/hat.wav",
	"res://assets/audio/shred_drums/snare.wav",
	"res://assets/audio/shred_drums/tom.wav",
]
const LANE_COLORS: Array[Color] = [
	Color(0.95, 0.35, 0.4),  # left
	Color(0.95, 0.8, 0.3),  # up
	Color(0.35, 0.6, 0.95),  # right
	Color(0.45, 0.85, 0.45),  # action
]
const LANE_X: Array[float] = [-3.0, -1.0, 1.0, 3.0]
const LANE_W := 1.6
## The hit line sits toward the front; notes travel from the back toward it.
const HIT_Z := 5.0
## Units per second. LOOKAHEAD_SEC * NOTE_SPEED is the visible track length.
const NOTE_SPEED := 3.0
const TRACK_LEN := ShredSession.LOOKAHEAD_SEC * NOTE_SPEED
const NOTE_H := 0.35
const FLASH_SEC := 0.16
const JUDGMENT_HOLD_SEC := 0.55
## Star Power (#957): the lane highway floods this gold while the local player's
## 2x window runs — a flat tint under reduced motion, a gentle flare otherwise.
const STAR_GOLD := Color(1.0, 0.84, 0.2)
## Concert-stage mood: warm purple-amber atmosphere (#1154).
const STAGE_MOOD := Color(0.18, 0.12, 0.2)
## Stage platform sits just behind the hit line, filling the front area.
const STAGE_W := 8.0
const STAGE_D := 3.0
const STAGE_H := 0.3
## Spotlight count and spread for the beat-driven stage lights (#1154).
const STAGE_SPOTLIGHT_COUNT := 4
const STAGE_SPOTLIGHT_POSITIONS: Array[Vector2] = [
	Vector2(-3.5, -2.0),
	Vector2(3.5, -2.0),
	Vector2(-3.5, 7.0),
	Vector2(3.5, 7.0),
]
## Note trail extrusion length (#1154): a glowing bar behind each note.
const NOTE_TRAIL_LEN := 1.2
## Rim props: concert gear scattered around the stage perimeter (#1154).
const RIM_PROP_COUNT := 12
const RIM_PROP_SEED := 2254
## Concert gear rim props (#1154): crates, barrels, and poles from the
## platformer kit, scattered around the stage perimeter.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_platformer_kit/crate.glb"),
	preload("res://assets/environment/kenney_platformer_kit/barrel.glb"),
	preload("res://assets/environment/kenney_platformer_kit/poles.glb"),
	preload("res://assets/environment/kenney_platformer_kit/sign.glb"),
	preload("res://assets/environment/kenney_platformer_kit/plant.glb"),
	preload("res://assets/environment/kenney_platformer_kit/rocks.glb"),
]

var _clock := 0.0
var _snapshot_at := 0.0
var _notes: Array = []
var _players := {}

## key "time:lane" -> {node: MeshInstance3D, time: float, lane: int}
var _note_nodes := {}
var _lane_mats: Array[StandardMaterial3D] = []
var _lane_flash_until: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _hitline_mat: StandardMaterial3D

var _judgment_label: Label
var _streak_label: Label
var _judgment_until := 0.0
var _score_rows := {}  # slot -> Label
var _scoreboard: VBoxContainer
var _my_last_event := 0
## Star Power (#957): last-seen local 2x-active flag, for the rising-edge cue.
var _star_seen := false

## Screen-space lane-header glyph labels (#585): the device-aware bound input
## per lane, refreshed live on InputGlyphs.device_changed.
var _lane_glyph_labels: Array[Label] = []
## Stage spotlight beam nodes (#1154).
var _stage_spotlights: Array[MeshInstance3D] = []
## Stage spotlight material instances for beat-driven color pulses (#1154).
var _stage_spotlight_mats: Array[StandardMaterial3D] = []
## One AudioStreamPlayer per lane, preloaded with that lane's drum (#585).
var _lane_players: Array[AudioStreamPlayer] = []


## Neon stage-purple floor (#589).
func _floor_tint() -> Color:
	return Color(0.88, 0.85, 1.0)


## Warm concert-theatre mood (#1154): purple-amber atmosphere for the stage shell.
func _mood() -> Color:
	return STAGE_MOOD.lerp(_floor_tint(), 0.2)


func _arena_half() -> float:
	return 8.0


func _setup_3d() -> void:
	_build_lanes()
	_build_hitline()
	_build_concert_stage()
	_build_stage_spotlights()
	_build_rim_props()
	_build_rig_row()
	_build_hud()
	_build_lane_headers()
	_build_drums()
	InputGlyphs.device_changed.connect(_on_device_changed)


func _process(_delta: float) -> void:
	_read_input()
	var clock := _clock + (_now_sec() - _snapshot_at)
	_position_notes(clock)
	_update_flashes()
	_update_stage_spotlights(clock)


func _render_3d(game: Dictionary) -> void:
	_clock = float(game.get("elapsed", 0.0))
	_snapshot_at = _now_sec()
	_notes = game.get("notes", [])
	_players = game.get("players", {})
	_reconcile_notes()
	_position_notes(_clock)
	_handle_local_judgment()
	_update_scoreboard()
	_update_rigs()
	# Star Power call-out on the rising edge of the local player's 2x window (#957).
	var star := _local_star_active()
	if star and not _star_seen:
		_announce_star()
	_star_seen = star


# --- Build --------------------------------------------------------------------


func _build_lanes() -> void:
	for lane in ShredSession.LANES:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(LANE_W, 0.05, TRACK_LEN)
		var material := StandardMaterial3D.new()
		material.albedo_color = LANE_COLORS[lane].darkened(0.55)
		material.emission_enabled = true
		material.emission = LANE_COLORS[lane]
		material.emission_energy_multiplier = 0.12
		mesh.material = material
		_lane_mats.append(material)
		var node := MeshInstance3D.new()
		node.name = "Lane%d" % lane
		node.mesh = mesh
		node.position = to_arena(Vector2(LANE_X[lane], HIT_Z - TRACK_LEN / 2.0), 0.02)
		arena.add_child(node)


func _build_hitline() -> void:
	var span: float = LANE_X[LANE_X.size() - 1] - LANE_X[0] + LANE_W
	var mesh := BoxMesh.new()
	mesh.size = Vector3(span, 0.12, 0.3)
	_hitline_mat = StandardMaterial3D.new()
	_hitline_mat.albedo_color = Color(0.95, 0.95, 1.0)
	_hitline_mat.emission_enabled = true
	_hitline_mat.emission = Color(0.95, 0.95, 1.0)
	mesh.material = _hitline_mat
	var bar := MeshInstance3D.new()
	bar.name = "HitLine"
	bar.mesh = mesh
	bar.position = to_arena(Vector2(0.0, HIT_Z), 0.08)
	arena.add_child(bar)
	# Lane identity now reads off the flat screen-space header (_build_lane_headers,
	# #585) — the old iso-projected Label3D arrows were ambiguous on the grid.


## Players stand in a row across the back of the highway, facing the camera.
func _build_rig_row() -> void:
	var sorted: Array = names.keys()
	sorted.sort()
	for i in sorted.size():
		var rig := rig_for_slot(sorted[i])
		if rig == null:
			continue
		var spread := 6.0
		var x := lerpf(
			-spread, spread, 0.5 if sorted.size() == 1 else float(i) / (sorted.size() - 1)
		)
		rig.position = to_arena(Vector2(x, HIT_Z - TRACK_LEN - 1.0))
		rig.rotation.y = PI  # face the camera / oncoming notes


func _build_hud() -> void:
	_judgment_label = Label.new()
	_judgment_label.name = "JudgmentLabel"
	_judgment_label.add_theme_font_override(&"font", PartyTheme.FONT_DISPLAY)
	_judgment_label.add_theme_font_size_override(&"font_size", PartyTheme.SIZE_DISPLAY)
	_judgment_label.set_anchors_preset(Control.PRESET_CENTER)
	_judgment_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_judgment_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_judgment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_judgment_label.visible = false
	add_child(_judgment_label)

	_streak_label = make_status_label(&"StreakLabel")
	_streak_label.add_theme_font_override(&"font", PartyTheme.FONT_DISPLAY)
	_streak_label.add_theme_color_override(&"font_color", PartyTheme.ACCENT_BRIGHT)
	# #924: gap below the primary line, relative to the chrome-cleared baseline.
	_streak_label.position.y = MinigameView3D.CHROME_CLEARANCE_Y + 104.0
	_streak_label.visible = false

	_scoreboard = VBoxContainer.new()
	_scoreboard.name = "Scoreboard"
	_scoreboard.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_scoreboard.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# Below the match-chrome header (~100px) — at y=16 the top score rows hid
	# behind it (#831 render spot-check).
	_scoreboard.position = Vector2(-16.0, 120.0)
	_scoreboard.add_theme_constant_override(&"separation", PartyTheme.SPACE_XS)
	add_child(_scoreboard)


## Flat, screen-space lane headers (#585): a row of chips, one per lane in
## left-to-right order, each a clear direction arrow plus the device-aware
## bound input below it. Replaces the iso-projected Label3D arrows.
## #798: the original bottom-edge placement (-24px) still went unnoticed in
## owner playtesting — moved well up toward where the hit line reads on
## screen, and enlarged, so it's impossible to miss.
func _build_lane_headers() -> void:
	var row := HBoxContainer.new()
	row.name = "LaneHeaders"
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.position.y = -220.0
	row.add_theme_constant_override(&"separation", PartyTheme.SPACE_LG)
	add_child(row)
	_lane_glyph_labels.clear()
	for lane in ShredSession.LANES:
		var chip := VBoxContainer.new()
		chip.alignment = BoxContainer.ALIGNMENT_CENTER
		var arrow := Label.new()
		arrow.text = LANE_LABELS[lane]
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.add_theme_font_size_override(&"font_size", PartyTheme.SIZE_DISPLAY)
		arrow.add_theme_color_override(&"font_color", LANE_COLORS[lane])
		chip.add_child(arrow)
		var glyph := Label.new()
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override(&"font_size", PartyTheme.SIZE_HEADER)
		chip.add_child(glyph)
		row.add_child(chip)
		_lane_glyph_labels.append(glyph)
	_refresh_lane_glyphs()


## One preloaded player per lane on the SFX bus (#585), so a strum fires that
## lane's drum without contending for the shared chrome SFX pool.
func _build_drums() -> void:
	_lane_players.clear()
	for lane in ShredSession.LANES:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		player.stream = load(LANE_DRUMS[lane])
		add_child(player)
		_lane_players.append(player)


## Concert stage (#1154): a raised platform filling the front of the arena,
## with speaker stacks and a drum kit made from Kenney Food Kit props.
func _build_concert_stage() -> void:
	# Raised platform — a wide shallow box sitting just behind the hit line.
	var platform := MeshInstance3D.new()
	platform.name = "ConcertStage"
	var stage_mesh := BoxMesh.new()
	stage_mesh.size = Vector3(STAGE_W, STAGE_H, STAGE_D)
	var stage_mat := StandardMaterial3D.new()
	stage_mat.albedo_color = Color(0.08, 0.06, 0.1)
	stage_mat.emission_enabled = true
	stage_mat.emission = Color(0.15, 0.1, 0.2)
	stage_mat.emission_energy_multiplier = 0.4
	stage_mesh.material = stage_mat
	platform.mesh = stage_mesh
	platform.position = to_arena(Vector2(0.0, HIT_Z - STAGE_D / 2.0), STAGE_H / 2.0)
	arena.add_child(platform)

	# Speaker stacks at stage corners (BoxMesh columns).
	var speaker_positions := [
		Vector2(-STAGE_W / 2.0 + 0.4, HIT_Z - 0.3),
		Vector2(STAGE_W / 2.0 - 0.4, HIT_Z - 0.3),
		Vector2(-STAGE_W / 2.0 + 0.4, HIT_Z - STAGE_D + 0.3),
		Vector2(STAGE_W / 2.0 - 0.4, HIT_Z - STAGE_D + 0.3),
	]
	for pos: Vector2 in speaker_positions:
		var stack := Node3D.new()
		stack.name = "SpeakerStack"
		for j in 3:
			var speaker := MeshInstance3D.new()
			speaker.name = "Speaker%d" % j
			var sm := BoxMesh.new()
			sm.size = Vector3(0.5, 0.4, 0.5)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.05, 0.05, 0.05)
			mat.emission_enabled = true
			mat.emission = Color(0.08, 0.08, 0.12)
			mat.emission_energy_multiplier = 0.15
			sm.material = mat
			speaker.mesh = sm
			speaker.position.y = float(j) * 0.4 + 0.2
			stack.add_child(speaker)
		stack.position = to_arena(pos, 0.0)
		arena.add_child(stack)

	# Drum kit from Kenney Food Kit pots/pans, placed across the stage front.
	var drum_positions := [
		Vector2(-2.0, HIT_Z - 0.8),
		Vector2(-0.7, HIT_Z - 0.6),
		Vector2(0.7, HIT_Z - 0.6),
		Vector2(2.0, HIT_Z - 0.8),
	]
	var drum_scenes: Array[PackedScene] = [
		preload("res://assets/environment/kenney_food_kit/pot-lid.glb"),
		preload("res://assets/environment/kenney_food_kit/pot-stew-lid.glb"),
		preload("res://assets/environment/kenney_food_kit/plate-dinner.glb"),
		preload("res://assets/environment/kenney_food_kit/plate-deep.glb"),
	]
	for i in drum_positions.size():
		var drum := drum_scenes[i % drum_scenes.size()].instantiate() as Node3D
		if drum == null:
			continue
		drum.name = "DrumKit%d" % i
		drum.position = to_arena(drum_positions[i], 0.0)
		drum.scale = Vector3(0.8, 0.8, 0.8)
		arena.add_child(drum)


## Stage spotlights (#1154): emissive cones from above the stage, driven by the
## replicated clock so they pulse with the beat (one sweep per measure).
func _build_stage_spotlights() -> void:
	for i in STAGE_SPOTLIGHT_COUNT:
		var pos := STAGE_SPOTLIGHT_POSITIONS[i]
		var pivot := Node3D.new()
		pivot.name = "StageSpotlight%d" % i
		pivot.position = to_arena(pos, 4.0)
		pivot.look_at(to_arena(pos, 0.0), Vector3(0.0, 0.0, -1.0))
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 2.0
		cone.height = 4.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = LANE_COLORS[i % LANE_COLORS.size()]
		mat.albedo_color.a = 0.08
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		cone.material = mat
		var beam := MeshInstance3D.new()
		beam.name = "Beam"
		beam.mesh = cone
		beam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		beam.position = Vector3(0.0, 0.0, -cone.height / 2.0)
		pivot.add_child(beam)
		arena.add_child(pivot)
		_stage_spotlights.append(beam)
		_stage_spotlight_mats.append(mat)


## Rim props (#1154): concert gear (crates, barrels, poles) scattered around
## the stage perimeter via the shared scatter_rim_props helper.
func _build_rim_props() -> void:
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)


## Beat-driven spotlight update (#1154): the replicated clock drives color
## pulses and a gentle sway, matching the 4/4 rhythm of the song.
func _update_stage_spotlights(clock: float) -> void:
	var beat := clock * 2.0  # approximate beat count (2 beats per second at 120 BPM)
	for i in _stage_spotlight_mats.size():
		var mat: StandardMaterial3D = _stage_spotlight_mats[i]
		var color: Color = LANE_COLORS[i % LANE_COLORS.size()]
		# Pulse on the beat: each spotlight brightens on its own beat phase.
		var phase := fmod(beat + float(i) * 0.5, 4.0) / 4.0
		var pulse := 0.3 + 0.7 * pow(1.0 - phase, 4.0) if phase < 0.6 else 0.3
		mat.albedo_color = color
		mat.albedo_color.a = 0.04 * pulse
		# Gentle sway.
		var sway := sin(beat * 0.5 + float(i) * 1.57) * 0.15
		_stage_spotlights[i].get_parent().rotation.z = sway


func _on_device_changed(_device: InputGlyphs.Device) -> void:
	_refresh_lane_glyphs()


## Show each lane's bound input for the active device. Movement lanes are stick
## axes on a pad (no button glyph) — there the arrow alone is the instruction,
## so an empty glyph just clears the sub-label.
func _refresh_lane_glyphs() -> void:
	for lane in _lane_glyph_labels.size():
		_lane_glyph_labels[lane].text = InputGlyphs.glyph_for(LANE_ACTIONS[lane])


func _play_drum(lane: int) -> void:
	if lane >= 0 and lane < _lane_players.size():
		_lane_players[lane].play()


# --- Notes --------------------------------------------------------------------


func _note_key(note: Array) -> String:
	return "%s:%d" % [str(note[ShredSession.NT_TIME]), int(note[ShredSession.NT_LANE])]


func _reconcile_notes() -> void:
	var wanted := {}
	for note: Array in _notes:
		var key := _note_key(note)
		wanted[key] = true
		if not _note_nodes.has(key):
			_note_nodes[key] = _make_note(
				float(note[ShredSession.NT_TIME]), int(note[ShredSession.NT_LANE])
			)
	for key: String in _note_nodes.keys():
		if not wanted.has(key):
			var entry: Dictionary = _note_nodes[key]
			(entry.node as MeshInstance3D).queue_free()
			if entry.has("trail"):
				(entry.trail as MeshInstance3D).queue_free()
			_note_nodes.erase(key)


func _make_note(note_time: float, lane: int) -> Dictionary:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(LANE_W * 0.85, NOTE_H, 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = LANE_COLORS[lane]
	material.emission_enabled = true
	material.emission = LANE_COLORS[lane]
	material.emission_energy_multiplier = 0.7
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "Note"
	node.add_to_group(&"shred_notes")
	node.mesh = mesh
	arena.add_child(node)
	# Glowing trail behind the note (#1154): a thin emissive bar trailing
	# backward from the note along the lane direction.
	var trail_mesh := BoxMesh.new()
	trail_mesh.size = Vector3(LANE_W * 0.5, NOTE_H * 0.3, NOTE_TRAIL_LEN)
	var trail_mat := StandardMaterial3D.new()
	trail_mat.albedo_color = LANE_COLORS[lane]
	trail_mat.emission_enabled = true
	trail_mat.emission = LANE_COLORS[lane]
	trail_mat.emission_energy_multiplier = 0.3
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	trail_mesh.material = trail_mat
	var trail := MeshInstance3D.new()
	trail.name = "NoteTrail"
	trail.mesh = trail_mesh
	node.add_child(trail)
	return {"node": node, "trail": trail, "time": note_time, "lane": lane}


## A note sits at the hit line the instant the clock reaches its time; earlier it
## is up-track (smaller z), a hair past the line just after.
func _position_notes(clock: float) -> void:
	for key: String in _note_nodes:
		var entry: Dictionary = _note_nodes[key]
		var depth: float = HIT_Z - (float(entry.time) - clock) * NOTE_SPEED
		(entry.node as MeshInstance3D).position = to_arena(
			Vector2(LANE_X[int(entry.lane)], depth), NOTE_H / 2.0 + 0.05
		)


# --- Input & judgment ---------------------------------------------------------


func _read_input() -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	for lane in LANE_ACTIONS.size():
		if Input.is_action_just_pressed(LANE_ACTIONS[lane]):
			NetManager.send_match_input({"lane": lane})
			_lane_flash_until[lane] = _now_sec() + FLASH_SEC
			_play_drum(lane)
	# Star Power spend (#957): the server gates it to a full meter, so a press
	# with a half-charged meter is a harmless no-op.
	if Input.is_action_just_pressed(&"action_secondary"):
		NetManager.send_match_input({"star": true})


## The server's verdict for the local player: flash the lane and call it out.
func _handle_local_judgment() -> void:
	var me: Array = _players.get(my_slot, [])
	if me.size() < ShredSession.PS_COUNT:
		return
	var event: int = int(me[ShredSession.PS_EVENT_COUNT])
	if event <= _my_last_event:
		_update_streak(int(me[ShredSession.PS_STREAK]))
		return
	_my_last_event = event
	var judgment: int = int(me[ShredSession.PS_LAST_JUDGMENT])
	var lane: int = int(me[ShredSession.PS_LAST_LANE])
	if lane >= 0 and lane < ShredSession.LANES:
		_lane_flash_until[lane] = _now_sec() + FLASH_SEC
		# A clean hit vanishes its note immediately instead of sliding through
		# the line (#798) — a miss still rolls past, which is the miss itself
		# reading as feedback. The shared chart keeps the note in every other
		# player's snapshot until its window fully closes, so this is a
		# purely local, cosmetic early-removal, not a state change.
		if judgment == ShredSession.Judgment.PERFECT or judgment == ShredSession.Judgment.GOOD:
			_pop_judged_note(lane)
	_show_judgment(judgment)
	_update_streak(int(me[ShredSession.PS_STREAK]))


## Vanishes the note nearest the hit line in `lane` (#798) — a small sparkle
## instead of the usual queue_free, so a clean hit gets its own pop. Only
## targets a note actually near judgment time (the sim's own GOOD_SEC
## window), so this can't be mistaken for a note that hasn't arrived yet.
func _pop_judged_note(lane: int) -> void:
	var clock := _clock + (_now_sec() - _snapshot_at)
	var closest_key := ""
	var closest_dt := INF
	for key: String in _note_nodes:
		var entry: Dictionary = _note_nodes[key]
		if int(entry.lane) != lane:
			continue
		var dt := absf(float(entry.time) - clock)
		if dt < closest_dt:
			closest_dt = dt
			closest_key = key
	if closest_key.is_empty() or closest_dt > ShredSession.GOOD_SEC:
		return
	var entry: Dictionary = _note_nodes[closest_key]
	var node: MeshInstance3D = entry.node
	fx_sparkle(Vector2(node.position.x, node.position.z), LANE_COLORS[lane], node.position.y)
	if entry.has("trail"):
		(entry.trail as MeshInstance3D).queue_free()
	node.queue_free()
	_note_nodes.erase(closest_key)


func _show_judgment(judgment: int) -> void:
	if _judgment_label == null:
		return
	match judgment:
		ShredSession.Judgment.PERFECT:
			_judgment_label.text = "PERFECT!"
			_judgment_label.add_theme_color_override(&"font_color", PartyTheme.ACCENT_BRIGHT)
			# The lane drum (#585) already carries the beat; these judgment
			# stingers are separate feedback on the shared pool (#728) — a
			# perfect hit is the bigger checkpoint, good is the smaller one.
			play_sfx(&"bell")
		ShredSession.Judgment.GOOD:
			_judgment_label.text = "GOOD"
			_judgment_label.add_theme_color_override(&"font_color", PartyTheme.INFO)
			play_sfx(&"pop")
		ShredSession.Judgment.MISS:
			_judgment_label.text = "MISS"
			_judgment_label.add_theme_color_override(&"font_color", PartyTheme.DANGER)
			play_sfx(&"error")
			request_shake(3.0)
		_:
			return
	_judgment_label.visible = true
	_judgment_until = _now_sec() + JUDGMENT_HOLD_SEC


func _update_streak(streak: int) -> void:
	if _streak_label == null:
		return
	if streak < ShredSession.STREAK_X2:
		_streak_label.visible = false
		return
	var mult := 3 if streak >= ShredSession.STREAK_X3 else 2
	_streak_label.visible = true
	_streak_label.text = "%d STREAK  ×%d" % [streak, mult]


func _update_flashes() -> void:
	var now := _now_sec()
	# Gold flood while the local 2x window runs (#957): a flat gold tint under
	# reduced motion, a gentle flare pulse otherwise; a fresh strum still reads
	# brighter on top.
	var star := _local_star_active()
	var flare := 1.6 if ArenaFX.reduced_motion else 1.4 + 0.5 * sin(now * TAU * 1.5)
	for lane in _lane_mats.size():
		var lit := now < _lane_flash_until[lane]
		if star:
			_lane_mats[lane].emission = STAR_GOLD
			_lane_mats[lane].emission_energy_multiplier = 1.9 if lit else flare
		else:
			_lane_mats[lane].emission = LANE_COLORS[lane]
			_lane_mats[lane].emission_energy_multiplier = 1.4 if lit else 0.12
	if _judgment_label != null and _judgment_label.visible and now >= _judgment_until:
		_judgment_label.visible = false


## True while the local player's spent 2x window is running (#957).
func _local_star_active() -> bool:
	var me: Array = _players.get(my_slot, [])
	return me.size() > ShredSession.PS_STAR_ACTIVE and int(me[ShredSession.PS_STAR_ACTIVE]) == 1


## Local player just lit Star Power (#957): a gold call-out plus a cue, and
## stage-edge pyrotechnic bursts (#1154).
func _announce_star() -> void:
	if _judgment_label != null:
		_judgment_label.text = "STAR POWER!"
		_judgment_label.add_theme_color_override(&"font_color", STAR_GOLD)
		_judgment_label.visible = true
		_judgment_until = _now_sec() + JUDGMENT_HOLD_SEC
	play_sfx(&"bell")
	_burst_pyro()


## Pyrotechnics burst (#1154): gold and white CPUParticles3D bursts from stage
## edges on star power activation. Reuses the pyrotechnic nodes so repeated
## star activations trigger fresh bursts.
func _burst_pyro() -> void:
	if ArenaFX.reduced_motion:
		return
	var positions := [
		Vector2(-STAGE_W / 2.0 + 0.5, HIT_Z - 0.3),
		Vector2(STAGE_W / 2.0 - 0.5, HIT_Z - 0.3),
		Vector2(-STAGE_W / 2.0 + 0.5, HIT_Z - STAGE_D + 0.3),
		Vector2(STAGE_W / 2.0 - 0.5, HIT_Z - STAGE_D + 0.3),
	]
	for pos: Vector2 in positions:
		var particles := CPUParticles3D.new()
		particles.one_shot = true
		particles.explosiveness = 1.0
		particles.amount = 20
		particles.lifetime = 0.7
		particles.color = STAR_GOLD if (positions.find(pos) % 2 == 0) else Color(1.0, 1.0, 1.0, 0.9)
		var mesh := SphereMesh.new()
		mesh.radius = 0.05
		mesh.height = 0.1
		particles.mesh = mesh
		particles.direction = Vector3.UP
		particles.spread = 160.0
		particles.initial_velocity_min = 2.0
		particles.initial_velocity_max = 6.0
		particles.gravity = Vector3(0.0, -6.0, 0.0)
		particles.position = to_arena(pos, 0.5)
		arena.add_child(particles)
		particles.emitting = true
		particles.finished.connect(particles.queue_free)


## Round-end celebration (#1154): hide the highway labels, let the base cheer
## play through.
func _celebrate(placements: Array) -> void:
	_streak_label.visible = false
	_judgment_label.visible = false
	super(placements)


# --- Scoreboard & rigs --------------------------------------------------------


func _update_scoreboard() -> void:
	if _scoreboard == null:
		return
	var order: Array = _players.keys()
	order.sort_custom(
		func(a: int, b: int) -> bool:
			return int(_players[a][ShredSession.PS_SCORE]) > int(_players[b][ShredSession.PS_SCORE])
	)
	for slot: int in _players:
		if not _score_rows.has(slot):
			var row := Label.new()
			row.add_theme_font_override(&"font", PartyTheme.FONT_BODY)
			row.add_theme_font_size_override(&"font_size", PartyTheme.SIZE_HEADER)
			_scoreboard.add_child(row)
			_score_rows[slot] = row
		var stats: Array = _players[slot]
		var row: Label = _score_rows[slot]
		row.text = (
			"%s  %d%s" % [player_name(slot), int(stats[ShredSession.PS_SCORE]), _star_suffix(stats)]
		)
		row.add_theme_color_override(
			&"font_color", PartyTheme.ACCENT_BRIGHT if slot == my_slot else PartyTheme.TEXT
		)
	for i in order.size():
		(_score_rows[order[i]] as Label).get_parent().move_child(_score_rows[order[i]], i)


## Star Power state for a scoreboard row (#957): the spent 2x window, a ready
## meter, or the running charge — so rivals can read the race for the boost.
func _star_suffix(stats: Array) -> String:
	if stats.size() <= ShredSession.PS_STAR_ACTIVE:
		return ""
	if int(stats[ShredSession.PS_STAR_ACTIVE]) == 1:
		return "  ★2×"
	var meter := int(stats[ShredSession.PS_STAR_METER])
	if meter >= ShredSession.STAR_PERFECTS:
		return "  ★READY"
	if meter > 0:
		return "  ★%d/%d" % [meter, ShredSession.STAR_PERFECTS]
	return ""


func _update_rigs() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var stats: Array = _players.get(slot, [])
		if not stats.is_empty():
			rig.display_name = "%s  %d" % [player_name(slot), int(stats[ShredSession.PS_SCORE])]


func _now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0
