class_name CartPush
extends MinigameBase
## Cart Push (M4-12, recreated per #175): ONE shared ore cart on a straight
## center rail, both teams pushing it opposite ways — a tug-of-war you can
## walk around. Net force = your effective pushers minus theirs (capped per
## side). Dash-shoves (windup + cooldown) knock opponents off the cart;
## rumble strips stagger everyone touching the cart when it crosses; ore
## pickups delivered to your own depot add permanent bonus push. Win by
## shoving the cart into the opposing depot; at time-out the cart's side of
## center decides. Server-side simulation only.

const ARENA_HALF := 10.0
## Team 0 shoves the cart toward +TRACK_END (team 1's depot), team 1 toward
## -TRACK_END. Own depots are the rail ends behind each team.
const TRACK_END := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const BODY_PUSH := 0.35
## Reach around the cart within which players contribute push.
const CART_REACH := 1.8
const CART_SPEED_PER_PUSHER := 0.9
const MAX_EFFECTIVE_PUSHERS := 3
## Dash-shove: telegraphed windup, knockback + stagger, then a cooldown.
const SHOVE_WINDUP_SEC := 0.6
const SHOVE_COOLDOWN_SEC := 3.0
const SHOVE_RANGE := 1.6
const SHOVE_KNOCKBACK := 2.5
const SHOVE_STAGGER_SEC := 0.8
## Crossing a rumble strip staggers everyone currently touching the cart.
const RUMBLE_XS: Array[float] = [-4.5, 4.5]
const RUMBLE_STAGGER_SEC := 0.8
## Ore pickups: deliver to your own depot for a permanent bonus pusher.
const ORE_SPAWN_SEC := 10.0
const ORE_MAX_ACTIVE := 2
const ORE_PICKUP_RADIUS := 0.8
const ORE_BONUS_MAX := 2
const DEPOT_RADIUS := 1.6

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_FLAGS := 2
const PS_COUNT := 3

const OR_ID := 0
const OR_X := 1
const OR_Y := 2

var positions := {}
var move_dirs := {}
## Two randomly-drafted halves; teams[0] pushes +x, teams[1] pushes -x.
var teams: Array = []
## The one shared cart's position along the rail (y = 0).
var cart_x := 0.0
## slot -> seconds of stagger left (no movement, no push, no shove).
var staggers := {}
## slot -> windup seconds left before the shove lands (telegraphed).
var shove_windups := {}
var shove_cooldowns := {}
var ores: Array[Dictionary] = []
## slot -> true while carrying an ore (dropped on shove).
var carrying := {}
## Delivered-ore bonus pusher-equivalents per team, capped.
var bonus_pushers: Array[int] = [0, 0]

var _ore_accum := 0.0
var _next_ore_id := 0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"cart_push",
				"controls": "Move — WASD / left stick · Shove — SPACE / pad A",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				["Move — WASD / left stick · Shove — ", {"action": &"action_primary"}],
				"name": "Cart Push",
				"category": MinigameMeta.Category.TEAM,
				"min_players": 4,
				"max_players": 8,
				"even_players": true,
				"duration_sec": 75.0,
				"rules":
				(
					"One cart, two teams, opposite depots — shove it into theirs!"
					+ " Dash-shove defenders off the cart, brace for the rumble"
					+ " strips, and bank ore at your depot for permanent muscle."
				),
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
		var side := -1.0 if team_index == 0 else 1.0
		for i in teams[team_index].size():
			var slot: int = teams[team_index][i]
			# Each team starts on its own pushing side of the cart.
			positions[slot] = Vector2(side * 2.0, (i - (teams[team_index].size() - 1) / 2.0) * 1.5)
			move_dirs[slot] = Vector2.ZERO
			staggers[slot] = 0.0
			shove_windups[slot] = 0.0
			shove_cooldowns[slot] = 0.0
			carrying[slot] = false


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if (
		data.get("shove", false)
		and float(staggers[slot]) <= 0.0
		and float(shove_windups[slot]) <= 0.0
		and float(shove_cooldowns[slot]) <= 0.0
	):
		shove_windups[slot] = SHOVE_WINDUP_SEC


func _tick(delta: float) -> void:
	var cart_before := cart_x
	for slot: int in slots:
		staggers[slot] = maxf(0.0, float(staggers[slot]) - delta)
		shove_cooldowns[slot] = maxf(0.0, float(shove_cooldowns[slot]) - delta)
		if float(staggers[slot]) > 0.0:
			continue
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
	_tick_shoves(delta)
	_separate_bodies()
	_tick_ores(delta)
	_move_cart(delta)
	_check_rumble(cart_before)
	_check_end()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		var flags := 0
		flags |= 1 if carrying[slot] else 0
		flags |= 2 if float(staggers[slot]) > 0.0 else 0
		flags |= 4 if float(shove_windups[slot]) > 0.0 else 0
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), flags]
	var ore_list: Array = []
	for ore: Dictionary in ores:
		var pos: Vector2 = ore.pos
		ore_list.append([int(ore.id), snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)])
	return {
		"players": players,
		"cart": snappedf(cart_x, 0.01),
		"teams": teams.duplicate(true),
		"ores": ore_list,
		"bonus": bonus_pushers.duplicate(),
	}


