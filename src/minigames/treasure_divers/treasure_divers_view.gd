extends MinigameView3D
## Treasure Divers client view (M10-04): the seabed is the arena floor with
## the sunken coins on it; a translucent water surface floats above, and rigs
## swim on it or dive below it via update_rig's height (interpolated, so the
## plunge reads as motion, not a teleport). Air rides the nameplate as a
## meter; blacking out plays the hit flinch and shakes the screen.

const SURFACE_HEIGHT := 1.2
const WATER_COLOR := Color(0.2, 0.45, 0.8, 0.35)
const COIN_COLOR := Color(0.96, 0.79, 0.2)
const COIN_RADIUS := 0.3
const COIN_HEIGHT := 0.12
const COIN_POOL := 12
const AIR_METER_STEPS := 5

## Latest replicated state, straight from TreasureDivers.get_snapshot().
var players := {}
var treasure: Array = []

var _coin_pool: Array[MeshInstance3D] = []
# slot -> stunned seconds from the previous snapshot, to spot fresh blackouts.
var _stun_seen := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_primary"):
		NetManager.send_match_input({"dive": true})
	elif event.is_action_released(&"action_primary"):
		NetManager.send_match_input({"dive": false})


func _arena_half() -> float:
	return TreasureDivers.ARENA_HALF


func _setup_3d() -> void:
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2.ONE * TreasureDivers.ARENA_HALF * 2.0
	var water_material := StandardMaterial3D.new()
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.albedo_color = WATER_COLOR
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_mesh.material = water_material
	var water := MeshInstance3D.new()
	water.name = "WaterSurface"
	water.mesh = water_mesh
	water.position.y = SURFACE_HEIGHT
	arena.add_child(water)

	var coin_mesh := CylinderMesh.new()
	coin_mesh.top_radius = COIN_RADIUS
	coin_mesh.bottom_radius = COIN_RADIUS
	coin_mesh.height = COIN_HEIGHT
	var coin_material := StandardMaterial3D.new()
	coin_material.albedo_color = COIN_COLOR
	coin_material.metallic = 0.6
	coin_material.roughness = 0.35
	coin_mesh.material = coin_material
	for i in COIN_POOL:
		var node := MeshInstance3D.new()
		node.name = "Treasure%d" % i
		node.mesh = coin_mesh
		node.visible = false
		arena.add_child(node)
		_coin_pool.append(node)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	treasure = game.get("treasure", [])
	_update_players()
	_update_treasure()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var is_diving := int(state[3]) == 1
		update_rig(slot, Vector2(state[0], state[1]), 0.0 if is_diving else SURFACE_HEIGHT)
		rig.display_name = "%s  %d  %s" % [player_name(slot), int(state[2]), _air_meter(state[4])]
		var stun := float(state[5])
		if stun > 0.0 and float(_stun_seen.get(slot, 0.0)) <= 0.0:
			# Fresh blackout: gasp and rattle the screen.
			rig.play(&"hit")
			request_shake(8.0)
		_stun_seen[slot] = stun


func _air_meter(fraction: float) -> String:
	var filled := int(roundf(clampf(fraction, 0.0, 1.0) * AIR_METER_STEPS))
	return "|".repeat(filled) + ".".repeat(AIR_METER_STEPS - filled)


func _update_treasure() -> void:
	for i in _coin_pool.size():
		var node := _coin_pool[i]
		node.visible = i < treasure.size()
		if node.visible:
			var state: Array = treasure[i]
			node.position = to_arena(Vector2(state[0], state[1]), COIN_HEIGHT / 2.0)
