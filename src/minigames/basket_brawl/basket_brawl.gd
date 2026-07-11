class_name BasketBrawl
extends MinigameBase
## Basket Brawl (M10-09, PHASE2.md $4 #26): two teams, one ball — carry it
## into the enemy hoop to dunk. Carriers are slower and shovable (a shove
## pops the ball loose), and a pass zips the ball toward a teammate but
## flies loose and interceptable. Most dunks when time expires wins.
## Server-side simulation only — the client renders get_snapshot().

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const CARRY_SPEED_MULT := 0.7
const PLAYER_RADIUS := 0.45
## Hoops sit at x = ±HOOP_X: team 0 defends -x and dunks at +x, team 1 the
## mirror. Dunking means carrying the ball into the enemy hoop zone.
const HOOP_X := 8.0
const HOOP_RADIUS := 1.5
const CATCH_RADIUS := 0.8
const PASS_SPEED := 14.0
## Loose-ball friction: passes and fumbles skid to a stop.
const BALL_DRAG := 8.0
const FUMBLE_SPEED := 6.0
const SHOVE_RADIUS := 1.3
const SHOVE_COOLDOWN_SEC := 1.5
## A fresh pass or fumble can't be re-caught by its source for this long —
## otherwise the passer instantly re-grabs their own ball.
const NO_CATCH_SEC := 0.25

## Aimed shooting (#803, owner-approved): action_secondary while carrying lofts
## the ball at the enemy hoop. It flies a real arc across the court (the view
## renders the height), then either drops through for a score or clangs off and
## rebounds live for a scramble. The make chance is the skill/balance surface —
## near-automatic up close, a coin-flip-or-worse from downtown — so shooting
## adds a risk/reward call the carry-and-dunk game lacked; the dunk stays as the
## guaranteed close finish.
const SHOT_SPEED := 16.0
const MAKE_CHANCE_NEAR := 0.9
const MAKE_CHANCE_FAR := 0.3
const SHOT_NEAR_DIST := 3.0
const SHOT_FAR_DIST := 8.0
## A missed shot rebounds off the rim at this speed, back into live play.
const REBOUND_SPEED := 7.0

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is append-only.
const PS_X := 0
const PS_Y := 1
const PS_HAS_BALL := 2
const PS_COUNT := 3

const BALL_X := 0
const BALL_Y := 1
const BALL_HOLDER := 2
## 1 while the ball is a shot in flight (the view arcs it up to the hoop).
const BALL_SHOT := 3
const BALL_COUNT := 4

const HP_X := 0
const HP_Y := 1

var positions := {}
var move_dirs := {}
var shove_cooldowns := {}
## Two shuffled halves; even_players keeps the draft at 4 or 6 (#178).
var teams: Array = []
var scores: Array = [0, 0]
var ball_pos := Vector2.ZERO
var ball_vel := Vector2.ZERO
## Slot holding the ball, or -1 while it is loose.
var holder := -1

var _no_catch := {}
## Shot-in-flight state (#803): while active the ball is a committed shot flying
## to `_shot_target`, uncatchable, and resolves make/miss on arrival.
var _shot_active := false
var _shot_make := false
var _shot_team := -1
var _shot_target := Vector2.ZERO


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"basket_brawl",
				"name": "Basket Brawl",
				"category": MinigameMeta.Category.TEAM,
				"min_players": 4,
				"max_players": 8,
				"even_players": true,
				"duration_sec": 75.0,
				"rules":
				(
					"One ball, two hoops! Carry it into THEIR hoop to dunk."
					+ " Carriers are slow and shovable — pass to keep it moving,"
					+ " but a flying ball is anyone's ball."
				),
				"controls":
				(
					"Move — WASD / left stick · Pass (carrying) / Shove — SPACE / pad A"
					+ " · Shoot (carrying) — E / pad X"
				),
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				[
					"Move — WASD / left stick · Pass (carrying) / Shove — ",
					{"action": &"action_primary"},
					" · Shoot (carrying) — ",
					{"action": &"action_secondary"},
				],
				# Structured spec (#832/#844): move + role-qualified actions.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"verb": "Pass (carrying) / Shove", "input": &"action_primary"},
					{"verb": "Shoot (carrying)", "input": &"action_secondary"},
				],
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
		for i in teams[team_index].size():
			var slot: int = teams[team_index][i]
			var side := -1.0 if team_index == 0 else 1.0
			positions[slot] = Vector2(side * HOOP_X * 0.6, (i - 0.5) * 2.5)
			move_dirs[slot] = Vector2.ZERO
			shove_cooldowns[slot] = 0.0
			_no_catch[slot] = 0.0
	ball_pos = Vector2.ZERO
	ball_vel = Vector2.ZERO
	holder = -1
	_shot_active = false


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if data.get("act", false):
		if holder == slot:
			_pass_ball(slot)
		elif float(shove_cooldowns[slot]) <= 0.0:
			_try_shove(slot)
	if data.get("shoot", false) and holder == slot:
		_shoot(slot)


