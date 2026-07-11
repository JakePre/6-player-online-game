class_name TiltDeck
extends MinigameBase
## Tilt Deck (#794, retires Beat Bounce): collective-physics survival. Everyone
## stands on one circular free-floating deck over open water. The deck LEANS
## toward the crowd's weighted center of mass — pile onto one side and it pitches
## that way, so everyone there slides further out, over-corrects, and the mob
## tips itself into the opposite ocean. Slide past the rim and you're out (Thin
## Ice rules). Coins spawn out at the risky edge; the safe centre pays nothing.
## Tilt sensitivity ramps and cargo crates periodically crash onto one side to
## force mass migrations. Movement-only input, 2-24. Server-side simulation only
## — the client renders get_snapshot().

const DECK_RADIUS := 8.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
## Downhill push at full tilt (world u/s), tuned just above MOVE_SPEED so a lone
## player can crawl uphill but a lopsided crowd (or ramped sensitivity) out-slides
## them — that's the trap.
const SLIDE_SPEED := 7.0
## The deck eases toward its target lean at this rate/sec — enough lag that the
## crowd's over-correction whips it back the other way.
const TILT_RESPONSE := 2.2
## target lean = normalized COM offset * sensitivity (capped). Sensitivity ramps
## from START by RAMP/sec so late-game imbalances are unholdable.
const SENS_START := 0.6
const SENS_RAMP := 0.02
const TILT_MAX := 1.3
## Coins: banked on pickup; spawn only in the outer ring (risk = reward).
const COIN_PICKUP_RADIUS := 0.9
const COIN_WAVE_SEC := 2.5
const MAX_COINS := 8
const COIN_EDGE_MIN := 0.55
const COIN_EDGE_MAX := 0.95
## Cargo drops: a heavy crate crashes onto one side, dragging the COM toward it
## for a spell so the crowd must flee to the far side or ride it into the sea.
const CARGO_WEIGHT := 5.0
const CARGO_FIRST_SEC := 8.0
const CARGO_INTERVAL_SEC := 10.0
const CARGO_LIFE_SEC := 4.5
const CARGO_DROP_FRACTION := 0.65

## get_snapshot() wire shape (#708): named indices for the players positional
## array. Array SHAPE on the wire is unchanged — additive only.
const PS_X := 0
const PS_Y := 1
const PS_COINS := 2
const PS_COUNT := 3

const CG_X := 0
const CG_Y := 1
const CG_LIFE := 2
const CG_COUNT := 3

var positions := {}
var move_dirs := {}
var coins_of := {}
## The deck's current lean: direction = downhill, magnitude = steepness.
var tilt := Vector2.ZERO
var coins: Array[Vector2] = []
## Active cargo crates: {pos: Vector2, life_left: float}.
var cargo: Array[Dictionary] = []
## Slots in fall order; same-tick fallers share a tie group.
var down_order: Array = []

var _coin_accum := 0.0
var _cargo_next := CARGO_FIRST_SEC


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"tilt_deck",
				"name": "Tilt Deck",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 75.0,
				"rules":
				(
					"You're all on one raft — it TIPS toward the crowd! Don't pile up,"
					+ " grab the edge coins, and ride the wobble. Last one afloat wins."
				),
				"controls": "Move — WASD / left stick",
				# Structured spec (#832): the bare-movement template shape.
				"control_spec": [{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE}],
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * DECK_RADIUS * 0.4
		move_dirs[slots[i]] = Vector2.ZERO
		coins_of[slots[i]] = 0
	_spawn_coins()


## Ramps over the round so a wobble that was holdable early becomes fatal late.
func sensitivity() -> float:
	return SENS_START + elapsed * SENS_RAMP


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _is_in(slot):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	if finished:
		return
	var alive := _in_slots()
	_tick_tilt(alive, delta)
	_move_players(alive, delta)
	_check_falls(alive)
	_tick_cargo(delta)
	_tick_coins(delta, _in_slots())
	_check_end()


## The deck leans toward the weighted centre of mass of everyone (and every
## crate) aboard, easing there so it always lags the crowd. An empty side has no
## pull, so a balanced deck sits flat.
func _tick_tilt(alive: Array, delta: float) -> void:
	var sum := Vector2.ZERO
	var weight := 0.0
	for slot: int in alive:
		sum += positions[slot]
		weight += 1.0
	for crate: Dictionary in cargo:
		sum += (crate.pos as Vector2) * CARGO_WEIGHT
		weight += CARGO_WEIGHT
	var target := Vector2.ZERO
	if weight > 0.0:
		target = (sum / weight / DECK_RADIUS) * sensitivity()
		target = target.limit_length(TILT_MAX)
	tilt = tilt.lerp(target, clampf(TILT_RESPONSE * delta, 0.0, 1.0))


