extends MinigameView3D
## Turbo Lap client view (M14-02): renders the replicated race in the shared
## iso arena — a ribbon track built from the sim's own centerline, glowing
## boost pads, item pads that dim while cooling, box-karts riding under each
## character rig, pooled shells and oil slicks — without simulating anything
## locally. Drift is action_primary (held), the item is action_secondary.

const TRACK_COLOR := Color(0.16, 0.17, 0.21)
const EDGE_COLOR := Color(0.9, 0.9, 0.92)
const START_COLOR := Color(0.96, 0.79, 0.2)
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
var _drift_down := false
var _seen_snapshot := false


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(_delta: float) -> void:
	var held := Input.is_action_pressed(&"action_primary")
	if held != _drift_down:
		_drift_down = held
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"drift": held})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_secondary"):
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"use": true})


## Dark asphalt floor for the race track (#589).
func _floor_tint() -> Color:
	return Color(0.85, 0.86, 0.9)


func _arena_half() -> float:
	return TurboLap.TRACK_RX + TurboLap.TRACK_HALF_WIDTH + 1.0


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


## One flat strip per centerline segment approximates the ellipse ribbon;
## the start line gets a gold slab across the width.
func _build_track() -> void:
	var points := TurboLap.waypoints()
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var strip := MeshInstance3D.new()
		strip.name = "Track%d" % i
		var mesh := BoxMesh.new()
		# Overlength covers the polygon gap at each joint.
		mesh.size = Vector3(a.distance_to(b) * 1.12, 0.06, TurboLap.TRACK_HALF_WIDTH * 2.0)
		mesh.material = _flat_material(TRACK_COLOR)
		strip.mesh = mesh
		var mid := (a + b) / 2.0
		strip.position = Vector3(mid.x, 0.03, mid.y)
		strip.rotation.y = -(b - a).angle()
		arena.add_child(strip)
	var start := MeshInstance3D.new()
	start.name = "StartLine"
	var start_mesh := BoxMesh.new()
	start_mesh.size = Vector3(0.5, 0.08, TurboLap.TRACK_HALF_WIDTH * 2.0)
	start_mesh.material = _flat_material(START_COLOR)
	start.mesh = start_mesh
	start.position = Vector3(points[0].x, 0.05, points[0].y)
	arena.add_child(start)


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


## A low colored box under the rig, so every racer visibly rides a kart in
## their identity color; parented into the rig so interpolation carries it.
func _add_kart_body(slot: int) -> void:
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	var kart := MeshInstance3D.new()
	kart.name = "KartBody"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.9, 0.3, 1.3)
	mesh.material = _flat_material(PlayerPalette.color_for_slot(slot))
	kart.mesh = mesh
	kart.position = Vector3(0.0, 0.15, 0.0)
	rig.add_child(kart)


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
		var active := int(pads[i][2]) == 1
		_item_pad_nodes[i].transparency = 0.0 if active else 0.7
	_seen_snapshot = true


func _render_kart(slot: int, state: Array) -> void:
	if state.size() < 5:
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	update_rig(slot, Vector2(float(state[0]), float(state[1])))
	var bits := int(state[4])
	var spinning := bits & 1 > 0
	var world := Vector2(float(state[0]), float(state[1]))
	if spinning:
		rig.rotate_y(0.45)
	if spinning and not _spin_seen.get(slot, false) and _seen_snapshot:
		fx_burst(world, OIL_COLOR, 0.6)
		request_shake(5.0)
		if slot == my_slot:
			play_sfx(&"error")
	_spin_seen[slot] = spinning
	if bits & 2 > 0:
		fx_dust(world)
	var finished := bits & 8 > 0
	if finished and not _finish_seen.get(slot, false) and _seen_snapshot:
		fx_sparkle(world, START_COLOR, 1.0)
		if slot == my_slot:
			play_sfx(&"confirm")
	_finish_seen[slot] = finished
	_label_kart(slot, rig, int(state[3]), finished)


## Nameplate carries the live race position and the held item:
## "P3 Alice 🐢" tells the whole story at a glance.
func _label_kart(slot: int, rig: CharacterRig, item: int, finished: bool) -> void:
	var place := standings.find(slot)
	var prefix := "🏁 " if finished else ("P%d " % (place + 1) if place >= 0 else "")
	var icon: String = ITEM_ICONS.get(item, "")
	rig.display_name = "%s%s %s" % [prefix, player_name(slot), icon]


func _render_pool(pool: Array[MeshInstance3D], items: Array, height: float) -> void:
	for i in pool.size():
		if i < items.size():
			pool[i].visible = true
			pool[i].position = Vector3(float(items[i][0]), height, float(items[i][1]))
		else:
			pool[i].visible = false
