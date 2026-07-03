class_name PoisonFeast
extends MinigameBase
## Poison Feast (M4-14, SPEC $7 #15): everyone roams a shared table eating
## dishes for points. One randomly-chosen player is a hidden saboteur; three
## of the dishes spawned over the round are secretly poisoned. Eating a
## poisoned dish costs the eater points and credits the saboteur. The
## saboteur's identity never appears in get_snapshot() — the framework
## broadcasts one shared snapshot to every client, so any hidden-role field
## would deanonymize it for everyone. Server-side simulation only.

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const EAT_RADIUS := 0.8
const DISH_WAVE_SEC := 3.0
const DISHES_PER_WAVE := 2
const MAX_ACTIVE_DISHES := 10
const DISH_COUNT := 16
const POISONED_COUNT := 3
const SAFE_POINTS := 2
const POISON_PENALTY := 3
const POISON_CREDIT := 5

var positions := {}
var move_dirs := {}
var score := {}
var dishes: Array[Dictionary] = []
var saboteur := -1

var _wave_accum := 0.0
var _spawn_index := 0
var _poisoned_spawn_indices := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"poison_feast",
				"controls": "Move — WASD / left stick (eat by touch)",
				"name": "Poison Feast",
				"category": MinigameMeta.Category.SABOTAGE,
				"min_players": 4,
				"max_players": 6,
				"duration_sec": 45.0,
				"rules":
				(
					"Eat dishes for points — but one of you secretly poisoned three of"
					+ " them. The saboteur scores when someone else takes the bait."
				),
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * ARENA_HALF * 0.6
		move_dirs[slots[i]] = Vector2.ZERO
		score[slots[i]] = 0
	saboteur = slots[rng.randi_range(0, slots.size() - 1)]
	_poisoned_spawn_indices = _pick_poisoned_indices()
	_spawn_wave()


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	for slot: int in slots:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
	_eat_dishes()
	_wave_accum += delta
	if _wave_accum >= DISH_WAVE_SEC:
		_wave_accum -= DISH_WAVE_SEC
		_spawn_wave()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), score[slot]]
	var dish_list: Array = []
	for dish: Dictionary in dishes:
		var pos: Vector2 = dish.pos
		dish_list.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)])
	return {"players": players, "dishes": dish_list}


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


func _pick_poisoned_indices() -> Dictionary:
	var picked := {}
	while picked.size() < POISONED_COUNT:
		picked[rng.randi_range(0, DISH_COUNT - 1)] = true
	return picked


func _spawn_wave() -> void:
	for _i in DISHES_PER_WAVE:
		if dishes.size() >= MAX_ACTIVE_DISHES or _spawn_index >= DISH_COUNT:
			return
		(
			dishes
			. append(
				{
					"pos":
					Vector2(
						rng.randf_range(-ARENA_HALF, ARENA_HALF),
						rng.randf_range(-ARENA_HALF, ARENA_HALF)
					),
					"poisoned": _poisoned_spawn_indices.has(_spawn_index),
				}
			)
		)
		_spawn_index += 1


func _eat_dishes() -> void:
	for i in range(dishes.size() - 1, -1, -1):
		var dish: Dictionary = dishes[i]
		for slot: int in slots:
			if positions[slot].distance_to(dish.pos) > EAT_RADIUS:
				continue
			if dish.poisoned:
				score[slot] -= POISON_PENALTY
				if slot != saboteur:
					score[saboteur] += POISON_CREDIT
			else:
				score[slot] += SAFE_POINTS
			dishes.remove_at(i)
			break
