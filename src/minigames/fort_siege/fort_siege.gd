class_name FortSiege
extends MinigameBase
## Fort Siege (M10-12; #1028 relic rework): one team storms a walled fort,
## the other defends it — then they swap and the faster HEIST wins. Attackers
## batter the gate down (more attackers = faster), then STEAL the relic at
## the core and carry it out of the fort; the carrier is slowed and a
## defender's shove makes them drop it, after which a defender's touch (or a
## few unattended seconds) sends it home. An escape stops the clock, the
## timeout caps the run. If neither side escapes, the deeper run (gate
## damage + how far the relic ever got) wins.
##
## #1028/#962 history: the old endgame ("hold the core uncontested") was
## structurally unwinnable — one defender standing on the core stalled the
## meter forever, the shove out-ranged the core disc, and attackers had no
## verb against defenders, so every bot run (and every human run) ended 0-0.
## A movable objective dissolves that wall: presence can't be denied when the
## thing you're defending can be picked up and RUN.
## Server-side simulation only — the client renders get_snapshot().

enum Phase {
	SIEGE,
	SWAP,
}

## Where the relic is (#1028): home on its plinth, in a thief's hands, or
## loose on the ground mid-heist.
enum RelicState {
	AT_CORE,
	CARRIED,
	DROPPED,
}

## The gate verb a player last performed (#808), so the view animates each swing
## / repair / shove exactly once off a monotonic counter. NONE is the resting
## state, never sent as a fresh action.
enum Act {
	NONE,
	BATTER,
	REPAIR,
	SHOVE,
}

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
## The fort occupies the -y end: a full-width gate wall at GATE_Y that
## attackers cannot pass while it stands, and the core disc behind it.
const GATE_Y := -3.0
const GATE_MAX_HP := 12.0
## Attackers this close to the gate line can batter (or defenders repair) it.
const GATE_TOUCH := 1.0
## Battering is now an explicit swing on a cooldown (#808), tuned so a raider's
## average damage matches the old proximity rate (1 hp/s): 1 hp per 1.0s swing,
## so mashing or holding the button caps at the same DPS and balance is unchanged.
const BATTER_DAMAGE := 1.0
const BATTER_COOLDOWN_SEC := 1.0
## The mirrored defender verb (#808): hold the gate together by repairing it,
## ~0.5 hp per 1.0s while it still stands — real pre-breach agency beyond shoving.
const REPAIR_AMOUNT := 0.5
const REPAIR_COOLDOWN_SEC := 1.0
const CORE_POS := Vector2(0.0, -6.5)
const CORE_RADIUS := 1.5
## Relic heist (#1028). Touch range for both sides' relic interactions: a
## raider this close grabs it (home or loose); a defender this close to a
## LOOSE relic sends it home. Raiders win a simultaneous touch — the comeback
## re-grab is the attackers' counterplay to the shove.
const RELIC_TOUCH := 0.9
## A loose relic nobody touches walks itself home after this long.
const RELIC_AUTO_RETURN_SEC := 4.0
## The thief runs at this fraction of MOVE_SPEED — catchable, not helpless.
const CARRY_SLOW := 0.7
## Carrying the relic past this line (out through the breach) scores the run.
const ESCAPE_Y := GATE_Y + 1.0
const SIEGE_SEC := 40.0
const SWAP_SEC := 3.0
const SHOVE_RADIUS := 1.4
const SHOVE_KNOCK := 9.0
const SHOVE_COOLDOWN_SEC := 1.5
const KNOCK_DECAY := 6.0

## get_snapshot() wire shape (#708): named indices for the players positional
## array. Array SHAPE on the wire is unchanged — additive only.
const PS_X := 0
const PS_Y := 1
## #808 additive fields: a monotonic gate-action counter and its kind (Act.*)
## so the view plays each swing/repair/shove once, plus the shove cooldown as a
## 0..1 fraction remaining for the on-player cooldown ring.
const PS_ACT_SEQ := 2
const PS_ACT_KIND := 3
const PS_SHOVE_CD := 4
const PS_COUNT := 5
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. Validated by test_snapshot_schema against get_snapshot().
const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_INT, TYPE_FLOAT]

