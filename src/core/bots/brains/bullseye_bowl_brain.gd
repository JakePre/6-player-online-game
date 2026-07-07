class_name BullseyeBowlBrain
extends BotBrain
## Predictive-timing archetype (M19-02, #686): the ball scores against the
## target's offset at LANDING time (FLIGHT_SEC after the roll), and the target
## oscillates as A*sin(ωt + φ). So the bot models the sine — solving phase
## from two samples — and rolls only when the target will be at ring-center
## once the ball arrives.
##
## Snapshot: {players: {slot: [score, balls_left, flight_t, target_offset]}}
## (BullseyeBowl). Input: {roll: true}.

## Mirror the sim's oscillation + flight so the prediction matches.
const AMPLITUDE := BullseyeBowl.TARGET_AMPLITUDE
const OMEGA := TAU / BullseyeBowl.TARGET_PERIOD_SEC
const LEAD := BullseyeBowl.FLIGHT_SEC
## Roll when the predicted landing offset is within this of center — inside
## the mid ring, biased toward the bullseye. Tighter than RING_MID so bots
## favor good rolls over merely scoring ones.
const ROLL_WINDOW := 0.7

var _last_offset := INF


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var state: Array = players.get(slot, [])
	if state.size() < 4:
		return {}
	var balls_left := int(state[1])
	var in_flight := float(state[2]) >= 0.0
	var offset := float(state[3])
	var previous := _last_offset
	_last_offset = offset
	if balls_left <= 0 or in_flight or previous == INF:
		return {}  # nothing to roll, mid-flight, or no direction sample yet
	# Solve the current sine phase from offset + direction, then predict where
	# the target sits one flight-time from now.
	var rising := offset >= previous
	var landing := _predict_landing(offset, rising)
	if absf(landing) <= ROLL_WINDOW:
		return {"roll": true}
	return {}


## Offset FLIGHT_SEC ahead, given the current offset and whether it's rising.
## phase = asin(offset/A) resolved by direction; advance by OMEGA*LEAD.
func _predict_landing(offset: float, rising: bool) -> float:
	var ratio := clampf(offset / AMPLITUDE, -1.0, 1.0)
	var phase := asin(ratio)
	if not rising:
		phase = PI - phase  # falling half of the cycle
	return AMPLITUDE * sin(phase + OMEGA * LEAD)
