extends MinigameView3D
## Faulty Wiring client view (M10-16): the repair race rendered in a dark
## arena — the base light rig is dimmed, each player carries a small lamp and
## each node glows from red (broken) to green (repaired). A cut sparks its
## node globally and unattributed; only the local saboteur sees their own
## role and cut-cooldown, read from private_state (#254). A REVEAL banner
## names the saboteur and the outcome. Renders get_snapshot() only.

const BROKEN_COLOR := Color(0.9, 0.2, 0.15)
const FIXED_COLOR := Color(0.3, 0.9, 0.4)
const NODE_RADIUS := 0.6
const NODE_HEIGHT := 1.4
const PLAYER_LAMP_RANGE := 6.0
const PLAYER_LAMP_ENERGY := 1.6

var phase: int = FaultyWiring.Phase.WORK
var players := {}
var nodes: Array = []
var saboteur := -1
var outcome := ""

var _node_pylons: Array[MeshInstance3D] = []
var _node_materials: Array[StandardMaterial3D] = []
var _node_lights: Array[OmniLight3D] = []
var _spark_seen: Array[int] = []
var _banner: Label
var _role_label: Label


## Electric cyan floor for the circuit-repair tension (#589).
func _floor_tint() -> Color:
	return Color(0.8, 0.95, 0.98)


func _arena_half() -> float:
	return FaultyWiring.ARENA_HALF


func _process(_delta: float) -> void:
	send_move_intent()
	if Input.is_action_just_pressed(&"action_primary"):
		NetManager.send_match_input({"cut": true})


func _setup_3d() -> void:
	_darken()
	_build_nodes()
	_attach_player_lamps()
	_build_labels()


func _render_3d(game: Dictionary) -> void:
	phase = int(game.get("phase", FaultyWiring.Phase.WORK))
	players = game.get("players", {})
	nodes = game.get("nodes", [])
	saboteur = int(game.get("saboteur", -1))
	outcome = String(game.get("outcome", ""))
	_update_players()
	_update_nodes()
	_update_labels()


## Kill the base's daylight rig so the arena reads as a dark room; the node
## and player lamps become the only real light sources. Opts back into a
## solid background color (#590 made the base transparent so the drifting
## backdrop shows through by default) — a pitch-black room is the mechanic
## here, not a grey backdrop to replace.
func _darken() -> void:
	(arena.get_node("KeyLight") as DirectionalLight3D).light_energy = 0.12
	(arena.get_node("FillLight") as DirectionalLight3D).light_energy = 0.05
	var world_env := arena.get_node("Environment") as WorldEnvironment
	var environment := world_env.environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.01, 0.01, 0.02)
	environment.ambient_light_color = Color(0.06, 0.07, 0.1)
	environment.ambient_light_energy = 0.4


func _build_nodes() -> void:
	for i in FaultyWiring.NODE_POSITIONS.size():
		var mesh := CylinderMesh.new()
		mesh.top_radius = NODE_RADIUS
		mesh.bottom_radius = NODE_RADIUS
		mesh.height = NODE_HEIGHT
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		mesh.material = material
		var pylon := MeshInstance3D.new()
		pylon.name = "Node%d" % i
		pylon.mesh = mesh
		pylon.position = to_arena(FaultyWiring.NODE_POSITIONS[i], NODE_HEIGHT * 0.5)
		arena.add_child(pylon)
		var light := OmniLight3D.new()
		light.name = "NodeLight%d" % i
		light.omni_range = 5.0
		light.position = to_arena(FaultyWiring.NODE_POSITIONS[i], NODE_HEIGHT)
		arena.add_child(light)
		_node_pylons.append(pylon)
		_node_materials.append(material)
		_node_lights.append(light)
		_spark_seen.append(0)


## A small lamp on every rig so players are visible pools of light moving in
## the dark — childed to the rig so it follows without per-frame bookkeeping.
func _attach_player_lamps() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var lamp := OmniLight3D.new()
		lamp.name = "PlayerLamp"
		lamp.omni_range = PLAYER_LAMP_RANGE
		lamp.light_energy = PLAYER_LAMP_ENERGY
		lamp.light_color = player_color(slot)
		lamp.position = Vector3(0.0, 1.4, 0.0)
		rig.add_child(lamp)


func _build_labels() -> void:
	_banner = Label.new()
	_banner.name = "Banner"
	_banner.add_theme_font_size_override(&"font_size", 40)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position.y = 18.0
	add_child(_banner)

	_role_label = Label.new()
	_role_label.name = "RoleLabel"
	_role_label.add_theme_font_size_override(&"font_size", 26)
	_role_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_role_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Grow upward off the bottom anchor, or long role text runs downward off
	# screen — reported unreadable at the bottom edge (#576).
	_role_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role_label.position.y = -60.0
	add_child(_role_label)


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		if state.size() < 2:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
		var rig := rig_for_slot(slot)
		if rig != null:
			rig.display_name = player_name(slot)


## Each node glows from red to green with its repair value; a fresh spark
## pulse (a cut just landed) throws an unattributed burst — you see the node
## sputter, not the hand that cut it.
func _update_nodes() -> void:
	for i in mini(nodes.size(), _node_pylons.size()):
		var state: Array = nodes[i]
		var progress := float(state[2])
		var color := BROKEN_COLOR.lerp(FIXED_COLOR, progress)
		_node_materials[i].albedo_color = color
		_node_materials[i].emission = color
		_node_materials[i].emission_energy_multiplier = 0.4 + progress * 1.6
		_node_lights[i].light_color = color
		_node_lights[i].light_energy = 0.6 + progress * 2.2
		var pulse := int(state[3])
		if pulse > _spark_seen[i]:
			var at := Vector2(float(state[0]), float(state[1]))
			fx_burst(at, Color(1.0, 0.85, 0.3), NODE_HEIGHT)
			request_shake(5.0)
			play_sfx(&"error")
		_spark_seen[i] = pulse


func _update_labels() -> void:
	if phase == FaultyWiring.Phase.REVEAL:
		var who := player_name(saboteur) if saboteur >= 0 else "?"
		if outcome == "crew":
			_banner.text = "CIRCUIT RESTORED!"
			_banner.add_theme_color_override(&"font_color", FIXED_COLOR)
		else:
			_banner.text = "POWER FAILED — SABOTEUR WINS"
			_banner.add_theme_color_override(&"font_color", BROKEN_COLOR)
		_role_label.text = "The saboteur was %s" % who
		_role_label.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.4))
		return
	_banner.text = "REPAIR THE WIRING"
	_banner.add_theme_color_override(&"font_color", Color(0.85, 0.88, 0.95))
	# Only the saboteur's own client shows the secret prompt (#254).
	if String(private_state.get("role", "")) == "saboteur":
		var cd := float(private_state.get("cut_cd", 0.0))
		if cd > 0.0:
			_role_label.text = "YOU ARE THE SABOTEUR — cut ready in %.1fs" % cd
			_role_label.add_theme_color_override(&"font_color", Color(0.8, 0.5, 0.5))
		else:
			_role_label.text = "YOU ARE THE SABOTEUR — SPACE to cut a wire"
			_role_label.add_theme_color_override(&"font_color", BROKEN_COLOR)
	else:
		_role_label.text = ""