func _tick(delta: float) -> void:
	for slot: int in slots:
		shove_cooldowns[slot] = maxf(float(shove_cooldowns[slot]) - delta, 0.0)
		_no_catch[slot] = maxf(float(_no_catch[slot]) - delta, 0.0)
		var speed := MOVE_SPEED * (CARRY_SPEED_MULT if holder == slot else 1.0)
		var pos: Vector2 = positions[slot] + move_dirs[slot] * speed * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
	if _shot_active:
		_tick_shot(delta)
	elif holder == -1:
		ball_pos += ball_vel * delta
		ball_pos = ball_pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
		ball_vel = ball_vel.move_toward(Vector2.ZERO, BALL_DRAG * delta)
		_try_catch()
	else:
		ball_pos = positions[holder]
		_check_dunk()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), 1 if holder == slot else 0]
	return {
		"players": players,
		"ball":
		[snappedf(ball_pos.x, 0.01), snappedf(ball_pos.y, 0.01), holder, 1 if _shot_active else 0],
		"scores": scores.duplicate(),
		"teams": teams.duplicate(true),
		"hoops": [[-HOOP_X, 0.0], [HOOP_X, 0.0]],
	}


## Higher-scoring team first (SPEC $5 team tables via team_mode); a dead
## heat is a full tie.
func _rank_players() -> Array:
	var a := int(scores[0])
	var b := int(scores[1])
	if a == b:
		return [slots.duplicate()]
	var order := [teams[0], teams[1]] if a > b else [teams[1], teams[0]]
	return [order[0].duplicate(), order[1].duplicate()]


func _team_of(slot: int) -> int:
	return 0 if slot in teams[0] else 1


## The hoop this slot dunks at (the enemy's side).
func attack_hoop(slot: int) -> Vector2:
	return Vector2(HOOP_X if _team_of(slot) == 0 else -HOOP_X, 0.0)


func _pass_ball(slot: int) -> void:
	var nearest := -1
	var best := INF
	for mate: int in teams[_team_of(slot)]:
		if mate == slot:
			continue
		var dist: float = positions[slot].distance_to(positions[mate])
		if dist < best:
			best = dist
			nearest = mate
	if nearest == -1:
		return
	holder = -1
	var dir: Vector2 = positions[nearest] - positions[slot]
	ball_vel = (dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT) * PASS_SPEED
	_no_catch[slot] = NO_CATCH_SEC


## Loft the carried ball at the enemy hoop (#803). The make is rolled from the
## distance-based chance curve now; the ball still flies the full arc so the
## outcome only lands when it reaches the rim (a make drops in, a miss rebounds
## live). Close range is near-automatic; downtown is a gamble.
func _shoot(slot: int) -> void:
	var target := attack_hoop(slot)
	var dist: float = positions[slot].distance_to(target)
	var chance := lerpf(
		MAKE_CHANCE_NEAR,
		MAKE_CHANCE_FAR,
		clampf((dist - SHOT_NEAR_DIST) / (SHOT_FAR_DIST - SHOT_NEAR_DIST), 0.0, 1.0)
	)
	_shot_make = rng.randf() < chance
	_shot_team = _team_of(slot)
	_shot_target = target
	_shot_active = true
	holder = -1
	ball_pos = positions[slot]
	var dir := target - ball_pos
	ball_vel = (dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT) * SHOT_SPEED
	_no_catch[slot] = NO_CATCH_SEC


## Advance a shot in flight; it can't be caught mid-air. When it reaches the
## rim, a made shot scores and resets, a miss clangs off into a live rebound.
func _tick_shot(delta: float) -> void:
	ball_pos += ball_vel * delta
	if ball_pos.distance_to(_shot_target) > HOOP_RADIUS:
		return
	_shot_active = false
	if _shot_make:
		scores[_shot_team] = int(scores[_shot_team]) + 1
		ball_pos = Vector2.ZERO
		ball_vel = Vector2.ZERO
	else:
		# Clang: scatter back into the court, away from the rim, as a live ball.
		var away := ball_pos - _shot_target
		if away.length() <= 0.001:
			away = Vector2(-signf(_shot_target.x), 0.0)
		var jitter := rng.randf_range(-0.6, 0.6)
		ball_vel = away.normalized().rotated(jitter) * REBOUND_SPEED


## Shoving an adjacent enemy carrier pops the ball loose away from the
## shover. Whiffs still start the cooldown — spam has a cost.
func _try_shove(slot: int) -> void:
	shove_cooldowns[slot] = SHOVE_COOLDOWN_SEC
	if holder == -1 or _team_of(holder) == _team_of(slot):
		return
	if positions[slot].distance_to(positions[holder]) > SHOVE_RADIUS:
		return
	var away: Vector2 = positions[holder] - positions[slot]
	ball_vel = (away.normalized() if away.length() > 0.001 else Vector2.RIGHT) * FUMBLE_SPEED
	_no_catch[holder] = NO_CATCH_SEC
	holder = -1


func _try_catch() -> void:
	for slot: int in slots:
		if float(_no_catch[slot]) > 0.0:
			continue
		if positions[slot].distance_to(ball_pos) <= CATCH_RADIUS:
			holder = slot
			ball_vel = Vector2.ZERO
			return


func _check_dunk() -> void:
	if positions[holder].distance_to(attack_hoop(holder)) > HOOP_RADIUS:
		return
	var team := _team_of(holder)
	scores[team] = int(scores[team]) + 1
	holder = -1
	ball_pos = Vector2.ZERO
	ball_vel = Vector2.ZERO
