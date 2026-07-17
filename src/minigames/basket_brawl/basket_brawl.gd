class_name BasketBrawl
extends MinigameBase
## Basket Brawl (M10-09; #1037 NBA2K-feel rework): two teams, one ball.
## Dunk (carry into the enemy hoop zone) for 2, or SHOOT — a charge-and-
## release with a 2K-style timing window: hold to wind up (rooted while
## charging), release inside the sweet window for full odds, early/late for
## a brick. Beyond the arc pays 3. A defender in the shooter's face at
## release halves the odds — contest is real. Passes fly along the passer's
## aim (nearest teammate in that half-plane), loose and interceptable; a
## whiffed steal staggers the poker, so carriers can bait. After a score
## the scored-on team inbounds at their own hoop (the scorers can't touch
## the ball for a beat) — score, then defend the length of the court.
## Most points when time expires wins.
## Server-side simulation only — the client renders get_snapshot().
##
## #1037 history: shooting arrived in #803 but was uncontestable RNG worth
## the same 1 point as everything else, and scores dumped the ball back
## into a center scrum — a shapeless coin-flip drill. This rework gives it
## basketball's actual skeleton: a reward curve, defensive agency, a skill
## verb, and possession rhythm.

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

## Shooting (#803, reworked #1037): a charge-and-release. Holding the shoot
## button winds up (CHARGE_FULL_SEC to full) and roots the shooter to a
## shuffle — the risk window stealers and contesters play against. Release
## timing is the skill: inside the sweet window (as a fraction of full
## charge) keeps full odds, releasing early or hanging late decays toward
## TIMING_WORST_MULT. Distance still sets the base curve, and a defender
## within CONTEST_RADIUS at release halves it — an open look is a real
## thing. Makes pay POINTS_SHOT, or POINTS_ARC from beyond ARC_DIST; the
## dunk stays the guaranteed close finish at POINTS_DUNK.
const SHOT_SPEED := 16.0
const MAKE_CHANCE_NEAR := 0.9
const MAKE_CHANCE_FAR := 0.3
const SHOT_NEAR_DIST := 3.0
const SHOT_FAR_DIST := 8.0
## A missed shot rebounds off the rim at this speed, back into live play.
const REBOUND_SPEED := 7.0
## The 2K skill surface (#1037): wind-up time, the sweet release window as
## charge fractions, and how badly a mistimed release decays the odds.
const CHARGE_FULL_SEC := 0.9
const PERFECT_LO := 0.7
const PERFECT_HI := 0.95
const TIMING_WORST_MULT := 0.35
## Charging roots the shooter to a shuffle — the contested-shot risk window.
const CHARGE_MOVE_MULT := 0.2
## A defender this close at release halves the make (#1037): contest is real.
const CONTEST_RADIUS := 1.6
const CONTEST_MULT := 0.5
## The scoring curve (#1037): dunks and inside shots pay 2, beyond the arc
## pays 3 — the long gamble finally pays MORE, not the same.
const POINTS_DUNK := 2
const POINTS_SHOT := 2
const POINTS_ARC := 3
const ARC_DIST := 6.0
## A whiffed steal staggers the poker (#1037) — spam is punishable, carriers
## can bait the lunge.
const STEAL_STAGGER_SEC := 0.5
const STAGGER_MOVE_MULT := 0.3
## After a score the scorers can't touch the inbound ball for this long, so
## the scored-on team's possession actually starts (#1037).
const INBOUND_LOCK_SEC := 1.0

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is append-only.
const PS_X := 0
const PS_Y := 1
const PS_HAS_BALL := 2
## #1037 append-only addition: shot charge as a 0..1 fraction of full wind-up
## (0 while not charging) — the view's meter and the brain's release timing.
const PS_CHARGE := 3
const PS_COUNT := 4
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. Validated by test_snapshot_schema against get_snapshot().
const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_FLOAT]

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
## What the in-flight shot pays if it drops (#1037): 2 inside, 3 from deep.
var _shot_points := POINTS_SHOT
## Wind-up seconds per slot while the shoot button is held (#1037); -1 = not
## charging. Cleared on release/fumble/pass.
var _charge := {}
## Whiffed-steal stagger seconds remaining per slot (#1037).
var _stagger := {}


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
					"Dunk for 2 — or CHARGE a shot and release in the sweet spot"
					+ " (3 from downtown, but a hand in your face halves it!)."
					+ " Aim your passes, time your steals: a whiff staggers you."
					+ " Score, then defend — they inbound at their hoop."
				),
				"controls":
				(
					"Move — WASD / left stick · Pass (carrying) / Steal — SPACE / pad A"
					+ " · Shoot — HOLD & release E / pad X"
				),
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				[
					"Move — WASD / left stick · Pass (carrying) / Steal — ",
					{"action": &"action_primary"},
					" · Shoot — hold & release ",
					{"action": &"action_secondary"},
				],
				# Structured spec (#832/#844): move + role-qualified actions.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"verb": "Pass (carrying) / Steal", "input": &"action_primary"},
					{"verb": "Shoot", "input": &"action_secondary", "modifier": "hold & release"},
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
			_charge[slot] = -1.0
			_stagger[slot] = 0.0
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
		elif float(shove_cooldowns[slot]) <= 0.0 and float(_stagger[slot]) <= 0.0:
			_try_shove(slot)
	# The 2K shot (#1037): press starts the wind-up, release fires with the
	# timing quality. A packet without the key changes nothing (held state).
	if data.has("shoot") and holder == slot:
		if bool(data.shoot):
			if float(_charge[slot]) < 0.0:
				_charge[slot] = 0.0
		elif float(_charge[slot]) >= 0.0:
			_shoot(slot, _release_quality(float(_charge[slot])))
			_charge[slot] = -1.0


