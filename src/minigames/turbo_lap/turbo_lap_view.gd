extends MinigameView3D
## Turbo Lap client view (M14-02): renders the replicated race in the shared
## iso arena — a ribbon track built from the sim's own centerline, glowing
## boost pads, item pads that dim while cooling, box-karts riding under each
## character rig, pooled shells and oil slicks — without simulating anything
## locally. Gas is action_primary (held, #1067), the item is action_secondary;
## drifting is steering hard at speed.

const TRACK_COLOR := Color(0.16, 0.17, 0.21)
const START_COLOR := Color(0.96, 0.79, 0.2)
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


## Dark asphalt floor for the race track (#589).
func _floor_tint() -> Color:
	return Color(0.85, 0.86, 0.9)


func _arena_half() -> float:
	# The shaped course (#785) can reach past TRACK_RX, so size to its real extent.
	return TurboLap.course_bound() + TurboLap.TRACK_HALF_WIDTH + 1.0


func _setup_3d() -> void:
	_build_track()
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
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var heading := (b - a).angle()
		var strip := MeshInstance3D.new()
		strip.name = "Track%d" % i
		var mesh := BoxMesh.new()
		# Overlength covers the polygon gap at each joint.
		mesh.size = Vector3(a.distance_to(b) * 1.12, 0.06, TurboLap.TRACK_HALF_WIDTH * 2.0)
		mesh.material = _flat_material(TRACK_COLOR)
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
