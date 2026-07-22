class_name TurboLapBrain
extends BotBrain
## Racing archetype (M19-02, #686): follow the elliptical centerline with a
## look-ahead aim point, steering relative to the kart's heading, full
## throttle, drifting through the tight ends to charge boost, and firing any
## item the moment it's held. The kart's next_wp isn't in the snapshot, so the
## racing line is reconstructed from the kart's angular position on the track
## ellipse (which the sim races counter-clockwise).
##
## Snapshot: {players: {slot: [x, y, heading, item, bits]}, shells, oils,
## pads, standings} (TurboLap). bits: 1 spun-out, 2 boosting, 4 drifting,
## 8 finished. Input: {mx: steer, my: -throttle, drift: bool, use: bool}.
## Indices named via TurboLap.PS_* (#708).

## How far ahead on the ellipse to aim, in radians (~1.5 waypoints of the 16).
const LOOKAHEAD_RAD := 0.6
## Steer gain converting a heading error (radians) into a [-1, 1] steer.
const STEER_GAIN := 1.6
## Drift (to charge boost) once the heading error exceeds this — the ellipse
## ends need it; the straights don't.
const DRIFT_ERROR := 0.5
## Shield (#956): a shell within this range is treated as an incoming threat, so
## a held shell is trailed as a blocker instead of fired.
const SHELL_THREAT_RANGE := 5.0
## Shortcut (#956): only committed to with boost banked, and only once the kart
## is within this range of the cut's entry waypoint — aim through the mud then.
const SHORTCUT_AIM_RANGE := 3.5

## Held-item edge state (#956): the item button is now hold-to-shield / release-
## to-fire, so firing a shell offensively is a press one tick, release the next.
var _use_held := false


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < TurboLap.PS_COUNT or (int(state[TurboLap.PS_BITS]) & 8) != 0:
		return {}  # not racing, or already finished
	var pos := Vector2(float(state[TurboLap.PS_X]), float(state[TurboLap.PS_Y]))
	var heading := float(state[TurboLap.PS_HEADING])
	var boosting := (int(state[TurboLap.PS_BITS]) & 2) != 0
	# Aim a look-ahead point along the centerline ellipse (raced CCW) — unless a
	# boost is banked near the shortcut entry, in which case cut through the mud.
	var aim := _aim_point(pos, boosting)
	# Steer toward the aim relative to current heading (positive steer turns
	# CCW, matching the sim's heading += steer * rate).
	var error := wrapf((aim - pos).angle() - heading, -PI, PI)
	var intent := {"mx": clampf(error * STEER_GAIN, -1.0, 1.0), "my": -1.0}  # -throttle: full
	if absf(error) > DRIFT_ERROR:
		intent["drift"] = true
	_decide_item(int(state[TurboLap.PS_ITEM]), pos, game, intent)
	return intent


## The point to steer at: the shortcut exit when a boost is banked near the cut's
## entry (spend the boost on the mud), else the usual look-ahead on the ellipse.
func _aim_point(pos: Vector2, boosting: bool) -> Vector2:
	if boosting:
		var seg := TurboLap.shortcut_segment()
		if pos.distance_to(seg[0]) <= SHORTCUT_AIM_RANGE:
			return seg[1]  # cut through the mud toward the exit
	var track_angle := atan2(pos.y / TurboLap.TRACK_RY, pos.x / TurboLap.TRACK_RX)
	var aim_angle := track_angle + LOOKAHEAD_RAD
	return Vector2(cos(aim_angle) * TurboLap.TRACK_RX, sin(aim_angle) * TurboLap.TRACK_RY)


## Item use (#956): oil/boost fire on press; a shell is trailed as a shield while
## a shell threatens, else tapped (press then release) to fire it forward.
func _decide_item(item: int, pos: Vector2, game: Dictionary, intent: Dictionary) -> void:
	if item == TurboLap.ITEM_NONE:
		_use_held = false
		return
	if item != TurboLap.ITEM_SHELL:
		intent["use"] = true  # oil/boost fire immediately on press
		_use_held = false
		return
	if _shell_threatens(pos, game):
		intent["use"] = true  # hold to shield behind us
		_use_held = true
	elif _use_held:
		intent["use"] = false  # release -> fire the shell forward
		_use_held = false
	else:
		intent["use"] = true  # press this tick; the release next tick fires it
		_use_held = true


## True if any shell is close enough to count as incoming (#956) — the snapshot
## carries no target, so proximity stands in for "this one is hunting me".
func _shell_threatens(pos: Vector2, game: Dictionary) -> bool:
	for shell: Array in game.get("shells", []):
		if (
			pos.distance_to(Vector2(float(shell[TurboLap.SH_X]), float(shell[TurboLap.SH_Y])))
			<= SHELL_THREAT_RANGE
		):
			return true
	return false
