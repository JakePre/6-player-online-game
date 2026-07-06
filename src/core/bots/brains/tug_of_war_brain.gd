class_name TugOfWarBrain
extends BotBrain
## Rhythm-masher archetype (M19): alternate the pull phase every think tick —
## the sim only counts phase CHANGES ({"pull": 0} -> {"pull": 1} -> ...), so
## strict alternation at the 0.25 s bot cadence is a steady, fair pull rate
## (4 pulls/sec, in the human ballpark). Snapshot: {rope, win_offset, team_a,
## team_b} (TugOfWar).

var _phase := 0


func think(_match_state: Dictionary, _private: Dictionary) -> Dictionary:
	_phase = 1 - _phase
	return {"pull": _phase}
