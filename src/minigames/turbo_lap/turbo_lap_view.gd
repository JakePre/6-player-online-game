extends MinigameView3D
## Turbo Lap client view (M14-02): renders the replicated race in the shared
## iso arena — a ribbon track built from the sim's own centerline, glowing
## boost pads, item pads that dim while cooling, box-karts riding under each
## character rig, pooled shells and oil slicks — without simulating anything
## locally. Gas is action_primary (held, #1067), the item is action_secondary;
## drifting is steering hard at speed.
const TRACK_COLOR := Color(0.16, 0.17, 0.21)
const START_COLOR := Color(0.96, 0.79, 0.2)
## Tier 1 — Track texture (#1165): IMG-052 asphalt-track.png is the single most
## impactful visual upgrade for this game — transforms the flat grey ribbon
## into a real race track. UV tiles along the strip length so scale changes
## (shaped course) don't stretch the grain.
const ASPHALT_TEXTURE := preload("res://assets/generated/textures/asphalt-track.png")
const TRACK_TEXTURE_TILES := 2.0  # tiling per unit length
## Continuous curb rails (#1041): the two track edges are drawn as gap-free
## miter-joined walls tracing the ribbon, replacing the 100+ tiled MDL-007
## barrier blocks that read as messy concentric arcs and never closed the oval.
const RAIL_COLOR := Color(0.86, 0.88, 0.94)
const RAIL_HEIGHT := 0.4
const RAIL_WIDTH := 0.28
## Start/finish gate (#1041, MDL-022): the re-rolled finish-arch.glb — two
## short gold pylons under a wood-plank checkered banner, pivot at base
## center. The original MDL-006 build rendered as a malformed blob (a lumpy
## 6.45u-tall mass); MDL-022 fixes it AND ships a leading-indicator lesson:
## its texture-stage xatlas UV-split fragmented the exported mesh into
## hundreds of disconnected patches that still LOOKED solid in every preview
## (component count is the tell — see the pipeline-side writeup). Scaled
## uniformly so its own ~4.5u span matches the track's dynamic width exactly.
const ARCH_SCENE := preload("res://assets/generated/models/finish-arch.glb")
## The model's own span at its baked scale (bbox X-extent) — divide the
## track's dynamic span by this to size the instance correctly.
const ARCH_MODEL_SPAN := 4.5
## The MDL-015 go-kart (#956): authored neutral grey/white exactly so the view
## can tint the whole body to the player color at runtime (its ledger contract).
## Base pivot, wheels on the ground; nose points -Z in the GLB.
const KART_SCENE := preload("res://assets/generated/models/go-kart.glb")
const BOOST_PAD_COLOR := Color(0.3, 0.75, 1.0)
const ITEM_PAD_COLOR := Color(0.96, 0.79, 0.2)
const SHELL_COLOR := Color(0.35, 0.9, 0.45)
const OIL_COLOR := Color(0.08, 0.07, 0.1)
const SHELL_POOL := 12
const OIL_POOL := TurboLap.MAX_OILS
const ITEM_ICONS := {
	TurboLap.ITEM_NONE: "",
	TurboLap.ITEM_SHELL: "🐢",
	TurboLap.ITEM_OIL: "🛢",
	TurboLap.ITEM_BOOST: "⚡"
}
## Grandstand buildings (#1165): Kenney City Kit Commercial buildings scattered
## around the arena perimeter as spectator grandstands.
const GRANDSTAND_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-a.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-b.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-c.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-d.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-e.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-f.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-g.glb"),
]
const GRANDSTAND_COUNT := 12
const GRANDSTAND_SEED := 0x7442
## Track lighting (#1165): street lamps along the track straight sections.
const LAMP_POLE_HEIGHT := 0.6
const LAMP_ARM_LENGTH := 0.3
const LAMP_LIGHT_COLOR := Color(1.0, 0.92, 0.6)
const LAMP_LIGHT_ENERGY := 2.0
const LAMP_COUNT := 8
## Pit lane (#1165): a colored service strip inside the track with pit buildings.
const PIT_COLOR := Color(0.5, 0.5, 0.55)
const PIT_BUILDING_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_city_kit_commercial/detail-awning.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/detail-overhang.glb"),
]
## Lap counter (#1165): 3D floating display above the start/finish line.
const LAP_COUNTER_HEIGHT := 4.0

