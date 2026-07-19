class_name TiltDeckBrain
extends BotBrain
## Raft-survivor archetype (#794): the deck tips toward the crowd, so the bot's
## first job is not to slide off — steer back toward the centre, against the
## lean, whenever it drifts out, and only chase the edge coins while it's still
## safe near the middle. Snapshot: {players: {slot: [x, y, coins]}, tilt:
## [x, y], deck_radius, coins: [[x, y]], cargo, fallen} (TiltDeck). Input:
## {mx, my}.

## Past this fraction of the deck radius the bot abandons coins and scrambles
## back toward the centre.
const DANGER_FRACTION := 0.5
## Commit to a coin this strongly, easing off as the deck tilts.
const VENTURE_GAIN := 1.4
## Coin reach as a fraction of deck radius (#926): reach out to the rim when the
## deck is balanced, pull in as tilt grows. This is the fix for the all-bots-at-
## dead-centre stalemate — everyone used to camp the no-tilt equilibrium, so the
## deck never tipped and rim coins were never collected. Now a balanced deck
## invites a venture, which tips it, which pulls the venturer back: a live
## give-and-take instead of a frozen middle.
const REACH_BALANCED := 0.95
const REACH_TILTED := 0.4


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var me := my_position(game.get("players", {}))
	if me == Vector2.INF:
		return {}
	var radius := float(game.get("deck_radius", TiltDeck.DECK_RADIUS))
	var tilt := _tilt(game)
	var tilt_frac := clampf(tilt.length() / TiltDeck.TILT_MAX, 0.0, 1.0)
	var danger := me.length() / maxf(radius, 0.01)
	# Always resist the downhill slide; near the rim, sprint for the centre with
	# urgency scaled by how far out (and against the lean) so it doesn't ride off.
	var desired := -tilt
	if danger > DANGER_FRACTION:
		desired = (-me).normalized() * (danger * 2.0) - tilt
	else:
		# Reach further for coins the flatter the deck is; commit less the more it
		# leans. A balanced deck (tilt_frac ~0) will chase rim coins and break the
		# center camp; a tilting one eases the venture and leans on the resist.
		var coin := _nearest_coin(game, me, radius, lerpf(REACH_BALANCED, REACH_TILTED, tilt_frac))
		if coin != Vector2.INF:
			desired = (coin - me).normalized() * VENTURE_GAIN * (1.0 - 0.5 * tilt_frac) - tilt
	if desired.length() < 0.05:
		return {}
	return {"mx": desired.x, "my": desired.y}


func _tilt(game: Dictionary) -> Vector2:
	var t: Array = game.get("tilt", [])
	if t.size() < 2:
		return Vector2.ZERO
	return Vector2(float(t[0]), float(t[1]))


## Nearest coin within `reach` (a fraction of the deck radius) of the centre —
## the reach shrinks as the deck tilts so the bot won't chase one off the edge
## while already leaning (#926).
func _nearest_coin(game: Dictionary, from: Vector2, radius: float, reach: float) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for coin: Array in game.get("coins", []):
		var pos := Vector2(float(coin[0]), float(coin[1]))
		if pos.length() > radius * reach:
			continue
		var d := from.distance_squared_to(pos)
		if d < best_dist:
			best_dist = d
			best = pos
	return best
