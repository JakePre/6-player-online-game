class_name ColorClash
extends MinigameBase
## Color Clash (M4-13, SPEC $7 #14): paint floor tiles your color by walking
## on them; most tiles when time expires wins. FFA at 2-3 players, two random
## teams at 4-6 (the explicit team_mode caveat from #41). Server-side
## simulation only — the client renders get_snapshot().

const GRID_SIZE := 12
const TILE_WORLD := 1.5
const ARENA_HALF := GRID_SIZE * TILE_WORLD / 2.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
## Team play starts at this player count (SPEC: FFA at 2-3, teams at 4-6).
const TEAM_THRESHOLD := 4
const UNPAINTED := -1

var positions := {}
var move_dirs := {}
## faction id per slot: the slot itself in FFA, 0/1 in team play.
var faction_of := {}
## Two arrays of slots in team play; empty in FFA.
var teams: Array = []
## GRID_SIZE * GRID_SIZE tile owners (faction id or UNPAINTED).
var grid: Array = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"color_clash",
				"controls": "Move — WASD / left stick (paint by walking)",
				"name": "Color Clash",
				"category": MinigameMeta.Category.TEAM,
				"min_players": 2,
				"max_players": 6,
				"duration_sec": 45.0,
				"rules": "Paint the floor by walking on it — most tiles when time runs out wins!",
			}
		)
	)


func _setup() -> void:
	grid.resize(GRID_SIZE * GRID_SIZE)
	grid.fill(UNPAINTED)
	team_mode = slots.size() >= TEAM_THRESHOLD
	if team_mode:
		var shuffled := slots.duplicate()
		for i in range(shuffled.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap: int = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = swap
		teams = [shuffled.slice(0, shuffled.size() / 2), shuffled.slice(shuffled.size() / 2)]
		for team_index in teams.size():
			for slot: int in teams[team_index]:
				faction_of[slot] = team_index
	else:
		for slot: int in slots:
			faction_of[slot] = slot
	for i in slots.size():
		var angle := TAU * i / slots.size()
		var slot: int = slots[i]
		positions[slot] = Vector2(cos(angle), sin(angle)) * ARENA_HALF * 0.6
		move_dirs[slot] = Vector2.ZERO
		_paint(slot)


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	for slot: int in slots:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		var limit := ARENA_HALF - PLAYER_RADIUS
		positions[slot] = pos.clamp(Vector2(-limit, -limit), Vector2(limit, limit))
		_paint(slot)


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), faction_of[slot]]
	return {
		"players": players,
		"grid": grid.duplicate(),
		"counts": _tile_counts(),
		"teams": teams.duplicate(true),
	}


## Most tiles wins. FFA: players ranked by their own tiles (ties grouped).
## Teams: the two teams best-first (team_mode routing awards SPEC $5 tables),
## a dead heat is a full tie.
func _rank_players() -> Array:
	var counts := _tile_counts()
	if team_mode:
		var a: int = counts.get(0, 0)
		var b: int = counts.get(1, 0)
		if a == b:
			return [slots.duplicate()]
		var order := [teams[0], teams[1]] if a > b else [teams[1], teams[0]]
		return [order[0].duplicate(), order[1].duplicate()]
	var by_count := {}
	for slot: int in slots:
		var count: int = counts.get(slot, 0)
		if not by_count.has(count):
			by_count[count] = []
		by_count[count].append(slot)
	var totals := by_count.keys()
	totals.sort()
	totals.reverse()
	var placements: Array = []
	for total: int in totals:
		placements.append(by_count[total])
	return placements


func _paint(slot: int) -> void:
	var pos: Vector2 = positions[slot]
	var col := clampi(int(floor((pos.x + ARENA_HALF) / TILE_WORLD)), 0, GRID_SIZE - 1)
	var row := clampi(int(floor((pos.y + ARENA_HALF) / TILE_WORLD)), 0, GRID_SIZE - 1)
	grid[row * GRID_SIZE + col] = faction_of[slot]


func _tile_counts() -> Dictionary:
	var counts := {}
	for owner: int in grid:
		if owner == UNPAINTED:
			continue
		counts[owner] = int(counts.get(owner, 0)) + 1
	return counts
