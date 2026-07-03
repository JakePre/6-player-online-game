extends MinigameView3D
## King of the Hill client view (M8-04): renders the replicated arena in the
## shared 2.5D iso-arena (M8-01, MinigameView3D) — players as CharacterRig
## instances (position/facing/walk-idle from the snapshot, points on the
## nameplate), the shrinking scoring zone as a translucent gold disc on the
## floor. Presentation-tier swap only: state storage and the render contract
## are unchanged from the 2D pass (M4-01).

const ZONE_COLOR := Color(0.96, 0.79, 0.2, 0.35)
## Unit-radius disc; the node's X/Z scale is the zone radius from the snapshot.
const ZONE_DISC_HEIGHT := 0.04

## Latest replicated state, straight from KingOfTheHill.get_snapshot().
var players := {}
var zone: Array = []

var _zone_node: MeshInstance3D


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _arena_half() -> float:
	return KingOfTheHill.ARENA_HALF


func _setup_3d() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = ZONE_DISC_HEIGHT
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = ZONE_COLOR
	material.emission_enabled = true
	material.emission = Color(ZONE_COLOR, 1.0)
	material.emission_energy_multiplier = 0.3
	mesh.material = material
	_zone_node = MeshInstance3D.new()
	_zone_node.name = "Zone"
	_zone_node.mesh = mesh
	_zone_node.visible = false
	arena.add_child(_zone_node)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	zone = game.get("zone", [])
	_update_players()
	_update_zone()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
		rig.display_name = "%s  %d" % [player_name(slot), int(state[2])]


func _update_zone() -> void:
	_zone_node.visible = zone.size() == 3
	if not _zone_node.visible:
		return
	_zone_node.position = to_arena(Vector2(zone[0], zone[1]), ZONE_DISC_HEIGHT / 2.0)
	# The sim never shrinks below ZONE_MIN_RADIUS; the floor only guards a
	# malformed snapshot from producing a degenerate (zero-scale) basis.
	var radius := maxf(float(zone[2]), 0.001)
	_zone_node.scale = Vector3(radius, 1.0, radius)
