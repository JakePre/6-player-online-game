class_name RumbleRing
extends MinigameBase
## Rumble Ring (M10-17, PHASE2.md $4 #34, owner-requested; #1066 guard
## stamina): arena brawler. Quick swings chip 1 HP with light knockback;
## holding guard blocks damage but DRAINS STAMINA (and you crawl) — guarded
## hits still shove you a little and bite the meter, and an empty meter
## breaks the guard and staggers you wide open. Releasing a full guard fires
## a charged smash — 2 HP and a big radial shove. KOs score for the attacker
## and scatter the victim's coins onto the floor for anyone to grab; victims
## respawn with brief invulnerability. Most KO points wins. Server-side
## simulation only.

const ARENA_HALF := 8.0
const MOVE_SPEED := 6.0
const GUARD_SPEED_MULT := 0.35
const PLAYER_RADIUS := 0.45

const MAX_HP := 3
## Generous melee (#257): commits at melee distance should connect.
const SWING_RANGE := 1.8
## Full frontal 180° arc — behind-the-back still whiffs.
const SWING_ARC_DOT := 0.0
const SWING_KNOCKBACK := 1.2
const SWING_COOLDOWN_SEC := 0.6
const SMASH_CHARGE_SEC := 0.8
const SMASH_RANGE := 2.2
const SMASH_KNOCKBACK := 3.0
const SMASH_COOLDOWN_SEC := 2.5
const KO_POINTS := 3
const KO_COIN_SCATTER := 3
const PICKUP_RADIUS := 0.8
const RESPAWN_INVULN_SEC := 1.5
## Respawns jitter within this radius of center (M15, ADR 003): at a fuller
## ring, KOs land more often, so more respawns land in the same tick — a fixed
## dead-center point would stack them exactly on top of each other.
const RESPAWN_JITTER_RADIUS := 1.2
## Guard is a resource now (#1066, owner playtest: full-time guard was the
## meta — approved fix: stamina + chip). The meter holds this many seconds of
## guarding, refills at GUARD_REGEN_MULT of the drain rate while down, and a
## guarded hit still lands CHIP_KNOCKBACK_MULT of its shove plus a stamina
## bite (CHIP_STAMINA_PER_HP per HP the hit would have dealt) — so attacking
## a turtle actively melts the shell. Empty = guard break + a long stagger.
const GUARD_STAMINA_SEC := 2.5
const GUARD_REGEN_MULT := 0.6
const CHIP_KNOCKBACK_MULT := 0.25
const CHIP_STAMINA_PER_HP := 0.5
const GUARD_BREAK_STAGGER_SEC := 1.2
const STAGGER_SPEED_MULT := 0.3

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_HP := 2
const PS_POINTS := 3
const PS_GUARDING := 4
const PS_INVULN := 5
const PS_FACING_X := 6
const PS_FACING_Y := 7
## Appended (#1066): guard stamina as a 0..1 fraction of GUARD_STAMINA_SEC.
const PS_STAMINA := 8
const PS_COUNT := 9
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. Validated by test_snapshot_schema against get_snapshot().
const PLAYER_SCHEMA := [
	TYPE_FLOAT,
	TYPE_FLOAT,
	TYPE_INT,
	TYPE_INT,
	TYPE_INT,
	TYPE_FLOAT,
	TYPE_FLOAT,
	TYPE_FLOAT,
	TYPE_FLOAT,
]

const CN_X := 0
const CN_Y := 1

var positions := {}
var move_dirs := {}
var facings := {}
var hp := {}
var points := {}
var collected := {}
var guarding := {}
var swing_cooldown := {}
var smash_cooldown := {}
var invuln_left := {}
## Floor coins scattered by KOs, each a Vector2.
var coins: Array[Vector2] = []
## Set for one tick after each event so the view can flash it.
var last_events: Array[Dictionary] = []

## #1066: seconds of guard left (0..GUARD_STAMINA_SEC) and stagger remaining.
var stamina := {}
var stagger := {}

