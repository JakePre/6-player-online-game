class_name Gauntlet
extends MinigameBase
## The Gauntlet (M5-02, SPEC $6): last-player-standing finale on a shrinking
## circular platform with escalating telegraphed hazards. Server-side pure
## simulation via the Minigame Contract (M3-02); consumes FinaleShop loadouts
## (M5-01). Elimination order becomes the placements that M5-03 turns into
## final match ranking. Not a roster minigame — never registered in the
## catalog; the match framework enters it directly for the finale.

## Base 6-player platform; the start radius and shrink rate scale together with
## the head count (ADR 003) so a big lobby gets a proportionally bigger disc
## that still compresses to MIN_RADIUS in the same number of stages.
const START_RADIUS := 10.0
const MIN_RADIUS := 2.5
const SHRINK_STAGE_SEC := 15.0
const SHRINK_PER_STAGE := 1.5
## How far out the client telegraphs the doomed ring before a shrink actually
## lands (#583 — "the ring has to indicate the area being deleted before it
## gets deleted").
const SHRINK_WARN_SEC := 3.0

const MOVE_SPEED := 6.0
const SPEED_BOOST_MULT := 1.3
const PLAYER_RADIUS := 0.45
const PUSH_DISTANCE := 0.35

const RESPAWN_SEC := 3.0
## Spawn protection (#787): a short window after a round starts and after every
## respawn during which a player can't be KO'd or flung, so you never die the
## instant you appear (you can still move and act throughout).
const SPAWN_PROTECT_SEC := 2.0

## Weapon pickups (#584, owner decision 2026-07-06): battle axes drop on the
## platform; walk over one to grab it, action_primary swings it. A swing is a
## radial hit (it matches the client's spin animation, so no facing state) that
## launches everyone in reach away from the attacker — the launch itself never
## KOs, the rim does, via the existing falls check.
const WEAPON_SPAWN_INTERVAL := 6.0
const WEAPON_PICKUP_RADIUS := 0.8
## Swings per axe; it breaks on the last one.
const WEAPON_SWINGS := 3
const SWING_RANGE := 1.9
const SWING_COOLDOWN := 0.9
## Impulse magnitude and its exponential decay rate: total launch distance is
## KNOCKBACK / IMPULSE_DECAY = 5u — lethal near the rim, never from center
## (the platform starts at 10u+). Tuned 18 -> 30 (M12-01, #760): at 3u the axe
## converted ~2% of KOs across a 240-finale sim sweep; 5u lands ~9% without
## moving match durations.
const SWING_KNOCKBACK := 30.0
const IMPULSE_DECAY := 6.0
## Fraction of the live radius weapons may spawn within, so a fresh axe never
## sits on a rim about to be shed.
const WEAPON_SPAWN_BAND := 0.8

const HAZARD_WARN_SEC := 1.5
const HAZARD_START_INTERVAL := 6.0
const HAZARD_MIN_INTERVAL := 2.0
const HAZARD_START_RADIUS := 1.5
const HAZARD_MAX_RADIUS := 3.0
const HAZARD_RAMP_SEC := 90.0

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read, replacing magic-index prose with a checkable
## contract. Array SHAPE on the wire is unchanged — additive only.
const PS_X := 0
const PS_Y := 1
const PS_LIVES := 2
const PS_RESPAWN := 3
const PS_ARMED := 4
const PS_SWING_SEQ := 5
const PS_HIT_SEQ := 6
## Seconds of spawn protection remaining, 0 when vulnerable (#787).
const PS_INVULN := 7
const PS_COUNT := 8

const HZ_X := 0
const HZ_Y := 1
const HZ_RADIUS := 2
const HZ_WARN := 3
const HZ_COUNT := 4

const WP_X := 0
const WP_Y := 1
const WP_COUNT := 2

var radius := START_RADIUS
## Per-instance platform tuning (base at ≤6 players, scaled up beyond).
var start_radius := START_RADIUS
var shrink_per_stage := SHRINK_PER_STAGE
var positions := {}
var move_dirs := {}
var lives := {}
var shields := {}
var speed_boosts := {}
var sabotage_tokens := {}
var grudges_left := {}
## Active hazards, each {pos: Vector2, radius: float, warn_left: float}.
var hazards: Array[Dictionary] = []
## Slots in the order they were fully eliminated; simultaneous KOs share an
## inner array (a tie group).
var elimination_order: Array = []
## Floor axes waiting to be grabbed (#584).
var weapons: Array[Vector2] = []
## slot -> swings left on the held axe; absent = unarmed.
var armed := {}
## Monotonic per-slot counters so the view animates each swing / each hit taken
## exactly once, however snapshots are sampled.
var swing_seq := {}
var hit_seq := {}

