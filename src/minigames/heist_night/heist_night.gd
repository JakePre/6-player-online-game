class_name HeistNight
extends MinigameBase
## Heist Night (M4-16, SPEC $7 #17): coins bank into your vault on pickup;
## when the lights cycle off, siphon coins from other players' vaults.
## Theft is anonymous until the end reveal. Server-side simulation only —
## the client renders get_snapshot().

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const PICKUP_RADIUS := 0.8
const VAULT_RADIUS := 1.2
const COIN_WAVE_SEC := 2.0
const COINS_PER_WAVE := 3
const MAX_ACTIVE_COINS := 15
## Lights alternate: on for LIGHT_SEC, off for DARK_SEC, from elapsed time.
const LIGHT_SEC := 8.0
const DARK_SEC := 5.0
## One coin moves per this much continuous vault contact in the dark.
const STEAL_SEC_PER_COIN := 0.5

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_COUNT := 2

const VT_X := 0
const VT_Y := 1
const VT_COINS := 2
const VT_COUNT := 3

const CN_X := 0
const CN_Y := 1

var positions := {}
var move_dirs := {}
var vault_pos := {}
var vaults := {}
var coins: Array[Vector2] = []
## {thief: {victim: coins}} — revealed only after the round ends.
var steal_log := {}

var _wave_accum := 0.0
var _steal_accum := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"heist_night",
				"controls": "Move — WASD / left stick",
				# Structured spec (#832/#844): the bare-movement template shape.
				"control_spec": [{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE}],
				"name": "Heist Night",
				"category": MinigameMeta.Category.SABOTAGE,
				"min_players": 3,
				"max_players": 8,
				"duration_sec": 60.0,
				"rules":
				"Bank coins in your vault — and when the lights go out, rob everyone else's!",
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		var slot: int = slots[i]
		vault_pos[slot] = Vector2(cos(angle), sin(angle)) * ARENA_HALF * 0.75
		positions[slot] = Vector2(vault_pos[slot]) * 0.6
		move_dirs[slot] = Vector2.ZERO
		vaults[slot] = 0
		_steal_accum[slot] = 0.0
	_spawn_wave()


func is_dark() -> bool:
	return fmod(elapsed, LIGHT_SEC + DARK_SEC) >= LIGHT_SEC


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	for slot: int in slots:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
	_collect_coins()
	_resolve_steals(delta)
	_wave_accum += delta
	if _wave_accum >= COIN_WAVE_SEC:
		_wave_accum -= COIN_WAVE_SEC
		_spawn_wave()


func get_snapshot() -> Dictionary:
	var dark := is_dark()
	var players := {}
	for slot: int in slots:
		# In the light everyone's on the radar; in the dark you vanish — except
		# while standing in a vault's glow, which lights you up for every client
		# the same way (#806). Robbing a vault therefore exposes you.
		if not dark or _in_vault_glow(slot):
			var pos: Vector2 = positions[slot]
			players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
	var vault_list := {}
	for slot: int in slots:
		var pos: Vector2 = vault_pos[slot]
		vault_list[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), int(vaults[slot])]
	var coin_list: Array = []
	for coin in coins:
		coin_list.append([snappedf(coin.x, 0.01), snappedf(coin.y, 0.01)])
	var snapshot := {
		"dark": dark,
		"players": players,
		"vaults": vault_list,
		"coins": coin_list,
	}
	if finished:
		# The end reveal (SPEC: theft is anonymous until now).
		snapshot["reveal"] = steal_log.duplicate(true)
	return snapshot


## Richest vault wins; ties grouped. Vault totals double as capped pickup
## coins (SPEC $5), like Coin Scramble.
func _rank_players() -> Array:
	var by_coins := {}
	for slot: int in slots:
		var total: int = vaults[slot]
		if not by_coins.has(total):
			by_coins[total] = []
		by_coins[total].append(slot)
	var totals := by_coins.keys()
	totals.sort()
	totals.reverse()
	var placements: Array = []
	for total: int in totals:
		placements.append(by_coins[total])
	_pickup_coins = vaults.duplicate()
	return placements


func _spawn_wave() -> void:
	for _i in COINS_PER_WAVE:
		if coins.size() >= MAX_ACTIVE_COINS:
			return
		coins.append(
			Vector2(
				rng.randf_range(-ARENA_HALF, ARENA_HALF), rng.randf_range(-ARENA_HALF, ARENA_HALF)
			)
		)


func _collect_coins() -> void:
	for i in range(coins.size() - 1, -1, -1):
		for slot: int in slots:
			if positions[slot].distance_to(coins[i]) <= PICKUP_RADIUS:
				vaults[slot] = int(vaults[slot]) + 1
				coins.remove_at(i)
				break


func _resolve_steals(delta: float) -> void:
	if not is_dark():
		for slot: int in slots:
			_steal_accum[slot] = 0.0
		return
	for thief: int in slots:
		var victim := _vault_under(thief)
		if victim == -1 or victim == thief or int(vaults[victim]) <= 0:
			_steal_accum[thief] = 0.0
			continue
		_steal_accum[thief] = float(_steal_accum[thief]) + delta
		while float(_steal_accum[thief]) >= STEAL_SEC_PER_COIN and int(vaults[victim]) > 0:
			_steal_accum[thief] = float(_steal_accum[thief]) - STEAL_SEC_PER_COIN
			vaults[victim] = int(vaults[victim]) - 1
			vaults[thief] = int(vaults[thief]) + 1
			if not steal_log.has(thief):
				steal_log[thief] = {}
			steal_log[thief][victim] = int(steal_log[thief].get(victim, 0)) + 1


func _vault_under(slot: int) -> int:
	for owner: int in slots:
		if owner == slot:
			continue
		if positions[slot].distance_to(vault_pos[owner]) <= VAULT_RADIUS:
			return owner
	return -1


## Whether `slot` stands within any vault's glow — the always-lit vault discs
## reveal a silhouette even in the dark (#806), own vault or someone else's.
func _in_vault_glow(slot: int) -> bool:
	for owner: int in slots:
		if positions[slot].distance_to(vault_pos[owner]) <= VAULT_RADIUS:
			return true
	return false
