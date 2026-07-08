class_name RelaySprintBrain
extends BotBrain
## Relay-racer archetype (M19-02, #686): only the currently active runner on
## each team affects progress (the sim reads _move[active_runner] and ignores
## everyone else's), so a benched teammate just idles. The active runner runs
## flat out, swerving away from whichever oscillating sweeper is both close
## ahead and lined up with our current lane position — using its CURRENT
## snapshot position, the same instant-in-time read a human watching the
## sweeper would react to.
##
## Snapshot: {lanes: {team_index: [team_slots, active_leg, progress, lateral,
## done]}, track_len, hazards: [[x, current_lateral], ...]}. Input: {mx, my}.
## Indices named via RelaySprint.LN_*/HZ_* (#708).

## How far ahead (in progress units) an upcoming sweeper starts mattering.
const LOOKAHEAD := 3.0
## Return-to-center drift once nothing nearby is dangerous.
const CENTER_PULL := 0.3


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var lanes: Dictionary = game.get("lanes", {})
	var team_index := _find_team(lanes)
	if team_index == -1:
		return {}
	var lane: Array = lanes[team_index]
	if bool(lane[RelaySprint.LN_DONE]):
		return {}  # team finished
	var team_slots: Array = lane[RelaySprint.LN_ROSTER]
	var active_leg := int(lane[RelaySprint.LN_ACTIVE_LEG])
	if active_leg < 0 or active_leg >= team_slots.size() or int(team_slots[active_leg]) != slot:
		return {}  # benched: only the active runner's input matters
	var progress := float(lane[RelaySprint.LN_PROGRESS])
	var lateral := float(lane[RelaySprint.LN_LATERAL])
	# INF means "no imminent threat" — a sentinel float, not Variant/null, so
	# the comparison below stays statically typed.
	var threat_lateral := _imminent_threat(game.get("hazards", []), progress)
	var danger_margin := RelaySprint.HAZARD_RADIUS + RelaySprint.RUNNER_RADIUS + 0.3
	if threat_lateral != INF and absf(lateral - threat_lateral) <= danger_margin:
		var away := signf(lateral - threat_lateral)
		return {"mx": 1.0, "my": away if away != 0.0 else 1.0}
	var recenter := -signf(lateral) if absf(lateral) > 0.1 else 0.0
	return {"mx": 1.0, "my": recenter * CENTER_PULL}


func _find_team(lanes: Dictionary) -> int:
	for team_index: Variant in lanes:
		var lane: Array = lanes[team_index]
		if slot in (lane[RelaySprint.LN_ROSTER] as Array):
			return int(team_index)
	return -1


## The lateral offset of the nearest sweeper within LOOKAHEAD progress units
## ahead of us, or INF if nothing's close enough to react to yet.
func _imminent_threat(hazards: Array, progress: float) -> float:
	var best := INF
	var best_dist := INF
	for hazard: Array in hazards:
		var dx := float(hazard[RelaySprint.HZ_X]) - progress
		if dx < -RelaySprint.HAZARD_RADIUS or dx > LOOKAHEAD:
			continue
		if dx < best_dist:
			best_dist = dx
			best = float(hazard[RelaySprint.HZ_LATERAL])
	return best
