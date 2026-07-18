class_name RelaySprint
extends MinigameBase
## Relay Sprint (M4-11, SPEC $7 #12, M15 12-cap ADR 003): relay through a
## hazard lane — each teammate runs one leg and tags the next. Even counts
## from four up split into 2-person teams (2v2v2 at six, up to six teams of
## two at the twelve-player cap, using Economy's N-team award table); head-
## to-head FFA sprint at two (SPEC fallback) and at odd counts (deviation
## noted in the PR). Server-side simulation only — the client renders
## get_snapshot().

## The hazard archetypes (#1068, owner playtest: "more obstacles / maybe
## spinners"): a station seeds one of these per round. All of them replicate
## as plain [x, lateral] dots, so the view and the brain's lead-the-target
## dodge work on every type unchanged.
enum Hazard { SWEEPER, SPINNER, GATE }

const TRACK_LEN := 24.0
const RUN_SPEED := 6.0
## Seeded hazard stations (#1068): four per round (was three fixed sweepers),
## each drawn from the type bag with a little x jitter.
const STATION_XS: Array[float] = [5.0, 10.0, 15.0, 20.0]
const STATION_JITTER := 0.8
## How far a sweeper swings across the lane, and how wide the safe lane is.
const HAZARD_SWING := 1.6
const HAZARD_PERIOD_SEC := 2.4
const HAZARD_RADIUS := 0.7
## Spinner: a pivot dot plus two tips orbiting it — thread past the arm.
const SPINNER_ARM := 1.5
const SPINNER_RATE := 1.8
## Gate: static wall dots flanking a seeded gap — a weave, not a timing test.
const GATE_GAP_HALF := 1.0
const GATE_DOT_SPACING := 0.9
## A hit knocks you back one station gap (#1068), not to zero: with four
## stations a full leg reset was brutal; losing a gap stings without a restart.
const HIT_KNOCKBACK := 5.0
const LANE_HALF := 2.0
const RUNNER_RADIUS := 0.45
const TEAM_SIZE := 2

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const LN_ROSTER := 0
const LN_ACTIVE_LEG := 1
const LN_PROGRESS := 2
const LN_LATERAL := 3
const LN_DONE := 4
const LN_COUNT := 5

const HZ_X := 0
const HZ_LATERAL := 1

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

## Seeded per round in _setup (#1068): {type, x, phase, gap} per station —
## shared by every lane, so all teams face the identical gauntlet.
var hazard_stations: Array[Dictionary] = []

var _move := {}
var _pending_finishes: Array = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"relay_sprint",
				"controls": "Move — WASD / left stick",
				# Structured spec (#832/#844): the bare-movement template shape.
				"control_spec": [{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE}],
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
				(
					"Run your leg — dodge sweepers, spinners and gates — tag your partner. "
					+ "First team home wins!"
				),
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
		# The true team count (#811): _rank_players merges TIED teams into one
		# placements group, so the award path can't count teams from the group
		# count — without this, two-of-three teams tying for first got paid
		# from the two-team table (20) instead of sharing the three-team
		# first-place award (25).
		team_count = teams.size()
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
	_generate_hazards()


## One station per STATION_XS entry: a bag of one of each type plus a random
## fourth, shuffled by the round seed — every round has variety, no round is
## all gates or all spinners.
func _generate_hazards() -> void:
	var bag: Array = [Hazard.SWEEPER, Hazard.SPINNER, Hazard.GATE, rng.randi_range(0, 2)]
	for i in range(bag.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = bag[i]
		bag[i] = bag[j]
		bag[j] = swap
	for i in STATION_XS.size():
		(
			hazard_stations
			. append(
				{
					"type": bag[i],
					"x": STATION_XS[i] + rng.randf_range(-STATION_JITTER, STATION_JITTER),
					"phase": rng.randf_range(0.0, TAU),
					"gap": rng.randf_range(-(LANE_HALF - GATE_GAP_HALF), LANE_HALF - GATE_GAP_HALF),
				}
			)
		)


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
			# One station's worth of setback (#1068), recentred in the lane.
			progress[team_index] = maxf(0.0, float(progress[team_index]) - HIT_KNOCKBACK)
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


## Every hazard as plain [x, lateral] dots at time `at_elapsed` (#1068): one
## swinging dot per sweeper, a pivot + two orbiting tips per spinner, static
## wall dots flanking the gap per gate. Dot count and order are fixed for the
## round, so the brain's per-index velocity estimate stays keyed correctly.
func hazard_dots(at_elapsed: float) -> Array:
	var dots: Array = []
	for i in hazard_stations.size():
		var station: Dictionary = hazard_stations[i]
		var x: float = station.x
		match int(station.type):
			Hazard.SWEEPER:
				var phase: float = TAU * at_elapsed / HAZARD_PERIOD_SEC + float(station.phase)
				dots.append([x, sin(phase) * HAZARD_SWING])
			Hazard.SPINNER:
				var theta: float = float(station.phase) + at_elapsed * SPINNER_RATE
				var arm := Vector2(cos(theta), sin(theta)) * SPINNER_ARM
				dots.append([x, 0.0])
				dots.append([x + arm.x, arm.y])
				dots.append([x - arm.x, -arm.y])
			Hazard.GATE:
				var gap: float = station.gap
				for side_end: Array in (
					[[-LANE_HALF, gap - GATE_GAP_HALF], [gap + GATE_GAP_HALF, LANE_HALF]] as Array
				):
					var lo: float = side_end[0]
					var hi: float = side_end[1]
					var span := hi - lo
					if span <= 0.0:
						continue
					var count := maxi(1, int(ceil(span / GATE_DOT_SPACING)))
					for d in count:
						dots.append([x, lo + span * (float(d) + 0.5) / float(count)])
	return dots


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
	for dot: Array in hazard_dots(elapsed):
		if absf(float(progress[team_index]) - float(dot[HZ_X])) > HAZARD_RADIUS:
			continue
		if (
			absf(float(lateral[team_index]) - float(dot[HZ_LATERAL]))
			<= (HAZARD_RADIUS + RUNNER_RADIUS)
		):
			return true
	return false


func _hazard_snapshot() -> Array:
	var out: Array = []
	for dot: Array in hazard_dots(elapsed):
		out.append([snappedf(dot[HZ_X], 0.01), snappedf(dot[HZ_LATERAL], 0.01)])
	return out
