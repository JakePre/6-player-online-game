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

## How far ahead on the ellipse to aim, in radians (~1.5 waypoints of the 16).
const LOOKAHEAD_RAD := 0.6
## Steer gain converting a heading error (radians) into a [-1, 1] steer.
const STEER_GAIN := 1.6
## Drift (to charge boost) once the heading error exceeds this — the ellipse
## ends need it; the straights don't.
const DRIFT_ERROR := 0.5


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < 5 or (int(state[4]) & 8) != 0:
		return {}  # not racing, or already finished
	var pos := Vector2(float(state[0]), float(state[1]))
	var heading := float(state[2])
	var has_item := int(state[3]) != 0
	# Aim a look-ahead point along the centerline ellipse (raced CCW).
	var track_angle := atan2(pos.y / TurboLap.TRACK_RY, pos.x / TurboLap.TRACK_RX)
	var aim_angle := track_angle + LOOKAHEAD_RAD
	var aim := Vector2(cos(aim_angle) * TurboLap.TRACK_RX, sin(aim_angle) * TurboLap.TRACK_RY)
	# Steer toward the aim relative to current heading (positive steer turns
	# CCW, matching the sim's heading += steer * rate).
	var error := wrapf((aim - pos).angle() - heading, -PI, PI)
	var steer := clampf(error * STEER_GAIN, -1.0, 1.0)
	var intent := {"mx": steer, "my": -1.0}  # my = -throttle: full forward
	if absf(error) > DRIFT_ERROR:
		intent["drift"] = true
	if has_item:
		intent["use"] = true
	return intent