## Balance telemetry (#706): cause -> count of life-losing KOs. Shield saves
## are excluded (no life lost, nothing to attribute) — this answers whether
## axes are pulling their weight against hazards and the shrinking rim, the
## #584 weapons-tuning question the M12-01 balance pass needs data for.
## Causes: "hazard" (a blast catches you), "rim" (you walked/were pushed off
## on your own), "axe_launch" (a swing's knockback carried you off the rim).
var ko_causes := {}
## Attacker slot -> axe_launch KOs credited to them.
var axe_kills := {}

var _respawn_left := {}
## slot -> seconds of spawn protection remaining (#787); absent = vulnerable.
var _invuln_left := {}
var _hazard_accum := 0.0
var _weapon_accum := 0.0
var _stage_accum := 0.0
var _pending_elims: Array = []
## slot -> decaying knockback velocity from axe hits.
var _impulses := {}
## slot -> the attacker whose swing produced the live entry in _impulses,
## mirrored 1:1 with it so a rim fall mid-launch can be attributed to
## "axe_launch" instead of a plain "rim" walk-off (#706).
var _impulse_attacker := {}
var _swing_cooldowns := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"gauntlet",
				"controls":
				"Move — WASD / left stick · Swing axe — Space / pad A · Sabotage — E / pad X",
				"name": "The Gauntlet",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 180.0,
				"rules":
				(
					"Last one standing wins the match! Grab an axe and swing rivals off"
					+ " the shrinking platform — hazards rain down either way."
				),
			}
		)
	)


## Start radius for `count` players: grows with the sqrt of the head count
## (MinigameScaling) so per-player space stays roughly constant, never below
## the tuned 6-player base.
static func start_radius_for(count: int) -> float:
	return START_RADIUS * sqrt(MinigameScaling.growth(count))


## Shrink-per-stage scaled by the same factor as the start radius, so a bigger
## platform still reaches MIN_RADIUS in the same number of stages — the squeeze
## keeps its wall-clock pacing regardless of head count.
static func shrink_per_stage_for(count: int) -> float:
	return SHRINK_PER_STAGE * sqrt(MinigameScaling.growth(count))


func _setup() -> void:
	start_radius = start_radius_for(slots.size())
	shrink_per_stage = shrink_per_stage_for(slots.size())
	radius = start_radius
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * start_radius * 0.6
		move_dirs[slots[i]] = Vector2.ZERO
		lives[slots[i]] = 1
		_invuln_left[slots[i]] = SPAWN_PROTECT_SEC  # can't be KO'd the instant the round opens (#787)
		shields[slots[i]] = false
		speed_boosts[slots[i]] = false
		sabotage_tokens[slots[i]] = 0
		grudges_left[slots[i]] = 0
		swing_seq[slots[i]] = 0
		hit_seq[slots[i]] = 0


## `shop_loadouts` is FinaleShop.loadouts(): {slot: {"items": {...}, ...}}.
## Call after setup(); slots absent from the shop keep the base loadout.
func apply_loadouts(shop_loadouts: Dictionary) -> void:
	for slot: int in shop_loadouts:
		if slot not in slots:
			continue
		var items: Dictionary = shop_loadouts[slot].get("items", {})
		lives[slot] = 1 + int(items.get(&"extra_life", 0))
		shields[slot] = int(items.get(&"shield", 0)) > 0
		speed_boosts[slot] = int(items.get(&"speed_boost", 0)) > 0
		sabotage_tokens[slot] = int(items.get(&"sabotage_token", 0))


