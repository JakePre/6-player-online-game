class_name SnakeChainBrain
extends BotBrain
## Snake Chain archetype (M19-02, #686): steer toward the nearest pellet while
## never aiming the head into a body — anyone's, including our own trail past
## its self-grace segments (matches the sim's own SnakeChain.SELF_GRACE_SEGMENTS
## exemption so the brain isn't more cautious than the game requires).
##
## Snapshot: {players: {slot: [x, y, pellets_eaten, invuln_left]},
## trails: {slot: [[x, y], ...]}, pellets: [[x, y], ...]}. Input: {mx, my}
## only — this is a steering wheel, not a stop/go throttle.

## Candidate headings sampled around the pellet-seeking direction.
const CANDIDATE_COUNT := 8
## How far ahead of the head a candidate direction is checked for a body hit.
const LOOKAHEAD := 1.6
## A body point within this distance of the lookahead point is a collision.
const HIT_RADIUS := SnakeChain.HEAD_RADIUS + SnakeChain.SEGMENT_RADIUS + 0.15


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.is_empty():
		return {}
	var me := Vector2(float(state[0]), float(state[1]))
	var trails: Dictionary = game.get("trails", {})
	var goal := nearest_point(me, game.get("pellets", []))
	var best_dir := Vector2.ZERO
	var best_score := -INF
	for k in CANDIDATE_COUNT:
		var dir := Vector2.RIGHT.rotated(TAU * k / CANDIDATE_COUNT)
		var ahead := me + dir * LOOKAHEAD
		if _hits_a_body(ahead, trails):
			continue
		var score := 0.0
		if goal != Vector2.INF:
			score = -ahead.distance_squared_to(goal)
		if score > best_score:
			best_score = score
			best_dir = dir
	if best_dir == Vector2.ZERO:
		# Every sampled heading looks dangerous (tight quarters): keep whatever
		# heading points at the goal and hope the sim's own clamp saves us —
		# stopping isn't an option, the chain never stops moving.
		if goal != Vector2.INF:
			return move_toward_point(me, goal, 0.0)
		return {}
	return {"mx": best_dir.x, "my": best_dir.y}


## True if `point` lands on any snake's body, skipping each snake's own
## newest SELF_GRACE_SEGMENTS points (the sim's own forgiveness for tight
## turns, applied identically whether the body in question is ours or not).
func _hits_a_body(point: Vector2, trails: Dictionary) -> bool:
	for other: Variant in trails:
		var trail: Array = trails[other]
		var start := SnakeChain.SELF_GRACE_SEGMENTS if int(other) == slot else 0
		for i in range(start, trail.size()):
			var seg: Array = trail[i]
			if point.distance_to(Vector2(float(seg[0]), float(seg[1]))) <= HIT_RADIUS:
				return true
	return false
