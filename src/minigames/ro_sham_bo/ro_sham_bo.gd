class_name RoShamBo
extends MinigameBase
## Ro-Sham-Bo Royale (M14-05, PHASE2.md $8/9 #M14-05): mass rock-paper-scissors.
## Every alive player runs to one of three pads each sub-round; whichever
## shape loses the group vote is eliminated in one go (a wash — every shape
## present, or everyone matching — changes nothing and the round redraws).
## Once exactly two players remain, a same-shape tie can no longer resolve by
## group vote, so it becomes a sudden-death duel: a target shape is revealed
## and whoever throws its counter first survives. Eliminated players spectate
## and may cast one vote for the eventual champion, paid out as a bonus coin
## if they call it right. Server-side simulation only — the client renders
## get_snapshot().

enum Shape { ROCK, PAPER, SCISSORS }
enum Phase { THROW, REVEAL }

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const PAD_RADIUS := 1.3
const PAD_DISTANCE := 6.0
const THROW_SEC := 3.0
const SUDDEN_DEATH_SEC := 2.5
const REVEAL_SEC := 1.4
const VOTE_BONUS_COINS := 5

var positions := {}
var move_dirs := {}
## slot -> shape locked in this sub-round; absent = still deciding.
var throws := {}
## Groups of slots eliminated together, in elimination order.
var eliminated_order: Array = []
## Eliminated slot -> the slot they predict will be champion.
var votes := {}
var phase: Phase = Phase.THROW
## True while the current/last sub-round is the 1v1 reaction-time decider.
var sudden_death := false
## The shape sudden-death players must counter; -1 outside sudden death.
var target_shape := -1
## Pads are fixed per match (not per round) so players learn their layout.
var pads: Array = []
## Result of the most recently resolved sub-round, for the REVEAL phase.
var last_result := {}
var _phase_left := THROW_SEC


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"ro_sham_bo",
				"controls": "Move — WASD / left stick (run onto Rock / Paper / Scissors to throw)",
				"name": "Ro-Sham-Bo Royale",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 60.0,
				"rules":
				(
					"Run to Rock, Paper, or Scissors — the losing shape is out! Down to two and"
					+ " tied? Fastest correct counter wins it."
				),
			}
		)
	)


## World position of the pad for `shape`. Fixed geometry (not per-match
## random), so the view derives it from this same helper instead of the
## snapshot carrying it every tick — one less thing on the wire.
static func pad_position(shape: int) -> Vector2:
	match shape:
		Shape.ROCK:
			return Vector2(0.0, -PAD_DISTANCE)
		Shape.PAPER:
			return Vector2(-PAD_DISTANCE * 0.87, PAD_DISTANCE * 0.5)
		_:
			return Vector2(PAD_DISTANCE * 0.87, PAD_DISTANCE * 0.5)


func _setup() -> void:
	pads = [
		{"shape": Shape.ROCK, "pos": pad_position(Shape.ROCK)},
		{"shape": Shape.PAPER, "pos": pad_position(Shape.PAPER)},
		{"shape": Shape.SCISSORS, "pos": pad_position(Shape.SCISSORS)},
	]
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * 2.0
		move_dirs[slots[i]] = Vector2.ZERO
	_start_round()


func _handle_input(slot: int, data: Dictionary) -> void:
	if data.has("vote") and not _is_alive(slot) and not votes.has(slot):
		var target := int(data.get("vote", -1))
		if target != slot and target in _alive_slots():
			votes[slot] = target
		return
	if not _is_alive(slot):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	var alive := _alive_slots()
	for slot: int in alive:
		if throws.has(slot):
			continue  # a locked throw parks you on your pad
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.limit_length(ARENA_HALF)
	if phase == Phase.THROW:
		_resolve_pad_touches(alive)
	_phase_left -= delta
	match phase:
		Phase.THROW:
			if _phase_left <= 0.0 or _all_thrown(alive):
				_resolve_round(alive)
		Phase.REVEAL:
			if _phase_left <= 0.0:
				_advance_after_reveal()


func get_snapshot() -> Dictionary:
	return {
		"phase": phase,
		"players": _player_states(),
		"eliminated_order": eliminated_order.duplicate(true),
		"sudden_death": sudden_death,
		"target_shape": target_shape,
		"phase_left": snappedf(maxf(_phase_left, 0.0), 0.1),
		"last_result": last_result.duplicate(true) if phase == Phase.REVEAL else {},
	}


## Timeout safety net: everyone still alive ties ahead of the eliminated,
## same convention as Thin Ice's fall order.
func _rank_players() -> Array:
	var alive := _alive_slots()
	var placements: Array = []
	if not alive.is_empty():
		placements.append(alive)
	return placements + _out_placements()


func _resolve_pad_touches(alive: Array) -> void:
	for slot: int in alive:
		if throws.has(slot):
			continue
		for pad: Dictionary in pads:
			if positions[slot].distance_to(pad.pos) <= PAD_RADIUS + PLAYER_RADIUS:
				throws[slot] = int(pad.shape)
				break