func _handle_input(slot: int, data: Dictionary) -> void:
	if data.has("grudge"):
		_handle_grudge(slot, data.grudge)
		return
	if not _is_alive(slot) or _respawn_left.has(slot):
		return
	if data.has("sabotage"):
		_handle_sabotage(slot, data.sabotage)
		return
	if data.has("swing"):
		_handle_swing(slot)
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	_tick_shrink(delta)
	_tick_respawns(delta)
	_tick_invuln(delta)
	_move_players(delta)
	_apply_impulses(delta)
	_resolve_pushes()
	_tick_weapons(delta)
	_tick_hazards(delta)
	_check_falls()
	_flush_eliminations()
	_check_end()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			int(lives[slot]),
			snappedf(_respawn_left.get(slot, 0.0), 0.01),
			# #584 weapon state: swings left on the held axe (0 = unarmed) and
			# the monotonic swing/hit counters the view animates from.
			int(armed.get(slot, 0)),
			int(swing_seq[slot]),
			int(hit_seq[slot]),
			# Spawn-protection remaining (#787), so the view can shimmer the rig.
			snappedf(_invuln_left.get(slot, 0.0), 0.01),
		]
	var hazard_list: Array = []
	for hazard in hazards:
		var pos: Vector2 = hazard.pos
		(
			hazard_list
			. append(
				[
					snappedf(pos.x, 0.01),
					snappedf(pos.y, 0.01),
					snappedf(hazard.radius, 0.01),
					snappedf(hazard.warn_left, 0.01),
				]
			)
		)
	var weapon_list: Array = []
	for pos in weapons:
		weapon_list.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)])
	return {
		"radius": snappedf(radius, 0.01),
		# Seconds until the next shrink stage lands — the client derives the
		# ring telegraph from this rather than the sim exposing new state.
		"shrink_in": snappedf(SHRINK_STAGE_SEC - _stage_accum, 0.01),
		"players": players,
		"hazards": hazard_list,
		"weapons": weapon_list,
	}


## Extends the base placements/pickup_coins/team_mode with the KO-cause
## breakdown (#706) so the playtest telemetry can carry it alongside
## placements without a separate reporting path.
func get_results() -> Dictionary:
	var results := super.get_results()
	results["ko_causes"] = ko_causes.duplicate()
	results["axe_kills"] = axe_kills.duplicate()
	return results


## Timeout fallback: survivors (grouped by lives left, more first), then the
## eliminated in reverse KO order.
func _rank_players() -> Array:
	var by_lives := {}
	for slot: int in slots:
		if _is_alive(slot):
			var count: int = lives[slot]
			if not by_lives.has(count):
				by_lives[count] = []
			by_lives[count].append(slot)
	var counts := by_lives.keys()
	counts.sort()
	counts.reverse()
	var placements: Array = []
	for count: int in counts:
		placements.append(by_lives[count])
	return placements + _eliminated_placements()


# --- Phase internals ----------------------------------------------------------


func _tick_shrink(delta: float) -> void:
	_stage_accum += delta
	while _stage_accum >= SHRINK_STAGE_SEC:
		_stage_accum -= SHRINK_STAGE_SEC
		radius = maxf(radius - shrink_per_stage, MIN_RADIUS)


func _tick_respawns(delta: float) -> void:
	for slot: int in _respawn_left.keys():
		_respawn_left[slot] -= delta
		if _respawn_left[slot] <= 0.0:
			_respawn_left.erase(slot)
			positions[slot] = Vector2.ZERO
			move_dirs[slot] = Vector2.ZERO
			# Reappear protected, so a hazard/axe can't KO you the frame you're back.
			_invuln_left[slot] = SPAWN_PROTECT_SEC


func _tick_invuln(delta: float) -> void:
	for slot: int in _invuln_left.keys():
		_invuln_left[slot] -= delta
		if _invuln_left[slot] <= 0.0:
			_invuln_left.erase(slot)


## Spawn-protected right now (#787): immune to KO and to swing knockback.
func _is_protected(slot: int) -> bool:
	return _invuln_left.has(slot)


func _move_players(delta: float) -> void:
	for slot: int in _active_slots():
		var speed := MOVE_SPEED * (SPEED_BOOST_MULT if speed_boosts[slot] else 1.0)
		positions[slot] += move_dirs[slot] * speed * delta


