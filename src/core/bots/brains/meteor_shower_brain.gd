class_name MeteorShowerBrain
extends BotBrain
## Telegraph-dodger archetype (M19): stay inside the safe zone, flee any
## meteor telegraph we're standing in. Snapshot: {players: {slot: [x, y]},
## zone: [x, y, radius], meteors: [[x, y, seconds_left], ...]} (MeteorShower).

## Flee a telegraph when inside this multiple of a nominal blast radius.
const DANGER_RADIUS := 2.2


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var me := my_position(game.get("players", {}))
	if me == Vector2.INF:
		return {}
	# Most urgent threat first: the soonest-landing meteor we're close to.
	var threat := Vector2.INF
	var soonest := INF
	for meteor: Array in game.get("meteors", []):
		if meteor.size() < 3:
			continue
		var pos := Vector2(float(meteor[0]), float(meteor[1]))
		var left := float(meteor[2])
		if me.distance_to(pos) < DANGER_RADIUS and left < soonest:
			soonest = left
			threat = pos
	var zone: Array = game.get("zone", [])
	var zone_radius := float(zone[2]) if zone.size() >= 3 else INF
	if threat != Vector2.INF:
		var flee := move_away_from_point(me, threat)
		# Never dodge out of the shrinking zone: bias the flee back inward
		# when we're already near the rim.
		if me.length() > zone_radius * 0.8:
			var inward := move_toward_point(me, Vector2.ZERO, 0.0)
			flee = {
				"mx": (float(flee.mx) + float(inward.mx)) / 2.0,
				"my": (float(flee.my) + float(inward.my)) / 2.0,
			}
		return flee
	# No immediate threat: drift toward center where the zone lasts longest.
	return move_toward_point(me, Vector2.ZERO, zone_radius * 0.4)
