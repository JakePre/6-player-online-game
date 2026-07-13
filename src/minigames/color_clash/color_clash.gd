class_name ColorClash
extends MinigameBase
## Color Clash (M4-13, SPEC $7 #14): paint floor tiles your color by walking
## on them; most tiles when time expires wins. FFA at 2-3 players, N balanced
## teams from 4 up (2 near the 6-player baseline, up to MAX_TEAMS at 24 —
## ADR 003). The grid and arena grow with the lobby so tiles-per-player stays
## meaningful. Server-side simulation only — the client renders get_snapshot().

## Baseline (<=6 players) grid; larger lobbies scale up from here.
const GRID_SIZE := 12
const TILE_WORLD := 1.5
const ARENA_HALF := GRID_SIZE * TILE_WORLD / 2.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
## Team play starts at this player count (SPEC: FFA at 2-3, teams at 4+).
const TEAM_THRESHOLD := 4
## Most teams a large lobby splits into (ADR 003: 4 teams of 6 at 24).
const MAX_TEAMS := 4
const UNPAINTED := -1
## Full-grid keyframe cadence for replication (#479). Snapshots are
## unreliable_ordered, so a single dropped tile delta would leave a client's
## tile wrong forever — a periodic full grid self-heals dropped deltas and
## mounts late joiners, at a bounded staleness of this many broadcasts (~1s at
## the 30 Hz snapshot rate). Between keyframes only changed tiles are sent.
const KEYFRAME_EVERY := 30

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_FACTION := 2
const PS_COUNT := 3
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. Validated by test_snapshot_schema against get_snapshot().
const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT, TYPE_INT]

## grid_changes entries: [index, owner], not a per-slot array like PS_* above.
const GC_INDEX := 0
const GC_OWNER := 1

var positions := {}
var move_dirs := {}
## faction id per slot: the slot itself in FFA, else the team index.
var faction_of := {}
## Arrays of slots per team in team play; empty in FFA.
var teams: Array = []
## grid_dim * grid_dim tile owners (faction id or UNPAINTED).
var grid: Array = []
## This match's scaled grid dimension and arena size (equal to the consts at
## <=6 players). Both sim and view derive these from the head count via the
## static helpers below, so tile layout stays in lockstep without threading
## through the snapshot.
var grid_dim := GRID_SIZE
var arena_half := ARENA_HALF
## Grid as of the last snapshot, for diffing tile deltas, plus the snapshot
## counter that schedules keyframes. Kept in lockstep with what clients hold,
## so a delta always describes the exact change since the last send.
var _prev_grid: Array = []
var _snapshot_seq := 0


## N x N grid dimension for a lobby of `count`: grows so tiles-per-player
## (area) holds — a side scales with the square root of the head-count growth.
static func grid_dim_for(count: int) -> int:
	return maxi(GRID_SIZE, roundi(GRID_SIZE * sqrt(MinigameScaling.growth(count))))


## Half-extent of the square arena for `count` players, derived from the grid.
static func arena_half_for(count: int) -> float:
	return grid_dim_for(count) * TILE_WORLD / 2.0


## How many balanced teams a lobby of `n` splits into (0 = FFA). Targets the
## 6-player baseline team size, then searches nearby counts for one that
## divides `n` evenly with at least 2 per team; a count with no clean split
## (e.g. a prime like 23) falls back to FFA.
static func team_count_for(n: int) -> int:
	if n < TEAM_THRESHOLD:
		return 0
	var target := clampi(roundi(float(n) / MinigameScaling.BASELINE_PLAYERS), 2, MAX_TEAMS)
	for delta: int in [0, -1, 1, -2, 2]:
		var tc := target + delta
		if tc >= 2 and tc <= MAX_TEAMS and n % tc == 0 and n / tc >= 2:
			return tc
	return 0


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
				"max_players": 24,
				"duration_sec": 45.0,
				"rules": "Paint the floor by walking on it — most tiles when time runs out wins!",
				# Structured spec (#832/#844): a move row plus a plain note row.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"note": "Paint by walking"},
				],
			}
		)
	)


