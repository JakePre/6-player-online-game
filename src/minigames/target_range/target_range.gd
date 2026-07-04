class_name TargetRange
extends MinigameBase
## Target Range (M4-08, SPEC $7 #9): mouse/stick-aimed shooting gallery in a
## shared arena. Targets drift across the back band at escalating speed;
## players move a crosshair and fire on a short cooldown. Smaller and faster
## targets are worth more. Highest score wins. Server-side simulation only —
## the client renders get_snapshot().

enum Kind {
	STANDARD,
	SMALL,
	GOLD,
}

## Baseline (<=6 players) half-width; larger lobbies widen the gallery so
## target density stays fair (M15 → 24, ADR 003).
const ARENA_HALF := 8.0
## Targets drift horizontally inside this depth band (top-down y, far side).
const BAND_NEAR := -1.0
const BAND_FAR := -6.0
const FIRE_COOLDOWN_SEC := 0.6
## A shot lands if the crosshair is within target radius + this grace.
const HIT_GRACE := 0.15
## Speed multiplier grows linearly to this at the end of the round.
const END_SPEED_SCALE := 1.8
const BASE_TARGETS := 3

## Kind -> {radius, value, speed, weight} (weights drive the spawn roll).
const KIND_STATS := {
	Kind.STANDARD: {"radius": 0.8, "value": 1, "speed": 2.2, "weight": 6},
	Kind.SMALL: {"radius": 0.45, "value": 3, "speed": 3.4, "weight": 3},
	Kind.GOLD: {"radius": 0.55, "value": 5, "speed": 4.5, "weight": 1},
}

var targets: Array[Dictionary] = []
var aims := {}
var scores := {}
var cooldowns := {}
## This match's scaled half-width (equals ARENA_HALF at <=6 players). Both sim
## and view derive it from the head count via arena_half_for().
var arena_half := ARENA_HALF

var _next_target_id := 0


## Half-width of the gallery for a lobby of `count`: grows so per-player target
## density holds — a side scales with the square root of the head-count growth.
static func arena_half_for(count: int) -> float:
	return MinigameScaling.arena_half(ARENA_HALF, count)


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"target_range",
				"name": "Target Range",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 45.0,
				"rules":
				"Shoot the moving targets! Small and gold ones are worth more. Highest score wins.",
				"controls": "Aim — mouse or WASD / left stick · Fire — click or SPACE / pad A",
			}
		)
	)


func _setup() -> void:
	arena_half = arena_half_for(slots.size())
	for slot: int in slots:
		aims[slot] = Vector2.ZERO
		scores[slot] = 0
		cooldowns[slot] = 0.0
	for _i in _alive_target_count():
		targets.append(_spawn_target())


func _tick(delta: float) -> void:
	for slot: int in slots:
		cooldowns[slot] = maxf(0.0, float(cooldowns[slot]) - delta)
	var scale := _speed_scale()
	for target: Dictionary in targets:
		var pos: Vector2 = target.pos
		pos.x += float(target.speed) * scale * float(target.dir) * delta
		target.pos = pos
	for i in targets.size():
		var target: Dictionary = targets[i]
		if absf((target.pos as Vector2).x) > arena_half + float(target.radius) * 2.0:
			targets[i] = _spawn_target()


## `data` comes straight off the wire — validate everything. Aim intents
## carry the crosshair position; fire intents attempt a shot at it.
func _handle_input(slot: int, data: Dictionary) -> void:
	if data.has("ax") or data.has("ay"):
		var aim: Vector2 = aims[slot]
		aim.x = clampf(float(data.get("ax", aim.x)), -arena_half, arena_half)
		aim.y = clampf(float(data.get("ay", aim.y)), -arena_half, arena_half)
		aims[slot] = aim
	if data.get("fire", false):
		_fire(slot)


func get_snapshot() -> Dictionary:
	var target_list: Array = []
	for target: Dictionary in targets:
		var pos: Vector2 = target.pos
		(
			target_list
			. append(
				[
					int(target.id),
					snappedf(pos.x, 0.01),
					snappedf(pos.y, 0.01),
					float(target.radius),
					int(target.kind),
				]
			)
		)
	var aim_list := {}
	for slot: int in slots:
		var aim: Vector2 = aims[slot]
		aim_list[slot] = [snappedf(aim.x, 0.01), snappedf(aim.y, 0.01)]
	return {
		"targets": target_list,
		"aims": aim_list,
		"scores": scores.duplicate(),
		"cd": _cooldown_snapshot(),
	}


func _rank_players() -> Array:
	var by_score := {}
	for slot: int in slots:
		var score: int = scores.get(slot, 0)
		if not by_score.has(score):
			by_score[score] = []
		by_score[score].append(slot)
	var counts := by_score.keys()
	counts.sort()
	counts.reverse()
	var placements: Array = []
	for count: int in counts:
		placements.append(by_score[count])
	return placements


func _fire(slot: int) -> void:
	if float(cooldowns[slot]) > 0.0:
		return
	cooldowns[slot] = FIRE_COOLDOWN_SEC
	var aim: Vector2 = aims[slot]
	var best := -1
	var best_distance := INF
	for i in targets.size():
		var target: Dictionary = targets[i]
		var distance := aim.distance_to(target.pos)
		if distance <= float(target.radius) + HIT_GRACE and distance < best_distance:
			best = i
			best_distance = distance
	if best == -1:
		return
	scores[slot] = int(scores[slot]) + int(targets[best].value)
	targets[best] = _spawn_target()


func _speed_scale() -> float:
	return 1.0 + (END_SPEED_SCALE - 1.0) * clampf(elapsed / effective_duration(), 0.0, 1.0)


func _alive_target_count() -> int:
	return BASE_TARGETS + int(ceilf(slots.size() / 2.0))


func _cooldown_snapshot() -> Dictionary:
	var out := {}
	for slot: int in slots:
		out[slot] = snappedf(float(cooldowns[slot]), 0.01)
	return out


## New targets enter from a random side at a random depth in the band.
func _spawn_target() -> Dictionary:
	var kind := _roll_kind()
	var stats: Dictionary = KIND_STATS[kind]
	var dir := 1 if rng.randf() < 0.5 else -1
	var target := {
		"id": _next_target_id,
		"kind": kind,
		"radius": float(stats.radius),
		"value": int(stats.value),
		"speed": float(stats.speed),
		"dir": dir,
		"pos":
		Vector2(
			-dir * (arena_half + float(stats.radius)),
			rng.randf_range(BAND_FAR, BAND_NEAR),
		),
	}
	_next_target_id += 1
	return target


func _roll_kind() -> Kind:
	var total := 0
	for stats: Dictionary in KIND_STATS.values():
		total += int(stats.weight)
	var roll := rng.randi_range(1, total)
	for kind: Kind in KIND_STATS:
		roll -= int(KIND_STATS[kind].weight)
		if roll <= 0:
			return kind
	return Kind.STANDARD
