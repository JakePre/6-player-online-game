extends MinigameView3D
## Shred Session client view (M14-04): a four-lane note highway. Notes stream
## down the lanes toward a hit line at the front; the local player strums the
## four lane inputs as each note crosses. Everything is driven by the replicated
## `elapsed` clock (extrapolated between snapshots for smoothness) — the view
## simulates nothing and scores nothing. Per-player scores ride a scoreboard;
## the local player's verdict flashes big, its lane lighting up. Audio is
## decorative: the round loop is the vibe, the replicated clock is the truth.

const LANE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"action_primary"]
const LANE_LABELS: Array[String] = ["◀", "▶", "▲", "●"]
const LANE_COLORS: Array[Color] = [
	Color(0.95, 0.35, 0.4),  # left
	Color(0.35, 0.6, 0.95),  # right
	Color(0.95, 0.8, 0.3),  # up
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


func _arena_half() -> float:
	return 8.0


func _setup_3d() -> void:
	_build_lanes()
	_build_hitline()
	_build_rig_row()
	_build_hud()


func _process(_delta: float) -> void:
	_read_input()
	var clock := _clock + (_now_sec() - _snapshot_at)
	_position_notes(clock)
	_update_flashes()


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
	# A colored arrow target sits on the line under each lane.
	for lane in ShredSession.LANES:
		var tag := Label3D.new()
		tag.name = "LaneTarget%d" % lane
		tag.text = LANE_LABELS[lane]
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.fixed_size = true
		tag.pixel_size = 0.005
		tag.font_size = 48
		tag.outline_size = 14
		tag.modulate = LANE_COLORS[lane]
		tag.position = to_arena(Vector2(LANE_X[lane], HIT_Z), 0.9)
		arena.add_child(tag)


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

	_streak_label = Label.new()
	_streak_label.name = "StreakLabel"
	_streak_label.add_theme_font_override(&"font", PartyTheme.FONT_DISPLAY)
	_streak_label.add_theme_font_size_override(&"font_size", PartyTheme.SIZE_TITLE)
	_streak_label.add_theme_color_override(&"font_color", PartyTheme.ACCENT_BRIGHT)
	_streak_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_streak_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_streak_label.position.y = 120.0
	_streak_label.visible = false
	add_child(_streak_label)

	_scoreboard = VBoxContainer.new()
	_scoreboard.name = "Scoreboard"
	_scoreboard.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_scoreboard.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_scoreboard.position = Vector2(-16.0, 16.0)
	_scoreboard.add_theme_constant_override(&"separation", PartyTheme.SPACE_XS)
	add_child(_scoreboard)


# --- Notes --------------------------------------------------------------------


func _note_key(note: Array) -> String:
	return "%s:%d" % [str(note[0]), int(note[1])]


func _reconcile_notes() -> void:
	var wanted := {}
	for note: Array in _notes:
		var key := _note_key(note)
		wanted[key] = true
		if not _note_nodes.has(key):
			_note_nodes[key] = _make_note(float(note[0]), int(note[1]))
	for key: String in _note_nodes.keys():
		if not wanted.has(key):
			(_note_nodes[key].node as MeshInstance3D).queue_free()
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
	return {"node": node, "time": note_time, "lane": lane}


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
			play_sfx(&"click")


## The server's verdict for the local player: flash the lane and call it out.
func _handle_local_judgment() -> void:
	var me: Array = _players.get(my_slot, [])
	if me.size() < 5:
		return
	var event: int = int(me[4])
	if event <= _my_last_event:
		_update_streak(int(me[1]))
		return
	_my_last_event = event
	var judgment: int = int(me[2])
	var lane: int = int(me[3])
	if lane >= 0 and lane < ShredSession.LANES:
		_lane_flash_until[lane] = _now_sec() + FLASH_SEC
	_show_judgment(judgment)
	_update_streak(int(me[1]))


func _show_judgment(judgment: int) -> void:
	if _judgment_label == null:
		return
	match judgment:
		ShredSession.Judgment.PERFECT:
			_judgment_label.text = "PERFECT!"
			_judgment_label.add_theme_color_override(&"font_color", PartyTheme.ACCENT_BRIGHT)
			play_sfx(&"confirm")
		ShredSession.Judgment.GOOD:
			_judgment_label.text = "GOOD"
			_judgment_label.add_theme_color_override(&"font_color", PartyTheme.INFO)
			play_sfx(&"confirm")
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
	for lane in _lane_mats.size():
		var lit := now < _lane_flash_until[lane]
		_lane_mats[lane].emission_energy_multiplier = 1.4 if lit else 0.12
	if _judgment_label != null and _judgment_label.visible and now >= _judgment_until:
		_judgment_label.visible = false


# --- Scoreboard & rigs --------------------------------------------------------


func _update_scoreboard() -> void:
	if _scoreboard == null:
		return
	var order: Array = _players.keys()
	order.sort_custom(
		func(a: int, b: int) -> bool: return int(_players[a][0]) > int(_players[b][0])
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
		row.text = "%s  %d" % [player_name(slot), int(stats[0])]
		row.add_theme_color_override(
			&"font_color", PartyTheme.ACCENT_BRIGHT if slot == my_slot else PartyTheme.TEXT
		)
	for i in order.size():
		(_score_rows[order[i]] as Label).get_parent().move_child(_score_rows[order[i]], i)


func _update_rigs() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var stats: Array = _players.get(slot, [])
		if not stats.is_empty():
			rig.display_name = "%s  %d" % [player_name(slot), int(stats[0])]


func _now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0
