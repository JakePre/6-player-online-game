class_name SideScrollView
extends MinigameView
## Client presentation base for the side-view games (M14-00): draws the
## SideScrollSim stage (PartyTheme-styled platforms over a parallax
## backdrop), manages 2D player rigs with nameplates in PlayerPalette
## colors, and brings M12-04-style snapshot interpolation to the 2D tier.
##
## A game view calls setup_stage() with the same rects its sim uses, then
## render_side_scroll(players) per snapshot with SideScrollSim's
## {slot: [x, y, facing, grounded]} samples. World space is y-up (the sim's
## convention); this class owns the flip to screen coordinates.

const SNAPSHOT_INTERVAL := 1.0 / NetConfig.SNAPSHOT_HZ
const MAX_SAMPLE_INTERVAL := 0.35
## World-unit jump treated as a teleport (respawn) rather than motion.
const TELEPORT_SNAP_DISTANCE := 4.0
const PLATFORM_COLOR := Color(0.2, 0.23, 0.3)
const PLATFORM_BORDER := Color(0.38, 0.42, 0.52)
const BACKDROP_BLOB_COUNT := 14
const DRIFT_SPEED := 0.02

var _stage_solids: Array[Rect2] = []
var _stage_one_way: Array[Rect2] = []
var _world := Rect2(-12.0, -6.0, 24.0, 18.0)

var _backdrop: Control
var _platform_layer: Control
var _rig_layer: Control
var _platform_nodes: Array[Panel] = []
var _rigs := {}
var _samples := {}
var _drift := 0.0


func _ready() -> void:
	_ensure_layers()


## Layer construction is lazy + idempotent: the production mount order
## (match_screen._mount_view) calls setup() → _setup() → setup_stage() BEFORE
## add_child fires _ready(), so building only in _ready() left _platform_layer
## null at setup_stage() time and crashed every side-scroll game at round start
## (#575). Mirrors MinigameView3D, which builds its scene tree from _setup().
## Safe to add_child a layer before this node is itself in the tree.
func _ensure_layers() -> void:
	if _platform_layer != null:
		return
	set_process_internal(true)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop = _layer()
	_backdrop.draw.connect(_draw_backdrop)
	_platform_layer = _layer()
	_rig_layer = _layer()
	resized.connect(_layout_stage)


## Stage geometry, in the sim's y-up world units. Call from _setup() with
## the exact rects the server sim uses so what players see is the truth.
func setup_stage(solids: Array[Rect2], one_way: Array[Rect2], world_bounds: Rect2) -> void:
	_ensure_layers()
	_stage_solids = solids
	_stage_one_way = one_way
	_world = world_bounds
	for node in _platform_nodes:
		node.queue_free()
	_platform_nodes.clear()
	for platform in solids + one_way:
		_platform_nodes.append(_make_platform())
	_layout_stage()
	_backdrop.queue_redraw()


## Feed SideScrollSim.snapshot_players() output; missing slots keep their
## last pose, unknown slots get rigs on first sight.
func render_side_scroll(players: Dictionary) -> void:
	_ensure_layers()
	for slot: int in players:
		var sample: Array = players[slot]
		if sample.size() < 4:
			continue
		var rig: Control = _rigs.get(slot)
		if rig == null:
			rig = _make_rig(slot)
		_record_sample(slot, Vector2(float(sample[0]), float(sample[1])))
		_face_rig(rig, int(sample[2]))


func rig_for_slot(slot: int) -> Control:
	return _rigs.get(slot)


## Uniform-scale world→screen mapping with the y flip, letterboxed to
## keep the whole stage in frame at any window shape.
func world_to_screen(world_pos: Vector2) -> Vector2:
	var scale_px := _world_scale()
	var center := size / 2.0
	var offset := world_pos - _world.get_center()
	return center + Vector2(offset.x, -offset.y) * scale_px


func _world_scale() -> float:
	if _world.size.x <= 0.0 or size.x <= 0.0:
		return 1.0
	return minf(size.x / _world.size.x, size.y / _world.size.y)


func _layer() -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


func _make_platform() -> Panel:
	var node := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PLATFORM_COLOR
	style.border_color = PLATFORM_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(PartyTheme.RADIUS_SM)
	node.add_theme_stylebox_override(&"panel", style)
	_platform_layer.add_child(node)
	return node


