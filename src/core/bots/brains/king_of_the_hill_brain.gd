class_name KingOfTheHillBrain
extends BotBrain
## Zone-holder archetype (M19): stand in the scoring zone; grab a nearby item
## when one spawns closer than the zone; use a held item immediately.
## Snapshot: {players: {slot: [x, y, points]}, zone: [x, y, radius],
## items: [[x, y, type], ...], held: {slot: type}} (KingOfTheHill).


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var me := my_position(game.get("players", {}))
	if me == Vector2.INF:
		return {}
	# Fire a held item right away — both types (shove blast / anchor) pay off
	# most while contesting the zone, which is where this brain lives anyway.
	var held: Dictionary = game.get("held", {})
	if held.has(slot):
		return {"use": true}
	var zone: Array = game.get("zone", [])
	var zone_center := Vector2(float(zone[0]), float(zone[1])) if zone.size() >= 3 else Vector2.ZERO
	# Detour for an item only when it is meaningfully closer than the zone.
	var item := nearest_point(me, game.get("items", []))
	if item != Vector2.INF and me.distance_to(item) < me.distance_to(zone_center) * 0.5:
		return move_toward_point(me, item, 0.05)
	# Inside the zone: shuffle around its center so shoves don't line up.
	var zone_radius := float(zone[2]) if zone.size() >= 3 else 1.0
	if me.distance_to(zone_center) < zone_radius * 0.6:
		var jitter := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
		return {"mx": jitter.x, "my": jitter.y}
	return move_toward_point(me, zone_center, 0.2)