## The 2K release curve (#1037): full odds inside the sweet window, decaying
## linearly to TIMING_WORST_MULT at a stone-cold-early or hung-to-the-cap
## release (charge holds at the cap, so hanging on IS the max-late brick).
func _release_quality(charge_sec: float) -> float:
	var fraction := clampf(charge_sec / CHARGE_FULL_SEC, 0.0, 1.0)
	if fraction >= PERFECT_LO and fraction <= PERFECT_HI:
		return 1.0
	var miss := (
		(PERFECT_LO - fraction) / PERFECT_LO
		if fraction < PERFECT_LO
		else (fraction - PERFECT_HI) / (1.0 - PERFECT_HI)
	)
	return lerpf(1.0, TIMING_WORST_MULT, clampf(miss, 0.0, 1.0))


func _tick(delta: float) -> void:
	for slot: int in slots:
		shove_cooldowns[slot] = maxf(float(shove_cooldowns[slot]) - delta, 0.0)
		_no_catch[slot] = maxf(float(_no_catch[slot]) - delta, 0.0)
		_stagger[slot] = maxf(float(_stagger[slot]) - delta, 0.0)
		if float(_charge[slot]) >= 0.0:
			if holder == slot:
				_charge[slot] = minf(float(_charge[slot]) + delta, CHARGE_FULL_SEC)
			else:
				_charge[slot] = -1.0  # fumbled/passed mid-wind-up: it's gone
		var speed := MOVE_SPEED * (CARRY_SPEED_MULT if holder == slot else 1.0)
		if float(_charge[slot]) >= 0.0:
			speed *= CHARGE_MOVE_MULT  # rooted mid-wind-up (#1037)
		elif float(_stagger[slot]) > 0.0:
			speed *= STAGGER_MOVE_MULT  # eating a whiffed steal (#1037)
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
		var charge := float(_charge[slot])
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			1 if holder == slot else 0,
			snappedf(clampf(charge / CHARGE_FULL_SEC, 0.0, 1.0) if charge >= 0.0 else 0.0, 0.01),
		]
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


## Aimed pass (#1037): the target is the nearest teammate in the passer's
## steer half-plane — you choose WHERE the pass goes by facing it, and an
## unaimed panic pass falls back to the nearest mate. The ball still flies
## loose and interceptable either way; a bad read is a turnover.
func _pass_ball(slot: int) -> void:
	var steer: Vector2 = move_dirs[slot]
	var aimed := steer.length() > 0.3
	var nearest := -1
	var best := INF
	for mate: int in teams[_team_of(slot)]:
		if mate == slot:
			continue
		var to_mate: Vector2 = positions[mate] - positions[slot]
		if aimed and to_mate.dot(steer) <= 0.0:
			continue  # behind the aim: not this pass's target
		var dist := to_mate.length()
		if dist < best:
			best = dist
			nearest = mate
	_charge[slot] = -1.0
	if nearest == -1 and aimed:
		# Nobody in the aimed half-plane: the pass flies where you aimed it
		# anyway — into space, probably a turnover. Aim better.
		holder = -1
		ball_vel = steer.normalized() * PASS_SPEED
		_no_catch[slot] = NO_CATCH_SEC
		return
	if nearest == -1:
		return
	holder = -1
	var dir: Vector2 = positions[nearest] - positions[slot]
	ball_vel = (dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT) * PASS_SPEED
	_no_catch[slot] = NO_CATCH_SEC


