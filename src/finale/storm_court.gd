class_name StormCourt
extends MinigameBase
## Storm Court (#936, owner-locked concept, build 1 of 3): the finale-variant
## dodgeball royale. FFA dodgeball (the #791 ball model: loose/held/flying,
## facing throws, buffered catches) on a Gauntlet-style staged-shrink court —
## the storm walls close in, the dodging room disappears. Everyone has lives
## from the buy-in shop; a CATCH with lives in play swings two at once
## (thrower loses one, catcher gains one). Sabotage is a telegraphed
## ball-strike from the sky on a rival. Last player with lives wins the
## match. Not a roster minigame — never registered in the catalog; the match
## framework enters it via FinaleVariants (M5-02 contract).

## The #791 ball lifecycle, unchanged.
enum BallState { LOOSE, HELD, FLYING }

## Court scaling mirrors Gauntlet: base 6-player disc, sqrt head-count growth,
## same number of stages to the minimum whatever the size.
const START_RADIUS := 9.0
const MIN_RADIUS := 3.0
const SHRINK_STAGE_SEC := 12.0
const SHRINK_PER_STAGE := 1.2
## #583 telegraph: the doomed band is shown this long before a stage lands.
const SHRINK_WARN_SEC := 3.0

const MOVE_SPEED := 6.0
const SPEED_BOOST_MULT := 1.3
const PLAYER_RADIUS := 0.45

## The #791 ball model, retuned for a royale court.
const THROW_SPEED := 15.0
const BALL_RADIUS := 0.3
const HIT_RADIUS := 0.75
const CATCH_RADIUS := 1.15
const CATCH_WINDOW := 0.3
const PICKUP_RADIUS := 0.7

## A hit's grace: briefly unhittable after losing a life (and at the whistle,
## #787) so nobody gets combo'd out of the finale in one volley.
const SPAWN_PROTECT_SEC := 2.0
const HIT_PROTECT_SEC := 1.5

## Sabotage (#936): a telegraphed strike from the sky at the target's position
## when spent — dodgeable by anyone watching the warn circle.
const SABOTAGE_WARN_SEC := 1.2
const SABOTAGE_RADIUS := 1.6

## get_snapshot() wire shapes (#708).
const PS_X := 0
const PS_Y := 1
const PS_FACING_X := 2
const PS_FACING_Y := 3
const PS_LIVES := 4
const PS_HOLDING := 5
const PS_INVULN := 6
const PS_HIT_SEQ := 7
const PS_CATCH_SEQ := 8
const PS_COUNT := 9
const PLAYER_SCHEMA := [
	TYPE_FLOAT,
	TYPE_FLOAT,
	TYPE_FLOAT,
	TYPE_FLOAT,
	TYPE_INT,
	TYPE_INT,
	TYPE_FLOAT,
	TYPE_INT,
	TYPE_INT,
]

const BL_X := 0
const BL_Y := 1
const BL_STATE := 2
const BL_HOLDER := 3
const BL_COUNT := 4

const ST_X := 0
const ST_Y := 1
const ST_WARN := 2

var radius := START_RADIUS
var start_radius := START_RADIUS
var shrink_per_stage := SHRINK_PER_STAGE
var positions := {}
var move_dirs := {}
var facings := {}
var lives := {}
var shields := {}
var speed_boosts := {}
var sabotage_tokens := {}
var catch_until := {}
## Each {pos, vel, state, holder, thrower} — the #791 dict model.
var balls: Array[Dictionary] = []
## Pending sabotage strikes, each {pos, warn_left}.
var strikes: Array[Dictionary] = []
## Slots in full-elimination order; simultaneous KOs share a tie group.
var elimination_order: Array = []
## Monotonic per-slot counters so the view animates each hit/catch once.
var hit_seq := {}
var catch_seq := {}

var _invuln_left := {}
var _stage_accum := 0.0
var _pending_elims: Array = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"storm_court",
				"controls":
				"Move — WASD / left stick · Throw / Catch — Space / pad A · Sabotage — E / pad X",
				"name": "Storm Court",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 150.0,
				"rules":
				(
					"Finale dodgeball royale! Last one with lives wins the match. Throw to"
					+ " strip a life, CATCH to steal one back — the storm walls close in."
				),
			}
		)
	)


static func start_radius_for(count: int) -> float:
	return START_RADIUS * sqrt(MinigameScaling.growth(count))


static func shrink_per_stage_for(count: int) -> float:
	return SHRINK_PER_STAGE * sqrt(MinigameScaling.growth(count))


## One ball per two players keeps scarcity (fights over ammo) at every size.
static func ball_count_for(count: int) -> int:
	return maxi(3, int(ceil(count / 2.0)))


