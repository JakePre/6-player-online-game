extends MinigameView3D
## Faulty Wiring client view (M10-16): the repair race rendered in a dark
## arena — the base light rig is dimmed, each player carries a small lamp and
## each node glows from red (broken) to green (repaired). A cut sparks its
## node globally and unattributed; only the local saboteur sees their own
## role and cut-cooldown, read from private_state (#254). A REVEAL banner
## names the saboteur and the outcome. Renders get_snapshot() only.

## Declarative button input (#947): cut a wire (the saboteur's verb). Was a
## raw Input poll in _process with no null-peer guard — the event-based base
## structurally closes that gap.
const INPUT_ACTIONS := {&"action_primary": "cut"}

const BROKEN_COLOR := Color(0.9, 0.2, 0.15)
const FIXED_COLOR := Color(0.3, 0.9, 0.4)
const NODE_RADIUS := 0.6
const NODE_HEIGHT := 1.4
const PLAYER_LAMP_RANGE := 6.0
const PLAYER_LAMP_ENERGY := 1.6

## The circuit made visible (#802): a central power core with a conduit run out
## to each corner node. Each conduit lies flat near the floor and its energized
## stretch grows from the core outward in proportion to that node's repair value
## — the dark remaining run is the still-broken segment, so "which node needs
## work, and how much" reads spatially instead of only as a pylon color. A cut
## sparks at the fault (the break point where the live run ends). Emission-only
## (no lights), so the wires glow without defeating the dark-room mechanic.
const WIRE_Y := 0.12
const WIRE_THICKNESS := 0.14
const HUB_RADIUS := 0.7
const HUB_HEIGHT := 0.45
const CONDUIT_DARK := Color(0.04, 0.05, 0.08)
## Live-current cyan-green: distinct from the red↔green pylon so the wire's
## *length* (not its hue) carries the progress reading.
const WIRE_LIVE_COLOR := Color(0.3, 0.95, 0.9)
## Metal-deck floor (#1132): industrial diamond-plate under the dark room —
## still barely lit (the dark-room mechanic), but reads as a real floor
## wherever a lamp catches it.
const FLOOR_TEXTURE := preload("res://assets/generated/textures/metal-deck.png")
const FLOOR_TEXTURE_TILES := 6.0
## Per-pylon repair panel (#1132): a small screen readout above each node
## showing its live repair percentage.
const PANEL_COLOR := Color(0.05, 0.06, 0.08)
const PANEL_SIZE := Vector2(0.7, 0.4)
## Rim rubble (#1132): the issue's flagged "no scatter_rim_props()" gap.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_platformer_kit/crate.glb"),
	preload("res://assets/environment/kenney_platformer_kit/barrel.glb"),
]
const RIM_PROP_COUNT := 12
const RIM_PROP_SEED := 0xF00713

var phase: int = FaultyWiring.Phase.WORK
var players := {}
var nodes: Array = []
var saboteur := -1
var outcome := ""

var _node_pylons: Array[MeshInstance3D] = []
var _node_materials: Array[StandardMaterial3D] = []
var _node_lights: Array[OmniLight3D] = []
## Per-pylon repair-percentage panel labels (#1132).
var _node_panel_labels: Array[Label3D] = []
var _spark_seen: Array[int] = []
## Per-node "already fully repaired" flag, for the completion cue (#728).
var _fixed_seen: Array[bool] = []
var _banner: Label
var _role_label: Label
## Wire runs (#802): the bright energized fill per node, plus the fixed
## hub-end / direction / full run-length used to size it and to place the
## fault spark. Indexed like FaultyWiring.NODE_POSITIONS.
var _wire_fills: Array[MeshInstance3D] = []
var _wire_fill_materials: Array[StandardMaterial3D] = []
var _wire_hub: Array[Vector3] = []
var _wire_dir: Array[Vector3] = []
var _wire_len: Array[float] = []


## Electric cyan floor for the circuit-repair tension (#589).
func _floor_tint() -> Color:
	return Color(0.8, 0.95, 0.98)


## Metal-deck floor (#1132): industrial diamond-plate, still dim under the
## dark-room lighting but reads as a real surface wherever a lamp catches it.
func _build_floor() -> void:
	var floor_node := _dresser.build_floor(_floor_tile_scene(), _floor_tint(), _arena_half())
	if floor_node != null:
		var mat := floor_node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_texture = FLOOR_TEXTURE
			mat.uv1_scale = Vector3(FLOOR_TEXTURE_TILES, FLOOR_TEXTURE_TILES, 1.0)


func _arena_half() -> float:
	return FaultyWiring.ARENA_HALF


func _process(_delta: float) -> void:
	send_move_intent()


