class_name BulletWaltz
extends MinigameBase
## Bullet Waltz (M10-18, PHASE2.md $4 #35, owner-requested): bullet-hell
## survival. A center turret fires seeded, escalating patterns — spirals,
## ring bursts, and shots aimed at the current leader. One hit KOs you;
## last standing wins, and grazing (a bullet skimming past) banks pickup
## coins so brave dodging pays before the win. Server-side simulation only.

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.4
## Bullets die past this multiple of the play radius (scaled per lobby in _setup).
const BULLET_RANGE_FACTOR := 1.6
const BULLET_RANGE := ARENA_HALF * BULLET_RANGE_FACTOR
const BULLET_RADIUS := 0.25
## A bullet passing within this ring (but not hitting) is a graze.
const GRAZE_RADIUS := 1.1
const GRAZE_COIN := 1
## Waltz Bomb (#959): one panic clear per round. action_primary detonates a
## radial bloom that culls every bullet within this radius of the caster — the
## bullet-hell escape hatch. Spend it early or hold it for the dense finale.
const WALTZ_BOMB_RADIUS := 4.0
## Escalation: pattern cadence and bullet speed ramp over the round.
const RAMP_SEC := 50.0
## Quiet opening (#208): no volleys until players have had a beat to read
## the arena — the first pattern otherwise landed before anyone had moved.
const SPAWN_GRACE_SEC := 1.75
const FIRE_INTERVAL_START := 1.4
const FIRE_INTERVAL_MIN := 0.55
const BULLET_SPEED_START := 4.0
const BULLET_SPEED_MAX := 7.5
const SPIRAL_ARMS := 4
const RING_BULLETS := 10

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_GRAZE := 2
## 1 while the player still holds their once-per-round Waltz Bomb, else 0 —
## drives the nameplate ready pip and the spend bloom (a 1->0 transition), and
## lets a bot brain know whether it can still panic-clear (#959).
const PS_BOMB := 3
const PS_COUNT := 4
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. Validated by test_snapshot_schema against get_snapshot().
const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_INT]

const BU_X := 0
const BU_Y := 1

var positions := {}
var move_dirs := {}
## Active bullets, each {pos: Vector2, vel: Vector2}.
var bullets: Array[Dictionary] = []
var graze_coins := {}
## Slot -> true while its once-per-round Waltz Bomb is unspent (#959).
var bomb_ready := {}
## Slots in KO order; same-tick KOs share a tie group.
var ko_order: Array = []

## Play area + bullet range scale with the lobby (M15, ADR 003 F4); the turret
## storm does not — a crowd just gets more floor to dodge on. At <=6 these equal
## the consts above, leaving the tuned small-lobby game untouched.
var _play_half := ARENA_HALF
var _bullet_range := BULLET_RANGE

var _fire_accum := 0.0
var _spiral_angle := 0.0
var _pattern_index := 0
var _pending_kos: Array = []
## Bullets currently inside each slot's graze ring, so one pass counts once.
var _grazing := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"bullet_waltz",
				"controls": "Move — WASD / left stick",
				"name": "Bullet Waltz",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 60.0,
				"rules":
				(
					"Dodge the storm — one hit and you're out! Skim bullets for coins, "
					+ "and spend your one Waltz Bomb to clear the crush."
				),
				# Structured spec (#832/#844): move cluster + the #959 panic bomb.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{
						"verb": "Waltz Bomb",
						"input": &"action_primary",
						"note": "one per round — clears nearby bullets",
					},
				],
			}
		)
	)


func _setup() -> void:
	# Grow the dodge floor (and the range bullets must clear) with the lobby so a
	# crowd isn't shoulder-to-shoulder (M15, ADR 003 F4); the turret storm itself
	# is player-count-independent, so it is deliberately NOT scaled. At <=6 these
	# equal the consts above and the tuned small-lobby game is unchanged.
	_play_half = MinigameScaling.arena_half(ARENA_HALF, slots.size())
	_bullet_range = _play_half * BULLET_RANGE_FACTOR
	var spawns := SpawnLayout.ring_positions(slots.size(), _play_half * 0.6)
	for i in slots.size():
		positions[slots[i]] = spawns[i]
		move_dirs[slots[i]] = Vector2.ZERO
		graze_coins[slots[i]] = 0
		bomb_ready[slots[i]] = true
		_grazing[slots[i]] = []
	# Negative accumulator = the opening grace before the first volley.
	_fire_accum = -SPAWN_GRACE_SEC


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _is_in(slot):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if data.get("bomb", false):
		_trigger_bomb(slot)


## Waltz Bomb (#959): the once-per-round panic clear. Culls every bullet inside
## the bloom radius around the caster and spends the charge; a no-op once spent.
## Bullets are removed mid-array the same way expiry and hits already thin the
## field, so the loose graze index-tracking needs no special handling here.
func _trigger_bomb(slot: int) -> void:
	if not bomb_ready.get(slot, false):
		return
	bomb_ready[slot] = false
	var center: Vector2 = positions[slot]
	for i in range(bullets.size() - 1, -1, -1):
		if (bullets[i].pos as Vector2).distance_to(center) <= WALTZ_BOMB_RADIUS:
			bullets.remove_at(i)


