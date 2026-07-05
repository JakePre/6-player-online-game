extends MinigameView3D
## Wall Builders client view (M10-10): stacked wall rows at each end, floor
## blocks in the contested middle, carriers glow with a block overhead.

const BLOCK_COLOR := Color(0.8, 0.65, 0.4)
const WALL_COLORS: Array[Color] = [Color(0.85, 0.45, 0.3), Color(0.35, 0.55, 0.85)]
const BLOCK_SIZE := 0.7
const WALL_WIDTH := 4.0
const ROW_BLOCKS := 5

## Latest replicated state, straight from WallBuilders.get_snapshot().
var players := {}
var blocks: Array = []
var walls: Array = [0, 0]
var teams: Array = []

var _floor_pool: Array[MeshInstance3D] = []
var _wall_pools := {}
var _carry_markers := {}
var _carrying_seen := {}
var _walls_seen: Array = [0, 0]


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _arena_half() -> float:
	return WallBuilders.ARENA_HALF + 1.0


func _setup_3d() -> void:
	var block_mesh := BoxMesh.new()
	block_mesh.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	var block_material := StandardMaterial3D.new()
	block_material.albedo_color = BLOCK_COLOR
	block_mesh.material = block_material
	for i in WallBuilders.MAX_FLOOR_BLOCKS + 4:
		var node := MeshInstance3D.new()
		node.mesh = block_mesh
		node.visible = false
		arena.add_child(node)
		_floor_pool.append(node)
	for team_index in 2:
		var side := -1.0 if team_index == 0 else 1.0
		var wall_mesh := BoxMesh.new()
		wall_mesh.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
		var material := StandardMaterial3D.new()
		material.albedo_color = WALL_COLORS[team_index]
		wall_mesh.material = material
		var pool: Array[MeshInstance3D] = []
		for i in WallBuilders.WIN_HEIGHT + 4:
			var node := MeshInstance3D.new()
			node.mesh = wall_mesh
			node.visible = false
			var row := i / ROW_BLOCKS
			var col := i % ROW_BLOCKS
			node.position = Vector3(
				side * WallBuilders.WALL_X,
				BLOCK_SIZE / 2.0 + row * BLOCK_SIZE,
				(col - ROW_BLOCKS / 2.0) * BLOCK_SIZE * 1.05
			)
			arena.add_child(node)
			pool.append(node)
		_wall_pools[team_index] = pool
	for slot: int in names:
		var marker := MeshInstance3D.new()
		marker.mesh = block_mesh
		marker.scale = Vector3.ONE * 0.7
		marker.visible = false
		arena.add_child(marker)
		_carry_markers[slot] = marker


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	blocks = game.get("blocks", [])
	walls = game.get("walls", [0, 0])
	teams = game.get("teams", [])
	for i in _floor_pool.size():
		var node := _floor_pool[i]
		if i < blocks.size():
			var block: Array = blocks[i]
			node.position = to_arena(Vector2(float(block[0]), float(block[1])), BLOCK_SIZE / 2.0)
			node.visible = true
		else:
			node.visible = false
	for team_index in 2:
		var pool: Array = _wall_pools[team_index]
		var height := int(walls[team_index]) if walls.size() > team_index else 0
		for i in pool.size():
			(pool[i] as MeshInstance3D).visible = i < height
		# Your own team's wall rising a row pays off (M12-02).
		if height > int(_walls_seen[team_index]) and team_index < teams.size():
			if my_slot in (teams[team_index] as Array):
				play_sfx(&"confirm")
		_walls_seen[team_index] = height
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
		var carrying := int(state[2]) == 1
		var marker: MeshInstance3D = _carry_markers.get(slot)
		if marker != null:
			marker.visible = carrying
			if carrying:
				marker.position = to_arena(Vector2(state[0], state[1]), 2.4)
		rig.display_name = player_name(slot) + ("  🧱" if carrying else "")
		if slot == my_slot and carrying and not bool(_carrying_seen.get(slot, false)):
			play_sfx(&"coin")
		_carrying_seen[slot] = carrying
