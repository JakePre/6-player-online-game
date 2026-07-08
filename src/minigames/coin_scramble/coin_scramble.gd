class_name CoinScramble
extends MinigameBase
## Reference minigame (M3-06, SPEC $7 #1): coins rain onto an arena; grab the
## most. Bumping into a richer player makes them scatter 20% of their haul.
## Server-side simulation only — the client renders get_snapshot().

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const PICKUP_RADIUS := 0.8
const COIN_WAVE_SEC := 1.5
const COINS_PER_WAVE := 4
const MAX_ACTIVE_COINS := 24
const BUMP_DROP_FRACTION := 0.2
const BUMP_COOLDOWN_SEC := 2.0

## get_snapshot() wire shape (#708): named indices for the players positional
## array. Array SHAPE on the wire is unchanged — additive only.
const PS_X := 0
const PS_Y := 1
const PS_COLLECTED := 2
const PS_COUNT := 3

const CO_X := 0
const CO_Y := 1

var positions := {}
var move_dirs := {}
var collected := {}
var coins: Array[Vector2] = []

## Play area and coin economy scale with the lobby size (M15, ADR 003 F4): a
## 12-player match gets a bigger arena and proportionally more coins so density
## and per-capita pacing hold. At <=6 players these equal the consts above, so
## the original game is unchanged.
var _play_half := ARENA_HALF
var _coins_per_wave := COINS_PER_WAVE
var _max_coins := MAX_ACTIVE_COINS
var _wave_accum := 0.0
var _bump_cooldowns := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"coin_scramble",
				"controls": "Move — WASD / left stick",
				"name": "Coin Scramble",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 12,
				"duration_sec": 60.0,
				"rules":
				"Coins rain from the sky — grab the most! Bump richer players to scatter their haul.",
			}
		)
	)


func _setup() -> void:
	_play_half = MinigameScaling.arena_half(ARENA_HALF, slots.size())
	_coins_per_wave = MinigameScaling.supply(COINS_PER_WAVE, slots.size())
	_max_coins = MinigameScaling.supply(MAX_ACTIVE_COINS, slots.size())
	var spawns := SpawnLayout.ring_positions(slots.size(), _play_half * 0.6)
	for i in slots.size():
		positions[slots[i]] = spawns[i]
		move_dirs[slots[i]] = Vector2.ZERO
		collected[slots[i]] = 0
	_spawn_wave()


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	for slot: int in slots:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-_play_half, -_play_half), Vector2(_play_half, _play_half)
		)
	_collect_coins()
	_resolve_bumps(delta)
	_wave_accum += delta
	if _wave_accum >= COIN_WAVE_SEC:
		_wave_accum -= COIN_WAVE_SEC
		_spawn_wave()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), collected[slot]]
	var coin_list: Array = []
	for coin in coins:
		coin_list.append([snappedf(coin.x, 0.01), snappedf(coin.y, 0.01)])
	return {"players": players, "coins": coin_list}


func _rank_players() -> Array:
	var by_coins := {}
	for slot: int in slots:
		var count: int = collected[slot]
		if not by_coins.has(count):
			by_coins[count] = []
		by_coins[count].append(slot)
	var counts := by_coins.keys()
	counts.sort()
	counts.reverse()
	var placements: Array = []
	for count: int in counts:
		placements.append(by_coins[count])
	# Collected coins double as capped pickup coins (SPEC $5).
	_pickup_coins = collected.duplicate()
	return placements


func _spawn_wave() -> void:
	for _i in _coins_per_wave:
		if coins.size() >= _max_coins:
			return
		coins.append(
			Vector2(
				rng.randf_range(-_play_half, _play_half), rng.randf_range(-_play_half, _play_half)
			)
		)


func _collect_coins() -> void:
	for i in range(coins.size() - 1, -1, -1):
		for slot: int in slots:
			if positions[slot].distance_to(coins[i]) <= PICKUP_RADIUS:
				collected[slot] += 1
				coins.remove_at(i)
				break


func _resolve_bumps(delta: float) -> void:
	for key: String in _bump_cooldowns.keys():
		_bump_cooldowns[key] -= delta
		if _bump_cooldowns[key] <= 0.0:
			_bump_cooldowns.erase(key)
	for i in slots.size():
		for j in range(i + 1, slots.size()):
			var a: int = slots[i]
			var b: int = slots[j]
			if positions[a].distance_to(positions[b]) > PLAYER_RADIUS * 2.0:
				continue
			var pair := "%d:%d" % [a, b]
			if _bump_cooldowns.has(pair):
				continue
			_bump_cooldowns[pair] = BUMP_COOLDOWN_SEC
			var victim := a if collected[a] > collected[b] else b
			if collected[a] == collected[b]:
				continue
			_scatter(victim)


func _scatter(slot: int) -> void:
	var dropped := int(collected[slot] * BUMP_DROP_FRACTION)
	collected[slot] -= dropped
	for _i in dropped:
		if coins.size() >= _max_coins:
			return
		var offset := Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
		coins.append(
			(positions[slot] + offset).clamp(
				Vector2(-_play_half, -_play_half), Vector2(_play_half, _play_half)
			)
		)