func _layout_stage() -> void:
	var rects := _stage_solids + _stage_one_way
	for i in mini(rects.size(), _platform_nodes.size()):
		var rect := rects[i]
		# The rect's top-left on screen is its y-up top-left corner.
		var top_left := world_to_screen(Vector2(rect.position.x, rect.position.y + rect.size.y))
		_platform_nodes[i].position = top_left
		_platform_nodes[i].size = rect.size * _world_scale()


func _make_rig(slot: int) -> Control:
	var rig := Control.new()
	rig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color := PlayerPalette.color_for_slot(slot)
	var body := Panel.new()
	body.name = "Body"
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(PartyTheme.RADIUS_SM)
	body.add_theme_stylebox_override(&"panel", style)
	rig.add_child(body)
	var eye := Panel.new()
	eye.name = "Eye"
	var eye_style := StyleBoxFlat.new()
	eye_style.bg_color = Color(0.98, 0.98, 0.98)
	eye_style.set_corner_radius_all(PartyTheme.RADIUS_SM)
	eye.add_theme_stylebox_override(&"panel", eye_style)
	rig.add_child(eye)
	var plate := Label.new()
	plate.name = "Plate"
	plate.text = str(names.get(slot, ""))
	plate.theme_type_variation = PartyTheme.SMALL_VARIATION
	plate.add_theme_color_override(&"font_color", color)
	plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rig.add_child(plate)
	_rig_layer.add_child(rig)
	_size_rig(rig)
	_rigs[slot] = rig
	return rig


func _size_rig(rig: Control) -> void:
	var px := SideScrollSim.HALF * 2.0 * _world_scale()
	var body: Panel = rig.get_node("Body")
	body.position = -px / 2.0
	body.size = px
	var eye: Panel = rig.get_node("Eye")
	eye.size = px * 0.22
	var plate: Label = rig.get_node("Plate")
	plate.position = Vector2(-60.0, -px.y / 2.0 - 24.0)
	plate.size = Vector2(120.0, 18.0)


func _face_rig(rig: Control, facing: int) -> void:
	var body: Panel = rig.get_node("Body")
	var eye: Panel = rig.get_node("Eye")
	var lean := body.size.x * 0.18
	eye.position = Vector2(
		-eye.size.x / 2.0 + signf(facing) * lean, -body.size.y * 0.28 - eye.size.y / 2.0
	)


# --- Snapshot interpolation (M12-04 pattern, world-space samples) -------------


func _record_sample(slot: int, target: Vector2) -> void:
	var now := _now_sec()
	var sample: Dictionary = _samples.get(slot, {})
	if sample.is_empty() or target.distance_to(sample.to) > TELEPORT_SNAP_DISTANCE:
		_samples[slot] = {"from": target, "to": target, "at": now, "interval": SNAPSHOT_INTERVAL}
		return
	var interval := clampf(now - float(sample.at), SNAPSHOT_INTERVAL, MAX_SAMPLE_INTERVAL)
	_samples[slot] = {
		# Start from the interpolated pose so jittery snapshot timing never
		# pops a rig backwards (same trick as MinigameView3D).
		"from": _sample_position(sample, now),
		"to": target,
		"at": now,
		"interval": interval,
	}


func _sample_position(sample: Dictionary, now: float) -> Vector2:
	var t := clampf((now - float(sample.at)) / float(sample.interval), 0.0, 1.0)
	return (sample.from as Vector2).lerp(sample.to, t)


func _interpolate_rigs(now: float) -> void:
	for slot: int in _samples:
		var rig: Control = _rigs.get(slot)
		if rig != null:
			rig.position = world_to_screen(_sample_position(_samples[slot], now))


func _now_sec() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_INTERNAL_PROCESS:
		_interpolate_rigs(_now_sec())
		if not ArenaFX.reduced_motion:
			_drift += get_process_delta_time() * DRIFT_SPEED
			_backdrop.queue_redraw()


## Soft drifting blobs behind the stage — depth without noise. Seeded off
## the blob index so the field is stable frame to frame.
func _draw_backdrop() -> void:
	for i in BACKDROP_BLOB_COUNT:
		var phase := float(i) * 2.399
		var x := fposmod(
			phase * 191.0 + _drift * size.x * (0.35 + 0.4 * fposmod(phase, 1.0)), size.x
		)
		var y := fposmod(phase * 127.0, size.y)
		var radius := 24.0 + 40.0 * fposmod(phase * 0.71, 1.0)
		var tint := PartyTheme.BG_RAISED
		tint.a = 0.35
		_backdrop.draw_circle(Vector2(x, y), radius, tint)
