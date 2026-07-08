class_name WallBuilders
extends MinigameBase
## Wall Builders (M10-10, PHASE2.md $4 #27): two teams race to stack the
## taller wall. Blocks spawn in the contested middle; carry one at a time
## (slowly!) to your wall to stack it — or pry one off the enemy's wall and
## haul it home. Bumping a carrier knocks their block loose. First to the
## target height wins. Server-side simulation only.

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const CARRY_SPEED_MULT := 0.65
const PLAYER_RADIUS := 0.45
## Team walls sit at x = ±WALL_X; deliveries land within WALL_REACH of it.
const WALL_X := 8.0
const WALL_REACH := 1.6
const WIN_HEIGHT := 10
const BLOCK_PICKUP_RADIUS := 0.7
const BLOCK_WAVE_SEC := 2.5
const MAX_FLOOR_BLOCKS := 6
## Prying a block off the enemy wall takes this much continuous contact.
const STEAL_SEC := 1.2
const BUMP_DROP_SHOVE := 1.5

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_CARRYING := 2
const PS_COUNT := 3

const BL_X := 0
const BL_Y := 1

var positions := {}
var move_dirs := {}
var carrying := {}
## Two teams; team 0 owns the -x wall, team 1 the +x wall.
var teams: Array = []
var wall_heights: Array = [0, 0]
## Floor blocks up for grabs, each a Vector2.
var blocks: Array[Vector2] = []

var _steal_accum := {}
var _wave_accum := 0.0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"wall_builders",
				"controls": "Move — WASD / left stick (touch to grab, walk home to stack)",
				"name": "Wall Builders",
				"category": MinigameMeta.Category.TEAM,
				"min_players": 4,
				"max_players": 8,
				"even_players": true,
				"duration_sec": 75.0,
				"rules": "Stack your wall tallest! Haul blocks home — or pry them off THEIR wall.",
			}
		)
	)


func _setup() -> void:
	team_mode = true
	var shuffled := slots.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: int = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = swap
	teams = [shuffled.slice(0, shuffled.size() / 2), shuffled.slice(shuffled.size() / 2)]
	for team_index in teams.size():
		for i in teams[team_index].size():
			var slot: int = teams[team_index][i]
			var side := -1.0 if team_index == 0 else 1.0
			positions[slot] = Vector2(side * WALL_X * 0.7, (i - 0.5) * 2.0)
			move_dirs[slot] = Vector2.ZERO
			carrying[slot] = false
			_steal_accum[slot] = 0.0
	_spawn_blocks()


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	for slot: int in slots:
		var speed := MOVE_SPEED * (CARRY_SPEED_MULT if carrying[slot] else 1.0)
		var pos: Vector2 = positions[slot] + move_dirs[slot] * speed * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
	_grab_blocks()
	_deliveries()
	_steals(delta)
	_bumps()
	_wave_accum += delta
	if _wave_accum >= BLOCK_WAVE_SEC:
		_wave_accum = 0.0
		_spawn_blocks()
	if int(wall_heights[0]) >= WIN_HEIGHT or int(wall_heights[1]) >= WIN_HEIGHT:
		finish(_rank_players())


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), 1 if carrying[slot] else 0]
	var block_list: Array = []
	for block in blocks:
		block_list.append([snappedf(block.x, 0.01), snappedf(block.y, 0.01)])
	return {
		"players": players,
		"blocks": block_list,
		"walls": wall_heights.duplicate(),
		"wall_x": WALL_X,
		"teams": teams.duplicate(true),
	}


## Taller wall's team first; dead heat is a full tie.
func _rank_players() -> Array:
	var a := int(wall_heights[0])
	var b := int(wall_heights[1])
	if a == b:
		return [slots.duplicate()]
	var order := [teams[0], teams[1]] if a > b else [teams[1], teams[0]]
	return [order[0].duplicate(), order[1].duplicate()]


func _team_of(slot: int) -> int:
	return 0 if slot in teams[0] else 1


func _own_wall_pos(slot: int) -> Vector2:
	return Vector2(-WALL_X if _team_of(slot) == 0 else WALL_X, 0.0)


func _enemy_wall_pos(slot: int) -> Vector2:
	return Vector2(WALL_X if _team_of(slot) == 0 else -WALL_X, 0.0)


func _grab_blocks() -> void:
	for i in range(blocks.size() - 1, -1, -1):
		for slot: int in slots:
			if carrying[slot]:
				continue
			if positions[slot].distance_to(blocks[i]) <= BLOCK_PICKUP_RADIUS:
				carrying[slot] = true
				blocks.remove_at(i)
				break


func _deliveries() -> void:
	for slot: int in slots:
		if not carrying[slot]:
			continue
		if positions[slot].distance_to(_own_wall_pos(slot)) <= WALL_REACH:
			carrying[slot] = false
			wall_heights[_team_of(slot)] = int(wall_heights[_team_of(slot)]) + 1


## Continuous contact with the enemy wall pries a block off it.
func _steals(delta: float) -> void:
	for slot: int in slots:
		var enemy := 1 - _team_of(slot)
		if carrying[slot] or int(wall_heights[enemy]) <= 0:
			_steal_accum[slot] = 0.0
			continue
		if positions[slot].distance_to(_enemy_wall_pos(slot)) > WALL_REACH:
			_steal_accum[slot] = 0.0
			continue
		_steal_accum[slot] = float(_steal_accum[slot]) + delta
		if float(_steal_accum[slot]) >= STEAL_SEC:
			_steal_accum[slot] = 0.0
			wall_heights[enemy] = int(wall_heights[enemy]) - 1
			carrying[slot] = true


## Opponent contact knocks a carried block loose onto the floor.
func _bumps() -> void:
	for slot: int in slots:
		if not carrying[slot]:
			continue
		for other: int in slots:
			if _team_of(other) == _team_of(slot):
				continue
			var apart: Vector2 = positions[slot] - positions[other]
			if apart.length() > PLAYER_RADIUS * 2.0:
				continue
			carrying[slot] = false
			if blocks.size() < MAX_FLOOR_BLOCKS + 4:
				blocks.append(positions[slot])
			var axis := apart.normalized() if apart.length() > 0.001 else Vector2.RIGHT
			positions[slot] = ((positions[slot] as Vector2) + axis * BUMP_DROP_SHOVE).clamp(
				Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
			)
			break


func _spawn_blocks() -> void:
	while blocks.size() < MAX_FLOOR_BLOCKS:
		# Blocks spawn in the contested middle third.
		blocks.append(
			Vector2(
				rng.randf_range(-ARENA_HALF / 3.0, ARENA_HALF / 3.0),
				rng.randf_range(-ARENA_HALF + 1.0, ARENA_HALF - 1.0)
			)
		)