func _setup_3d() -> void:
	_darken()
	_build_wires()
	_build_nodes()
	_attach_player_lamps()
	_build_labels()
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)


func _render_3d(game: Dictionary) -> void:
	phase = int(game.get("phase", FaultyWiring.Phase.WORK))
	players = game.get("players", {})
	nodes = game.get("nodes", [])
	saboteur = int(game.get("saboteur", -1))
	outcome = String(game.get("outcome", ""))
	_update_players()
	_update_nodes()
	_update_wires()
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
		_fixed_seen.append(false)
		_node_panel_labels.append(_build_node_panel(i))


## A small screen panel above a pylon (#1132) showing its live repair
## percentage — an electrical-panel readout, distinct from the pylon's
## color/light which already read progress at a glance.
func _build_node_panel(index: int) -> Label3D:
	var panel := MeshInstance3D.new()
	panel.name = "Panel%d" % index
	var mesh := BoxMesh.new()
	mesh.size = Vector3(PANEL_SIZE.x, PANEL_SIZE.y, 0.05)
	var material := StandardMaterial3D.new()
	material.albedo_color = PANEL_COLOR
	mesh.material = material
	panel.mesh = mesh
	panel.position = to_arena(FaultyWiring.NODE_POSITIONS[index], NODE_HEIGHT + 0.4)
	arena.add_child(panel)
	var label := Label3D.new()
	label.name = "PanelLabel%d" % index
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0015
	label.font_size = 32
	label.outline_size = 10
	label.modulate = WIRE_LIVE_COLOR
	label.text = "0%"
	label.position = to_arena(FaultyWiring.NODE_POSITIONS[index], NODE_HEIGHT + 0.41)
	arena.add_child(label)
	return label


## The central power core plus a dark base conduit out to each corner node
## (#802). The base conduit is the physical wire — always visible, so the whole
## circuit's layout reads from the first frame; the bright energized fill that
## grows along it is built here but sized per snapshot in _update_wires.
func _build_wires() -> void:
	var core := MeshInstance3D.new()
	core.name = "PowerCore"
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = HUB_RADIUS
	core_mesh.bottom_radius = HUB_RADIUS * 1.15
	core_mesh.height = HUB_HEIGHT
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = Color(0.1, 0.12, 0.16)
	core_material.metallic = 0.6
	core_material.emission_enabled = true
	core_material.emission = WIRE_LIVE_COLOR
	core_material.emission_energy_multiplier = 0.5
	core_mesh.material = core_material
	core.mesh = core_mesh
	core.position = Vector3(0.0, HUB_HEIGHT * 0.5, 0.0)
	arena.add_child(core)

	var hub := Vector3(0.0, WIRE_Y, 0.0)
	for i in FaultyWiring.NODE_POSITIONS.size():
		var node_point := to_arena(FaultyWiring.NODE_POSITIONS[i], WIRE_Y)
		var run := hub.distance_to(node_point)
		var dir := (node_point - hub) / run
		_wire_hub.append(hub)
		_wire_dir.append(dir)
		_wire_len.append(run)

		# Dark base conduit spanning the whole run: box length along local Z,
		# centered at the midpoint, look_at aims that axis down the run. Sits a
		# hair below the fill so the bright fill never z-fights it.
		var base := MeshInstance3D.new()
		base.name = "Conduit%d" % i
		var base_mesh := BoxMesh.new()
		base_mesh.size = Vector3(WIRE_THICKNESS, WIRE_THICKNESS, run)
		var base_material := StandardMaterial3D.new()
		base_material.albedo_color = CONDUIT_DARK
		base_material.metallic = 0.4
		base_mesh.material = base_material
		base.mesh = base_mesh
		arena.add_child(base)
		base.position = (hub + node_point) * 0.5 - Vector3(0.0, 0.02, 0.0)
		base.look_at(node_point, Vector3.UP)

		# Energized fill: a unit-length box (scaled along Z per snapshot) with a
		# bright emissive material. Oriented once here; only its scale/position
		# move as the repair value changes.
		var fill := MeshInstance3D.new()
		fill.name = "WireFill%d" % i
		var fill_mesh := BoxMesh.new()
		fill_mesh.size = Vector3(WIRE_THICKNESS * 1.3, WIRE_THICKNESS * 1.3, 1.0)
		var fill_material := StandardMaterial3D.new()
		fill_material.albedo_color = WIRE_LIVE_COLOR
		fill_material.emission_enabled = true
		fill_material.emission = WIRE_LIVE_COLOR
		fill_material.emission_energy_multiplier = 1.4
		fill_mesh.material = fill_material
		fill.mesh = fill_mesh
		fill.visible = false
		arena.add_child(fill)
		fill.position = hub
		fill.look_at(node_point, Vector3.UP)
		_wire_fills.append(fill)
		_wire_fill_materials.append(fill_material)