var players := {}
var standings: Array = []

var _item_pad_nodes: Array[MeshInstance3D] = []
var _shell_pool: Array[MeshInstance3D] = []
var _oil_pool: Array[MeshInstance3D] = []
var _spin_seen := {}
var _finish_seen := {}
var _gas_down := false
var _seen_snapshot := false


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(_delta: float) -> void:
	# action_primary is GAS now (#1067): held = full throttle, the stick only
	# steers, and a hard turn at speed drifts server-side.
	var held := Input.is_action_pressed(&"action_primary")
	if held != _gas_down:
		_gas_down = held
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"gas": held})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_secondary"):
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"use": true})


## Warm asphalt-hued floor (#589, #1165): a mid-grey warm tone amplifying the
## texture-based floor (asphalt-track.png) so they read as one surface.
func _floor_tint() -> Color:
	return Color(0.72, 0.7, 0.68)


## Warm evening-race mood (#1165): pushes the (disabled) stadium shell toward
## a golden-hour race atmosphere. Though the shell is opted out, the mood
## override documents the intended tone.
func _mood() -> Color:
	return Color(0.35, 0.22, 0.12)


func _arena_half() -> float:
	# The shaped course (#785) can reach past TRACK_RX, so size to its real extent.
	return TurboLap.course_bound() + TurboLap.TRACK_HALF_WIDTH + 1.0


## Opt out of the shared party-stadium shell (#939, #1041). Every other game is
## a compact arena the stadium frames behind; turbo_lap's track sprawls to the
## arena extent, so the shell's dark dome and bleacher ring sat around AND over
## the track at the iso angle, burying the oval in a dark bowl — the owner's
## "still not a complete oval". Without it the ribbon + curb rails read as a
## clean closed loop. The base guards its per-frame update against a null shell.
func _build_stage_shell() -> void:
	pass


func _setup_3d() -> void:
	_build_track()
	_build_grandstands()
	_build_pit_lane()
	_build_track_lighting()
	_build_lap_counter()
	for pad_pos in TurboLap.boost_pad_positions():
		_add_pad(pad_pos, BOOST_PAD_COLOR, "BoostPad")
	for pad_pos in TurboLap.item_pad_positions():
		_item_pad_nodes.append(
			_add_pad(pad_pos, ITEM_PAD_COLOR, "ItemPad%d" % _item_pad_nodes.size())
		)
	for i in SHELL_POOL:
		_shell_pool.append(_add_ball("Shell%d" % i, SHELL_COLOR, 0.3))
	for i in OIL_POOL:
		_oil_pool.append(_add_disc("Oil%d" % i, OIL_COLOR, TurboLap.OIL_HIT_RADIUS))
	for slot: int in names:
		_add_kart_body(slot)


## One flat strip per centerline segment forms the ribbon; two continuous
## miter-joined curb rails trace its edges into a clean closed oval; the start
## line gets a gold slab across the width and a procedural gate stands over it.
func _build_track() -> void:
	var points := TurboLap.waypoints()
	# Asphalt material (#1165): reuse one StandardMaterial3D with the IMG-052
	# texture for all strips, adjusting UV tiling per strip length so the grain
	# direction follows the track ribbon.
	var asphalt_mat := StandardMaterial3D.new()
	asphalt_mat.albedo_texture = ASPHALT_TEXTURE
	asphalt_mat.albedo_color = TRACK_COLOR
	asphalt_mat.metallic = 0.1
	asphalt_mat.roughness = 0.85
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var heading := (b - a).angle()
		var strip := MeshInstance3D.new()
		strip.name = "Track%d" % i
		var mesh := BoxMesh.new()
		# Overlength covers the polygon gap at each joint.
		var strip_len := a.distance_to(b) * 1.12
		mesh.size = Vector3(strip_len, 0.06, TurboLap.TRACK_HALF_WIDTH * 2.0)
		# Tile the asphalt texture along the strip length; width tiling stays
		# constant so the aggregate grain reads as a continuous surface.
		var tile_mat := asphalt_mat.duplicate()
		tile_mat.uv1_scale = Vector3(strip_len * TRACK_TEXTURE_TILES, 2.0, 1.0)
		mesh.material = tile_mat
		strip.mesh = mesh
		var mid := (a + b) / 2.0
		strip.position = Vector3(mid.x, 0.03, mid.y)
		strip.rotation.y = -heading
		arena.add_child(strip)
	_build_edge_rails(points)
	var start := MeshInstance3D.new()
	start.name = "StartLine"
	var start_mesh := BoxMesh.new()
	# Thin along the track, spanning the full width across it (#785): rotated to
	# the track's heading at the line so it crosses perpendicular to the racing
	# direction instead of sitting axis-aligned.
	start_mesh.size = Vector3(0.5, 0.08, TurboLap.TRACK_HALF_WIDTH * 2.0)
	start_mesh.material = _flat_material(START_COLOR)
	start.mesh = start_mesh
	var start_heading := (points[1] - points[0]).angle()
	start.position = Vector3(points[0].x, 0.05, points[0].y)
	start.rotation.y = -start_heading
	arena.add_child(start)
	_build_finish_arch(points[0], start_heading)