func _tick(delta: float) -> void:
	# Alive-set cache (cleanup #467): computed once, shared by the movement
	# loop, _fire_pattern() (only _fire_aimed() reads it), and
	# _resolve_hits_and_grazes() — none of these touch ko_order before this
	# point in the tick, so they all see the same pre-elimination roster.
	# _check_end() still calls _in_slots() fresh — it must see the roster
	# *after* this tick's _pending_kos are flushed into ko_order above.
	var alive := _in_slots()
	for slot: int in alive:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-_play_half, -_play_half), Vector2(_play_half, _play_half)
		)
	_fire_accum += delta
	if _fire_accum >= fire_interval():
		_fire_accum = 0.0
		_fire_pattern(alive)
	_move_bullets(delta)
	_resolve_hits_and_grazes(alive)
	if not _pending_kos.is_empty():
		ko_order.append(_pending_kos.duplicate())
		_pending_kos.clear()
	_check_end()


func fire_interval() -> float:
	return lerpf(FIRE_INTERVAL_START, FIRE_INTERVAL_MIN, _escalation())


func bullet_speed() -> float:
	return lerpf(BULLET_SPEED_START, BULLET_SPEED_MAX, _escalation())


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in _in_slots():
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			int(graze_coins[slot]),
			int(bomb_ready.get(slot, false)),
		]
	var bullet_list: Array = []
	for bullet in bullets:
		var pos: Vector2 = bullet.pos
		bullet_list.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)])
	return {"players": players, "bullets": bullet_list, "out": ko_order.duplicate(true)}


## Survivors rank ahead of the KO'd (who rank in reverse elimination order).
## Within each tier — the survivor pack and every same-tick KO group — graze
## score breaks the tie (#959): dancing close to death out-places corner-hiding,
## which is exactly the incentive #926's camping bots were missing. Graze coins
## also double as capped pickup coins (SPEC $5).
func _rank_players() -> Array:
	_pickup_coins = graze_coins.duplicate()
	var placements: Array = []
	var survivors := _in_slots()
	if not survivors.is_empty():
		placements.append_array(_split_by_graze(survivors))
	var out := ko_order.duplicate(true)
	out.reverse()
	for group: Array in out:
		placements.append_array(_split_by_graze(group))
	return placements


## Orders a tie group by graze score (highest first) and splits it into
## sub-tiers at each distinct score; equal graze stays tied. Slot number is the
## final tiebreak so the ordering is deterministic run to run (#959).
func _split_by_graze(group: Array) -> Array:
	var ranked := group.duplicate()
	ranked.sort_custom(
		func(a: int, b: int) -> bool:
			var ga := int(graze_coins.get(a, 0))
			var gb := int(graze_coins.get(b, 0))
			return ga > gb if ga != gb else a < b
	)
	var tiers: Array = []
	var current: Array = []
	var current_graze := -1
	for slot: int in ranked:
		var g := int(graze_coins.get(slot, 0))
		if g != current_graze and not current.is_empty():
			tiers.append(current)
			current = []
		current_graze = g
		current.append(slot)
	if not current.is_empty():
		tiers.append(current)
	return tiers


func _fire_pattern(alive: Array) -> void:
	match _pattern_index % 3:
		0:
			_fire_spiral()
		1:
			_fire_ring()
		2:
			_fire_aimed(alive)
	_pattern_index += 1


func _fire_spiral() -> void:
	_spiral_angle += 0.9
	for arm in SPIRAL_ARMS:
		var angle := _spiral_angle + TAU * arm / SPIRAL_ARMS
		_spawn_bullet(Vector2.from_angle(angle))


func _fire_ring() -> void:
	var offset := rng.randf_range(0.0, TAU)
	for i in RING_BULLETS:
		_spawn_bullet(Vector2.from_angle(offset + TAU * i / RING_BULLETS))


## Aims at the current graze-coin leader — success paints a target on you.
func _fire_aimed(survivors: Array) -> void:
	if survivors.is_empty():
		return
	var target: int = survivors[0]
	for slot: int in survivors:
		if graze_coins[slot] > graze_coins[target]:
			target = slot
	var direction: Vector2 = positions[target]
	if direction.length() < 0.01:
		direction = Vector2.RIGHT
	for spread: float in [-0.18, 0.0, 0.18]:
		_spawn_bullet(direction.normalized().rotated(spread))


func _spawn_bullet(direction: Vector2) -> void:
	bullets.append({"pos": Vector2.ZERO, "vel": direction * bullet_speed()})


func _move_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		bullets[i].pos += bullets[i].vel * delta
		if (bullets[i].pos as Vector2).length() > _bullet_range:
			bullets.remove_at(i)


func _resolve_hits_and_grazes(alive: Array) -> void:
	for slot: int in alive:
		var pos: Vector2 = positions[slot]
		var near: Array = []
		for i in range(bullets.size() - 1, -1, -1):
			var distance: float = (bullets[i].pos as Vector2).distance_to(pos)
			if distance <= PLAYER_RADIUS + BULLET_RADIUS:
				_pending_kos.append(slot)
				bullets.remove_at(i)
				near = []
				break
			if distance <= GRAZE_RADIUS:
				near.append(i)
				if i not in _grazing[slot]:
					graze_coins[slot] = int(graze_coins[slot]) + GRAZE_COIN
		if slot not in _pending_kos:
			_grazing[slot] = near


func _check_end() -> void:
	if finished:
		return
	var survivors := _in_slots()
	if survivors.size() > 1:
		return
	finish(_rank_players())


func _escalation() -> float:
	return clampf(elapsed / RAMP_SEC, 0.0, 1.0)


func _is_in(slot: int) -> bool:
	if slot in _pending_kos:
		return false
	for group: Array in ko_order:
		if slot in group:
			return false
	return slot in slots


func _in_slots() -> Array:
	return slots.filter(_is_in)