func _setup() -> void:
	start_radius = start_radius_for(slots.size())
	shrink_per_stage = shrink_per_stage_for(slots.size())
	radius = start_radius
	for i in slots.size():
		var slot: int = slots[i]
		var angle := TAU * i / slots.size()
		positions[slot] = Vector2(cos(angle), sin(angle)) * start_radius * 0.7
		move_dirs[slot] = Vector2.ZERO
		facings[slot] = Vector2(-cos(angle), -sin(angle))
		lives[slot] = 1
		shields[slot] = false
		speed_boosts[slot] = false
		sabotage_tokens[slot] = 0
		catch_until[slot] = -1.0
		hit_seq[slot] = 0
		catch_seq[slot] = 0
		_invuln_left[slot] = SPAWN_PROTECT_SEC
	for b in ball_count_for(slots.size()):
		var angle := TAU * b / ball_count_for(slots.size())
		(
			balls
			. append(
				{
					"pos": Vector2(cos(angle), sin(angle)) * start_radius * 0.35,
					"vel": Vector2.ZERO,
					"state": BallState.LOOSE,
					"holder": -1,
					"thrower": -1,
				}
			)
		)


## FinaleShop.loadouts() interface, identical to Gauntlet's (M5-01/M5-02).
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
	if not _is_alive(slot):
		return
	if data.has("sabotage"):
		_handle_sabotage(slot, data.sabotage)
		return
	if data.has("mx") or data.has("my"):
		var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
		move_dirs[slot] = dir.limit_length(1.0)
	if not bool(data.get("act", false)):
		return
	var held: Variant = _ball_held_by(slot)
	if held != null:
		_throw(slot, held)
	else:
		# Empty-handed press buffers a catch (beats the hit check on arrival).
		catch_until[slot] = elapsed + CATCH_WINDOW


func _tick(delta: float) -> void:
	_tick_shrink(delta)
	var alive := _alive_slots()
	for slot: int in alive:
		_invuln_left[slot] = maxf(0.0, float(_invuln_left.get(slot, 0.0)) - delta)
		var dir: Vector2 = move_dirs[slot]
		if dir.length() > 0.01:
			facings[slot] = dir.normalized()
		var speed := MOVE_SPEED * (SPEED_BOOST_MULT if speed_boosts[slot] else 1.0)
		positions[slot] = ((positions[slot] as Vector2) + dir * speed * delta).limit_length(
			radius - PLAYER_RADIUS
		)
	_resolve_pickups(alive)
	_carry_held_balls(alive)
	_tick_flying(delta, alive)
	_tick_strikes(delta, alive)
	_flush_eliminations()
	_check_end()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		if not _is_alive(slot):
			continue
		var pos: Vector2 = positions[slot]
		var facing: Vector2 = facings[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			snappedf(facing.x, 0.01),
			snappedf(facing.y, 0.01),
			int(lives[slot]),
			1 if _ball_held_by(slot) != null else 0,
			snappedf(_invuln_left.get(slot, 0.0), 0.01),
			int(hit_seq[slot]),
			int(catch_seq[slot]),
		]
	var ball_list: Array = []
	for ball: Dictionary in balls:
		var pos: Vector2 = ball.pos
		ball_list.append(
			[snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), int(ball.state), int(ball.holder)]
		)
	var strike_list: Array = []
	for strike: Dictionary in strikes:
		var pos: Vector2 = strike.pos
		strike_list.append(
			[snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(strike.warn_left, 0.01)]
		)
	return {
		"radius": snappedf(radius, 0.01),
		"shrink_in": snappedf(SHRINK_STAGE_SEC - _stage_accum, 0.01),
		"players": players,
		"balls": ball_list,
		"strikes": strike_list,
		"eliminated": _flat_eliminated(),
	}


## Timeout fallback: survivors grouped by lives (more first), then the
## eliminated in reverse KO order — Gauntlet's exact shape for FinaleRanking.
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
	var fallen := elimination_order.duplicate()
	fallen.reverse()
	for group: Array in fallen:
		placements.append(group.duplicate())
	return placements


# --- Court ---------------------------------------------------------------------


func _tick_shrink(delta: float) -> void:
	if radius <= MIN_RADIUS:
		return
	_stage_accum += delta
	if _stage_accum >= SHRINK_STAGE_SEC:
		_stage_accum = 0.0
		radius = maxf(MIN_RADIUS, radius - shrink_per_stage)


# --- Balls -----------------------------------------------------------------------


func _throw(slot: int, ball: Dictionary) -> void:
	var facing: Vector2 = facings.get(slot, Vector2.RIGHT)
	if facing.length() < 0.01:
		facing = Vector2.RIGHT
	ball.state = BallState.FLYING
	ball.holder = slot
	ball.thrower = slot
	ball.vel = facing.normalized() * THROW_SPEED
	ball.pos = (positions[slot] as Vector2) + facing.normalized() * (PLAYER_RADIUS + BALL_RADIUS)


func _tick_flying(delta: float, alive: Array) -> void:
	for ball: Dictionary in balls:
		if int(ball.state) != BallState.FLYING:
			continue
		ball.pos = (ball.pos as Vector2) + (ball.vel as Vector2) * delta
		# The storm wall stops every throw: balls drop loose at the edge.
		if (ball.pos as Vector2).length() > radius - BALL_RADIUS:
			_drop_ball(ball)
			ball.pos = (ball.pos as Vector2).limit_length(radius - BALL_RADIUS)
			continue
		_resolve_flying_ball(ball, alive)


