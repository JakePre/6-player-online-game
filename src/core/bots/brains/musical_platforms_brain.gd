class_name MusicalPlatformsBrain
extends BotBrain
## Musical-chairs archetype (M19-02, #686): idle-wander during MUSIC (nothing
## to react to — platforms don't exist yet), then race the nearest unclaimed
## platform the instant STOP hits. Snapshot: {players: {slot: [x, y]}, phase,
## platforms: [[x, y, claimed_by], ...], fallen}. Input: {mx, my} only.
## Indices named via MusicalPlatforms.PT_* (#708).

## Re-picked whenever reached, so a MUSIC-phase bot drifts instead of
## standing dead still.
var _wander_target := Vector2.INF


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var me := my_position(game.get("players", {}))
	if me == Vector2.INF:
		return {}
	if int(game.get("phase", MusicalPlatforms.Phase.MUSIC)) == MusicalPlatforms.Phase.STOP:
		_wander_target = Vector2.INF  # forget the old wander target for next MUSIC
		return _race_for_a_platform(game.get("platforms", []), me)
	if _wander_target == Vector2.INF or me.distance_to(_wander_target) < 1.0:
		_wander_target = me + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0))
	return move_toward_point(me, _wander_target)


## Already holding one: sit tight. Otherwise beeline the nearest still-free
## platform; if every platform is spoken for, there's nothing left to do.
func _race_for_a_platform(platforms: Array, me: Vector2) -> Dictionary:
	var best := Vector2.INF
	var best_dist := INF
	for platform: Array in platforms:
		var claimed_by := int(platform[MusicalPlatforms.PT_CLAIMED_BY])
		if claimed_by == slot:
			return {"mx": 0.0, "my": 0.0}
		if claimed_by != -1:
			continue
		var pos := Vector2(
			float(platform[MusicalPlatforms.PT_X]), float(platform[MusicalPlatforms.PT_Y])
		)
		var dist := me.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	if best == Vector2.INF:
		return {}
	return move_toward_point(me, best, MusicalPlatforms.PLATFORM_RADIUS * 0.4)
