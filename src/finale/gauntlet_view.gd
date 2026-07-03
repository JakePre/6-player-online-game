extends MinigameView3D
## Finale Gauntlet client view (M8-12): renders the shrinking platform,
## telegraphed hazard discs, and players in the shared 2.5D iso-arena
## (M8-01). New build — the Gauntlet sim (M5-02) had server logic only.
## Renders Gauntlet.get_snapshot() untouched: {radius, players:
## {slot: [x, y, lives, respawn_left]}, hazards: [[x, y, r, warn_left]]}.

const PLATFORM_COLOR := Color(0.45, 0.43, 0.4)
const PLATFORM_THICKNESS := 0.4
const HAZARD_COLOR := Color(0.9, 0.25, 0.2, 0.45)
## Telegraphs darken toward detonation.
const HAZARD_ARMED_COLOR := Color(0.7, 0.1, 0.05, 0.7)

## Latest replicated state, straight from Gauntlet.get_snapshot().
var radius := Gauntlet.START_RADIUS
var players := {}
var hazards: Array = []

var _platform: MeshInstance3D
var _platform_mesh: CylinderMesh
var _hazard_nodes: Array[MeshInstance3D] = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	# Sabotage tokens / grudge hazards aim at the arena center for now; the
	# targeting UI belongs to the finale HUD pass.
	if event.is_action_pressed(&"action_secondary"):
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"sabotage": [0.0, 0.0]})


func _arena_half() -> float:
	return Gauntlet.START_RADIUS + 2.0


func _setup_3d() -> void:
	_platform_mesh = CylinderMesh.new()
	_platform_mesh.height = PLATFORM_THICKNESS
	_platform_mesh.top_radius = radius
	_platform_mesh.bottom_radius = radius
	var material := StandardMaterial3D.new()
	material.albedo_color = PLATFORM_COLOR
	_platform_mesh.material = material
	_platform = MeshInstance3D.new()
	_platform.name = "Platform"
	_platform.mesh = _platform_mesh
	_platform.position = Vector3(0.0, PLATFORM_THICKNESS / 2.0, 0.0)
	arena.add_child(_platform)


func _render_3d(game: Dictionary) -> void:
	radius = float(game.get("radius", Gauntlet.START_RADIUS))
	players = game.get("players", {})
	hazards = game.get("hazards", [])
	_platform_mesh.top_radius = radius
	_platform_mesh.bottom_radius = radius
	_update_players()
	_update_hazards()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var lives := int(state[2])
		var respawning := float(state[3]) > 0.0
		rig.visible = lives > 0 and not respawning
		if not rig.visible:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
		rig.position.y = PLATFORM_THICKNESS
		rig.display_name = "%s %s" % [player_name(slot), "♥".repeat(lives)]


func _update_hazards() -> void:
	for node in _hazard_nodes:
		node.queue_free()
	_hazard_nodes.clear()
	for hazard: Array in hazards:
		var mesh := CylinderMesh.new()
		mesh.top_radius = float(hazard[2])
		mesh.bottom_radius = float(hazard[2])
		mesh.height = 0.05
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var armed := 1.0 - clampf(float(hazard[3]) / Gauntlet.HAZARD_WARN_SEC, 0.0, 1.0)
		material.albedo_color = HAZARD_COLOR.lerp(HAZARD_ARMED_COLOR, armed)
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = to_arena(
			Vector2(float(hazard[0]), float(hazard[1])), PLATFORM_THICKNESS + 0.03
		)
		arena.add_child(node)
		_hazard_nodes.append(node)
