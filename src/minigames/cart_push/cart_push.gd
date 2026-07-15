class_name CartPush
extends MinigameBase
## Payload Race (#932, reworked from the shared-cart Cart Push #175): two teams,
## two parallel rails. Each team pushes THEIR OWN cart from the start line to
## the finish. Active pushing — alternate ◀▶ beside your cart to add impulse,
## with diminishing per-pusher returns (sqrt), so peeling off to sabotage the
## enemy lane has real value. Sabotage = the telegraphed dash-shove staggers a
## pusher off their mash rhythm. Progress is monotonic per lane (carts never
## roll back), so there is never a stalemate and the standings read from any
## frame. First cart home wins; on timeout the farther cart wins, a dead heat
## ties. Server-side simulation only.
##
## The id stays `cart_push` (catalog slot, key art, credits) — this is the same
## slot, rebuilt from a passive shared cart into an active two-lane race.

const ARENA_HALF := 10.0
## Two rails: team 0 on -LANE_Y, team 1 on +LANE_Y; both race from the start
## line at -TRACK_HALF to the finish at +TRACK_HALF.
const LANE_Y := 3.5
const TRACK_HALF := 8.0
const TRACK_LENGTH := TRACK_HALF * 2.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
## An alternation counts as a push only within this reach of your own cart.
const CART_REACH := 1.9
## Cart progress (world units) added per valid ◀▶ alternation, before the crowd
## diminish. The whole team packed on one cart is sqrt-diminished, so a lone
## pusher is worth 1× and four are worth ~2× — splitting off to sabotage pays.
const PUSH_PER_ALTERNATION := 0.42
## Brief per-slot "actively pushing" flash for the view, set on each push.
const PUSH_FLASH_SEC := 0.2
## Dash-shove (the sabotage verb): telegraphed windup, knockback + stagger, then
## a cooldown — reused from the original Cart Push.
const SHOVE_WINDUP_SEC := 0.6
const SHOVE_COOLDOWN_SEC := 3.0
const SHOVE_RANGE := 1.6
const SHOVE_KNOCKBACK := 2.5
const SHOVE_STAGGER_SEC := 0.9

## get_snapshot() wire shapes (#708): named indices for the players positional
## array. Array SHAPE on the wire is unchanged — additive only.
const PS_X := 0
const PS_Y := 1
const PS_FLAGS := 2
const PS_COUNT := 3
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. Validated by test_snapshot_schema against get_snapshot().
const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT, TYPE_INT]
## PS_FLAGS bitfield.
const FLAG_STAGGERED := 1
const FLAG_WINDUP := 2
const FLAG_PUSHING := 4

