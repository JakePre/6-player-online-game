class_name KingslayerBrain
extends GauntletBrain
## Kingslayer finale archetype (#936): shop thinking inherited from
## GauntletBrain (survivability-first, then confirm). Showdown: as a HUNTER,
## converge on the King and swing in range; as the KING, kite — back away
## from the nearest hunter, and swing anyone who closes into royal reach.
## Snapshot: {king, court, players: {slot: [x, y, fx, fy, hp, respawn,
## invuln, hit_seq, swing_seq]}, strikes} (Kingslayer, #708 named indices).

## The King starts backing off when the nearest hunter is this close.
const KITE_RANGE := 4.0


func _think_play(game: Dictionary) -> Dictionary:
	var players: Dictionary = game.get("players", {})
	var my_state: Array = players.get(slot, [])
	if my_state.size() < Kingslayer.PS_COUNT:
		return {}
	if float(my_state[Kingslayer.PS_RESPAWN]) > 0.0:
		return {}  # downed — nothing to do until the respawn lands
	var me := Vector2(float(my_state[Kingslayer.PS_X]), float(my_state[Kingslayer.PS_Y]))
	var king := int(game.get("king", -1))
	if slot == king:
		return _reign(players, me)
	return _hunt_the_king(players, me, king)


## Hunters: drive at the crown, swing in reach. Steering INTO the King also
## faces us at them, which is what the sim's swing arc reads.
func _hunt_the_king(players: Dictionary, me: Vector2, king: int) -> Dictionary:
	var king_state: Array = players.get(king, [])
	if king_state.size() < Kingslayer.PS_COUNT:
		return {}
	var king_pos := Vector2(float(king_state[Kingslayer.PS_X]), float(king_state[Kingslayer.PS_Y]))
	if me.distance_to(king_pos) <= Kingslayer.HUNTER_SWING_RANGE:
		return {"swing": true}
	return move_toward_point(me, king_pos, 0.0)


## The King: swing anyone in royal reach, else back away from the nearest
## live hunter while pressed — attrition favors the pack, distance favors us.
func _reign(players: Dictionary, me: Vector2) -> Dictionary:
	var nearest := Vector2.INF
	var nearest_dist := INF
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() < Kingslayer.PS_COUNT or float(state[Kingslayer.PS_RESPAWN]) > 0.0:
			continue
		var pos := Vector2(float(state[Kingslayer.PS_X]), float(state[Kingslayer.PS_Y]))
		var dist := me.distance_to(pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = pos
	if nearest == Vector2.INF:
		return {}
	if nearest_dist <= Kingslayer.KING_SWING_RANGE:
		return {"swing": true}
	if nearest_dist <= KITE_RANGE:
		return move_away_from_point(me, nearest)
	return {}
