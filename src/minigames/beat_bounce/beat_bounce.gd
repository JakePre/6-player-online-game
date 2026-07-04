class_name BeatBounce
extends MinigameBase
## Beat Bounce (M4-09, reworked #259): Simon Says on a metronome. Each round
## the game flashes a growing pad sequence, one pad per beat (WATCH), then the
## players must reproduce it on the beat (REPEAT) — hit the right pad inside
## the window around its beat. A wrong pad or a missed/off-beat step is a
## strike; two strikes in a round eliminate you. The sequence grows and the
## tempo climbs each round; last bouncer standing wins, the fallen rank by how
## far they got. Server-side simulation only — the client renders
## get_snapshot(); the sequence is withheld during REPEAT so no one can peek.

enum Phase { WATCH, REPEAT }

const PAD_COUNT := 4
const STRIKES_TO_ELIMINATE := 2
const START_LENGTH := 2
## Lead-in before the first beat so players find the tempo.
const LEAD_IN_SEC := 2.0
const START_INTERVAL_SEC := 0.9
const MIN_INTERVAL_SEC := 0.42
## Interval multiplier applied per round (tempo ramps up between rounds).
const TEMPO_DECAY := 0.92
## A press within this many seconds of a beat instant is on-beat. Kept below
## half the min interval so adjacent beat windows never overlap.
const HIT_WINDOW_SEC := 0.18
## A short breath between WATCH's last flash and the first REPEAT beat.
const PHASE_GAP_BEATS := 1

var phase: Phase = Phase.WATCH
var round_index := 0
var sequence: Array[int] = []
## Global beat counter (drives the view's metronome tick).
var beat_index := 0
## Index within the current phase: which sequence step is flashing (WATCH) or
## expected (REPEAT).
var phase_step := 0
## The pad flashing this beat during WATCH, else -1.
var flash_pad := -1
var interval := START_INTERVAL_SEC
## Absolute `elapsed` of the upcoming beat.
var next_beat := LEAD_IN_SEC

var strikes := {}
var alive := {}
## slot -> round_index it was eliminated on (for ranking the fallen).
var eliminated_on := {}
## slot -> how many steps of the current round it has cleared (view feedback).
var progress := {}

## Slots that already resolved the currently-open REPEAT beat (hit or struck).
var _resolved_this_beat := {}
## The most recent beat instant, still accepting late hits until + window.
var _prev_beat := -1.0
var _prev_closed := true


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"beat_bounce",
				"name": "Beat Bounce",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 6,
				"duration_sec": 90.0,
				"rules":
				(
					"Watch the pattern, then bounce it back on the beat! "
					+ "Wrong pad or off the beat is a strike — two and you're out."
				),
				"controls": "Bounce the pads — WASD / D-pad, on the beat",
			}
		)
	)


func _setup() -> void:
	for slot: int in slots:
		strikes[slot] = 0
		alive[slot] = true
		progress[slot] = 0
	_deal_round()


func _deal_round() -> void:
	var target_length := START_LENGTH + round_index
	while sequence.size() < target_length:
		sequence.append(rng.randi_range(0, PAD_COUNT - 1))
	phase = Phase.WATCH
	phase_step = -1  # first beat advances to 0
	flash_pad = -1
	for slot: int in slots:
		if alive[slot]:
			strikes[slot] = 0
			progress[slot] = 0
	_resolved_this_beat.clear()
	_prev_closed = true


func _tick(_delta: float) -> void:
	if finished:
		return
	if elapsed >= next_beat:
		_open_beat()
	if not _prev_closed and elapsed > _prev_beat + HIT_WINDOW_SEC:
		_close_beat()