## A live catch buffer inside the catch band SWINGS TWO (#936): the thrower
## loses a life, the catcher gains one and holds the ball. Otherwise the hit
## band strips a life (shield shrugs the first).
func _resolve_flying_ball(ball: Dictionary, alive: Array) -> void:
	var thrower := int(ball.thrower)
	var nearest := -1
	var nearest_d := INF
	for slot: int in alive:
		if slot == thrower:
			continue
		var d: float = (ball.pos as Vector2).distance_to(positions[slot])
		if d < nearest_d:
			nearest_d = d
			nearest = slot
	if nearest == -1:
		return
	if nearest_d <= CATCH_RADIUS and elapsed <= float(catch_until.get(nearest, -1.0)):
		catch_seq[nearest] = int(catch_seq[nearest]) + 1
		catch_until[nearest] = -1.0
		lives[nearest] = int(lives[nearest]) + 1
		if thrower in _alive_slots():
			_lose_life(thrower)
		ball.state = BallState.HELD
		ball.holder = nearest
		ball.thrower = -1
	elif nearest_d <= HIT_RADIUS and float(_invuln_left.get(nearest, 0.0)) <= 0.0:
		_lose_life(nearest)
		_drop_ball(ball)


func _drop_ball(ball: Dictionary) -> void:
	ball.state = BallState.LOOSE
	ball.holder = -1
	ball.thrower = -1
	ball.vel = Vector2.ZERO


func _resolve_pickups(alive: Array) -> void:
	for slot: int in alive:
		if _ball_held_by(slot) != null:
			continue
		for ball: Dictionary in balls:
			if int(ball.state) != BallState.LOOSE:
				continue
			if (positions[slot] as Vector2).distance_to(ball.pos) <= PICKUP_RADIUS:
				ball.state = BallState.HELD
				ball.holder = slot
				break


func _carry_held_balls(alive: Array) -> void:
	for ball: Dictionary in balls:
		if int(ball.state) == BallState.HELD:
			if int(ball.holder) in alive:
				ball.pos = positions[int(ball.holder)]
			else:
				_drop_ball(ball)


func _ball_held_by(slot: int) -> Variant:
	for ball: Dictionary in balls:
		if int(ball.state) == BallState.HELD and int(ball.holder) == slot:
			return ball
	return null


# --- Sabotage --------------------------------------------------------------------


## Spend a token on a rival: a strike telegraphs at their CURRENT position for
## SABOTAGE_WARN_SEC, then hits everything in its circle — dodgeable, and it
## doesn't care who walks in (the buyer included; storms are impartial).
func _handle_sabotage(slot: int, target: Variant) -> void:
	if int(sabotage_tokens[slot]) <= 0 or typeof(target) not in [TYPE_INT, TYPE_FLOAT]:
		return
	var victim := int(target)
	if victim == slot or victim not in slots or not _is_alive(victim):
		return
	sabotage_tokens[slot] = int(sabotage_tokens[slot]) - 1
	strikes.append({"pos": positions[victim], "warn_left": SABOTAGE_WARN_SEC})


func _tick_strikes(delta: float, alive: Array) -> void:
	for i in range(strikes.size() - 1, -1, -1):
		var strike: Dictionary = strikes[i]
		strike.warn_left = float(strike.warn_left) - delta
		if float(strike.warn_left) > 0.0:
			continue
		for slot: int in alive:
			if float(_invuln_left.get(slot, 0.0)) > 0.0:
				continue
			if (positions[slot] as Vector2).distance_to(strike.pos) <= SABOTAGE_RADIUS:
				_lose_life(slot)
		strikes.remove_at(i)


# --- Lives -----------------------------------------------------------------------


func _lose_life(slot: int) -> void:
	# Two hits landing the same tick (ball + strike) can both see a stale
	# alive list — never double-eliminate or drive lives negative.
	if int(lives[slot]) <= 0:
		return
	if shields[slot]:
		shields[slot] = false
		hit_seq[slot] = int(hit_seq[slot]) + 1
		_invuln_left[slot] = HIT_PROTECT_SEC
		return
	lives[slot] = int(lives[slot]) - 1
	hit_seq[slot] = int(hit_seq[slot]) + 1
	if int(lives[slot]) > 0:
		_invuln_left[slot] = HIT_PROTECT_SEC
		return
	_pending_elims.append(slot)


func _flush_eliminations() -> void:
	if _pending_elims.is_empty():
		return
	elimination_order.append(_pending_elims.duplicate())
	_pending_elims.clear()


func _check_end() -> void:
	if finished:
		return
	if _alive_slots().size() <= 1:
		finish(_rank_players())


func _is_alive(slot: int) -> bool:
	return int(lives.get(slot, 0)) > 0


func _alive_slots() -> Array:
	var out: Array = []
	for slot: int in slots:
		if _is_alive(slot):
			out.append(slot)
	return out


func _flat_eliminated() -> Array:
	var out: Array = []
	for group: Array in elimination_order:
		for slot: int in group:
			out.append(slot)
	return out
