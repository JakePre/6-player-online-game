extends MinigameView3D
## Faulty Wiring client view (M10-16): a ring of circuit nodes on a darkened
## arena. Each node glows from dead-red toward live-green as the crew fill it,
## snapping bright when fixed and bursting dark again when the saboteur cuts it.
## A banner tells THIS client alone whether they are CREW or the SABOTEUR (from
## the private snapshot, #254), above a "lit X / N" tally. Renders the shared
## get_snapshot() only — the saboteur's identity never rides the public wire.

const DARK_COLOR := Color(0.03, 0.04, 0.08, 0.72)
const BROKEN_COLOR := Color(0.85, 0.2, 0.15)
const FIXED_COLOR := Color(0.3, 0.95, 0.4)
const NODE_HEIGHT := 1.1
const NODE_RADIUS := 0.42

var players := {}
var wires: Array = []
var fixed := 0
var total := 0

var _wire_nodes: Array[MeshInstance3D] = []
var _wire_materials: Array[StandardMaterial3D] = []
var _wire_lit_seen: Array[bool] = []
var _role_label: Label
var _tally_label: Label


func _arena_half() -> float:
	return FaultyWiring.ARENA_HALF


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	# Only the saboteur can act on it server-side, but sending is harmless.
	if event.is_action_pressed(&"action_primary"):
		NetManager.send_match_input({"act": true})


func _setup_3d() -> void:
	_build_darkness()
	_build_labels()


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	wires = game.get("wires", [])
	fixed = int(game.get("fixed", 0))
	total = int(game.get("total", 0))
	_sync_wires()
	_update_players()
	_update_labels()


## A dim unshaded plane over the floor sells "in the dark" and lets the emissive
## wire nodes read as the only light sources.
func _build_darkness() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * _arena_half() * 2.5
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = DARK_COLOR
	mesh.material = material
	var dark := MeshInstance3D.new()
	dark.name = "Darkness"
	dark.mesh = mesh
	dark.position.y = 0.02
	arena.add_child(dark)


func _build_labels() -> void:
	_role_label = Label.new()
	_role_label.name = "RoleLabel"
	_role_label.add_theme_font_size_override(&"font_size", 34)
	_role_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_role_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role_label.position.y = 16.0
	add_child(_role_label)

	_tally_label = Label.new()
	_tally_label.name = "TallyLabel"
	_tally_label.add_theme_font_size_override(&"font_size", 26)
	_tally_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tally_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tally_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tally_label.position.y = 58.0
	add_child(_tally_label)


## Wire nodes are built lazily from the first snapshot (their count/positions are
## authoritative), then just recolored each frame; a fresh fix sparkles and a cut
## bursts, seeded off the lit-state flip.
func _sync_wires() -> void:
	for w in wires.size():
		var entry: Array = wires[w]
		if w >= _wire_nodes.size():
			_build_wire(w)
		var world := Vector2(float(entry[0]), float(entry[1]))
		_wire_nodes[w].position = to_arena(world, NODE_HEIGHT * 0.5)
		var lit := int(entry[2]) == 1
		var progress := float(entry[3])
		var color := BROKEN_COLOR.lerp(FIXED_COLOR, 1.0 if lit else progress)
		var material := _wire_materials[w]
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = 1.8 if lit else 0.4 + progress
		if _wire_lit_seen[w] != lit:
			if lit:
				fx_sparkle(world, FIXED_COLOR, NODE_HEIGHT)
			else:
				fx_burst(world, BROKEN_COLOR, NODE_HEIGHT)
			_wire_lit_seen[w] = lit


func _build_wire(w: int) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = NODE_RADIUS
	mesh.bottom_radius = NODE_RADIUS
	mesh.height = NODE_HEIGHT
	var material := StandardMaterial3D.new()
	material.emission_enabled = true
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "Wire%d" % w
	node.mesh = mesh
	arena.add_child(node)
	_wire_nodes.append(node)
	_wire_materials.append(material)
	_wire_lit_seen.append(false)


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		update_rig(slot, Vector2(float(state[0]), float(state[1])))


func _update_labels() -> void:
	if _role_label == null:
		return
	var is_saboteur := bool(private_state.get("saboteur", false))
	_role_label.text = "SABOTEUR — cut the wires" if is_saboteur else "CREW — repair the circuit"
	_role_label.add_theme_color_override(
		&"font_color", BROKEN_COLOR if is_saboteur else FIXED_COLOR
	)
	_tally_label.text = "Lit %d / %d" % [fixed, total]
