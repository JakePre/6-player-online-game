class_name CartPush
extends MinigameBase
## Cart Push (M4-12, SPEC $7 #13): two teams each push their mine cart to
## their depot; opponents can body-block. First cart home wins. Server-side
## simulation only — the client renders get_snapshot().

const ARENA_HALF := 10.0
## Carts run along y = ±LANE_Y toward +x; depots sit at +TRACK_END.
const LANE_Y := 4.0
const TRACK_END := 9.0
const TRACK_START := -9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const PUSH_DISTANCE := 0.35
const CART_RADIUS := 1.0
## Reach around the cart within which players interact with it.
const CART_REACH := 1.6
## Cart speed per pusher (diminishing crowd bonus handled by the cap).
const CART_SPEED_PER_PUSHER := 1.5
const MAX_EFFECTIVE_PUSHERS := 3
## Unattended carts roll back toward the start.
const ROLLBACK_SPEED := 0.6

var positions := {}
var move_dirs := {}
## Two teams of slots; team 0 pushes the cart in lane -LANE_Y, team 1 +LANE_Y.
var teams: Array = []
## Cart progress along x, TRACK_START..TRACK_END, per team.
var cart_x := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"cart_push",
				"controls": "Move — WASD / left stick (push by contact)",
				"name": "Cart Push",
				"category": MinigameMeta.Category.TEAM,
				"min_players": 4,
				"max_players": 6,
				"duration_sec": 75.0,
				"rules":
				"Push your cart to the depot — and body-block theirs! First cart home wins.",
			}
		)
	)


func _setup() -> void:
	team_mode = true
	var shuffled := slots.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: int = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = swap
	teams = [shuffled.slice(0, shuffled.size() / 2), shuffled.slice(shuffled.size() / 2)]
	for team_index in teams.size():
		cart_x[team_index] = TRACK_START
		for i in teams[team_index].size():
			var slot: int = teams[team_index][i]
			positions[slot] = Vector2(TRACK_START - 0.5 - i, _lane_y(team_index))
			move_dirs[slot] = Vector2.ZERO


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	for slot: int in slots:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
	_resolve_shoves()
	for team_index in teams.size():
		_move_cart(team_index, delta)
	_check_end()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
	return {
		"players": players,
		"carts": [snappedf(cart_x[0], 0.01), snappedf(cart_x[1], 0.01)],
		"track": [TRACK_START, TRACK_END],
		"lane_y": LANE_Y,
		"teams": teams.duplicate(true),
	}


## Teams best-first by cart progress (the #52 team routing awards SPEC $5
## tables); a dead heat is a full tie.
func _rank_players() -> Array:
	var a: float = cart_x[0]
	var b: float = cart_x[1]
	if is_equal_approx(a, b):
		return [slots.duplicate()]
	var order := [teams[0], teams[1]] if a > b else [teams[1], teams[0]]
	return [order[0].duplicate(), order[1].duplicate()]


func pushers_of(team_index: int) -> int:
	var cart := _cart_pos(team_index)
	var count := 0
	for slot: int in teams[team_index]:
		var pos: Vector2 = positions[slot]
		if pos.distance_to(cart) <= CART_REACH and pos.x < float(cart_x[team_index]):
			if float(move_dirs[slot].x) > 0.1:
				count += 1
	return count


func blockers_of(team_index: int) -> int:
	var cart := _cart_pos(team_index)
	var count := 0
	for slot: int in teams[1 - team_index]:
		var pos: Vector2 = positions[slot]
		if pos.distance_to(cart) <= CART_REACH and pos.x > float(cart_x[team_index]):
			count += 1
	return count


func _move_cart(team_index: int, delta: float) -> void:
	if blockers_of(team_index) > 0:
		return
	var pushers := mini(pushers_of(team_index), MAX_EFFECTIVE_PUSHERS)
	if pushers > 0:
		cart_x[team_index] = minf(
			float(cart_x[team_index]) + pushers * CART_SPEED_PER_PUSHER * delta, TRACK_END
		)
	else:
		cart_x[team_index] = maxf(float(cart_x[team_index]) - ROLLBACK_SPEED * delta, TRACK_START)


func _resolve_shoves() -> void:
	for i in slots.size():
		for j in range(i + 1, slots.size()):
			var a: int = slots[i]
			var b: int = slots[j]
			var apart: Vector2 = positions[b] - positions[a]
			if apart.length() > PLAYER_RADIUS * 2.0:
				continue
			var axis := apart.normalized() if apart.length() > 0.001 else Vector2.RIGHT
			positions[a] -= axis * PUSH_DISTANCE
			positions[b] += axis * PUSH_DISTANCE


func _check_end() -> void:
	if finished:
		return
	if float(cart_x[0]) >= TRACK_END or float(cart_x[1]) >= TRACK_END:
		finish(_rank_players())


func _cart_pos(team_index: int) -> Vector2:
	return Vector2(float(cart_x[team_index]), _lane_y(team_index))


func _lane_y(team_index: int) -> float:
	return -LANE_Y if team_index == 0 else LANE_Y