## Axe-hit knockback rides a decaying velocity so a launch is a fling, not a
## teleport — and the rim KO comes from the existing falls check, untouched.
func _apply_impulses(delta: float) -> void:
	for slot: int in _impulses.keys():
		if not _is_alive(slot) or _respawn_left.has(slot):
			_impulses.erase(slot)
			_impulse_attacker.erase(slot)
			continue
		positions[slot] += _impulses[slot] * delta
		_impulses[slot] *= exp(-IMPULSE_DECAY * delta)
		if (_impulses[slot] as Vector2).length() < 0.1:
			_impulses.erase(slot)
			_impulse_attacker.erase(slot)


## Spawns floor axes on a cadence (capped by head count) and arms whoever walks
## over one — automatic, no button, and never while already armed.
func _tick_weapons(delta: float) -> void:
	for slot: int in _swing_cooldowns.keys():
		_swing_cooldowns[slot] -= delta
		if _swing_cooldowns[slot] <= 0.0:
			_swing_cooldowns.erase(slot)
	_weapon_accum += delta
	if _weapon_accum >= WEAPON_SPAWN_INTERVAL and weapons.size() < _weapon_cap():
		_weapon_accum = 0.0
		var pos := Vector2(rng.randf_range(-radius, radius), rng.randf_range(-radius, radius))
		weapons.append(pos.limit_length(radius * WEAPON_SPAWN_BAND))
	for i in range(weapons.size() - 1, -1, -1):
		for slot: int in _active_slots():
			if armed.has(slot):
				continue
			if positions[slot].distance_to(weapons[i]) <= WEAPON_PICKUP_RADIUS:
				armed[slot] = WEAPON_SWINGS
				weapons.remove_at(i)
				break


## Concurrent floor-axe cap: one per six alive players, at least one.
func _weapon_cap() -> int:
	return 1 + _alive_slots().size() / 6


## A swing is a radial strike: everyone in reach is flung away from the
## attacker. Shields absorb it (and break); armed victims drop their axe on the
## spot — attacking axe-carriers is how you disarm them.
func _handle_swing(slot: int) -> void:
	if not armed.has(slot) or _swing_cooldowns.has(slot):
		return
	_swing_cooldowns[slot] = SWING_COOLDOWN
	armed[slot] = int(armed[slot]) - 1
	if int(armed[slot]) <= 0:
		armed.erase(slot)  # the axe breaks on its last swing
	swing_seq[slot] = int(swing_seq[slot]) + 1
	for victim: int in _active_slots():
		if victim == slot:
			continue
		# Spawn-protected players aren't flung or staggered (#787).
		if _is_protected(victim):
			continue
		var apart: Vector2 = positions[victim] - positions[slot]
		if apart.length() > SWING_RANGE:
			continue
		if shields[victim]:
			shields[victim] = false
			continue
		var axis := apart.normalized() if apart.length() > 0.001 else Vector2.RIGHT
		_impulses[victim] = _impulses.get(victim, Vector2.ZERO) + axis * SWING_KNOCKBACK
		_impulse_attacker[victim] = slot
		hit_seq[victim] = int(hit_seq[victim]) + 1
		if armed.has(victim):
			armed.erase(victim)
			weapons.append(positions[victim])


func _resolve_pushes() -> void:
	var active := _active_slots()
	for i in active.size():
		for j in range(i + 1, active.size()):
			var a: int = active[i]
			var b: int = active[j]
			var apart: Vector2 = positions[b] - positions[a]
			if apart.length() > PLAYER_RADIUS * 2.0:
				continue
			var axis := apart.normalized() if apart.length() > 0.001 else Vector2.RIGHT
			positions[a] -= axis * PUSH_DISTANCE
			positions[b] += axis * PUSH_DISTANCE


func _tick_hazards(delta: float) -> void:
	_hazard_accum += delta
	if _hazard_accum >= _hazard_interval():
		_hazard_accum = 0.0
		var pos := Vector2(rng.randf_range(-radius, radius), rng.randf_range(-radius, radius))
		_spawn_hazard(pos.limit_length(radius))
	for i in range(hazards.size() - 1, -1, -1):
		hazards[i].warn_left -= delta
		if hazards[i].warn_left > 0.0:
			continue
		for slot: int in _active_slots():
			if positions[slot].distance_to(hazards[i].pos) <= hazards[i].radius:
				_knock_out(slot, "hazard")
		hazards.remove_at(i)


