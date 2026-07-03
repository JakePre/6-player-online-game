extends MinigameView3D
## Bomb Courier client view (M10-15, on the M8-01 MinigameView3D tier):
## packages are id-keyed crates whose glow reddens as the fuse burns down;
## the pile, delivery depot, and defuse pad are colored floor rings. A
## carried package floats over its courier with a fuse label. Dash lunges
## play the interact pose, detonations flinch + shake the local courier.

const PILE_COLOR := Color(0.6, 0.55, 0.35)
const DEPOT_COLOR := Color(0.4, 0.85, 0.45)
const DEFUSE_COLOR := Color(0.35, 0.6, 0.95)
const CRATE_SIZE := 0.7
const CARRIED_HEIGHT := 2.6
## Fuse color lerps SAFE -> HOT as it burns from FUSE_MAX to 0.
const SAFE_COLOR := Color(0.9, 0.85, 0.4)
const HOT_COLOR := Color(0.95, 0.2, 0.15)

var players := {}
var pile: Array = []

var _crates := {}  # id (int) -> MeshInstance3D
var _carried := {}  # slot (int) -> {mesh, label}
var _staggered := {}  # slot (int) -> bool
var _my_score := 0
var _score_label: Label


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"action_primary"):
		var dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		NetManager.send_match_input({"mx": dir.x, "my": dir.y, "dash": true})


func _arena_half() -> float:
	return BombCourier.ARENA_HALF


func _setup_3d() -> void:
	_build_zone("Pile", BombCourier.PILE_POS, PILE_COLOR)
	_build_zone("Depot", BombCourier.DEPOT_POS, DEPOT_COLOR)
	_build_zone("Defuse", BombCourier.DEFUSE_POS, DEFUSE_COLOR)
	_score_label = Label.new()
	_score_label.name = "HintLabel"
	_score_label.add_theme_font_size_override(&"font_size", 22)
	_score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score_label.position.y = 20.0
	_score_label.text = "Pile → Depot before it blows!"
	add_child(_score_label)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	pile = game.get("pile", [])
	_update_players()
	_update_pile()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
		var fuse := float(state[3])
		var staggered := int(state[4]) == 1
		var caption := "%s  %d" % [player_name(slot), int(state[2])]
		if slot == my_slot:
			if staggered and not _staggered.get(slot, false):
				play_sfx(&"error")
				request_shake(7.0)
			elif int(state[2]) > _my_score:
				play_sfx(&"coin")
			_my_score = int(state[2])
		if staggered and rig.current_action() != &"hit":
			rig.play(&"hit")
		_staggered[slot] = staggered
		rig.display_name = caption
		_update_carried(slot, fuse)


func _update_carried(slot: int, fuse: float) -> void:
	var entry: Dictionary = _carried.get(slot, {})
	var holding := fuse >= 0.0
	if holding and entry.is_empty():
		entry = _build_carried(slot)
		_carried[slot] = entry
	if entry.is_empty():
		return
	var mesh: MeshInstance3D = entry.mesh
	var label: Label3D = entry.label
	mesh.visible = holding
	label.visible = holding
	if not holding:
		return
	var rig := rig_for_slot(slot)
	if rig != null:
		mesh.position = rig.position + Vector3(0.0, CARRIED_HEIGHT, 0.0)
		label.position = rig.position + Vector3(0.0, CARRIED_HEIGHT + 0.7, 0.0)
	_tint_fuse(mesh, fuse)
	label.text = "%.1f" % maxf(fuse, 0.0)


func _update_pile() -> void:
	var seen := {}
	for entry: Array in pile:
		var id := int(entry[0])
		seen[id] = true
		var crate: MeshInstance3D = _crates.get(id)
		if crate == null:
			crate = _build_crate(id)
		crate.position = to_arena(Vector2(float(entry[1]), float(entry[2])), CRATE_SIZE * 0.5)
		_tint_fuse(crate, float(entry[3]))
	for id: int in _crates.keys():
		if not seen.has(id):
			(_crates[id] as MeshInstance3D).queue_free()
			_crates.erase(id)


func _tint_fuse(mesh: MeshInstance3D, fuse: float) -> void:
	var t := clampf(fuse / BombCourier.FUSE_MAX, 0.0, 1.0)
	var color := HOT_COLOR.lerp(SAFE_COLOR, t)
	var material := mesh.mesh.surface_get_material(0) as StandardMaterial3D
	material.albedo_color = color
	material.emission = color


func _build_crate(id: int) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * CRATE_SIZE
	var material := StandardMaterial3D.new()
	material.emission_enabled = true
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "Crate%d" % id
	node.mesh = mesh
	arena.add_child(node)
	_crates[id] = node
	return node


func _build_carried(slot: int) -> Dictionary:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * CRATE_SIZE
	var material := StandardMaterial3D.new()
	material.emission_enabled = true
	mesh.material = material
	var crate := MeshInstance3D.new()
	crate.name = "Carried%d" % slot
	crate.mesh = mesh
	arena.add_child(crate)
	var label := Label3D.new()
	label.name = "Fuse%d" % slot
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48
	arena.add_child(label)
	return {"mesh": crate, "label": label}


func _build_zone(node_name: String, pos: Vector2, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = BombCourier.ZONE_RADIUS
	mesh.bottom_radius = BombCourier.ZONE_RADIUS
	mesh.height = 0.08
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.4
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = to_arena(pos, 0.04)
	arena.add_child(node)