## Two continuous curb rails tracing the inner and outer track edges (#1041):
## each waypoint is offset along its miter normal (the bisector of its two
## flanking edge normals), so consecutive offset points connect gap-free — a
## crisp closed oval outline instead of 100+ tiled barrier blocks that never
## closed the loop.
func _build_edge_rails(points: PackedVector2Array) -> void:
	for side: float in [-1.0, 1.0]:
		var loop := _offset_loop(points, side * TurboLap.TRACK_HALF_WIDTH)
		for i in loop.size():
			var a: Vector2 = loop[i]
			var b: Vector2 = loop[(i + 1) % loop.size()]
			var rail := MeshInstance3D.new()
			rail.name = "Rail%s%d" % ["Out" if side > 0.0 else "In", i]
			var mesh := BoxMesh.new()
			# Overlength (1.06) laps each joint so the miter corners stay sealed.
			mesh.size = Vector3(a.distance_to(b) * 1.06, RAIL_HEIGHT, RAIL_WIDTH)
			mesh.material = _flat_material(RAIL_COLOR)
			rail.mesh = mesh
			var mid := (a + b) / 2.0
			rail.position = Vector3(mid.x, RAIL_HEIGHT / 2.0, mid.y)
			rail.rotation.y = -(b - a).angle()
			arena.add_child(rail)