## Fire the wound-up shot (#803, reworked #1037). Odds = the distance curve ×
## the release timing quality × the contest penalty (a defender in the
## shooter's face at release halves it). The ball still flies the full arc so
## the outcome only lands at the rim — a make drops in for POINTS_SHOT (or
## POINTS_ARC from beyond the arc), a miss clangs into a live rebound.
func _shoot(slot: int, quality: float) -> void:
	var target := attack_hoop(slot)
	var dist: float = positions[slot].distance_to(target)
	var chance := lerpf(
		MAKE_CHANCE_NEAR,
		MAKE_CHANCE_FAR,
		clampf((dist - SHOT_NEAR_DIST) / (SHOT_FAR_DIST - SHOT_NEAR_DIST), 0.0, 1.0)
	)
	chance *= quality
	if _is_contested(slot):
		chance *= CONTEST_MULT
	_shot_make = rng.randf() < clampf(chance, 0.02, 0.98)
	_shot_team = _team_of(slot)
	_shot_target = target
	_shot_points = POINTS_ARC if dist >= ARC_DIST else POINTS_SHOT
	_shot_active = true
	holder = -1
	ball_pos = positions[slot]
	var dir := target - ball_pos
	ball_vel = (dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT) * SHOT_SPEED
	_no_catch[slot] = NO_CATCH_SEC


## A defender within CONTEST_RADIUS of the shooter (#1037) — the open look.
func _is_contested(shooter: int) -> bool:
	for defender: int in teams[1 - _team_of(shooter)]:
		if positions[shooter].distance_to(positions[defender]) <= CONTEST_RADIUS:
			return true
	return false


## Advance a shot in flight; it can't be caught mid-air. When it reaches the
## rim, a made shot scores and resets, a miss clangs off into a live rebound.
func _tick_shot(delta: float) -> void:
	ball_pos += ball_vel * delta
	if ball_pos.distance_to(_shot_target) > HOOP_RADIUS:
		return
	_shot_active = false
	if _shot_make:
		_score(_shot_team, _shot_points)
	else:
		# Clang: scatter back into the court, away from the rim, as a live ball.
		var away := ball_pos - _shot_target
		if away.length() <= 0.001:
			away = Vector2(-signf(_shot_target.x), 0.0)
		var jitter := rng.randf_range(-0.6, 0.6)
		ball_vel = away.normalized().rotated(jitter) * REBOUND_SPEED


## Award points and start the inbound (#1037): the ball respawns at the
## scored-on team's OWN hoop and the scorers can't touch it for a beat, so
## possession genuinely changes hands — score, then defend the court length.
func _score(team: int, points: int) -> void:
	scores[team] = int(scores[team]) + points
	holder = -1
	var scored_on := 1 - team
	# The scored-on team defends -x when they're team 0, +x when team 1.
	ball_pos = Vector2(-HOOP_X if scored_on == 0 else HOOP_X, 0.0) * 0.9
	ball_vel = Vector2.ZERO
	for scorer: int in teams[team]:
		_no_catch[scorer] = INBOUND_LOCK_SEC


## The steal poke (#1037): connecting with an adjacent enemy carrier pops the
## ball loose away from the poker — but a WHIFF staggers you (STEAL_STAGGER_SEC
## at a crawl) on top of the cooldown, so lunging is a read, not a spam. A
## carrier dancing at the edge of your reach is baiting you.
func _try_shove(slot: int) -> void:
	shove_cooldowns[slot] = SHOVE_COOLDOWN_SEC
	if (
		holder == -1
		or _team_of(holder) == _team_of(slot)
		or positions[slot].distance_to(positions[holder]) > SHOVE_RADIUS
	):
		_stagger[slot] = STEAL_STAGGER_SEC
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
	_score(_team_of(holder), POINTS_DUNK)
