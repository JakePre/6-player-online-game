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
## Solid platforms wear stone; jump-through lids wear wood, so a standable
## surface reads differently from a pass-up ledge at a glance (#925). Both
## get a bright top edge so the walkable top is obvious.
const SOLID_TEXTURE := preload("res://assets/generated/textures/castle-stone.png")
const ONE_WAY_TEXTURE := preload("res://assets/generated/textures/wood-court.png")
const PLATFORM_TOP_EDGE := Color(0.55, 0.62, 0.75)
const ONE_WAY_TOP_EDGE := Color(0.78, 0.6, 0.34)
## Backdrop (#925): a vertical gradient sky, a dim cool parallax silhouette
## band, and soft far clouds — deliberately cool, low-contrast and cloud-
## shaped so nothing back here reads as a foreground hazard.
const SKY_TOP := Color(0.10, 0.13, 0.22)
const SKY_BOTTOM := Color(0.17, 0.16, 0.24)
const HILL_COLOR := Color(0.13, 0.16, 0.26)
const HILL_FAR_COLOR := Color(0.11, 0.14, 0.22)
const CLOUD_COLOR := Color(0.22, 0.25, 0.34, 0.30)
const BACKDROP_BLOB_COUNT := 8
const DRIFT_SPEED := 0.02

var _stage_solids: Array[Rect2] = []
var _stage_one_way: Array[Rect2] = []
var _world := Rect2(-12.0, -6.0, 24.0, 18.0)

var _backdrop: Control
var _platform_layer: Control
var _rig_layer: Control
var _platform_nodes: Array[Panel] = []
var _platform_is_solid: Array[bool] = []
var _rigs := {}
var _samples := {}
var _drift := 0.0


## A top-anchored headline offset below the match chrome bar (#925): the
## side-scroll games hand-rolled a PRESET_TOP_WIDE label at y≈0 that clipped
## under the chrome. Every side-scroll game (and Magma Ascent) mounts its HUD
## through this so the clearance lives in one place.
func make_sidescroll_hud(hud_name: StringName = &"Hud") -> Label:
	_ensure_layers()
	var label := Label.new()
	label.name = String(hud_name)
	label.theme_type_variation = PartyTheme.HEADER_VARIATION
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Clear the HudBar chrome (~90px) the same way MinigameView3D's status
	# label does (#924 CHROME_CLEARANCE_Y) — no text under the match bar.
	label.position.y += MinigameView3D.CHROME_CLEARANCE_Y
	label.grow_vertical = Control.GROW_DIRECTION_END
	add_child(label)
	return label


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
	_platform_is_solid.clear()
	for _solid in solids:
		_platform_nodes.append(_make_platform(true))
		_platform_is_solid.append(true)
	for _lid in one_way:
		_platform_nodes.append(_make_platform(false))
		_platform_is_solid.append(false)
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


## Textured platform (#925): a tiled stone/wood fill instead of a bare outline
## slab, with a bright top edge so the walkable surface reads at a glance.
func _make_platform(is_solid: bool) -> Panel:
	var node := Panel.new()
	var style := StyleBoxTexture.new()
	style.texture = SOLID_TEXTURE if is_solid else ONE_WAY_TEXTURE
	# Tile rather than stretch, so a wide floor keeps stone-sized detail.
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	node.add_theme_stylebox_override(&"panel", style)
	# The bright standable lip (a child so it rides the top edge on resize).
	var edge := ColorRect.new()
	edge.name = "TopEdge"
	edge.color = PLATFORM_TOP_EDGE if is_solid else ONE_WAY_TOP_EDGE
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(edge)
	_platform_layer.add_child(node)
	return node


