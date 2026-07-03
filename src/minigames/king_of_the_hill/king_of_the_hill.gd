class_name KingOfTheHill
extends MinigameBase
## King of the Hill (M4-01, SPEC $7 #2): score points standing inside a zone
## that shrinks over its lifetime, then relocates. Everyone inside scores, so
## the game stays fair at any player count (2-6); the shrink forces contact.
## Server-side simulation only — the client renders get_snapshot().

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const ZONE_START_RADIUS := 3.0
const ZONE_MIN_RADIUS := 1.1
const ZONE_LIFETIME_SEC := 10.0
## Keeps a relocated zone fully inside the arena.
const ZONE_MARGIN := ZONE_START_RADIUS + 0.5
const POINTS_PER_SEC := 2.0

var positions := {}
var move_dirs := {}
var score_accum := {}
var zone_center := Vector2.ZERO
var zone_age := 0.0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"king_of_the_hill",
				"controls": "Move — WASD / left stick",
				"name": "King of the Hill",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 6,
				"duration_sec": 60.0,
				"rules":
				"Stand in the glowing zone to score! It shrinks, then jumps somewhere new.",
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * ARENA_HALF * 0.6
		move_dirs[slots[i]] = Vector2.ZERO
		score_accum[slots[i]] = 0.0
	zone_center = Vector2.ZERO
	zone_age = 0.0


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	for slot: int in slots:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
	var radius := zone_radius()
	for slot: int in slots:
		if positions[slot].distance_to(zone_center) <= radius:
			score_accum[slot] += POINTS_PER_SEC * delta
	zone_age += delta
	if zone_age >= ZONE_LIFETIME_SEC:
		_relocate_zone()


## Shrinks linearly from start to minimum over the zone's lifetime.
func zone_radius() -> float:
	var t := clampf(zone_age / ZONE_LIFETIME_SEC, 0.0, 1.0)
	return lerpf(ZONE_START_RADIUS, ZONE_MIN_RADIUS, t)


func points(slot: int) -> int:
	return int(score_accum[slot])


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), points(slot)]
	return {
		"players": players,
		"zone":
		[
			snappedf(zone_center.x, 0.01),
			snappedf(zone_center.y, 0.01),
			snappedf(zone_radius(), 0.01),
		],
	}


func _rank_players() -> Array:
	var by_points := {}
	for slot: int in slots:
		var score := points(slot)
		if not by_points.has(score):
			by_points[score] = []
		by_points[score].append(slot)
	var scores := by_points.keys()
	scores.sort()
	scores.reverse()
	var placements: Array = []
	for score: int in scores:
		placements.append(by_points[score])
	return placements


func _relocate_zone() -> void:
	zone_age = 0.0
	var previous := zone_center
	# Reroll until the new zone is meaningfully away from the old one, so a
	# camper cannot straddle back-to-back zones.
	for _attempt in 8:
		zone_center = Vector2(
			rng.randf_range(-ARENA_HALF + ZONE_MARGIN, ARENA_HALF - ZONE_MARGIN),
			rng.randf_range(-ARENA_HALF + ZONE_MARGIN, ARENA_HALF - ZONE_MARGIN)
		)
		if zone_center.distance_to(previous) >= ZONE_START_RADIUS * 1.5:
			return