## Grows each wire's bright energized run from the core to a length proportional
## to its node's repair value (#802): a fully repaired wire reaches the node, a
## broken one is a short stub — so the still-dark remainder is the work left.
func _update_wires() -> void:
	for i in mini(nodes.size(), _wire_fills.size()):
		var progress := clampf(float((nodes[i] as Array)[FaultyWiring.ND_VALUE]), 0.0, 1.0)
		var fill_len := progress * _wire_len[i]
		var fill := _wire_fills[i]
		fill.visible = fill_len > 0.03
		if not fill.visible:
			continue
		# Anchored at the core: centered half the live length down the run, and
		# scaled to that length (the box is unit-length along Z). Rotation set at
		# build stays put — only position/scale track the value.
		fill.position = _wire_hub[i] + _wire_dir[i] * (fill_len * 0.5)
		fill.scale = Vector3(1.0, 1.0, fill_len)
		_wire_fill_materials[i].emission_energy_multiplier = 1.2 + 0.5 * progress


## The world-space fault point for node `i`: the tip of its energized run, i.e.
## where the live wire is severed. Cuts spark here (#802) instead of at the
## pylon, so the break reads as a break in the wire itself.
func _fault_point(i: int, progress: float) -> Vector2:
	var tip := _wire_hub[i] + _wire_dir[i] * (clampf(progress, 0.0, 1.0) * _wire_len[i])
	return Vector2(tip.x, tip.z)


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
	_banner = make_status_label(&"Banner")
	# The secret-role prompt is exactly what make_banner exists for (#258/#576):
	# bottom-center, grows upward, never hides under the emote band.
	_role_label = make_banner(&"RoleLabel")


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		if state.size() < FaultyWiring.PS_COUNT:
			continue
		update_rig(slot, Vector2(state[FaultyWiring.PS_X], state[FaultyWiring.PS_Y]))
		var rig := rig_for_slot(slot)
		if rig != null:
			rig.display_name = player_name(slot)


## Each node glows from red to green with its repair value; a fresh spark
## pulse (a cut just landed) throws an unattributed burst — you see the node
## sputter, not the hand that cut it.
func _update_nodes() -> void:
	for i in mini(nodes.size(), _node_pylons.size()):
		var state: Array = nodes[i]
		var progress := float(state[FaultyWiring.ND_VALUE])
		_node_panel_labels[i].text = "%d%%" % int(round(progress * 100.0))
		var color := BROKEN_COLOR.lerp(FIXED_COLOR, progress)
		_node_materials[i].albedo_color = color
		_node_materials[i].emission = color
		_node_materials[i].emission_energy_multiplier = 0.4 + progress * 1.6
		_node_lights[i].light_color = color
		_node_lights[i].light_energy = 0.6 + progress * 2.2
		var pulse := int(state[FaultyWiring.ND_SPARK])
		if pulse > _spark_seen[i]:
			# Spark at the break in the wire (the tip of the live run), not at the
			# pylon — the cut reads as the circuit being severed (#802).
			var at := _fault_point(i, progress)
			fx_burst(at, Color(1.0, 0.85, 0.3), WIRE_Y + 0.2)
			request_shake(5.0)
			# `zap` (#728, docs/AUDIO_GUIDE.md) names "live wire" as its own
			# use case, replacing the generic UI `error`.
			play_sfx(&"zap")
		_spark_seen[i] = pulse
		var fixed := progress >= 1.0
		if fixed and not _fixed_seen[i]:
			play_sfx(&"bell")
		_fixed_seen[i] = fixed


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
		_role_label.add_theme_color_override(&"font_color", PartyTheme.ACCENT_BRIGHT)
		return
	_banner.text = "REPAIR THE WIRING"
	_banner.add_theme_color_override(&"font_color", PartyTheme.TEXT)
	# Only the saboteur's own client shows the secret prompt (#254).
	if String(private_state.get("role", "")) == "saboteur":
		var cd := float(private_state.get("cut_cd", 0.0))
		if cd > 0.0:
			_role_label.text = "YOU ARE THE SABOTEUR — cut ready in %.1fs" % cd
			_role_label.add_theme_color_override(&"font_color", PartyTheme.DANGER.darkened(0.2))
		else:
			_role_label.text = "YOU ARE THE SABOTEUR — SPACE to cut a wire"
			_role_label.add_theme_color_override(&"font_color", BROKEN_COLOR)
	else:
		_role_label.text = ""