var teams: Array = []
var phase := Phase.SIEGE
## Index of the team currently (or last) attacking.
var attacking := 0
var phase_elapsed := 0.0
var gate_hp := GATE_MAX_HP
## Best relic progress this siege, 0..1 from the plinth to the escape line
## (#1028): monotonic, so a failed run's depth records how close the heist got.
var capture := 0.0
var positions := {}
var move_dirs := {}
var knocks := {}
var shove_cooldowns := {}
## Relic heist state (#1028): where it is, who holds it, where it lies when
## loose, and the loose-relic homing timer.
var relic_state := RelicState.AT_CORE
var relic_carrier := -1
var relic_pos := CORE_POS
var relic_return_left := 0.0
## Gate-verb state (#808): a shared batter/repair cooldown (role-exclusive), a
## monotonic per-slot action counter, and the last action's kind (Act.*).
var gate_cooldowns := {}
var act_seq := {}
var act_kind := {}
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
				"max_players": 12,
				"even_players": true,
				"duration_sec": 90.0,
				"rules":
				(
					"Smash the gate, STEAL the relic, and run it out of the fort!"
					+ " Defenders: shove the thief to make them drop it, then touch"
					+ " it to send it home. SWAP sides — the faster heist wins."
				),
				# Stale as bare "Shove (defending)" since #808 gave the one button a
				# third meaning (BATTER for raiders, REPAIR for an unthreatened
				# defender) — updated alongside the #844 conversion.
				"controls": "Move — WASD / left stick · Batter/Repair/Shove — SPACE / pad A",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				[
					"Move — WASD / left stick · Batter/Repair/Shove — ",
					{"action": &"action_primary"},
				],
				# Structured spec (#832/#844): one button, three role/context-
				# dependent meanings (#808) — named together since control_spec
				# rows are static per game, not per-role.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"verb": "Batter / Repair / Shove", "input": &"action_primary"},
				],
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
	for slot: int in slots:
		# Monotonic across the whole game (both sieges), so the view's play-once
		# tracking survives the swap — only the transient cooldowns reset per side.
		act_seq[slot] = 0
		act_kind[slot] = Act.NONE
	_start_siege(0)


func _start_siege(team_index: int) -> void:
	phase = Phase.SIEGE
	attacking = team_index
	phase_elapsed = 0.0
	gate_hp = GATE_MAX_HP
	capture = 0.0
	relic_state = RelicState.AT_CORE
	relic_carrier = -1
	relic_pos = CORE_POS
	relic_return_left = 0.0
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
	gate_cooldowns[slot] = 0.0


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	# The one action button (#808) is context-sensitive by role: raiders BATTER
	# the gate, defenders SHOVE a raider off it (or REPAIR it when none are on
	# them). Held or mashed, each verb is gated to its own cooldown so the
	# average rate — and the balance — matches the old proximity model.
	if not data.get("act", false) or phase != Phase.SIEGE:
		return
	if slot in teams[attacking]:
		_try_batter(slot)
	else:
		_try_defend(slot)


## A raider's swing: 1 hp off the gate if they're at the gate line and off
## cooldown. Records the swing so the view animates it and cracks the gate.
func _try_batter(slot: int) -> void:
	if gate_hp <= 0.0 or float(gate_cooldowns[slot]) > 0.0:
		return
	if (positions[slot] as Vector2).y - GATE_Y > GATE_TOUCH:
		return
	gate_hp = maxf(gate_hp - BATTER_DAMAGE, 0.0)
	gate_cooldowns[slot] = BATTER_COOLDOWN_SEC
	_record_act(slot, Act.BATTER)


## A defender's action: shove any raider in reach off the gate; if none are on
## them and the gate still stands, repair it instead — the mirrored gate verb.
func _try_defend(slot: int) -> void:
	if _raider_in_reach(slot):
		if float(shove_cooldowns[slot]) <= 0.0:
			_shove(slot)
		return
	if gate_hp <= 0.0 or gate_hp >= GATE_MAX_HP or float(gate_cooldowns[slot]) > 0.0:
		return
	if absf((positions[slot] as Vector2).y - GATE_Y) > GATE_TOUCH:
		return
	gate_hp = minf(gate_hp + REPAIR_AMOUNT, GATE_MAX_HP)
	gate_cooldowns[slot] = REPAIR_COOLDOWN_SEC
	_record_act(slot, Act.REPAIR)


func _raider_in_reach(slot: int) -> bool:
	for raider: int in teams[attacking]:
		if positions[slot].distance_to(positions[raider]) <= SHOVE_RADIUS:
			return true
	return false


## Defender-only radial shove: every attacker in reach gets bounced away —
## and a shoved THIEF drops the relic where they stood (#1028), turning the
## shove from blanket area denial into the carrier-stopping verb it should be.
func _shove(slot: int) -> void:
	shove_cooldowns[slot] = SHOVE_COOLDOWN_SEC
	for raider: int in teams[attacking]:
		if positions[slot].distance_to(positions[raider]) > SHOVE_RADIUS:
			continue
		var away: Vector2 = positions[raider] - positions[slot]
		knocks[raider] = (away.normalized() if away.length() > 0.001 else Vector2.UP) * SHOVE_KNOCK
		if raider == relic_carrier:
			_drop_relic(positions[raider])
	_record_act(slot, Act.SHOVE)


