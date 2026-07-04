class_name FortSiege
extends MinigameBase
## Fort Siege (M10-12, PHASE2.md $4 #29): one team storms a walled fort, the
## other defends it — then they swap and the faster siege wins. Attackers
## batter the gate down (more attackers = faster) and then hold the core
## uncontested to capture; defenders bounce them away with a shove on a
## cooldown. A capture stops the clock, the timeout caps the run. If neither
## side captures, the deeper run (gate damage + capture progress) wins.
## Server-side simulation only — the client renders get_snapshot().

enum Phase {
	SIEGE,
	SWAP,
}

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
## The fort occupies the -y end: a full-width gate wall at GATE_Y that
## attackers cannot pass while it stands, and the core disc behind it.
const GATE_Y := -3.0
const GATE_MAX_HP := 12.0
## Attackers this close to the wall batter it, 1 hp/s each.
const GATE_TOUCH := 1.0
const CORE_POS := Vector2(0.0, -6.5)
const CORE_RADIUS := 1.5
## Seconds of uncontested core-holding to capture (any defender on the core
## stalls the meter — the KotH contest rule).
const CAPTURE_SEC := 4.0
const SIEGE_SEC := 40.0
const SWAP_SEC := 3.0
const SHOVE_RADIUS := 1.4
const SHOVE_KNOCK := 9.0
const SHOVE_COOLDOWN_SEC := 1.5
const KNOCK_DECAY := 6.0

var teams: Array = []
var phase := Phase.SIEGE
## Index of the team currently (or last) attacking.
var attacking := 0
var phase_elapsed := 0.0
var gate_hp := GATE_MAX_HP
var capture := 0.0
var positions := {}
var move_dirs := {}
var knocks := {}
var shove_cooldowns := {}
## One entry per attacking team once its siege resolves:
## {captured, time, progress}.
var runs: Array = [{}, {}]

var _sieges_done := 0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"fort_siege",
				"name": "Fort Siege",
				"category": MinigameMeta.Category.TEAM,
				"min_players": 4,
				"max_players": 6,
				"even_players": true,
				"duration_sec": 90.0,
				"rules":
				(
					"Storm the fort! Batter the gate down, then hold the core to"
					+ " capture. Defenders shove you off. Then SWAP — the faster"
					+ " siege wins the day."
				),
				"controls": "Move — WASD / left stick · Shove (defending) — SPACE / pad A",
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
	_start_siege(0)


func _start_siege(team_index: int) -> void:
	phase = Phase.SIEGE
	attacking = team_index
	phase_elapsed = 0.0
	gate_hp = GATE_MAX_HP
	capture = 0.0
	var defenders: Array = teams[1 - team_index]
	var raiders: Array = teams[team_index]
	for i in raiders.size():
		var slot: int = raiders[i]
		positions[slot] = Vector2((i - raiders.size() / 2.0 + 0.5) * 2.0, ARENA_HALF * 0.8)
		_reset_slot(slot)
	for i in defenders.size():
		var slot: int = defenders[i]
		positions[slot] = Vector2((i - defenders.size() / 2.0 + 0.5) * 2.0, GATE_Y - 2.0)
		_reset_slot(slot)


func _reset_slot(slot: int) -> void:
	move_dirs[slot] = Vector2.ZERO
	knocks[slot] = Vector2.ZERO
	shove_cooldowns[slot] = 0.0


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if data.get("act", false) and phase == Phase.SIEGE:
		if slot in teams[1 - attacking] and float(shove_cooldowns[slot]) <= 0.0:
			_shove(slot)


## Defender-only radial shove: every attacker in reach gets bounced away.
func _shove(slot: int) -> void:
	shove_cooldowns[slot] = SHOVE_COOLDOWN_SEC
	for raider: int in teams[attacking]:
		if positions[slot].distance_to(positions[raider]) > SHOVE_RADIUS:
			continue
		var away: Vector2 = positions[raider] - positions[slot]
		knocks[raider] = (away.normalized() if away.length() > 0.001 else Vector2.UP) * SHOVE_KNOCK


