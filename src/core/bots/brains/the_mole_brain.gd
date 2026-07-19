class_name TheMoleBrain
extends BotBrain
## The Mole archetype (M19-02, #686): role-branching from the OWN private
## snapshot. As the mole, blend in by hauling but drain the machine when it's
## worth it; as crew, haul fuel and build a suspicion model from the
## unattributed sparks so the vote isn't a coin flip.
##
## Snapshot: {phase, progress, target, sparked, blackout, players: {slot: [x, y,
## carrying]}, cells: [[x, y], ...]}. Private: {"role": "mole", "blackout_ready"}
## for the mole only, WORK phase only (TheMole, #254). Input: {mx, my} + {act:
## true} (mole sabotage in range) + {blackout: true} (mole lights-out, #958)
## during WORK; {vote: slot} during VOTE. Indices named via TheMole.PS_*/CL_*
## (#708).

## Blackout (#958): the mole kills the lights when at least this many rivals are
## crowding the machine — right as the drain is about to be pinned on them.
const BLACKOUT_MIN_CROWD := 2
## A rival within this of the machine counts toward the crowd.
const BLACKOUT_CROWD_RADIUS := TheMole.MACHINE_RADIUS + 1.5

## Per-rival suspicion, accrued when a spark fires while they stand at the
## machine — the only tell the crew ever gets.
var _suspicion := {}
var _was_sparked := false
## Latch the vote so a bot commits instead of flip-flopping every tick.
var _vote_cast := -1


func think(match_state: Dictionary, private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var phase := int(game.get("phase", TheMole.Phase.WORK))
	var players: Dictionary = game.get("players", {})
	var me := my_position(players)
	if me == Vector2.INF:
		return {}
	var is_mole := String(private.get("role", "")) == "mole"
	if phase == TheMole.Phase.WORK:
		_track_suspicion(game, players, me)
		var blackout_ready := is_mole and bool(private.get("blackout_ready", false))
		return _work(game, players, me, is_mole, blackout_ready)
	if phase == TheMole.Phase.VOTE:
		return _vote(players, is_mole)
	return {}


## On each spark's rising edge, everyone (not me) standing on the machine is a
## suspect. The mole is always there when it drains, so it rises to the top.
func _track_suspicion(game: Dictionary, players: Dictionary, _me: Vector2) -> void:
	var sparked := bool(game.get("sparked", false))
	if sparked and not _was_sparked:
		for other: int in players:
			if other == slot:
				continue
			var pos: Vector2 = _player_pos(players[other])
			if pos.distance_to(TheMole.MACHINE_POS) <= TheMole.MACHINE_RADIUS + 0.3:
				_suspicion[other] = float(_suspicion.get(other, 0.0)) + 1.0
	_was_sparked = sparked


func _work(
	game: Dictionary, players: Dictionary, me: Vector2, is_mole: bool, blackout_ready: bool
) -> Dictionary:
	var carrying := int((players[slot] as Array)[TheMole.PS_CARRYING]) == 1
	if is_mole:
		# Blackout (#958): the crew is crowding the machine and about to pin the
		# drain — kill the lights and slip the read, still drifting in to drain.
		if blackout_ready and _rivals_near_machine(players) >= BLACKOUT_MIN_CROWD:
			var escape := move_toward_point(me, TheMole.MACHINE_POS, TheMole.MACHINE_RADIUS * 0.5)
			escape["blackout"] = true
			return escape
		# Worth draining once there's progress banked; otherwise haul to blend
		# (and a carried cell delivered is perfect cover early on).
		if int(game.get("progress", 0)) >= 3:
			var intent := move_toward_point(me, TheMole.MACHINE_POS, TheMole.MACHINE_RADIUS * 0.5)
			if me.distance_to(TheMole.MACHINE_POS) <= TheMole.MACHINE_RADIUS:
				intent["act"] = true
			return intent
	if carrying:
		return move_toward_point(me, TheMole.MACHINE_POS, TheMole.MACHINE_RADIUS * 0.6)
	var cell := nearest_point(me, game.get("cells", []))
	if cell == Vector2.INF:
		# Nothing to haul: loiter near the machine, ready for the next wave.
		return move_toward_point(me, TheMole.MACHINE_POS, TheMole.MACHINE_RADIUS + 1.0)
	return move_toward_point(me, cell, TheMole.CELL_PICKUP_RADIUS * 0.5)


## Crew votes the top suspect; the mole votes a random innocent to deflect.
## Latched so the intent is stable across the vote window.
func _vote(players: Dictionary, is_mole: bool) -> Dictionary:
	if _vote_cast == -1:
		_vote_cast = _pick_mole_deflection(players) if is_mole else _pick_top_suspect(players)
	if _vote_cast == -1:
		return {}
	return {"vote": _vote_cast}


func _pick_top_suspect(players: Dictionary) -> int:
	var best := -1
	var best_score := 0.0
	for other: int in players:
		if other == slot:
			continue
		var score := float(_suspicion.get(other, 0.0))
		if score > best_score:
			best_score = score
			best = other
	if best != -1:
		return best
	return _any_other(players)


func _pick_mole_deflection(players: Dictionary) -> int:
	return _any_other(players)


func _any_other(players: Dictionary) -> int:
	var others: Array = []
	for other: int in players:
		if other != slot:
			others.append(other)
	if others.is_empty():
		return -1
	return int(others[rng.randi_range(0, others.size() - 1)])


## Rivals (not me) clustered around the machine — the cue to spend the blackout.
func _rivals_near_machine(players: Dictionary) -> int:
	var n := 0
	for other: int in players:
		if other == slot:
			continue
		if _player_pos(players[other]).distance_to(TheMole.MACHINE_POS) <= BLACKOUT_CROWD_RADIUS:
			n += 1
	return n


func _player_pos(state: Array) -> Vector2:
	return Vector2(float(state[TheMole.PS_X]), float(state[TheMole.PS_Y]))