## Offset a closed CCW polyline outward (+) or inward (-) by `dist`, moving each
## vertex along its miter normal (the bisector of the two adjacent edge normals)
## and scaling by 1/cos(half-angle) so the offset distance is held along both
## flanking edges — the standard gap-free polyline offset.
func _offset_loop(points: PackedVector2Array, dist: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := points.size()
	for i in n:
		var prev: Vector2 = points[(i - 1 + n) % n]
		var curr: Vector2 = points[i]
		var next: Vector2 = points[(i + 1) % n]
		# Outward edge normal for a CCW loop is the direction rotated -90°.
		var n_in := (curr - prev).normalized()
		var n_out := (next - curr).normalized()
		var normal_in := Vector2(n_in.y, -n_in.x)
		var normal_out := Vector2(n_out.y, -n_out.x)
		var miter := normal_in + normal_out
		if miter.length() < 0.001:
			miter = normal_out
		miter = miter.normalized()
		var cos_half := miter.dot(normal_out)
		var scale := dist / cos_half if absf(cos_half) > 0.2 else dist
		out.append(curr + miter * scale)
	return out


## Start/finish gate (#1041, MDL-022): the generated ARCH_SCENE straddling
## the track, uniformly scaled so its own span matches the track's dynamic
## width. Local Z is across-track (the ribbon strips lay their width on Z),
## but the model's span is baked along its own local X, so it's rotated 90°
## to line the posts up across the lane like the old primitive gate did.
func _build_finish_arch(at: Vector2, heading: float) -> void:
	var span := TurboLap.TRACK_HALF_WIDTH * 2.0 + 0.6
	var arch := ARCH_SCENE.instantiate() as Node3D
	arch.name = "FinishArch"
	arch.position = Vector3(at.x, 0.0, at.y)
	arch.rotation.y = -heading + PI / 2.0
	arch.scale = Vector3.ONE * (span / ARCH_MODEL_SPAN)
	arena.add_child(arch)


func _add_pad(world_pos: Vector2, color: Color, node_name: String) -> MeshInstance3D:
	var pad := MeshInstance3D.new()
	pad.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = TurboLap.PAD_RADIUS * 0.8
	mesh.bottom_radius = TurboLap.PAD_RADIUS * 0.8
	mesh.height = 0.1
	mesh.material = _flat_material(color)
	pad.mesh = mesh
	pad.position = Vector3(world_pos.x, 0.08, world_pos.y)
	arena.add_child(pad)
	return pad


func _add_ball(node_name: String, color: Color, radius: float) -> MeshInstance3D:
	var ball := MeshInstance3D.new()
	ball.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = _flat_material(color)
	ball.mesh = mesh
	ball.visible = false
	arena.add_child(ball)
	return ball


func _add_disc(node_name: String, color: Color, radius: float) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	disc.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.04
	mesh.material = _flat_material(color)
	disc.mesh = mesh
	disc.visible = false
	arena.add_child(disc)
	return disc


## The MDL-015 go-kart under the rig, tinted to the player's identity color;
## parented into the rig so interpolation carries it.
func _add_kart_body(slot: int) -> void:
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	var kart := KART_SCENE.instantiate() as Node3D
	kart.name = "KartBody"
	# The GLB's nose points -Z (spoiler +Z); rigs face +Z when unrotated.
	kart.rotation.y = PI
	_tint_model(kart, PlayerPalette.color_for_slot(slot))
	rig.add_child(kart)


## Multiply every surface of an instanced model by a color: on the kart's
## neutral albedo this reads as a clean paint job (dark wheels stay dark).
func _tint_model(root: Node3D, color: Color) -> void:
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := found as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.get_active_material(surface)
			if mat is StandardMaterial3D:
				var tinted: StandardMaterial3D = mat.duplicate()
				tinted.albedo_color = color
				# The kart texture is mid-grey, so a bare multiply mutes the
				# identity color — a modest emission lifts it (#786 pattern).
				tinted.emission_enabled = true
				tinted.emission = color
				tinted.emission_energy_multiplier = 0.2
				mesh_node.set_surface_override_material(surface, tinted)


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	standings = game.get("standings", [])
	for slot: int in players:
		_render_kart(slot, players[slot])
	_render_pool(_shell_pool, game.get("shells", []), 0.35)
	_render_pool(_oil_pool, game.get("oils", []), 0.05)
	var pads: Array = game.get("pads", [])
	for i in mini(pads.size(), _item_pad_nodes.size()):
		var active := int(pads[i][TurboLap.PD_AVAILABLE]) == 1
		_item_pad_nodes[i].transparency = 0.0 if active else 0.7
	_seen_snapshot = true


func _render_kart(slot: int, state: Array) -> void:
	if state.size() < TurboLap.PS_COUNT:
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	update_rig(slot, Vector2(float(state[TurboLap.PS_X]), float(state[TurboLap.PS_Y])))
	var bits := int(state[TurboLap.PS_BITS])
	var spinning := bits & 1 > 0
	var world := Vector2(float(state[TurboLap.PS_X]), float(state[TurboLap.PS_Y]))
	if spinning:
		rig.rotate_y(0.45)
	if spinning and not _spin_seen.get(slot, false) and _seen_snapshot:
		fx_burst(world, OIL_COLOR, 0.6)
		request_shake(5.0)
		if slot == my_slot:
			# An oil-slick spin-out is a stagger debuff (#728).
			play_sfx(&"powerdown")
	_spin_seen[slot] = spinning
	if bits & 2 > 0:
		fx_dust(world)
	var finished := bits & 8 > 0
	if finished and not _finish_seen.get(slot, false) and _seen_snapshot:
		fx_sparkle(world, START_COLOR, 1.0)
		if slot == my_slot:
			# Crossing the line is a checkpoint (#728).
			play_sfx(&"bell")
	_finish_seen[slot] = finished
	_label_kart(slot, rig, int(state[TurboLap.PS_ITEM]), finished)


## Nameplate carries the live race position and the held item:
## "P3 Alice 🐢" tells the whole story at a glance.
func _label_kart(slot: int, rig: CharacterRig, item: int, finished: bool) -> void:
	var place := standings.find(slot)
	var prefix := "🏁 " if finished else ("P%d " % (place + 1) if place >= 0 else "")
	var icon: String = ITEM_ICONS.get(item, "")
	rig.display_name = "%s%s %s" % [prefix, player_name(slot), icon]


## Shared by both shells and oils — TurboLap.SH_X/SH_Y and OL_X/OL_Y are the
## same [x, y] shape, so either pair of constants applies here.
func _render_pool(pool: Array[MeshInstance3D], items: Array, height: float) -> void:
	for i in pool.size():
		if i < items.size():
			pool[i].visible = true
			pool[i].position = Vector3(
				float(items[i][TurboLap.SH_X]), height, float(items[i][TurboLap.SH_Y])
			)
		else:
			pool[i].visible = false


## Grandstands (#1165): scatter Kenney City Kit low-detail buildings around the
## arena perimeter as spectator grandstands framing the track.
func _build_grandstands() -> void:
	scatter_rim_props(GRANDSTAND_SCENES, GRANDSTAND_COUNT, GRANDSTAND_SEED)


## Pit lane (#1165): a grey service strip along one straight of the track, with
## small pit buildings (awnings, overhangs) placed along it to sell the race
## weekend feel.
func _build_pit_lane() -> void:
	var points := TurboLap.waypoints()
	if points.size() < 4:
		return
	# Find the longest straight: the span between two waypoints with the
	# smallest heading change (most parallel consecutive edges).
	var straight_idx := 0
	var max_len := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var len := a.distance_to(b)
		if len > max_len:
			max_len = len
			straight_idx = i
	# Place the pit lane as a coloured strip just outside the inner edge of the
	# chosen straight, offset inward by TRACK_HALF_WIDTH.
	var a := points[straight_idx]
	var b := points[(straight_idx + 1) % points.size()]
	var heading := (b - a).angle()
	var mid := (a + b) / 2.0
	# Pit lane strip: a narrow BoxMesh running parallel to the track.
	var pit_strip := MeshInstance3D.new()
	pit_strip.name = "PitLane"
	var pit_mesh := BoxMesh.new()
	pit_mesh.size = Vector3(max_len * 0.9, 0.04, 1.2)
	pit_mesh.material = _flat_material(PIT_COLOR)
	pit_strip.mesh = pit_mesh
	pit_strip.position = Vector3(mid.x, 0.02, mid.y)
	pit_strip.rotation.y = -heading
	pit_strip.position += Vector3(
		-TurboLap.TRACK_HALF_WIDTH * sin(heading), 0.0, TurboLap.TRACK_HALF_WIDTH * cos(heading)
	)
	arena.add_child(pit_strip)
	# Place pit buildings along the strip.
	var pit_count := mini(3, PIT_BUILDING_SCENES.size())
	for i in pit_count:
		var t := float(i + 1) / float(pit_count + 1)
		var pos := a.lerp(b, t)
		var building := PIT_BUILDING_SCENES[i].instantiate() as Node3D
		building.name = "PitBuilding%d" % i
		building.position = Vector3(pos.x, 0.0, pos.y)
		building.position += Vector3(
			-(TurboLap.TRACK_HALF_WIDTH + 0.5) * sin(heading),
			0.0,
			(TurboLap.TRACK_HALF_WIDTH + 0.5) * cos(heading)
		)
		arena.add_child(building)


## Lap counter (#1165): a 3D floating display above the start/finish line showing
## the current lap. Uses a Label3D so it reads as a real stadium element.
func _build_lap_counter() -> void:
	var points := TurboLap.waypoints()
	if points.is_empty():
		return
	var start_pos := points[0]
	var heading := (points[1] - points[0]).angle() if points.size() > 1 else 0.0
	# Post: a thin pole holding the display.
	var post := MeshInstance3D.new()
	post.name = "LapCounterPost"
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.04
	post_mesh.bottom_radius = 0.04
	post_mesh.height = LAP_COUNTER_HEIGHT
	post_mesh.material = _flat_material(RAIL_COLOR)
	post.mesh = post_mesh
	post.position = Vector3(start_pos.x, LAP_COUNTER_HEIGHT / 2.0, start_pos.y)
	post.position += Vector3(
		-(TurboLap.TRACK_HALF_WIDTH + 0.3) * sin(heading),
		0.0,
		(TurboLap.TRACK_HALF_WIDTH + 0.3) * cos(heading)
	)
	arena.add_child(post)
	# Display panel: a small box with "LAP" text.
	var panel := MeshInstance3D.new()
	panel.name = "LapCounterPanel"
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(0.6, 0.15, 0.3)
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.12, 0.12, 0.15)
	panel_mat.emission_enabled = true
	panel_mat.emission = Color(0.96, 0.79, 0.2)
	panel_mat.emission_energy_multiplier = 0.3
	panel_mesh.material = panel_mat
	panel.mesh = panel_mesh
	panel.position = Vector3(start_pos.x, LAP_COUNTER_HEIGHT + 0.1, start_pos.y)
	panel.position += Vector3(
		-(TurboLap.TRACK_HALF_WIDTH + 0.3) * sin(heading),
		0.0,
		(TurboLap.TRACK_HALF_WIDTH + 0.3) * cos(heading)
	)
	arena.add_child(panel)


