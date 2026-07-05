class_name RelaySprint
extends MinigameBase
## Relay Sprint (M4-11, SPEC $7 #12, M15 12-cap ADR 003): relay through a
## hazard lane — each teammate runs one leg and tags the next. Even counts
## from four up split into 2-person teams (2v2v2 at six, up to six teams of
## two at the twelve-player cap, using Economy's N-team award table); head-
## to-head FFA sprint at two (SPEC fallback) and at odd counts (deviation
## noted in the PR). Server-side simulation only — the client renders
## get_snapshot().

const TRACK_LEN := 24.0
const RUN_SPEED := 6.0
## Oscillating hazards per lane: center positions along the track.
const HAZARD_POSITIONS: Array[float] = [7.0, 13.0, 19.0]
## How far a hazard swings across the lane, and how wide the safe lane is.
const HAZARD_SWING := 1.6
const HAZARD_PERIOD_SEC := 2.4
const HAZARD_RADIUS := 0.7
const LANE_HALF := 2.0
const RUNNER_RADIUS := 0.45
const TEAM_SIZE := 2

## Ordered runner slots per team.
var teams: Array = []
## Per team: index of the runner currently on the track.
var active_leg := {}
## Per team: progress of the active runner along the track (0..TRACK_LEN).
var progress := {}
## Per team: sideways position of the active runner in the lane.
var lateral := {}
## Teams that completed all legs, in finish order (tie groups per tick).
var finished_order: Array = []

var _move := {}
var _pending_finishes: Array = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"relay_sprint",
				"controls": "Move — WASD / left stick",
				"name": "Relay Sprint",
				"category": MinigameMeta.Category.TEAM,
				"min_players": 2,
				# 12 by design (ADR 003): independent 2-person lanes, so team count
				# grows cleanly with headcount (6 teams of 2 at the cap) — the only
				# limiter was stacked-lane readability, already solved by the
				# shared M15-07 LaneLayout.fitted_scale() in the view.
				"max_players": 12,
				"duration_sec": 75.0,
				"rules":
				"Run your leg, dodge the sweepers, tag your partner. First team home wins!",
			}
		)
	)


func _setup() -> void:
	var shuffled := slots.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: int = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = swap
	team_mode = shuffled.size() % TEAM_SIZE == 0 and shuffled.size() > TEAM_SIZE
	if team_mode:
		for start in range(0, shuffled.size(), TEAM_SIZE):
			teams.append(shuffled.slice(start, start + TEAM_SIZE))
	else:
		# Head-to-head sprint: everyone is a one-runner team.
		for slot: int in shuffled:
			teams.append([slot])
	for team_index in teams.size():
		active_leg[team_index] = 0
		progress[team_index] = 0.0
		lateral[team_index] = 0.0
	for slot: int in slots:
		_move[slot] = Vector2.ZERO


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	_move[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	for team_index in teams.size():
		if _team_done(team_index):
			continue
		var runner := _active_runner(team_index)
		var move: Vector2 = _move[runner]
		# Forward is +x; my > 0 dodges down, my < 0 up.
		progress[team_index] = clampf(
			float(progress[team_index]) + maxf(move.x, 0.0) * RUN_SPEED * delta, 0.0, TRACK_LEN
		)
		lateral[team_index] = clampf(
			float(lateral[team_index]) + move.y * RUN_SPEED * delta, -LANE_HALF, LANE_HALF
		)
		if _hit_hazard(team_index):
			progress[team_index] = 0.0
			lateral[team_index] = 0.0
			continue
		if float(progress[team_index]) >= TRACK_LEN:
			_finish_leg(team_index)
	if not _pending_finishes.is_empty():
		finished_order.append(_pending_finishes.duplicate())
		_pending_finishes.clear()
	if finished_order.size() > 0 and _all_teams_done():
		finish(_rank_players())


func get_snapshot() -> Dictionary:
	var lanes := {}
	for team_index in teams.size():
		lanes[team_index] = [
			teams[team_index].duplicate(),
			int(active_leg[team_index]),
			snappedf(progress[team_index], 0.01),
			snappedf(lateral[team_index], 0.01),
			_team_done(team_index),
		]
	return {
		"lanes": lanes,
		"track_len": TRACK_LEN,
		"hazards": _hazard_snapshot(),
	}


## Finished teams first (in finish order, tick ties grouped), then unfinished
## teams by total progress (legs done + current leg).
func _rank_players() -> Array:
	var placements: Array = []
	for group: Array in finished_order:
		var merged: Array = []
		for team_index: int in group:
			merged += teams[team_index]
		placements.append(merged)
	var unfinished: Array = []
	for team_index in teams.size():
		if not _team_done(team_index):
			unfinished.append(team_index)
	var totals := {}
	for team_index: int in unfinished:
		var total := float(active_leg[team_index]) * TRACK_LEN + float(progress[team_index])
		if not totals.has(total):
			totals[total] = []
		totals[total].append(team_index)
	var keys := totals.keys()
	keys.sort()
	keys.reverse()
	for key: float in keys:
		var merged: Array = []
		for team_index: int in totals[key]:
			merged += teams[team_index]
		placements.append(merged)
	return placements


func hazard_lateral(hazard_index: int, at_elapsed: float) -> float:
	var phase := TAU * at_elapsed / HAZARD_PERIOD_SEC + hazard_index * TAU / 3.0
	return sin(phase) * HAZARD_SWING


func _active_runner(team_index: int) -> int:
	return teams[team_index][mini(int(active_leg[team_index]), teams[team_index].size() - 1)]


func _team_done(team_index: int) -> bool:
	return int(active_leg[team_index]) >= teams[team_index].size()


func _all_teams_done() -> bool:
	for team_index in teams.size():
		if not _team_done(team_index):
			return false
	return true


func _finish_leg(team_index: int) -> void:
	active_leg[team_index] = int(active_leg[team_index]) + 1
	progress[team_index] = 0.0
	lateral[team_index] = 0.0
	if _team_done(team_index):
		_pending_finishes.append(team_index)


func _hit_hazard(team_index: int) -> bool:
	for i in HAZARD_POSITIONS.size():
		if absf(float(progress[team_index]) - HAZARD_POSITIONS[i]) > HAZARD_RADIUS:
			continue
		var swing := hazard_lateral(i, elapsed)
		if absf(float(lateral[team_index]) - swing) <= HAZARD_RADIUS + RUNNER_RADIUS:
			return true
	return false


func _hazard_snapshot() -> Array:
	var out: Array = []
	for i in HAZARD_POSITIONS.size():
		out.append([HAZARD_POSITIONS[i], snappedf(hazard_lateral(i, elapsed), 0.01)])
	return out