## Winner is whoever's goal the cart is closer to; dead center is a full tie.
func _rank_players() -> Array:
	if is_zero_approx(cart_x):
		return [slots.duplicate()]
	var order := [teams[0], teams[1]] if cart_x > 0.0 else [teams[1], teams[0]]
	return [order[0].duplicate(), order[1].duplicate()]


## Effective pushers: teammates touching the cart from their own pushing
## side, not staggered; delivered-ore bonus counts only while at least one
## live pusher is on the cart (no ghost pushing).
func effective_pushers(team_index: int) -> int:
	var cart := Vector2(cart_x, 0.0)
	var side := -1.0 if team_index == 0 else 1.0
	var live := 0
	for slot: int in teams[team_index]:
		if float(staggers[slot]) > 0.0:
			continue
		var pos: Vector2 = positions[slot]
		if pos.distance_to(cart) <= CART_REACH and signf(pos.x - cart_x) == side:
			live += 1
	live = mini(live, MAX_EFFECTIVE_PUSHERS)
	if live == 0:
		return 0
	return live + bonus_pushers[team_index]


func _move_cart(delta: float) -> void:
	var net := effective_pushers(0) - effective_pushers(1)
	cart_x = clampf(cart_x + net * CART_SPEED_PER_PUSHER * delta, -TRACK_END, TRACK_END)


func _tick_shoves(delta: float) -> void:
	for slot: int in slots:
		if float(shove_windups[slot]) <= 0.0:
			continue
		# Getting staggered mid-windup cancels the shove (no refund).
		if float(staggers[slot]) > 0.0:
			shove_windups[slot] = 0.0
			shove_cooldowns[slot] = SHOVE_COOLDOWN_SEC
			continue
		shove_windups[slot] = float(shove_windups[slot]) - delta
		if float(shove_windups[slot]) > 0.0:
			continue
		shove_windups[slot] = 0.0
		shove_cooldowns[slot] = SHOVE_COOLDOWN_SEC
		_land_shove(slot)


func _land_shove(shover: int) -> void:
	var team_index := _team_of(shover)
	for slot: int in teams[1 - team_index]:
		var apart: Vector2 = positions[slot] - positions[shover]
		if apart.length() > SHOVE_RANGE:
			continue
		var axis := apart.normalized() if apart.length() > 0.001 else Vector2.RIGHT
		positions[slot] = (positions[slot] + axis * SHOVE_KNOCKBACK).clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
		staggers[slot] = SHOVE_STAGGER_SEC
		if carrying[slot]:
			# Shoved carriers drop their ore where they stood.
			carrying[slot] = false
			ores.append({"id": _next_ore_id, "pos": positions[slot]})
			_next_ore_id += 1


func _separate_bodies() -> void:
	for i in slots.size():
		for j in range(i + 1, slots.size()):
			var a: int = slots[i]
			var b: int = slots[j]
			var apart: Vector2 = positions[b] - positions[a]
			if apart.length() > PLAYER_RADIUS * 2.0:
				continue
			var axis := apart.normalized() if apart.length() > 0.001 else Vector2.RIGHT
			positions[a] -= axis * BODY_PUSH
			positions[b] += axis * BODY_PUSH


func _tick_ores(delta: float) -> void:
	_ore_accum += delta
	if _ore_accum >= ORE_SPAWN_SEC and ores.size() < ORE_MAX_ACTIVE:
		_ore_accum = 0.0
		(
			ores
			. append(
				{
					"id": _next_ore_id,
					"pos":
					Vector2(
						rng.randf_range(-ARENA_HALF + 1.0, ARENA_HALF - 1.0),
						(
							(1.0 if rng.randf() < 0.5 else -1.0)
							* rng.randf_range(2.5, ARENA_HALF - 1.0)
						)
					),
				}
			)
		)
		_next_ore_id += 1
	for slot: int in slots:
		if float(staggers[slot]) > 0.0:
			continue
		if not carrying[slot]:
			for i in ores.size():
				if positions[slot].distance_to(ores[i].pos) <= ORE_PICKUP_RADIUS:
					carrying[slot] = true
					ores.remove_at(i)
					break
			continue
		var team_index := _team_of(slot)
		if positions[slot].distance_to(_depot_of(team_index)) <= DEPOT_RADIUS:
			carrying[slot] = false
			bonus_pushers[team_index] = mini(bonus_pushers[team_index] + 1, ORE_BONUS_MAX)


## Crossing a rumble strip staggers everyone touching the cart — both sides.
func _check_rumble(cart_before: float) -> void:
	for strip: float in RUMBLE_XS:
		if signf(cart_before - strip) == signf(cart_x - strip) or cart_before == cart_x:
			continue
		var cart := Vector2(cart_x, 0.0)
		for slot: int in slots:
			if positions[slot].distance_to(cart) <= CART_REACH:
				staggers[slot] = maxf(float(staggers[slot]), RUMBLE_STAGGER_SEC)


func _check_end() -> void:
	if finished:
		return
	if absf(cart_x) >= TRACK_END:
		finish(_rank_players())


func _team_of(slot: int) -> int:
	return 0 if slot in (teams[0] as Array) else 1


## Your own depot is the rail end behind you — team 0 defends -x, pushes +x.
func _depot_of(team_index: int) -> Vector2:
	return Vector2(-TRACK_END if team_index == 0 else TRACK_END, 0.0)