var positions := {}
var move_dirs := {}
## Two randomly-drafted halves; teams[0] on the -y lane, teams[1] on +y.
var teams: Array = []
## Each team's cart progress along its rail, 0..TRACK_LENGTH. Monotonic — never
## decreases, so the race can't stalemate.
var progress: Array[float] = [0.0, 0.0]
## slot -> seconds of stagger left (no movement, no push, no shove).
var staggers := {}
var shove_windups := {}
var shove_cooldowns := {}
## slot -> seconds of "just pushed" flash left (view feedback only).
var push_flash := {}
## Last ◀▶ push phase per slot (-1 = none). Only alternations count, so holding
## a key does nothing (the Tug of War idiom).
var _last_phase := {}
## Set once a cart reaches the finish, so the win resolves on that team.
var _winner := -1


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"cart_push",
				"controls": "Push — alternate LEFT/RIGHT at your cart · Shove — SPACE / pad A",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				[
					"Push — alternate ◀▶ at your cart · Shove — ",
					{"action": &"action_primary"},
				],
				# Structured spec (#832/#844): the lr-cluster mash (Tug of War) plus
				# the shove button.
				"control_spec":
				[
					{
						"verb": "Push (at your cart)",
						"input": InputGlyphs.CLUSTER_MOVE_LR,
						"note": "alternate fast!",
					},
					{"verb": "Shove", "input": &"action_primary"},
				],
				"name": "Payload Race",
				"category": MinigameMeta.Category.TEAM,
				"min_players": 4,
				"max_players": 8,
				"even_players": true,
				"duration_sec": 75.0,
				"rules":
				(
					"Two carts, two lanes — race YOUR cart to the finish! Mash left"
					+ " and right beside it to push; peel off to shove the enemy's"
					+ " pushers and stall their lane. First cart home wins."
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
		var lane := lane_y(team_index)
		for i in teams[team_index].size():
			var slot: int = teams[team_index][i]
			# Line the team up behind the start line on its own lane.
			positions[slot] = Vector2(
				-TRACK_HALF - 1.0, lane + (i - (teams[team_index].size() - 1) / 2.0) * 0.9
			)
			move_dirs[slot] = Vector2.ZERO
			staggers[slot] = 0.0
			shove_windups[slot] = 0.0
			shove_cooldowns[slot] = 0.0
			_last_phase[slot] = -1
			push_flash[slot] = 0.0


func lane_y(team_index: int) -> float:
	return -LANE_Y if team_index == 0 else LANE_Y


## World position of a team's cart along its rail.
func cart_pos(team_index: int) -> Vector2:
	return Vector2(-TRACK_HALF + progress[team_index], lane_y(team_index))


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if float(staggers[slot]) > 0.0:
		return
	# Sabotage shove (telegraphed) — the original Cart Push verb.
	if (
		data.get("shove", false)
		and float(shove_windups[slot]) <= 0.0
		and float(shove_cooldowns[slot]) <= 0.0
	):
		shove_windups[slot] = SHOVE_WINDUP_SEC
	# Active push: only alternating ◀▶ phases count, and only beside your cart.
	if data.has("push"):
		var phase := int(data.push)
		if (phase == 0 or phase == 1) and phase != int(_last_phase[slot]):
			_last_phase[slot] = phase
			_apply_push(slot)


## A valid alternation from a pusher within reach of its own cart advances that
## cart, sqrt-diminished by how many teammates share the push — so the fourth
## pusher adds far less than the first, and splitting off to sabotage is worth
## more than piling on.
func _apply_push(slot: int) -> void:
	var team_index := _team_of(slot)
	if positions[slot].distance_to(cart_pos(team_index)) > CART_REACH:
		return
	var crowd := _pushers_at_cart(team_index)
	progress[team_index] = minf(
		progress[team_index] + PUSH_PER_ALTERNATION / sqrt(float(maxi(crowd, 1))), TRACK_LENGTH
	)
	push_flash[slot] = PUSH_FLASH_SEC


## Live teammates within reach of the team's cart — the crowd sharing the push.
func _pushers_at_cart(team_index: int) -> int:
	var cart := cart_pos(team_index)
	var count := 0
	for slot: int in teams[team_index]:
		if float(staggers[slot]) <= 0.0 and positions[slot].distance_to(cart) <= CART_REACH:
			count += 1
	return count


func _tick(delta: float) -> void:
	for slot: int in slots:
		staggers[slot] = maxf(0.0, float(staggers[slot]) - delta)
		shove_cooldowns[slot] = maxf(0.0, float(shove_cooldowns[slot]) - delta)
		push_flash[slot] = maxf(0.0, float(push_flash[slot]) - delta)
		if float(staggers[slot]) > 0.0:
			continue
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
	_tick_shoves(delta)
	_separate_bodies()
	_check_end()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		var flags := 0
		flags |= FLAG_STAGGERED if float(staggers[slot]) > 0.0 else 0
		flags |= FLAG_WINDUP if float(shove_windups[slot]) > 0.0 else 0
		flags |= FLAG_PUSHING if float(push_flash[slot]) > 0.0 else 0
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), flags]
	return {
		"players": players,
		"carts": [snappedf(progress[0], 0.01), snappedf(progress[1], 0.01)],
		"track_length": TRACK_LENGTH,
		"teams": teams.duplicate(true),
	}


## First cart home wins; else the farther cart; a dead heat ties (SPEC $5 team
## tables). The framework calls this on timeout; _check_end calls it on a win.
func _rank_players() -> Array:
	if _winner >= 0:
		return [teams[_winner].duplicate(), teams[1 - _winner].duplicate()]
	if is_equal_approx(progress[0], progress[1]):
		return [slots.duplicate()]
	var lead := 0 if progress[0] > progress[1] else 1
	return [teams[lead].duplicate(), teams[1 - lead].duplicate()]


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


## Overlapping bodies push apart (shared math, #945).
func _separate_bodies() -> void:
	var min_gap := PLAYER_RADIUS * 2.0
	for i in slots.size():
		for j in range(i + 1, slots.size()):
			var a: int = slots[i]
			var b: int = slots[j]
			var push := SimGeometry.separation_push(positions[a], positions[b], min_gap)
			if push == Vector2.ZERO:
				continue
			positions[a] -= push
			positions[b] += push


func _check_end() -> void:
	if finished:
		return
	for team_index in teams.size():
		if progress[team_index] >= TRACK_LENGTH:
			_winner = team_index
			finish(_rank_players())
			return


func _team_of(slot: int) -> int:
	return 0 if slot in (teams[0] as Array) else 1