func _tick(delta: float) -> void:
	phase_elapsed += delta
	if phase == Phase.SWAP:
		if phase_elapsed >= SWAP_SEC:
			_start_siege(1)
		return
	_move(delta)
	_batter_gate(delta)
	_fill_capture(delta)
	if capture >= 1.0:
		_end_siege(true)
	elif phase_elapsed >= SIEGE_SEC:
		_end_siege(false)


func _move(delta: float) -> void:
	for slot: int in slots:
		shove_cooldowns[slot] = maxf(float(shove_cooldowns[slot]) - delta, 0.0)
		var knock: Vector2 = knocks[slot]
		var pos: Vector2 = positions[slot] + (move_dirs[slot] * MOVE_SPEED + knock) * delta
		knocks[slot] = knock.move_toward(Vector2.ZERO, KNOCK_DECAY * delta)
		pos = pos.clamp(Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF))
		# The standing gate walls out the attackers (defenders pass freely).
		if gate_hp > 0.0 and slot in teams[attacking]:
			pos.y = maxf(pos.y, GATE_Y + PLAYER_RADIUS)
		positions[slot] = pos


func _batter_gate(delta: float) -> void:
	if gate_hp <= 0.0:
		return
	var batterers := 0
	for raider: int in teams[attacking]:
		if (positions[raider] as Vector2).y - GATE_Y <= GATE_TOUCH:
			batterers += 1
	gate_hp = maxf(gate_hp - batterers * delta, 0.0)


func _fill_capture(delta: float) -> void:
	if gate_hp > 0.0:
		return
	var raiders_on := 0
	for raider: int in teams[attacking]:
		if positions[raider].distance_to(CORE_POS) <= CORE_RADIUS:
			raiders_on += 1
	for defender: int in teams[1 - attacking]:
		if positions[defender].distance_to(CORE_POS) <= CORE_RADIUS:
			return  # Contested: the meter holds.
	if raiders_on > 0:
		capture = minf(capture + delta / CAPTURE_SEC, 1.0)


func _end_siege(captured: bool) -> void:
	runs[attacking] = _live_run(captured)
	_sieges_done += 1
	if _sieges_done >= 2:
		finish(_rank_players())
		return
	phase = Phase.SWAP
	phase_elapsed = 0.0


## The attacking team's current run, as it would be scored right now.
func _live_run(captured: bool) -> Dictionary:
	return {
		"captured": captured,
		"time": phase_elapsed if captured else SIEGE_SEC,
		# Depth of a failed run: gate damage plus core progress (a full
		# capture bar weighs as much as a whole gate).
		"progress": (GATE_MAX_HP - gate_hp) + capture * GATE_MAX_HP,
	}


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
	var limit := SIEGE_SEC if phase == Phase.SIEGE else SWAP_SEC
	var times: Array = []
	for run: Dictionary in runs:
		times.append(snappedf(run.time, 0.1) if run.get("captured", false) else -1.0)
	return {
		"phase": phase,
		"attacking": attacking,
		"phase_left": snappedf(maxf(limit - phase_elapsed, 0.0), 0.1),
		"gate": snappedf(gate_hp / GATE_MAX_HP, 0.01),
		"capture": snappedf(capture, 0.01),
		"players": players,
		"teams": teams.duplicate(true),
		"times": times,
	}


## Faster capture first; a lone captor beats a non-captor; two failed runs
## compare depth; identical results are a full tie. The backstop timeout can
## rank a mid-run siege — it scores as it stands (_live_run).
func _rank_players() -> Array:
	var results: Array = []
	for team in 2:
		var run: Dictionary = runs[team]
		results.append(run if not run.is_empty() else _live_run(false))
	var a: Dictionary = results[0]
	var b: Dictionary = results[1]
	var winner := -1
	if a.captured and b.captured:
		if not is_equal_approx(float(a.time), float(b.time)):
			winner = 0 if float(a.time) < float(b.time) else 1
	elif a.captured or b.captured:
		winner = 0 if a.captured else 1
	elif not is_equal_approx(float(a.progress), float(b.progress)):
		winner = 0 if float(a.progress) > float(b.progress) else 1
	if winner == -1:
		return [slots.duplicate()]
	return [teams[winner].duplicate(), teams[1 - winner].duplicate()]