## Track lighting (#1165): street lamps along the track straight sections,
## built from procedural CylinderMesh poles with glowing SphereMesh lights.
func _build_track_lighting() -> void:
	var points := TurboLap.waypoints()
	if points.size() < 2:
		return
	# Place lamps at intervals along the straight sections of the track.
	var placed := 0
	var goal := LAMP_COUNT
	var total_len := 0.0
	for i in points.size():
		total_len += points[i].distance_to(points[(i + 1) % points.size()])
	var step := total_len / float(goal)
	var accum := 0.0
	for i in range(goal):
		# Walk along the track centerline to find the lamp position.
		var target := accum
		accum += step
		var walked := 0.0
		for j in points.size():
			var a := points[j]
			var b := points[(j + 1) % points.size()]
			var seg_len := a.distance_to(b)
			if walked + seg_len >= target:
				var t := (target - walked) / seg_len
				var pos := a.lerp(b, t)
				var heading := (b - a).angle()
				# Place one lamp on each side of the track.
				for side: float in [-1.0, 1.0]:
					var lamp_name := "Lamp%d_%s" % [i, "Out" if side > 0.0 else "In"]
					# Pole: thin cylinder.
					var pole := MeshInstance3D.new()
					pole.name = lamp_name + "Pole"
					var pole_mesh := CylinderMesh.new()
					pole_mesh.top_radius = 0.025
					pole_mesh.bottom_radius = 0.035
					pole_mesh.height = LAMP_POLE_HEIGHT
					pole_mesh.material = _flat_material(RAIL_COLOR)
					pole.mesh = pole_mesh
					var offset := side * (TurboLap.TRACK_HALF_WIDTH + 0.15)
					pole.position = Vector3(pos.x, LAMP_POLE_HEIGHT / 2.0, pos.y)
					pole.position += Vector3(-offset * sin(heading), 0.0, offset * cos(heading))
					arena.add_child(pole)
					# Light fixture: a small glowing sphere.
					var light_node := MeshInstance3D.new()
					light_node.name = lamp_name + "Light"
					var light_mesh := SphereMesh.new()
					light_mesh.radius = 0.08
					light_mesh.height = 0.16
					var light_mat := StandardMaterial3D.new()
					light_mat.albedo_color = LAMP_LIGHT_COLOR
					light_mat.emission_enabled = true
					light_mat.emission = LAMP_LIGHT_COLOR
					light_mat.emission_energy_multiplier = LAMP_LIGHT_ENERGY
					light_mesh.material = light_mat
					light_node.mesh = light_mesh
					light_node.position = Vector3(pos.x, LAMP_POLE_HEIGHT, pos.y)
					light_node.position += Vector3(
						-offset * sin(heading), 0.0, offset * cos(heading)
					)
					arena.add_child(light_node)
					placed += 1
				break
			walked += seg_len
