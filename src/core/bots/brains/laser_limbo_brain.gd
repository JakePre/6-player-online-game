class_name LaserLimboBrain
extends BotBrain
## Sweeping-wall archetype (M19-02, #686): read the nearest wall bearing down on
## our x and take the kind-correct evasion — jump the LOW ones, duck the HIGH
## ones, and slide our y into the opening of a GAP. Walls carry no speed in the
## snapshot, so timing is distance-based (act a little early; the sim re-checks
## every crossing and the bot re-evaluates each tick).
##
## Snapshot: {players: {slot: [x, y, lives, airborne, ducking]}, walls: [[x,
## dir, kind, gap_y], ...], fallen} (LaserLimbo). WallKind: 0 LOW, 1 HIGH,
## 2 GAP. Input: {mx, my, jump, duck}. Indices named via
## LaserLimbo.PS_*/WL_* (#708).

## Jump this far out for a LOW wall so the 0.5 s airtime spans the crossing.
const JUMP_DISTANCE := 2.6
## Duck / hold for a HIGH wall once it's this close.
const DUCK_DISTANCE := 2.2
## Start sliding toward a GAP's opening from this far out.
const GAP_DISTANCE := 5.0


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var me: Array = players.get(slot, [])
	if me.size() < LaserLimbo.PS_COUNT:
		return {}
	var my_pos := Vector2(float(me[LaserLimbo.PS_X]), float(me[LaserLimbo.PS_Y]))
	var airborne := int(me[LaserLimbo.PS_AIRBORNE]) == 1
	var wall := _incoming_wall(game.get("walls", []), my_pos.x)
	if wall.is_empty():
		return {}  # nothing bearing down — hold and stay ready to jump
	var distance: float = wall.distance
	match int(wall.kind):
		LaserLimbo.WallKind.LOW:
			if distance <= JUMP_DISTANCE and not airborne:
				return {"jump": true}
		LaserLimbo.WallKind.HIGH:
			if distance <= DUCK_DISTANCE and not airborne:
				return {"duck": true}
		LaserLimbo.WallKind.GAP:
			if distance <= GAP_DISTANCE:
				# Slide y into the opening; stay put once aligned.
				var dy := float(wall.gap_y) - my_pos.y
				if absf(dy) > 0.2:
					return {"my": signf(dy), "duck": false}
	return {}


## The closest wall still approaching our x (moving toward it, not yet crossed),
## as {distance, kind, gap_y}; {} when none threatens.
func _incoming_wall(walls: Array, px: float) -> Dictionary:
	var best := {}
	var best_distance := INF
	for wall: Array in walls:
		if wall.size() < 4:
			continue
		var wx := float(wall[LaserLimbo.WL_X])
		var dir := float(wall[LaserLimbo.WL_DIR])
		# Approaching iff the wall moves toward our x (sign of the gap matches
		# the sweep direction) — a wall past us is moving away.
		if signf(px - wx) != signf(dir):
			continue
		var distance := absf(wx - px)
		if distance < best_distance:
			best_distance = distance
			best = {
				"distance": distance,
				"kind": int(wall[LaserLimbo.WL_KIND]),
				"gap_y": float(wall[LaserLimbo.WL_GAP_Y]),
			}
	return best