func _move_players(alive: Array, delta: float) -> void:
	for slot: int in alive:
		var drive: Vector2 = (move_dirs[slot] as Vector2) * MOVE_SPEED
		var slide := tilt * SLIDE_SPEED
		positions[slot] = positions[slot] + (drive + slide) * delta


## Anyone who has slid (or walked) past the rim falls — same-tick fallers tie.
func _check_falls(alive: Array) -> void:
	var fallers: Array = []
	for slot: int in alive:
		if (positions[slot] as Vector2).length() > DECK_RADIUS:
			fallers.append(slot)
	if not fallers.is_empty():
		down_order.append(fallers)


func _tick_cargo(delta: float) -> void:
	for i in range(cargo.size() - 1, -1, -1):
		cargo[i].life_left = float(cargo[i].life_left) - delta
		if float(cargo[i].life_left) <= 0.0:
			cargo.remove_at(i)
	if elapsed >= _cargo_next:
		_cargo_next = elapsed + CARGO_INTERVAL_SEC
		var angle := rng.randf_range(0.0, TAU)
		var pos := Vector2(cos(angle), sin(angle)) * DECK_RADIUS * CARGO_DROP_FRACTION
		cargo.append({"pos": pos, "life_left": CARGO_LIFE_SEC})


func _tick_coins(delta: float, alive: Array) -> void:
	for i in range(coins.size() - 1, -1, -1):
		for slot: int in alive:
			if positions[slot].distance_to(coins[i]) <= COIN_PICKUP_RADIUS + PLAYER_RADIUS:
				coins_of[slot] = int(coins_of[slot]) + 1
				coins.remove_at(i)
				break
	_coin_accum += delta
	if _coin_accum >= COIN_WAVE_SEC:
		_coin_accum = 0.0
		_spawn_coins()


## Tops the floor back up to MAX_COINS, always out in the risky outer ring.
func _spawn_coins() -> void:
	while coins.size() < MAX_COINS:
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(COIN_EDGE_MIN, COIN_EDGE_MAX) * DECK_RADIUS
		coins.append(Vector2(cos(angle), sin(angle)) * dist)


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in _in_slots():
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), int(coins_of[slot])]
	var coin_list: Array = []
	for coin in coins:
		coin_list.append([snappedf(coin.x, 0.01), snappedf(coin.y, 0.01)])
	var cargo_list: Array = []
	for crate: Dictionary in cargo:
		var pos: Vector2 = crate.pos
		(
			cargo_list
			. append(
				[
					snappedf(pos.x, 0.01),
					snappedf(pos.y, 0.01),
					snappedf(clampf(float(crate.life_left) / CARGO_LIFE_SEC, 0.0, 1.0), 0.01),
				]
			)
		)
	return {
		"players": players,
		"tilt": [snappedf(tilt.x, 0.01), snappedf(tilt.y, 0.01)],
		"deck_radius": DECK_RADIUS,
		"coins": coin_list,
		"cargo": cargo_list,
		"fallen": down_order,
	}


## Last afloat wins; among survivors (and among any same-tick fall group) more
## banked coins ranks higher. Coins double as capped pickup coins (SPEC $5).
func _rank_players() -> Array:
	_pickup_coins = coins_of.duplicate()
	var survivors := _in_slots()
	var placements: Array = []
	placements.append_array(_by_coins(survivors))
	for group: Array in _reversed_falls():
		placements.append_array(_by_coins(group))
	return placements


## Splits a slot list into coin-ranked tie groups (most coins first).
func _by_coins(group: Array) -> Array:
	if group.is_empty():
		return []
	var by_count := {}
	for slot: int in group:
		var count: int = coins_of[slot]
		if not by_count.has(count):
			by_count[count] = []
		by_count[count].append(slot)
	var counts := by_count.keys()
	counts.sort()
	counts.reverse()
	var out: Array = []
	for count: int in counts:
		out.append(by_count[count])
	return out


func _reversed_falls() -> Array:
	var out := down_order.duplicate(true)
	out.reverse()
	return out


func _check_end() -> void:
	if finished:
		return
	var survivors := _in_slots()
	if survivors.size() > 1:
		return
	finish(_rank_players())


func _is_in(slot: int) -> bool:
	if slot not in slots:
		return false
	for group: Array in down_order:
		if slot in group:
			return false
	return true


func _in_slots() -> Array:
	return slots.filter(_is_in)