func _check_falls() -> void:
	for slot: int in _active_slots():
		if positions[slot].length() <= radius:
			continue
		# A rim fall while a swing's knockback is still live on this slot is
		# an axe kill, not a plain walk-off (#706) — credited to the swinger.
		var attacker: int = _impulse_attacker.get(slot, -1)
		if attacker != -1:
			_knock_out(slot, "axe_launch", attacker)
		else:
			_knock_out(slot, "rim")


func _check_end() -> void:
	if finished:
		return
	var alive := _alive_slots()
	if alive.size() > 1:
		return
	var placements: Array = []
	if not alive.is_empty():
		placements.append(alive)
	finish(placements + _eliminated_placements())


## `cause` is "hazard", "rim", or "axe_launch" (#706 balance telemetry);
## `attacker` is the swinger credited for an axe_launch, else unused.
func _knock_out(slot: int, cause: String, attacker: int = -1) -> void:
	# Spawn-protected players shrug it off entirely — no life lost, no shield
	# spent (#787). Nothing to attribute, so this returns before telemetry too.
	if _is_protected(slot):
		return
	# A KO (or shield save) always ends the launch and drops the axe with them.
	_impulses.erase(slot)
	_impulse_attacker.erase(slot)
	armed.erase(slot)
	if shields[slot]:
		# The bought shield absorbs one KO on the spot: no life lost, pulled
		# back to safety instead of respawning — nothing to attribute.
		shields[slot] = false
		positions[slot] = Vector2.ZERO
		move_dirs[slot] = Vector2.ZERO
		return
	ko_causes[cause] = int(ko_causes.get(cause, 0)) + 1
	if cause == "axe_launch" and attacker != -1:
		axe_kills[attacker] = int(axe_kills.get(attacker, 0)) + 1
	lives[slot] = int(lives[slot]) - 1
	if lives[slot] > 0:
		_respawn_left[slot] = RESPAWN_SEC
		positions[slot] = Vector2.ZERO
		move_dirs[slot] = Vector2.ZERO
		return
	# Eliminated. Slots KO'd in the same tick share one tie group (SPEC $6
	# ranking is elimination order; a shared blast must not order them by
	# iteration accident).
	_pending_elims.append(slot)
	grudges_left[slot] = 1


func _flush_eliminations() -> void:
	if not _pending_elims.is_empty():
		elimination_order.append(_pending_elims.duplicate())
		_pending_elims.clear()


func _handle_sabotage(slot: int, target: Variant) -> void:
	if int(sabotage_tokens[slot]) <= 0 or not _valid_target(target):
		return
	sabotage_tokens[slot] = int(sabotage_tokens[slot]) - 1
	_spawn_hazard(_target_pos(target))


func _handle_grudge(slot: int, target: Variant) -> void:
	if _is_alive(slot) or int(grudges_left.get(slot, 0)) <= 0 or not _valid_target(target):
		return
	grudges_left[slot] = 0
	_spawn_hazard(_target_pos(target))


func _spawn_hazard(pos: Vector2) -> void:
	hazards.append(
		{"pos": pos.limit_length(radius), "radius": _hazard_radius(), "warn_left": HAZARD_WARN_SEC}
	)


func _hazard_interval() -> float:
	return lerpf(HAZARD_START_INTERVAL, HAZARD_MIN_INTERVAL, _escalation())


func _hazard_radius() -> float:
	return lerpf(HAZARD_START_RADIUS, HAZARD_MAX_RADIUS, _escalation())


func _escalation() -> float:
	return clampf(elapsed / HAZARD_RAMP_SEC, 0.0, 1.0)


func _valid_target(target: Variant) -> bool:
	return target is Array and target.size() == 2


func _target_pos(target: Array) -> Vector2:
	return Vector2(float(target[0]), float(target[1]))


func _is_alive(slot: int) -> bool:
	return slot in slots and int(lives.get(slot, 0)) > 0


func _alive_slots() -> Array:
	return slots.filter(_is_alive)


## Alive and on the platform (not waiting out a respawn).
func _active_slots() -> Array:
	return slots.filter(
		func(slot: int) -> bool: return _is_alive(slot) and not _respawn_left.has(slot)
	)


func _eliminated_placements() -> Array:
	var placements := elimination_order.duplicate(true)
	placements.reverse()
	return placements
