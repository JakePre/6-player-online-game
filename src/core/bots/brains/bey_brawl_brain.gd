class_name BeyBrawlBrain
extends BotBrain
## Bey Brawl archetype (#1034): momentum duelling in a bowl. Spin is both HP
## and clash power, so the call is simple and readable — HUNT the nearest
## rival while our meter is at least as healthy as theirs, EVADE (steer away,
## let the bowl decide when the next clash happens) while it is weaker. Near
## the lip, self-preservation outranks everything: a clash there is a
## ring-out (#1041's escape-speed lip), so steer back inside first.
## Snapshot: {radius, players: {slot: [x, y, spin, clash_seq]}}; input {mx, my}
## only (pure steering, no buttons). Indices named via BeyBrawl.PS_* (#708).

## Distance from the lip at which retreat overrides the duel.
const EDGE_MARGIN := 1.5
## A dead-even spin matchup favors engaging — the bowl forces the fight
## anyway, and first-strike clashes are won by speed, which the hunter has.
const HUNT_SPIN_EDGE := 0.05
## One-sample pursuit lead: aim this far along the rival's last observed
## displacement, so momentum carries the clash INTO them instead of arcing
## behind a moving target.
const LEAD_FACTOR := 4.0

## Rival slot -> last observed position, for the pursuit lead.
var _last_seen := {}


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < BeyBrawl.PS_COUNT:
		return {}
	var me := Vector2(float(state[BeyBrawl.PS_X]), float(state[BeyBrawl.PS_Y]))
	var radius := float(game.get("radius", BeyBrawl.BOWL_RADIUS))
	if me.length() > radius - EDGE_MARGIN:
		# Too close to the lip: a clash here launches us out. Back inside first.
		return move_toward_point(me, Vector2.ZERO, 0.0)
	var rival := _nearest_rival(players, me)
	if rival == -1:
		return {"mx": 0.0, "my": 0.0}
	var rival_state: Array = players[rival]
	var rival_pos := Vector2(float(rival_state[BeyBrawl.PS_X]), float(rival_state[BeyBrawl.PS_Y]))
	var my_spin := float(state[BeyBrawl.PS_SPIN])
	var rival_spin := float(rival_state[BeyBrawl.PS_SPIN])
	var target := rival_pos + _lead(rival, rival_pos)
	_last_seen[rival] = rival_pos
	if my_spin + HUNT_SPIN_EDGE >= rival_spin:
		return move_toward_point(me, target, 0.0)
	# Weaker: steer away and recover; the slope guarantees another meeting.
	return move_toward_point(me, me + (me - rival_pos), 0.0)


## The rival's displacement since our last look, scaled into a pursuit lead.
## First sighting has no sample, so pursuit starts pure and sharpens.
func _lead(rival: int, rival_pos: Vector2) -> Vector2:
	if not _last_seen.has(rival):
		return Vector2.ZERO
	return ((rival_pos - (_last_seen[rival] as Vector2)) * LEAD_FACTOR).limit_length(2.5)


func _nearest_rival(players: Dictionary, me: Vector2) -> int:
	var best := -1
	var best_dist := INF
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() < BeyBrawl.PS_COUNT:
			continue
		var pos := Vector2(float(state[BeyBrawl.PS_X]), float(state[BeyBrawl.PS_Y]))
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = other
	return best