var _guard_held_sec := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"rumble_ring",
				"controls":
				"Move — WASD/stick · Swing — Space/Ⓐ · Guard/Smash — E/Ⓧ (hold, release)",
				# Device-aware (#608): the buttons read as what the player holds.
				"control_hints":
				[
					"Move — WASD/stick · Swing — ",
					{"action": &"action_primary"},
					" · Guard/Smash — ",
					{"action": &"action_secondary"},
					" (hold, release)",
				],
				# Structured spec (#832/#844): move + swing + a hold-release guard/smash.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"verb": "Swing", "input": &"action_primary"},
					{
						"verb": "Guard / Smash",
						"input": &"action_secondary",
						"modifier": "hold, release",
					},
				],
				"name": "Rumble Ring",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				# 8 by design (ADR 003): the ring stays this fixed size on purpose —
				# it's a melee brawl, not a crowd game.
				"max_players": 8,
				"duration_sec": 60.0,
				"rules":
				(
					"Brawl! Guard blocks but burns stamina — run dry and you're staggered "
					+ "wide open. Release a full guard to SMASH. KOs score."
				),
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		var slot: int = slots[i]
		positions[slot] = Vector2(cos(angle), sin(angle)) * ARENA_HALF * 0.6
		move_dirs[slot] = Vector2.ZERO
		facings[slot] = Vector2(-cos(angle), -sin(angle))
		hp[slot] = MAX_HP
		points[slot] = 0
		collected[slot] = 0
		guarding[slot] = false
		swing_cooldown[slot] = 0.0
		smash_cooldown[slot] = 0.0
		invuln_left[slot] = 0.0
		_guard_held_sec[slot] = 0.0
		stamina[slot] = GUARD_STAMINA_SEC
		stagger[slot] = 0.0


func _handle_input(slot: int, data: Dictionary) -> void:
	# A broken guard leaves you staggered (#1066): no swinging, no re-guarding
	# until it wears off — movement crawls via the _tick speed multiplier.
	if data.has("attack"):
		if float(stagger[slot]) <= 0.0:
			_swing(slot)
		return
	if data.has("guard"):
		if float(stagger[slot]) <= 0.0 or not bool(data.guard):
			_set_guard(slot, bool(data.guard))
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if dir.length() > 0.1:
		facings[slot] = dir.normalized()


func _tick(delta: float) -> void:
	last_events.clear()
	for slot: int in slots:
		swing_cooldown[slot] = maxf(float(swing_cooldown[slot]) - delta, 0.0)
		smash_cooldown[slot] = maxf(float(smash_cooldown[slot]) - delta, 0.0)
		invuln_left[slot] = maxf(float(invuln_left[slot]) - delta, 0.0)
		stagger[slot] = maxf(float(stagger[slot]) - delta, 0.0)
		if guarding[slot]:
			_guard_held_sec[slot] = float(_guard_held_sec[slot]) + delta
			# Guarding spends the meter (#1066); running dry breaks the shell.
			stamina[slot] = float(stamina[slot]) - delta
			if float(stamina[slot]) <= 0.0:
				_break_guard(slot)
		else:
			stamina[slot] = minf(float(stamina[slot]) + GUARD_REGEN_MULT * delta, GUARD_STAMINA_SEC)
		var speed_mult := 1.0
		if guarding[slot]:
			speed_mult = GUARD_SPEED_MULT
		elif float(stagger[slot]) > 0.0:
			speed_mult = STAGGER_SPEED_MULT
		var speed := MOVE_SPEED * speed_mult
		var pos: Vector2 = positions[slot] + move_dirs[slot] * speed * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
	_collect_coins()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		var facing: Vector2 = facings[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			int(hp[slot]),
			int(points[slot]),
			1 if guarding[slot] else 0,
			snappedf(invuln_left[slot], 0.01),
			snappedf(facing.x, 0.01),
			snappedf(facing.y, 0.01),
			snappedf(clampf(float(stamina[slot]) / GUARD_STAMINA_SEC, 0.0, 1.0), 0.01),
		]
	var coin_list: Array = []
	for coin in coins:
		coin_list.append([snappedf(coin.x, 0.01), snappedf(coin.y, 0.01)])
	return {"players": players, "coins": coin_list, "events": last_events.duplicate(true)}


## Most KO points wins, ties grouped; scattered coins collected double as
## capped pickup coins (SPEC $5).
func _rank_players() -> Array:
	var by_points := {}
	for slot: int in slots:
		var score: int = points[slot]
		if not by_points.has(score):
			by_points[score] = []
		by_points[score].append(slot)
	var totals := by_points.keys()
	totals.sort()
	totals.reverse()
	var placements: Array = []
	for total: int in totals:
		placements.append(by_points[total])
	_pickup_coins = collected.duplicate()
	return placements


