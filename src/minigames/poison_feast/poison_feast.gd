class_name PoisonFeast
extends MinigameBase
## Poison Feast (M4-14, reworked per #174): push-your-luck banquet. Dishes
## spawn in waves at three visible risk tiers — clean (safe, cheap), spiced
## (sometimes poisoned), delicacy (often poisoned, rich). Eating a poisoned
## dish costs its points, feeds a visible pot, and staggers the eater; the
## next clean dish eaten claims the whole pot. A single golden dish lands
## center-table for the final course, worth double the pot. Whether any
## individual dish is poisoned stays server-side — only its tier (the odds)
## is replicated. Server-side simulation only.

enum Tier {
	CLEAN,
	SPICED,
	DELICACY,
	GOLDEN,
}

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const EAT_RADIUS := 0.8
const DISH_WAVE_SEC := 3.0
const DISHES_PER_WAVE := 3
const MAX_ACTIVE_DISHES := 12
## Eating poison staggers you: no eating, slowed movement.
const STAGGER_SEC := 2.0
const STAGGER_MOVE_SCALE := 0.4
## The golden dish is served this long before the round ends.
const GOLDEN_AT_REMAINING_SEC := 8.0
const GOLDEN_BASE_POINTS := 6
const GOLDEN_POT_MULTIPLIER := 2

## Tier -> {points, poison_chance, weight} (weights drive the spawn roll).
## Odds are public knowledge — they're printed on the intro card.
const TIER_STATS := {
	Tier.CLEAN: {"points": 1, "poison_chance": 0.0, "weight": 5},
	Tier.SPICED: {"points": 3, "poison_chance": 0.25, "weight": 3},
	Tier.DELICACY: {"points": 6, "poison_chance": 0.5, "weight": 1},
}

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_SCORE := 2
const PS_STAGGERED := 3
const PS_COUNT := 4

const DL_ID := 0
const DL_X := 1
const DL_Y := 2
const DL_TIER := 3

var positions := {}
var move_dirs := {}
var score := {}
## slot -> stagger seconds remaining (absent/<=0 means free to eat).
var staggers := {}
## Points forfeited by poisoned eaters, claimed by the next clean eat.
var pot := 0
var dishes: Array[Dictionary] = []
var golden_served := false

## Play area and dish economy scale with the lobby size (M15, ADR 003): a
## 12-player match gets a bigger table and proportionally more dishes so
## density and per-capita pacing hold. At <=6 players these equal the consts
## above, so the original game is unchanged.
var _play_half := ARENA_HALF
var _dishes_per_wave := DISHES_PER_WAVE
var _max_dishes := MAX_ACTIVE_DISHES

var _wave_accum := 0.0
var _next_dish_id := 0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"poison_feast",
				"controls": "Move — WASD / left stick (eat by touch)",
				"name": "Poison Feast",
				"category": MinigameMeta.Category.SABOTAGE,
				"min_players": 2,
				"max_players": 12,
				"duration_sec": 45.0,
				"rules":
				(
					"Feast, but mind the odds: white dishes are safe, orange are"
					+ " poisoned 1-in-4, purple 1-in-2 — richer if you survive."
					+ " Poison feeds the pot; the next clean bite claims it. The"
					+ " golden final course pays the pot double!"
				),
			}
		)
	)


func _setup() -> void:
	_play_half = MinigameScaling.arena_half(ARENA_HALF, slots.size())
	_dishes_per_wave = MinigameScaling.supply(DISHES_PER_WAVE, slots.size())
	_max_dishes = MinigameScaling.supply(MAX_ACTIVE_DISHES, slots.size())
	var spawns := SpawnLayout.ring_positions(slots.size(), _play_half * 0.6)
	for i in slots.size():
		positions[slots[i]] = spawns[i]
		move_dirs[slots[i]] = Vector2.ZERO
		score[slots[i]] = 0
		staggers[slots[i]] = 0.0
	_spawn_wave()


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	for slot: int in slots:
		staggers[slot] = maxf(0.0, float(staggers[slot]) - delta)
		var speed := MOVE_SPEED * (STAGGER_MOVE_SCALE if float(staggers[slot]) > 0.0 else 1.0)
		var pos: Vector2 = positions[slot] + move_dirs[slot] * speed * delta
		positions[slot] = pos.clamp(
			Vector2(-_play_half, -_play_half), Vector2(_play_half, _play_half)
		)
	_eat_dishes()
	_wave_accum += delta
	if _wave_accum >= DISH_WAVE_SEC:
		_wave_accum -= DISH_WAVE_SEC
		_spawn_wave()
	if not golden_served and effective_duration() - elapsed <= GOLDEN_AT_REMAINING_SEC:
		_serve_golden()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			score[slot],
			1 if float(staggers[slot]) > 0.0 else 0,
		]
	var dish_list: Array = []
	for dish: Dictionary in dishes:
		var pos: Vector2 = dish.pos
		# Only the tier ships — whether THIS dish is poisoned stays secret.
		dish_list.append([int(dish.id), snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), dish.tier])
	return {"players": players, "dishes": dish_list, "pot": pot}


func _rank_players() -> Array:
	var by_score := {}
	for slot: int in slots:
		var value: int = score[slot]
		if not by_score.has(value):
			by_score[value] = []
		by_score[value].append(slot)
	var values := by_score.keys()
	values.sort()
	values.reverse()
	var placements: Array = []
	for value: int in values:
		placements.append(by_score[value])
	return placements


func _spawn_wave() -> void:
	for _i in _dishes_per_wave:
		if dishes.size() >= _max_dishes:
			return
		var tier := _roll_tier()
		var stats: Dictionary = TIER_STATS[tier]
		(
			dishes
			. append(
				{
					"id": _next_dish_id,
					"pos":
					Vector2(
						rng.randf_range(-_play_half, _play_half),
						rng.randf_range(-_play_half, _play_half)
					),
					"tier": tier,
					"poisoned": rng.randf() < float(stats.poison_chance),
				}
			)
		)
		_next_dish_id += 1


func _roll_tier() -> Tier:
	var total := 0
	for stats: Dictionary in TIER_STATS.values():
		total += int(stats.weight)
	var roll := rng.randi_range(1, total)
	for tier: Tier in TIER_STATS:
		roll -= int(TIER_STATS[tier].weight)
		if roll <= 0:
			return tier
	return Tier.CLEAN


## The final course: one golden dish, center table, never poisoned.
func _serve_golden() -> void:
	golden_served = true
	dishes.append(
		{"id": _next_dish_id, "pos": Vector2.ZERO, "tier": Tier.GOLDEN, "poisoned": false}
	)
	_next_dish_id += 1


func _eat_dishes() -> void:
	for i in range(dishes.size() - 1, -1, -1):
		var dish: Dictionary = dishes[i]
		for slot: int in slots:
			if float(staggers[slot]) > 0.0:
				continue
			if positions[slot].distance_to(dish.pos) > EAT_RADIUS:
				continue
			_eat(slot, dish)
			dishes.remove_at(i)
			break


func _eat(slot: int, dish: Dictionary) -> void:
	if dish.tier == Tier.GOLDEN:
		score[slot] = int(score[slot]) + GOLDEN_BASE_POINTS + pot * GOLDEN_POT_MULTIPLIER
		pot = 0
		return
	var points := int(TIER_STATS[dish.tier].points)
	if dish.poisoned:
		score[slot] = int(score[slot]) - points
		pot += points
		staggers[slot] = STAGGER_SEC
		return
	score[slot] = int(score[slot]) + points + pot
	pot = 0