## `data` comes off the wire — validate everything. During REPEAT a press is
## judged against the open beat's window: right pad = clear the step, wrong pad
## or a press in dead air = strike. WATCH presses are ignored (you're
## watching). Repeats within a beat are swallowed.
func _handle_input(slot: int, data: Dictionary) -> void:
	if phase != Phase.REPEAT or not alive.get(slot, false):
		return
	var pad := int(data.get("pad", -1))
	if pad < 0 or pad >= PAD_COUNT:
		return
	if _resolved_this_beat.has(slot):
		return
	var window_open := not _prev_closed and phase_step >= 0 and phase_step < sequence.size()
	var early := absf(next_beat - elapsed) <= HIT_WINDOW_SEC and phase_step + 1 < sequence.size()
	if not window_open and not early:
		# A press in dead air between beats is an off-beat strike.
		_resolved_this_beat[slot] = true
		_strike(slot)
		return
	var expected: int = sequence[phase_step + 1] if early else sequence[phase_step]
	_resolved_this_beat[slot] = true
	if pad == expected:
		progress[slot] = int(progress[slot]) + 1
	else:
		_strike(slot)


func get_snapshot() -> Dictionary:
	return {
		"phase": phase,
		"round": round_index,
		"seq_len": sequence.size(),
		"pad_count": PAD_COUNT,
		"beat": beat_index,
		"step": phase_step,
		# Revealed only while demonstrating, so REPEAT can't be light-read.
		"sequence": sequence.duplicate() if phase == Phase.WATCH else ([] as Array[int]),
		"flash": flash_pad,
		"next_in": snappedf(maxf(next_beat - elapsed, 0.0), 0.01),
		"interval": snappedf(interval, 0.01),
		"strikes": strikes.duplicate(),
		"alive": alive.duplicate(),
		"progress": progress.duplicate(),
	}


func _rank_players() -> Array:
	var groups := {}
	for slot: int in slots:
		# Survivors outrank everyone eliminated; among survivors more cleared
		# rounds ranks higher, among the fallen a later elimination does.
		var key: int = (
			(1000000 + round_index * 100 + int(progress[slot]))
			if alive[slot]
			else int(eliminated_on[slot])
		)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(slot)
	var keys := groups.keys()
	keys.sort()
	keys.reverse()
	var placements: Array = []
	for key: int in keys:
		placements.append(groups[key])
	return placements


## A beat instant arrives: close any open window, advance the step, ramp the
## clock, and either flash the next demo pad (WATCH) or open the next expected
## step (REPEAT). Running past the sequence ends the phase.
func _open_beat() -> void:
	if not _prev_closed:
		_close_beat()
	beat_index += 1
	_prev_beat = next_beat
	next_beat += interval
	phase_step += 1
	flash_pad = -1
	if phase == Phase.WATCH:
		if phase_step < sequence.size():
			flash_pad = sequence[phase_step]
			_prev_closed = true  # WATCH has no hit window
		elif phase_step >= sequence.size() + PHASE_GAP_BEATS - 1:
			_begin_repeat()
		else:
			_prev_closed = true  # the breath beat between phases
	else:  # REPEAT
		if phase_step < sequence.size():
			_prev_closed = false  # open this step's hit window
			_resolved_this_beat.clear()
		else:
			_end_round()


func _begin_repeat() -> void:
	phase = Phase.REPEAT
	phase_step = -1  # the next beat opens step 0
	flash_pad = -1
	_prev_closed = true


## The window after a REPEAT beat closes: every alive player who never
## resolved this step missed it — that is a strike.
func _close_beat() -> void:
	_prev_closed = true
	if phase != Phase.REPEAT or phase_step < 0 or phase_step >= sequence.size():
		return
	for slot: int in slots:
		if alive[slot] and not _resolved_this_beat.has(slot):
			_strike(slot)
	_resolved_this_beat.clear()


func _end_round() -> void:
	if finished:
		return
	if _alive_count() <= 1:
		finish(_rank_players())
		return
	round_index += 1
	interval = maxf(MIN_INTERVAL_SEC, interval * TEMPO_DECAY)
	_deal_round()


func _strike(slot: int) -> void:
	if not alive.get(slot, false):
		return
	strikes[slot] = int(strikes[slot]) + 1
	if int(strikes[slot]) >= STRIKES_TO_ELIMINATE:
		alive[slot] = false
		eliminated_on[slot] = round_index
		if _alive_count() <= 1:
			finish(_rank_players())


func _alive_count() -> int:
	var count := 0
	for slot: int in slots:
		if alive[slot]:
			count += 1
	return count
