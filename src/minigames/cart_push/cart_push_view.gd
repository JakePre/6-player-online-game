extends MinigameView3D
## Cart Push client view (recreated per #175, on the M8-01 MinigameView3D
## tier): the shared cart rides a center rail between two team-colored
## depots; rumble strips band the track, ore pickups glint off-rail, and a
## carried ore floats over its carrier. Shove windups play the interact pose
## (the telegraph), staggered players flinch. A Control-layer banner tells
## the local player which way to push.

const TEAM_COLORS: Array[Color] = [Color(0.9, 0.5, 0.2), Color(0.35, 0.6, 0.95)]
const RAIL_COLOR := Color(0.35, 0.3, 0.25)
const RUMBLE_COLOR := Color(0.9, 0.65, 0.15)
const ORE_COLOR := Color(1.0, 0.82, 0.25)
const CART_SIZE := Vector3(1.8, 1.0, 1.2)
const ORE_RADIUS := 0.3
const CARRIED_ORE_HEIGHT := 2.6

## Latest replicated state, straight from CartPush.get_snapshot().
var players := {}
var teams: Array = []
var cart_x := 0.0
var bonus: Array = [0, 0]

var _cart: Node3D
var _ore_nodes := {}  # id (int) -> MeshInstance3D
var _carried := {}  # slot (int) -> MeshInstance3D floating over the carrier
var _push_label: Label
var _bonus_label: Label
var _my_team := -1


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"action_primary"):
		NetManager.send_match_input({"shove": true})


func _arena_half() -> float:
	return CartPush.ARENA_HALF


func _setup_3d() -> void:
	_build_rail()
	_build_depots()
	_build_rumble_strips()
	_build_cart()
	_build_labels()


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	teams = game.get("teams", [])
	cart_x = float(game.get("cart", 0.0))
	bonus = game.get("bonus", [0, 0])
	_cart.position = to_arena(Vector2(cart_x, 0.0), CART_SIZE.y * 0.5)
	_update_players()
	_update_ores(game.get("ores", []))
	_update_labels()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
		var flags := int(state[2])
		var caption := player_name(slot)
		if flags & 1:
			caption += "  [ORE]"
		var desired: StringName = &"idle"
		if flags & 2:
			desired = &"hit"
		elif flags & 4:
			desired = &"interact"  # shove windup telegraph
		if desired != &"idle" and rig.current_action() != desired:
			rig.play(desired)
		rig.display_name = caption
		_update_carried_ore(slot, flags & 1 == 1)


func _update_carried_ore(slot: int, is_carrying: bool) -> void:
	var node: MeshInstance3D = _carried.get(slot)
	if is_carrying and node == null:
		node = _build_ore_mesh("CarriedOre%d" % slot)
		arena.add_child(node)
		_carried[slot] = node
	if node == null:
		return
	node.visible = is_carrying
	if is_carrying:
		var rig := rig_for_slot(slot)
		if rig != null:
			node.position = rig.position + Vector3(0.0, CARRIED_ORE_HEIGHT, 0.0)


func _update_ores(ore_list: Array) -> void:
	var seen := {}
	for entry: Array in ore_list:
		var id := int(entry[0])
		seen[id] = true
		var node: MeshInstance3D = _ore_nodes.get(id)
		if node == null:
			node = _build_ore_mesh("Ore%d" % id)
			arena.add_child(node)
			_ore_nodes[id] = node
		node.position = to_arena(Vector2(float(entry[1]), float(entry[2])), ORE_RADIUS)
	for id: int in _ore_nodes.keys():
		if not seen.has(id):
			(_ore_nodes[id] as MeshInstance3D).queue_free()
			_ore_nodes.erase(id)


func _update_labels() -> void:
	if _my_team == -1 and not teams.is_empty():
		for team_index in teams.size():
			if my_slot in (teams[team_index] as Array):
				_my_team = team_index
	if _my_team != -1:
		_push_label.text = "PUSH THE CART %s" % ("→" if _my_team == 0 else "←")
		_push_label.add_theme_color_override(&"font_color", TEAM_COLORS[_my_team])
	_bonus_label.text = "Ore muscle — orange: +%d   blue: +%d" % [int(bonus[0]), int(bonus[1])]


func _build_rail() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CartPush.TRACK_END * 2.0, 0.06, 0.4)
	var material := StandardMaterial3D.new()
	material.albedo_color = RAIL_COLOR
	mesh.material = material
	var rail := MeshInstance3D.new()
	rail.name = "Rail"
	rail.mesh = mesh
	rail.position = Vector3(0.0, 0.03, 0.0)
	arena.add_child(rail)


func _build_depots() -> void:
	for team_index in 2:
		var mesh := CylinderMesh.new()
		mesh.top_radius = CartPush.DEPOT_RADIUS
		mesh.bottom_radius = CartPush.DEPOT_RADIUS
		mesh.height = 0.08
		var material := StandardMaterial3D.new()
		# The depot you defend wears your color: the cart arriving there
		# means the OTHER team scored, matching the sim's win rule.
		material.albedo_color = TEAM_COLORS[team_index]
		material.emission_enabled = true
		material.emission = TEAM_COLORS[team_index] * 0.4
		mesh.material = material
		var depot := MeshInstance3D.new()
		depot.name = "Depot%d" % team_index
		depot.mesh = mesh
		var x := -CartPush.TRACK_END if team_index == 0 else CartPush.TRACK_END
		depot.position = Vector3(x, 0.04, 0.0)
		arena.add_child(depot)


func _build_rumble_strips() -> void:
	for strip: float in CartPush.RUMBLE_XS:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5, 0.05, 3.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = RUMBLE_COLOR
		material.emission_enabled = true
		material.emission = RUMBLE_COLOR * 0.3
		mesh.material = material
		var node := MeshInstance3D.new()
		node.name = "Rumble%d" % roundi(strip)
		node.mesh = mesh
		node.position = Vector3(strip, 0.05, 0.0)
		arena.add_child(node)


func _build_cart() -> void:
	_cart = Node3D.new()
	_cart.name = "Cart"
	var mesh := BoxMesh.new()
	mesh.size = CART_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.35, 0.28)
	mesh.material = material
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mesh
	_cart.add_child(body)
	var ore := _build_ore_mesh("CartOre")
	ore.position = Vector3(0.0, CART_SIZE.y * 0.7, 0.0)
	_cart.add_child(ore)
	arena.add_child(_cart)


## Builds an unparented gold-ore mesh; callers decide where it hangs.
func _build_ore_mesh(node_name: String) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = ORE_RADIUS
	mesh.height = ORE_RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = ORE_COLOR
	material.emission_enabled = true
	material.emission = ORE_COLOR * 0.5
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	return node


func _build_labels() -> void:
	_push_label = Label.new()
	_push_label.name = "PushLabel"
	_push_label.add_theme_font_size_override(&"font_size", 30)
	_push_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_push_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_push_label.position.y = 16.0
	add_child(_push_label)

	_bonus_label = Label.new()
	_bonus_label.name = "BonusLabel"
	_bonus_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bonus_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bonus_label.position.y = 56.0
	add_child(_bonus_label)
