class_name SnakeChainBrain
extends BotBrain
## Snake Chain archetype (M19-02, #686): steer toward the nearest pellet while
## never aiming the head into a body — anyone's, including our own trail past
## its self-grace segments (matches the sim's own SnakeChain.SELF_GRACE_SEGMENTS
## exemption so the brain isn't more cautious than the game requires).
##
## Snapshot: {players: {slot: [x, y, pellets_eaten, invuln_left, boosting]},
## trails: {slot: [[x, y], ...]}, pellets: [[x, y], ...]}. Input: {mx, my} plus
## an optional {boost} (Tail Burn, #950). Indices via SnakeChain.PS_*/TR_* (#708).

## Candidate headings sampled around the pellet-seeking direction.
const CANDIDATE_COUNT := 8
## How far ahead of the head a candidate direction is checked for a body hit.
const LOOKAHEAD := 1.6
## A body point within this distance of the lookahead point is a collision.
const HIT_RADIUS := SnakeChain.HEAD_RADIUS + SnakeChain.SEGMENT_RADIUS + 0.15
## Tail Burn (#950): boost to cut across a rival head crossing perpendicular
## within CUT_RANGE ahead — but keep a buffer, never boosting the tail down past
## BOOST_MIN_SEGMENTS grown segments (and the sim's own floor stops a self-kill).
const BOOST_MIN_SEGMENTS := 3
const CUT_RANGE := 4.5


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.is_empty():
		return {}
	var me := Vector2(float(state[SnakeChain.PS_X]), float(state[SnakeChain.PS_Y]))
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
	var intent: Dictionary
	if best_dir == Vector2.ZERO:
		# Every sampled heading looks dangerous (tight quarters): keep whatever
		# heading points at the goal and hope the sim's own clamp saves us —
		# stopping isn't an option, the chain never stops moving.
		if goal == Vector2.INF:
			return {}
		intent = move_toward_point(me, goal, 0.0)
	else:
		intent = {"mx": best_dir.x, "my": best_dir.y}
	# Tail Burn (#950): spend tail to cut across a rival crossing ahead, but only
	# with segments to spare.
	var heading := Vector2(float(intent.get("mx", 0.0)), float(intent.get("my", 0.0)))
	if (
		int(state[SnakeChain.PS_COUNT_EATEN]) >= BOOST_MIN_SEGMENTS
		and heading.length() > 0.01
		and _cut_ahead(me, heading.normalized(), players, trails)
	):
		intent["boost"] = true
	return intent


## True if a rival head sits within CUT_RANGE ahead of `heading` and is crossing
## roughly perpendicular — the cut opportunity boosting is for (#950).
func _cut_ahead(me: Vector2, heading: Vector2, players: Dictionary, trails: Dictionary) -> bool:
	for other: Variant in players:
		if int(other) == slot:
			continue
		var ostate: Array = players[other]
		if ostate.size() <= SnakeChain.PS_Y:
			continue
		var opos := Vector2(float(ostate[SnakeChain.PS_X]), float(ostate[SnakeChain.PS_Y]))
		var to_rival := opos - me
		var dist := to_rival.length()
		if dist < 0.01 or dist > CUT_RANGE:
			continue
		if to_rival.normalized().dot(heading) < 0.3:
			continue  # rival is beside/behind us, not ahead
		var rival_heading := _rival_heading(other, opos, trails)
		if rival_heading != Vector2.ZERO and absf(rival_heading.dot(heading)) < 0.5:
			return true  # crossing our path roughly perpendicular
	return false


## A rival's heading inferred from head-minus-newest-trail-point, or ZERO if its
## trail is too short to tell.
func _rival_heading(other: Variant, opos: Vector2, trails: Dictionary) -> Vector2:
	var trail: Array = trails.get(other, [])
	if trail.is_empty():
		return Vector2.ZERO
	var newest := Vector2(float(trail[0][SnakeChain.TR_X]), float(trail[0][SnakeChain.TR_Y]))
	var d := opos - newest
	return Vector2.ZERO if d.length() < 0.01 else d.normalized()


## True if `point` lands on any snake's body, skipping each snake's own
## newest SELF_GRACE_SEGMENTS points (the sim's own forgiveness for tight
## turns, applied identically whether the body in question is ours or not).
func _hits_a_body(point: Vector2, trails: Dictionary) -> bool:
	for other: Variant in trails:
		var trail: Array = trails[other]
		var start := SnakeChain.SELF_GRACE_SEGMENTS if int(other) == slot else 0
		for i in range(start, trail.size()):
			var seg: Array = trail[i]
			var seg_pos := Vector2(float(seg[SnakeChain.TR_X]), float(seg[SnakeChain.TR_Y]))
			if point.distance_to(seg_pos) <= HIT_RADIUS:
				return true
	return false
