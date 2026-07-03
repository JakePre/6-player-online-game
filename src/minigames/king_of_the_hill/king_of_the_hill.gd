class_name KingOfTheHill
extends MinigameBase
## King of the Hill (M4-01, SPEC $7 #2; overhauled per #139): score points
## standing inside a zone that shrinks and visibly DRIFTS across the arena,
## then jumps somewhere new. Seeded pillar obstacles block movement, and
## pickup items add teeth: a Shove Blast knocks everyone nearby away, an
## Anchor freezes the zone in place while you milk it. Server-side
## simulation only — the client renders get_snapshot().

enum Item { SHOVE = 0, ANCHOR = 1 }

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const ZONE_START_RADIUS := 3.0
const ZONE_MIN_RADIUS := 1.1
const ZONE_LIFETIME_SEC := 10.0
## Keeps a relocated zone fully inside the arena.
const ZONE_MARGIN := ZONE_START_RADIUS + 0.5
const POINTS_PER_SEC := 2.0
## The zone glides toward a wander target between jumps (#139).
const ZONE_DRIFT_SPEED := 1.2
const PILLAR_COUNT := 4
const PILLAR_RADIUS := 0.8
## Pickup items (#139): grab by touch, fire with action_primary.
const ITEM_PICKUP_RADIUS := 0.8
const ITEM_SPAWN_SEC := 6.0
const MAX_ACTIVE_ITEMS := 2
const SHOVE_RADIUS := 3.0
const SHOVE_DISTANCE := 2.5
const ANCHOR_SEC := 3.0

var positions := {}
var move_dirs := {}
var score_accum := {}
var zone_center := Vector2.ZERO
var zone_age := 0.0
## Seeded obstacle circles, each a Vector2 center (radius PILLAR_RADIUS).
var pillars: Array[Vector2] = []
## Ground items, each {pos: Vector2, type: Item}.
var items: Array[Dictionary] = []
## {slot: Item} for players carrying one (one at a time).
var held := {}
## While positive, the zone neither shrinks, drifts, nor ages (Anchor).
var anchor_left := 0.0

var _drift_target := Vector2.ZERO
var _item_accum := 0.0


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
				"Stand in the zone to score — it drifts and shrinks! Grab items to shove or anchor.",
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
	_drift_target = _random_zone_point()
	for _i in PILLAR_COUNT:
		for _attempt in 12:
			var candidate := Vector2(
				rng.randf_range(-ARENA_HALF + 1.5, ARENA_HALF - 1.5),
				rng.randf_range(-ARENA_HALF + 1.5, ARENA_HALF - 1.5)
			)
			# Keep pillars off the starting zone and the spawn ring.
			if (
				candidate.length() > ZONE_START_RADIUS + 1.0
				and candidate.length() < ARENA_HALF * 0.85
			):
				pillars.append(candidate)
				break


func _handle_input(slot: int, data: Dictionary) -> void:
	if data.has("use"):
		_use_item(slot)
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	for slot: int in slots:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
	for slot: int in slots:
		_push_out_of_pillars(slot)
	_collect_items()
	_spawn_items(delta)
	var radius := zone_radius()
	for slot: int in slots:
		if positions[slot].distance_to(zone_center) <= radius:
			score_accum[slot] += POINTS_PER_SEC * delta
	if anchor_left > 0.0:
		anchor_left = maxf(anchor_left - delta, 0.0)
		return
	zone_center = zone_center.move_toward(_drift_target, ZONE_DRIFT_SPEED * delta)
	if zone_center.distance_to(_drift_target) < 0.1:
		_drift_target = _random_zone_point()
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
	var pillar_list: Array = []
	for pillar in pillars:
		pillar_list.append([snappedf(pillar.x, 0.01), snappedf(pillar.y, 0.01), PILLAR_RADIUS])
	var item_list: Array = []
	for item in items:
		var item_pos: Vector2 = item.pos
		item_list.append([snappedf(item_pos.x, 0.01), snappedf(item_pos.y, 0.01), int(item.type)])
	return {
		"players": players,
		"zone":
		[
			snappedf(zone_center.x, 0.01),
			snappedf(zone_center.y, 0.01),
			snappedf(zone_radius(), 0.01),
		],
		"pillars": pillar_list,
		"items": item_list,
		"held": held.duplicate(),
		"anchored": anchor_left > 0.0,
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
			break
	_drift_target = _random_zone_point()


func _random_zone_point() -> Vector2:
	return Vector2(
		rng.randf_range(-ARENA_HALF + ZONE_MARGIN, ARENA_HALF - ZONE_MARGIN),
		rng.randf_range(-ARENA_HALF + ZONE_MARGIN, ARENA_HALF - ZONE_MARGIN)
	)


func _push_out_of_pillars(slot: int) -> void:
	for pillar in pillars:
		var away: Vector2 = positions[slot] - pillar
		var min_gap := PILLAR_RADIUS + PLAYER_RADIUS
		if away.length() < min_gap:
			var axis := away.normalized() if away.length() > 0.001 else Vector2.RIGHT
			positions[slot] = pillar + axis * min_gap


func _spawn_items(delta: float) -> void:
	_item_accum += delta
	if _item_accum < ITEM_SPAWN_SEC or items.size() >= MAX_ACTIVE_ITEMS:
		return
	_item_accum = 0.0
	(
		items
		. append(
			{
				"pos":
				Vector2(
					rng.randf_range(-ARENA_HALF + 1.0, ARENA_HALF - 1.0),
					rng.randf_range(-ARENA_HALF + 1.0, ARENA_HALF - 1.0)
				),
				"type": Item.SHOVE if rng.randf() < 0.5 else Item.ANCHOR,
			}
		)
	)


func _collect_items() -> void:
	for i in range(items.size() - 1, -1, -1):
		for slot: int in slots:
			if held.has(slot):
				continue
			if positions[slot].distance_to(items[i].pos) <= ITEM_PICKUP_RADIUS:
				held[slot] = int(items[i].type)
				items.remove_at(i)
				break


func _use_item(slot: int) -> void:
	if not held.has(slot):
		return
	var item: int = held[slot]
	held.erase(slot)
	match item:
		Item.SHOVE:
			for other: int in slots:
				if other == slot:
					continue
				var away: Vector2 = positions[other] - positions[slot]
				if away.length() <= SHOVE_RADIUS:
					var axis := away.normalized() if away.length() > 0.001 else Vector2.RIGHT
					var pos: Vector2 = positions[other] + axis * SHOVE_DISTANCE
					positions[other] = pos.clamp(
						Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
					)
		Item.ANCHOR:
			anchor_left = ANCHOR_SEC
