extends MinigameView3D
## Thin Ice client view (M8-06): renders the replicated arena in the shared
## 2.5D iso-arena (M8-01, MinigameView3D) — the tile grid as ice boxes over a
## dark water plane (cracked tiles discolor, gone tiles vanish into the
## water), players as CharacterRig instances; fallen players' rigs disappear
## with their tile. Replaces the default arena floor by overriding
## _build_floor, since vanishing tiles are the game. Presentation-tier swap
## only: state storage and the render contract are unchanged from the 2D pass
## (M4-03).

const INTACT_COLOR := Color(0.55, 0.78, 0.95)
const CRACKED_COLOR := Color(0.75, 0.68, 0.55)
const WATER_COLOR := Color(0.03, 0.05, 0.1)
const TILE_THICKNESS := 0.3
const WATER_DEPTH := 0.45

## Latest replicated state, straight from ThinIce.get_snapshot().
var tiles: Array = []
var players := {}
var fallen: Array = []

var _tile_nodes: Array[MeshInstance3D] = []
var _intact_material: StandardMaterial3D
var _cracked_material: StandardMaterial3D


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _arena_half() -> float:
	return ThinIce.HALF_EXTENT


## The ice grid IS the floor: a dark water plane below, one box per tile with
## its top surface at y=0 so rigs stand on the ice.
func _build_floor() -> void:
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2.ONE * ThinIce.HALF_EXTENT * 2.5
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = WATER_COLOR
	water_mesh.material = water_material
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = water_mesh
	water.position.y = -WATER_DEPTH
	arena.add_child(water)

	_intact_material = StandardMaterial3D.new()
	_intact_material.albedo_color = INTACT_COLOR
	_intact_material.roughness = 0.2
	_cracked_material = StandardMaterial3D.new()
	_cracked_material.albedo_color = CRACKED_COLOR
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(ThinIce.TILE_SIZE, TILE_THICKNESS, ThinIce.TILE_SIZE)

	for y in ThinIce.GRID_SIZE:
		for x in ThinIce.GRID_SIZE:
			var node := MeshInstance3D.new()
			node.name = "Tile_%d_%d" % [x, y]
			node.mesh = tile_mesh
			node.material_override = _intact_material
			node.position = Vector3(
				-ThinIce.HALF_EXTENT + (x + 0.5) * ThinIce.TILE_SIZE,
				-TILE_THICKNESS / 2.0,
				-ThinIce.HALF_EXTENT + (y + 0.5) * ThinIce.TILE_SIZE
			)
			arena.add_child(node)
			_tile_nodes.append(node)


func _render_3d(game: Dictionary) -> void:
	tiles = game.get("tiles", [])
	players = game.get("players", {})
	fallen = game.get("fallen", [])
	_update_tiles()
	_update_players()


func _update_tiles() -> void:
	for idx in _tile_nodes.size():
		var state: int = tiles[idx] if idx < tiles.size() else ThinIce.TileState.INTACT
		var node := _tile_nodes[idx]
		node.visible = state != ThinIce.TileState.GONE
		if node.visible:
			node.material_override = (
				_cracked_material if state == ThinIce.TileState.CRACKED else _intact_material
			)


## The snapshot only carries players still standing; fallen rigs sink out of
## sight with their tile. `fallen` groups simultaneous falls (see
## ThinIce._flush_falls), so it flattens one level.
func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		rig.visible = true
		update_rig(slot, Vector2(state[0], state[1]))
	for group: Array in fallen:
		for slot: int in group:
			var rig := rig_for_slot(slot)
			if rig != null:
				rig.visible = false