func _setup() -> void:
	grid_dim = grid_dim_for(slots.size())
	arena_half = arena_half_for(slots.size())
	grid.resize(grid_dim * grid_dim)
	grid.fill(UNPAINTED)
	# Balanced teams from 4 up; counts with no clean even split play FFA — a
	# lopsided paint race is never fun (#178). team_count is the base-class
	# field: the award path needs the true count to pay merged ties (#811).
	team_count = team_count_for(slots.size())
	team_mode = team_count > 0
	if team_mode:
		var shuffled := slots.duplicate()
		for i in range(shuffled.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap: int = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = swap
		var per_team := shuffled.size() / team_count
		teams = []
		for t in team_count:
			var members: Array = shuffled.slice(t * per_team, (t + 1) * per_team)
			teams.append(members)
			for slot: int in members:
				faction_of[slot] = t
	else:
		for slot: int in slots:
			faction_of[slot] = slot
	var spawns := SpawnLayout.ring_positions(slots.size(), arena_half * 0.6)
	for i in slots.size():
		var slot: int = slots[i]
		positions[slot] = spawns[i]
		move_dirs[slot] = Vector2.ZERO
		_paint(slot)


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	for slot: int in slots:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		var limit := arena_half - PLAYER_RADIUS
		positions[slot] = pos.clamp(Vector2(-limit, -limit), Vector2(limit, limit))
		_paint(slot)


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), faction_of[slot]]
	var snapshot := {
		"players": players,
		"counts": _tile_counts(),
		"teams": teams.duplicate(true),
		"dim": grid_dim,
		"half": arena_half,
	}
	# Paint replication (#479): a full grid is 24x24 ints at the 24-player cap —
	# too big to broadcast every tick. Send a full-grid keyframe on the cadence
	# (and whenever the board was just resized, so _prev_grid can't be diffed),
	# and only the tiles that flipped in between. Broadcasts happen exactly once
	# per tick (NetManager._broadcast_snapshots), so advancing the counter and
	# diffing against _prev_grid here is deterministic.
	var keyframe := _snapshot_seq % KEYFRAME_EVERY == 0 or _prev_grid.size() != grid.size()
	_snapshot_seq += 1
	if keyframe:
		snapshot["grid"] = grid.duplicate()
		_prev_grid = grid.duplicate()
	else:
		var changes: Array = []
		for i in grid.size():
			if grid[i] != _prev_grid[i]:
				changes.append([i, grid[i]])
				_prev_grid[i] = grid[i]
		snapshot["grid_changes"] = changes
	return snapshot


## Most tiles wins. FFA: players ranked by their own tiles (ties grouped).
## Teams: rank groups best-first by painted tiles, TIED teams merged into one
## group (#811 — a partial tie used to sort arbitrarily and pay the "winner"
## more; award_for_teams now shares the higher award across a merged group
## using the base team_count). An all-teams dead heat falls out as one group.
func _rank_players() -> Array:
	var counts := _tile_counts()
	if team_mode:
		var by_tiles := {}
		for team_index in teams.size():
			var tiles: int = counts.get(team_index, 0)
			if not by_tiles.has(tiles):
				by_tiles[tiles] = []
			by_tiles[tiles].append(team_index)
		var tile_totals := by_tiles.keys()
		tile_totals.sort()
		tile_totals.reverse()
		var placements: Array = []
		for tiles: int in tile_totals:
			var group: Array = []
			for team_index: int in by_tiles[tiles]:
				group += teams[team_index]
			placements.append(group)
		return placements
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
	var col := clampi(int(floor((pos.x + arena_half) / TILE_WORLD)), 0, grid_dim - 1)
	var row := clampi(int(floor((pos.y + arena_half) / TILE_WORLD)), 0, grid_dim - 1)
	grid[row * grid_dim + col] = faction_of[slot]


func _tile_counts() -> Dictionary:
	var counts := {}
	for owner: int in grid:
		if owner == UNPAINTED:
			continue
		counts[owner] = int(counts.get(owner, 0)) + 1
	return counts
