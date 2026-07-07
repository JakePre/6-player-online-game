class_name TumbleRunBrain
extends BotBrain
## Vertical-climb archetype (M19-02, #686): head for the next ledge above,
## zig-zagging up the alternating-side ladder to the summit, hopping when the
## target sits higher, and sidestepping a falling boulder that's about to land
## on us. Ledges are static, so the ladder is known without the snapshot.
##
## Snapshot: {players: {slot: [x, y, facing, flags]}, boulders: [[x, y], ...],
## crumble, phase, standings} (TumbleRun). flags: 1 stun, 2 summit, 4 grounded.
## Phase: 0 COUNTDOWN, 1 CLIMB, 2 DONE. Input: {mx} (sets facing), {jump}.

## Sidestep a boulder within this radius that's above and dropping toward us.
const BOULDER_DODGE_RADIUS := 2.4
## Jump when the target ledge is at least this much above our feet.
const CLIMB_LEAD := 0.8

var _ledges: Array = []


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	if int(game.get("phase", TumbleRun.Phase.COUNTDOWN)) != TumbleRun.Phase.CLIMB:
		return {}
	var players: Dictionary = game.get("players", {})
	var me: Array = players.get(slot, [])
	# flags: stunned (1) can't act; summited (2) is done.
	if me.size() < 4 or (int(me[3]) & 1) != 0 or (int(me[3]) & 2) != 0:
		return {}
	var my_pos := Vector2(float(me[0]), float(me[1]))
	# Dodge a boulder dropping onto us first.
	var dodge := _dodge_boulder(game.get("boulders", []), my_pos)
	if not dodge.is_empty():
		return dodge
	# Climb toward the next ledge above; alternating sides make this zig-zag.
	var target := _next_ledge_above(my_pos.y)
	var intent := {"mx": signf(target.x - my_pos.x)}
	if target.y - my_pos.y > CLIMB_LEAD:
		intent["jump"] = true
	return intent


## Center of the lowest static ledge above `y`; the summit's x when none is
## left (final hop onto the goal platform).
func _next_ledge_above(y: float) -> Vector2:
	if _ledges.is_empty():
		for rect: Rect2 in TumbleRun.ledges():
			_ledges.append(Vector2(rect.position.x + rect.size.x / 2.0, rect.position.y))
		_ledges.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	for ledge: Vector2 in _ledges:
		if ledge.y > y + 0.3:
			return ledge
	return Vector2(0.0, TumbleRun.GOAL_HEIGHT)


func _dodge_boulder(boulders: Array, from: Vector2) -> Dictionary:
	for boulder: Array in boulders:
		if boulder.size() < 2:
			continue
		var pos := Vector2(float(boulder[0]), float(boulder[1]))
		# Above us and horizontally close — step out from under it.
		if pos.y > from.y and from.distance_to(pos) <= BOULDER_DODGE_RADIUS:
			var away := signf(from.x - pos.x)
			return {"mx": away if absf(away) > 0.0 else 1.0}
	return {}