func _drop_relic(at: Vector2) -> void:
	relic_state = RelicState.DROPPED
	relic_carrier = -1
	relic_pos = at
	relic_return_left = RELIC_AUTO_RETURN_SEC


func _record_act(slot: int, kind: Act) -> void:
	act_seq[slot] = int(act_seq[slot]) + 1
	act_kind[slot] = kind


func _tick(delta: float) -> void:
	phase_elapsed += delta
	if phase == Phase.SWAP:
		if phase_elapsed >= SWAP_SEC:
			_start_siege(1)
		return
	_move(delta)
	_tick_relic(delta)
	if relic_state == RelicState.CARRIED and relic_pos.y >= ESCAPE_Y:
		_end_siege(true)  # the thief made it out — heist complete
	elif phase_elapsed >= SIEGE_SEC:
		_end_siege(false)


func _move(delta: float) -> void:
	for slot: int in slots:
		shove_cooldowns[slot] = maxf(float(shove_cooldowns[slot]) - delta, 0.0)
		gate_cooldowns[slot] = maxf(float(gate_cooldowns[slot]) - delta, 0.0)
		var knock: Vector2 = knocks[slot]
		# The thief lugs the relic (#1028): slowed, so defenders can catch the
		# run — but knocks land at full force either way.
		var speed := MOVE_SPEED * (CARRY_SLOW if slot == relic_carrier else 1.0)
		var pos: Vector2 = positions[slot] + (move_dirs[slot] * speed + knock) * delta
		knocks[slot] = knock.move_toward(Vector2.ZERO, KNOCK_DECAY * delta)
		pos = pos.clamp(Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF))
		# The standing gate walls out the attackers (defenders pass freely).
		if gate_hp > 0.0 and slot in teams[attacking]:
			pos.y = maxf(pos.y, GATE_Y + PLAYER_RADIUS)
		positions[slot] = pos


## The relic heist (#1028). Behind a standing gate the relic is untouchable;
## once breached: a raider's touch grabs it (home or loose, and raiders win a
## simultaneous touch — the re-grab is their comeback verb), a defender's
## touch on a LOOSE relic sends it home, and an unattended loose relic walks
## home on its own. Carried, it rides the thief and records the run's depth.
func _tick_relic(delta: float) -> void:
	if gate_hp > 0.0:
		return
	match relic_state:
		RelicState.AT_CORE:
			relic_pos = CORE_POS
			_try_grab()
		RelicState.CARRIED:
			relic_pos = positions[relic_carrier]
			capture = maxf(capture, _relic_progress(relic_pos))
		RelicState.DROPPED:
			capture = maxf(capture, _relic_progress(relic_pos))
			if _try_grab():
				return
			for defender: int in teams[1 - attacking]:
				if positions[defender].distance_to(relic_pos) <= RELIC_TOUCH:
					_return_relic()
					return
			relic_return_left -= delta
			if relic_return_left <= 0.0:
				_return_relic()


## First raider in touch range takes the relic. Returns true on a grab.
func _try_grab() -> bool:
	for raider: int in teams[attacking]:
		if positions[raider].distance_to(relic_pos) <= RELIC_TOUCH:
			relic_state = RelicState.CARRIED
			relic_carrier = raider
			return true
	return false


func _return_relic() -> void:
	relic_state = RelicState.AT_CORE
	relic_carrier = -1
	relic_pos = CORE_POS


## 0 at the plinth, 1 at the escape line — the heist's how-close-it-got meter.
func _relic_progress(pos: Vector2) -> float:
	return clampf((pos.y - CORE_POS.y) / (ESCAPE_Y - CORE_POS.y), 0.0, 1.0)


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
		# Depth of a failed run: gate damage plus how far the relic ever got
		# (#1028 — a full heist-to-the-line weighs as much as a whole gate).
		"progress": (GATE_MAX_HP - gate_hp) + capture * GATE_MAX_HP,
	}


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			int(act_seq.get(slot, 0)),
			int(act_kind.get(slot, Act.NONE)),
			snappedf(clampf(float(shove_cooldowns[slot]) / SHOVE_COOLDOWN_SEC, 0.0, 1.0), 0.01),
		]
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
		# The heist itself (#1028): [x, y, RelicState, carrier slot or -1].
		"relic":
		[snappedf(relic_pos.x, 0.01), snappedf(relic_pos.y, 0.01), int(relic_state), relic_carrier],
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