func _swing(slot: int) -> void:
	if guarding[slot] or float(swing_cooldown[slot]) > 0.0:
		return
	swing_cooldown[slot] = SWING_COOLDOWN_SEC
	last_events.append({"type": "swing", "slot": slot})
	var facing: Vector2 = facings[slot]
	for other: int in slots:
		if other == slot:
			continue
		var to_other: Vector2 = positions[other] - positions[slot]
		if to_other.length() > SWING_RANGE:
			continue
		if to_other.normalized().dot(facing) < SWING_ARC_DOT:
			continue
		_damage(other, slot, 1, facing * SWING_KNOCKBACK)


func _set_guard(slot: int, on: bool) -> void:
	if on == bool(guarding[slot]):
		return
	if on:
		guarding[slot] = true
		_guard_held_sec[slot] = 0.0
		return
	guarding[slot] = false
	# Releasing a full charge fires the smash (if off cooldown).
	if float(_guard_held_sec[slot]) >= SMASH_CHARGE_SEC and float(smash_cooldown[slot]) <= 0.0:
		_smash(slot)


## An empty meter drops the guard the hard way (#1066): no smash on the way
## down (that release is the player's, not the break's), a long stagger, and
## the meter pinned at zero to regen from scratch.
func _break_guard(slot: int) -> void:
	guarding[slot] = false
	stamina[slot] = 0.0
	stagger[slot] = GUARD_BREAK_STAGGER_SEC
	last_events.append({"type": "guard_break", "slot": slot})


func _smash(slot: int) -> void:
	smash_cooldown[slot] = SMASH_COOLDOWN_SEC
	last_events.append({"type": "smash", "slot": slot})
	for other: int in slots:
		if other == slot:
			continue
		var to_other: Vector2 = positions[other] - positions[slot]
		if to_other.length() > SMASH_RANGE:
			continue
		var axis := to_other.normalized() if to_other.length() > 0.001 else Vector2.RIGHT
		_damage(other, slot, 2, axis * SMASH_KNOCKBACK)


func _damage(victim: int, attacker: int, amount: int, knockback: Vector2) -> void:
	if float(invuln_left[victim]) > 0.0:
		return
	if guarding[victim]:
		# Chip (#1066): the block holds, but a quarter of the shove leaks
		# through and the hit bites the meter — beating on a turtle cracks it.
		var chipped: Vector2 = positions[victim] + knockback * CHIP_KNOCKBACK_MULT
		positions[victim] = chipped.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
		stamina[victim] = float(stamina[victim]) - CHIP_STAMINA_PER_HP * float(amount)
		last_events.append({"type": "blocked", "slot": victim})
		if float(stamina[victim]) <= 0.0:
			_break_guard(victim)
		return
	var pos: Vector2 = positions[victim] + knockback
	positions[victim] = pos.clamp(
		Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
	)
	hp[victim] = int(hp[victim]) - amount
	last_events.append({"type": "hit", "slot": victim})
	if int(hp[victim]) > 0:
		return
	# KO: attacker scores, the victim's pockets hit the floor.
	points[attacker] = int(points[attacker]) + KO_POINTS
	last_events.append({"type": "ko", "slot": victim, "by": attacker})
	for _i in KO_COIN_SCATTER:
		var offset := Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		coins.append(
			((positions[victim] as Vector2) + offset).clamp(
				Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
			)
		)
	hp[victim] = MAX_HP
	guarding[victim] = false
	invuln_left[victim] = RESPAWN_INVULN_SEC
	positions[victim] = _respawn_position()


## A small random offset from center (M15, ADR 003): fuller rings KO more
## often, so several respawns can land the same tick — jittering keeps them
## from stacking on the exact same point while they're still invulnerable.
## Polar (not per-axis) so the offset never exceeds RESPAWN_JITTER_RADIUS.
func _respawn_position() -> Vector2:
	var angle := rng.randf_range(0.0, TAU)
	var radius := rng.randf_range(0.0, RESPAWN_JITTER_RADIUS)
	return Vector2(cos(angle), sin(angle)) * radius


func _collect_coins() -> void:
	for i in range(coins.size() - 1, -1, -1):
		for slot: int in slots:
			if positions[slot].distance_to(coins[i]) <= PICKUP_RADIUS:
				collected[slot] = int(collected[slot]) + 1
				coins.remove_at(i)
				break