func _all_thrown(alive: Array) -> bool:
	for slot: int in alive:
		if not throws.has(slot):
			return false
	return true


func _resolve_round(alive: Array) -> void:
	# Anyone who never committed a throw gets a random one — a network
	# hiccup or a slow decision shouldn't stall the whole pool.
	for slot: int in alive:
		if not throws.has(slot):
			throws[slot] = rng.randi_range(Shape.ROCK, Shape.SCISSORS)
	if sudden_death:
		_resolve_sudden_death(alive)
	else:
		_resolve_normal_round(alive)
	phase = Phase.REVEAL
	_phase_left = REVEAL_SEC


## Group RPS: exactly two distinct shapes among the alive players means one
## beats the other — every player on the losing shape is eliminated together.
## One shape (everyone matched) or all three (no clear winner) is a wash;
## nobody is eliminated and the pool redraws.
func _resolve_normal_round(alive: Array) -> void:
	var by_shape := {}
	for slot: int in alive:
		var shape: int = throws[slot]
		if not by_shape.has(shape):
			by_shape[shape] = []
		by_shape[shape].append(slot)
	var distinct: Array = by_shape.keys()
	var eliminated: Array = []
	if distinct.size() == 2:
		var a: int = distinct[0]
		var b: int = distinct[1]
		var loser_shape: int = a if _beats(b, a) else b
		eliminated = by_shape[loser_shape]
	_finish_resolution(eliminated, false, -1)


## The 1v1 stalemate breaker: whoever threw the revealed shape's counter
## survives; a shared correct throw (or neither correct) is still a tie and
## the pool redraws with a fresh target next round.
func _resolve_sudden_death(alive: Array) -> void:
	var correct: Array = []
	for slot: int in alive:
		if int(throws[slot]) == _counter(target_shape):
			correct.append(slot)
	var eliminated: Array = []
	if correct.size() == 1:
		for slot: int in alive:
			if slot != correct[0]:
				eliminated.append(slot)
	_finish_resolution(eliminated, true, target_shape)


func _finish_resolution(eliminated: Array, was_sudden_death: bool, shown_target: int) -> void:
	last_result = {
		"throws": throws.duplicate(),
		"eliminated": eliminated.duplicate(),
		"wash": eliminated.is_empty(),
		"sudden_death": was_sudden_death,
		"target_shape": shown_target,
	}
	if not eliminated.is_empty():
		eliminated_order.append(eliminated.duplicate())


func _advance_after_reveal() -> void:
	var alive := _alive_slots()
	if alive.size() <= 1:
		_finish_match(alive)
		return
	_start_round()


func _start_round() -> void:
	var alive := _alive_slots()
	throws.clear()
	sudden_death = alive.size() == 2 and bool(last_result.get("wash", false))
	target_shape = rng.randi_range(Shape.ROCK, Shape.SCISSORS) if sudden_death else -1
	phase = Phase.THROW
	_phase_left = SUDDEN_DEATH_SEC if sudden_death else THROW_SEC


func _finish_match(alive: Array) -> void:
	var placements: Array = []
	if not alive.is_empty():
		placements.append(alive)
	placements += _out_placements()
	_award_votes(alive)
	finish(placements)


## Eliminated players who called the champion correctly earn a bonus.
func _award_votes(alive: Array) -> void:
	if alive.is_empty():
		return
	var champion: int = alive[0]
	var coins := {}
	for voter: int in votes:
		if int(votes[voter]) == champion:
			coins[voter] = VOTE_BONUS_COINS
	_pickup_coins = coins


## True if shape `a` beats shape `b` (rock > scissors > paper > rock).
func _beats(a: int, b: int) -> bool:
	return (
		(a == Shape.ROCK and b == Shape.SCISSORS)
		or (a == Shape.PAPER and b == Shape.ROCK)
		or (a == Shape.SCISSORS and b == Shape.PAPER)
	)


## The shape that beats `shape`.
func _counter(shape: int) -> int:
	match shape:
		Shape.ROCK:
			return Shape.PAPER
		Shape.PAPER:
			return Shape.SCISSORS
		_:
			return Shape.ROCK


func _is_alive(slot: int) -> bool:
	if slot not in slots:
		return false
	for group: Array in eliminated_order:
		if slot in group:
			return false
	return true


func _alive_slots() -> Array:
	return slots.filter(_is_alive)


func _out_placements() -> Array:
	var placements := eliminated_order.duplicate(true)
	placements.reverse()
	return placements


## Anti-peek (M8-01 convention): only whether a slot has locked in is public
## during THROW — the shape itself leaks only once REVEAL shows last_result.
func _player_states() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			1 if _is_alive(slot) else 0,
			1 if throws.has(slot) else 0,
		]
	return players
