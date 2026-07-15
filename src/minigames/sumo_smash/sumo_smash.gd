class_name SumoSmash
extends MinigameBase
## Sumo Smash (M4-04, SPEC $7 #5): shove players off a circular platform;
## dash has a cooldown. Ring-out order = placement. Server-side simulation
## only — the client renders get_snapshot().

const PLATFORM_RADIUS := 8.0
const MOVE_SPEED := 5.0
const PLAYER_RADIUS := 0.5
const SHOVE_SPEED := 4.0
## The dasher's lunge speed. A knock of magnitude K decays linearly at
## KNOCK_DECAY, so it carries the body K²/(2·KNOCK_DECAY) units before stopping.
## The old 14/6 pairing flung the DASHER itself ~16 units and — because the 3×
## dash-shove re-applied every overlapping tick (now landed once per dash, see
## _resolve_shoves) — the victim far more, so a fresh 6-bot round emptied the
## ring in ~1s. Retuned together (#927) to DASH_SPEED 10 / KNOCK_DECAY 11: a
## dash lunges ~4.5 units and a clean dash-shove carries a victim ~6.5, still a
## real ring-out threat but no longer a one-pass wipe — full-field bot rounds now
## resolve in a healthy ~5-14s across player counts instead of ~1s or a 60s
## stalemate (see test_sumo_smash bot-round guards).
const DASH_SPEED := 10.0
const DASH_SEC := 0.25
const DASH_COOLDOWN_SEC := 2.0
const DASH_SHOVE_MULT := 3.0
const KNOCK_DECAY := 11.0

## get_snapshot() wire shape (#708): named indices for the players positional
## array. Array SHAPE on the wire is unchanged — additive only.
const PS_X := 0
const PS_Y := 1
const PS_COOLDOWN := 2
const PS_DASHING := 3
const PS_COUNT := 4
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row (dashing ships as a 0/1 int). Validated by test_snapshot_schema
## against get_snapshot().
const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT]

var positions := {}
var move_dirs := {}
## Knockback/dash velocity per slot, decaying toward zero.
var knocks := {}
var dash_left := {}
var cooldown_left := {}
## Per dasher, the set of victims its CURRENT dash has already shoved — so the
## strong dash bonus lands once, not every overlapping tick (#927). Reset when a
## fresh dash starts.
var _dash_hit := {}
## Elimination + placement bookkeeping (#940): same-tick ring-outs share a tie
## group, placements rank in reverse ring-out order. `.order` is the out groups.
var _elim := EliminationTracker.new()


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"sumo_smash",
				"controls": "Move — WASD / left stick · Dash — SPACE / pad A",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				["Move — WASD / left stick · Dash — ", {"action": &"action_primary"}],
				# Structured spec (#832/#844): the move + action template shape.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"verb": "Dash", "input": &"action_primary"},
				],
				"name": "Sumo Smash",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				# 8 by design (ADR 003): the platform stays this one tiny disc on
				# purpose — bigger would turn the shove-brawl into random pinball.
				"max_players": 8,
				"duration_sec": 60.0,
				"rules": "Shove everyone off the platform! Dash to hit harder — it has a cooldown.",
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * PLATFORM_RADIUS * 0.6
		move_dirs[slots[i]] = Vector2.ZERO
		knocks[slots[i]] = Vector2.ZERO
		dash_left[slots[i]] = 0.0
		cooldown_left[slots[i]] = 0.0
		_dash_hit[slots[i]] = {}


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _elim.is_in(slot, slots):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if data.get("dash", false) and float(cooldown_left[slot]) <= 0.0:
		var heading: Vector2 = move_dirs[slot]
		if heading.length() < 0.01:
			return
		cooldown_left[slot] = DASH_COOLDOWN_SEC
		dash_left[slot] = DASH_SEC
		knocks[slot] = heading.normalized() * DASH_SPEED
		_dash_hit[slot] = {}


func _tick(delta: float) -> void:
	# Alive-set cache (cleanup #467): computed once, shared by every helper
	# below that runs before this tick's own ring-outs are finalized.
	# _check_end() still calls _elim.in_slots(slots) fresh — it must see the roster
	# *after* _elim.flush() applies this tick's eliminations.
	var alive := _elim.in_slots(slots)
	for slot: int in alive:
		cooldown_left[slot] = maxf(float(cooldown_left[slot]) - delta, 0.0)
		dash_left[slot] = maxf(float(dash_left[slot]) - delta, 0.0)
		var knock: Vector2 = knocks[slot]
		positions[slot] += (move_dirs[slot] * MOVE_SPEED + knock) * delta
		knocks[slot] = knock.move_toward(Vector2.ZERO, KNOCK_DECAY * delta)
	_resolve_shoves(alive)
	_check_ringouts(alive)
	_elim.flush()
	_check_end()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		if not _elim.is_in(slot, slots):
			continue
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			snappedf(cooldown_left[slot], 0.01),
			1 if dash_left[slot] > 0.0 else 0,
		]
	return {"radius": PLATFORM_RADIUS, "players": players, "out": _elim.order}


## Timeout: everyone still on the platform ties ahead of the rung-out.
func _rank_players() -> Array:
	var survivors := _elim.in_slots(slots)
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	return placements + _elim.out_placements()


func _resolve_shoves(active: Array) -> void:
	for i in active.size():
		for j in range(i + 1, active.size()):
			var a: int = active[i]
			var b: int = active[j]
			var apart: Vector2 = positions[b] - positions[a]
			if apart.length() > PLAYER_RADIUS * 2.0:
				continue
			var axis := apart.normalized() if apart.length() > 0.001 else Vector2.RIGHT
			# Base contact repulsion, every overlapping tick: separates stacked
			# bodies and lands a light bump either way.
			knocks[a] -= axis * SHOVE_SPEED
			knocks[b] += axis * SHOVE_SPEED
			# The strong dash hit lands ONCE per victim per dash (#927): a dasher
			# plowing through must not re-apply the 3× shove every tick of the
			# overlap — that compounding flung victims clear off the disc in one
			# pass and emptied a 6-bot ring in ~1s.
			if float(dash_left[b]) > 0.0 and _mark_dash_hit(b, a):
				knocks[a] -= axis * _dash_bonus()
			if float(dash_left[a]) > 0.0 and _mark_dash_hit(a, b):
				knocks[b] += axis * _dash_bonus()


## The extra impulse a dash adds on top of a plain contact shove.
func _dash_bonus() -> float:
	return SHOVE_SPEED * (DASH_SHOVE_MULT - 1.0)


## Records that `shover`'s current dash has landed on `victim`. Returns true the
## first time this dash, false on repeat overlapping ticks — so the dash bonus
## is a single impulse, not a per-tick pile-up (#927).
func _mark_dash_hit(shover: int, victim: int) -> bool:
	var hits: Dictionary = _dash_hit[shover]
	if hits.has(victim):
		return false
	hits[victim] = true
	return true


func _check_ringouts(alive: Array) -> void:
	for slot: int in alive:
		if positions[slot].length() > PLATFORM_RADIUS:
			_elim.mark(slot)


func _check_end() -> void:
	if finished:
		return
	var survivors := _elim.in_slots(slots)
	if survivors.size() > 1:
		return
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	finish(placements + _elim.out_placements())