func _layout_stage() -> void:
	var rects := _stage_solids + _stage_one_way
	for i in mini(rects.size(), _platform_nodes.size()):
		var rect := rects[i]
		# The rect's top-left on screen is its y-up top-left corner.
		var top_left := world_to_screen(Vector2(rect.position.x, rect.position.y + rect.size.y))
		var node := _platform_nodes[i]
		node.position = top_left
		node.size = rect.size * _world_scale()
		var edge: ColorRect = node.get_node("TopEdge")
		edge.position = Vector2.ZERO
		edge.size = Vector2(node.size.x, maxf(2.0, node.size.y * 0.14))


## A little character (#925): a rounded body with two arms and two legs and a
## proper pair of eyes, in the player's palette color with a dark outline —
## so the fighters read as ducks-in-a-brawl, not bare capsules. Limbs and the
## second eye are extra children; Body/Eye/Plate keep their names + roles so
## the shared facing/sizing paths are unchanged.
func _make_rig(slot: int) -> Control:
	var rig := Control.new()
	rig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color := PlayerPalette.color_for_slot(slot)
	var limb_color := color.darkened(0.35)
	# Limbs first so the body sits over them.
	for limb_name in ["LegL", "LegR", "ArmL", "ArmR"]:
		rig.add_child(_rig_part(limb_name, limb_color, 0.0))
	var body := Panel.new()
	body.name = "Body"
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.darkened(0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(PartyTheme.RADIUS_MD)
	body.add_theme_stylebox_override(&"panel", style)
	rig.add_child(body)
	rig.add_child(_rig_part("Eye2", Color(0.98, 0.98, 0.98), PartyTheme.RADIUS_SM))
	var eye := Panel.new()
	eye.name = "Eye"
	var eye_style := StyleBoxFlat.new()
	eye_style.bg_color = Color(0.98, 0.98, 0.98)
	eye_style.set_corner_radius_all(PartyTheme.RADIUS_SM)
	eye.add_theme_stylebox_override(&"panel", eye_style)
	rig.add_child(eye)
	var plate := Label.new()
	plate.name = "Plate"
	# Number badge always shows; the name joins it only when show_names is on
	# (#580), same as the 3D CharacterRig nameplate.
	plate.text = player_name(slot)
	plate.theme_type_variation = PartyTheme.SMALL_VARIATION
	plate.add_theme_color_override(&"font_color", color)
	plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rig.add_child(plate)
	_rig_layer.add_child(rig)
	_size_rig(rig)
	_rigs[slot] = rig
	return rig


## A small colored Panel used for a limb or the second eye.
func _rig_part(part_name: String, color: Color, radius: int) -> Panel:
	var part := Panel.new()
	part.name = part_name
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	part.add_theme_stylebox_override(&"panel", style)
	return part


func _size_rig(rig: Control) -> void:
	var px := SideScrollSim.HALF * 2.0 * _world_scale()
	var body: Panel = rig.get_node("Body")
	# The body is a touch shorter than the hitbox to leave room for legs below.
	body.size = Vector2(px.x, px.y * 0.72)
	body.position = Vector2(-px.x / 2.0, -px.y / 2.0)
	var eye_px := px * 0.2
	(rig.get_node("Eye") as Panel).size = eye_px
	(rig.get_node("Eye2") as Panel).size = eye_px
	var leg := Vector2(px.x * 0.22, px.y * 0.3)
	var foot_y := px.y / 2.0 - leg.y
	(rig.get_node("LegL") as Panel).size = leg
	(rig.get_node("LegL") as Panel).position = Vector2(-px.x * 0.28 - leg.x / 2.0, foot_y)
	(rig.get_node("LegR") as Panel).size = leg
	(rig.get_node("LegR") as Panel).position = Vector2(px.x * 0.28 - leg.x / 2.0, foot_y)
	var arm := Vector2(px.x * 0.2, px.y * 0.34)
	var arm_y := -px.y * 0.12
	(rig.get_node("ArmL") as Panel).size = arm
	(rig.get_node("ArmL") as Panel).position = Vector2(-px.x / 2.0 - arm.x * 0.4, arm_y)
	(rig.get_node("ArmR") as Panel).size = arm
	(rig.get_node("ArmR") as Panel).position = Vector2(px.x / 2.0 - arm.x * 0.6, arm_y)
	var plate: Label = rig.get_node("Plate")
	plate.position = Vector2(-60.0, -px.y / 2.0 - 24.0)
	plate.size = Vector2(120.0, 18.0)


## Both eyes track the facing direction (#925: two eyes now, not one) — a pair
## of pupils that shift together toward where the fighter is heading.
func _face_rig(rig: Control, facing: int) -> void:
	var body: Panel = rig.get_node("Body")
	var eye: Panel = rig.get_node("Eye")
	var eye2: Panel = rig.get_node("Eye2")
	var lean := body.size.x * 0.16
	var gap := eye.size.x * 0.7
	var eye_y := -body.size.y * 0.5 - eye.size.y * 0.1
	var shift := signf(facing) * lean - eye.size.x / 2.0
	eye.position = Vector2(shift + gap, eye_y)
	eye2.position = Vector2(shift - gap, eye_y)


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


## The backdrop (#925): a vertical gradient sky, two parallax hill bands, and
## soft far clouds — all cool, dim and low-contrast, and drawn as gradients
## and wide hill polygons rather than sharp circles, so nothing here can be
## mistaken for a foreground hazard. Seeded off index so the field is stable.
func _draw_backdrop() -> void:
	# Gradient sky: a stack of horizontal bands from SKY_TOP to SKY_BOTTOM.
	var bands := 24
	for b in bands:
		var t := float(b) / float(bands - 1)
		var y := size.y * float(b) / float(bands)
		_backdrop.draw_rect(
			Rect2(0.0, y, size.x, size.y / float(bands) + 1.0), SKY_TOP.lerp(SKY_BOTTOM, t)
		)
	_draw_hill_band(0.72, 0.16, HILL_FAR_COLOR, 0.25)
	_draw_hill_band(0.82, 0.22, HILL_COLOR, 0.6)
	for i in BACKDROP_BLOB_COUNT:
		var phase := float(i) * 2.399
		var x := (
			fposmod(
				phase * 191.0 + _drift * size.x * (0.2 + 0.3 * fposmod(phase, 1.0)), size.x + 200.0
			)
			- 100.0
		)
		var y := size.y * (0.12 + 0.28 * fposmod(phase * 0.37, 1.0))
		_draw_cloud(Vector2(x, y), 40.0 + 55.0 * fposmod(phase * 0.71, 1.0))


## A rolling parallax hill: a filled polygon along a slow sine ridge, its crest
## at `base` (fraction of height), drifting by `parallax` of the cloud drift.
func _draw_hill_band(base: float, amplitude: float, color: Color, parallax: float) -> void:
	var points := PackedVector2Array()
	var crest := size.y * base
	var amp := size.y * amplitude
	var shift := _drift * size.x * parallax
	var steps := 16
	for s in steps + 1:
		var x := size.x * float(s) / float(steps)
		var y := crest - amp * (0.5 + 0.5 * sin(float(s) * 0.9 + shift * 0.05))
		points.append(Vector2(x, y))
	points.append(Vector2(size.x, size.y))
	points.append(Vector2(0.0, size.y))
	_backdrop.draw_colored_polygon(points, color)


## A soft cloud: three overlapping low-alpha lozenges — wide and flat, never a
## tight circle, so it never reads like a boulder or a projectile.
func _draw_cloud(center: Vector2, radius: float) -> void:
	for dx in [-radius * 0.7, 0.0, radius * 0.7]:
		_backdrop.draw_circle(center + Vector2(dx, 0.0), radius * 0.6, CLOUD_COLOR)
	_backdrop.draw_circle(center + Vector2(0.0, -radius * 0.25), radius * 0.7, CLOUD_COLOR)
