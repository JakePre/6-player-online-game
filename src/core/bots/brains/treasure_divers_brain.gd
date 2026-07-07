class_name TreasureDiversBrain
extends BotBrain
## Air-management archetype (M19-02, #686): dive for the nearest treasure,
## surface once air runs low, dive again once it's recovered enough — a
## hysteresis band so the bot doesn't flap between diving and surfacing right
## at the threshold. Snapshot: {players: {slot: [x, y, coins, diving,
## air_frac, stunned]}, treasure: [[x,y], ...]}. Input: {mx, my} + {dive}.

## Surface once air drops to this fraction; dive again only once it's back up
## to RESUME_AIR (a gap, not a single threshold, so it doesn't flap).
const LOW_AIR := 0.15
const RESUME_AIR := 0.6

var _surfacing := false


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < 6:
		return {}
	var me := Vector2(float(state[0]), float(state[1]))
	var diving := int(state[3]) == 1
	var air_frac := float(state[4])
	if diving and air_frac <= LOW_AIR:
		_surfacing = true
	elif not diving and air_frac >= RESUME_AIR:
		_surfacing = false
	if _surfacing:
		return {"dive": false}
	var target := nearest_point(me, game.get("treasure", []))
	if target == Vector2.INF:
		return {"dive": true}
	var intent := move_toward_point(me, target, TreasureDivers.COLLECT_RADIUS * 0.5)
	intent["dive"] = true
	return intent
