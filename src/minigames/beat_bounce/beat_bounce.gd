class_name BeatBounce
extends MinigameBase
## Beat Bounce (M4-09, SPEC $7 #10): jump on the pad in rhythm. A metronome
## beat fires on a shrinking interval; each alive player must press once
## inside the timing window around every beat. Missing a beat — or pressing
## off-beat — is a strike, and two strikes eliminate. Last bouncer standing
## wins; survivors outrank the eliminated, who rank by how long they lasted.
## Server-side simulation only — the client renders get_snapshot().

const STRIKES_TO_ELIMINATE := 2
## The first beat lands after a lead-in so players can find the rhythm.
const LEAD_IN_SEC := 2.5
const START_INTERVAL_SEC := 1.2
## Kept above 2x HIT_WINDOW_SEC so adjacent beat windows never overlap.
const MIN_INTERVAL_SEC := 0.5
## Interval multiplier applied every beat (tempo ramps up).
const TEMPO_DECAY := 0.96
## A press within this many seconds of a beat instant counts as on-beat.
const HIT_WINDOW_SEC := 0.2

var interval := START_INTERVAL_SEC
var beat_index := 0
## Absolute `elapsed` time of the upcoming beat.
var next_beat := LEAD_IN_SEC
var strikes := {}
var alive := {}
## slot -> beat_index the player was eliminated on (for ranking).
var eliminated_on := {}
## slot -> last beat index the player successfully hit (view feedback).
var last_hit := {}

## Slots that already hit the pending beat (cleared when the beat closes).
var _hit_this_beat := {}
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
				"Bounce on the beat! The tempo keeps climbing — miss twice and you're out.",
				"controls": "Bounce — SPACE / pad A, on the beat",
			}
		)
	)


func _setup() -> void:
	for slot: int in slots:
		strikes[slot] = 0
		alive[slot] = true
		last_hit[slot] = -1


func _tick(_delta: float) -> void:
	if elapsed >= next_beat:
		_open_beat()
	if not _prev_closed and elapsed > _prev_beat + HIT_WINDOW_SEC:
		_close_beat()


## `data` comes straight off the wire — validate everything. A press is
## on-beat if it lands inside the window around the previous or upcoming
## beat instant; anything else is an off-beat strike.
func _handle_input(slot: int, data: Dictionary) -> void:
	if not data.get("press", false) or not alive.get(slot, false):
		return
	if not _prev_closed:
		# Inside the open beat's window: first press hits, repeats are
		# swallowed (double-press leniency, never an off-beat strike).
		if not _hit_this_beat.has(slot):
			_hit_this_beat[slot] = true
			last_hit[slot] = beat_index
		return
	if absf(next_beat - elapsed) <= HIT_WINDOW_SEC:
		# Early press for the upcoming beat: credit it now so the close
		# pass does not double-count; repeats are swallowed the same way.
		if not _hit_this_beat.has(slot):
			_hit_this_beat[slot] = true
			last_hit[slot] = beat_index + 1
		return
	_strike(slot)


func get_snapshot() -> Dictionary:
	return {
		"beat": beat_index,
		"next_in": snappedf(maxf(next_beat - elapsed, 0.0), 0.01),
		"interval": snappedf(interval, 0.01),
		"strikes": strikes.duplicate(),
		"alive": alive.duplicate(),
		"last_hit": last_hit.duplicate(),
	}


func _rank_players() -> Array:
	var groups := {}
	for slot: int in slots:
		# Survivors sort above every eliminated player; fewer strikes rank
		# higher among survivors, later elimination among the fallen.
		var key: int = (10000 - int(strikes[slot])) if alive[slot] else int(eliminated_on[slot])
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


## The beat instant arrives: presses already banked for it carry over via
## _hit_this_beat (early hits); schedule the next beat and ramp the tempo.
func _open_beat() -> void:
	if not _prev_closed:
		_close_beat()
	beat_index += 1
	_prev_beat = next_beat
	_prev_closed = false
	interval = maxf(MIN_INTERVAL_SEC, interval * TEMPO_DECAY)
	next_beat += interval


## The grace window after a beat ends: every alive player who never hit it
## takes a strike.
func _close_beat() -> void:
	_prev_closed = true
	for slot: int in slots:
		if alive[slot] and not _hit_this_beat.has(slot):
			_strike(slot)
	_hit_this_beat.clear()


func _strike(slot: int) -> void:
	if not alive.get(slot, false):
		return
	strikes[slot] = int(strikes[slot]) + 1
	if int(strikes[slot]) >= STRIKES_TO_ELIMINATE:
		alive[slot] = false
		eliminated_on[slot] = beat_index
		if _alive_count() <= 1:
			finish(_rank_players())


func _alive_count() -> int:
	var count := 0
	for slot: int in slots:
		if alive[slot]:
			count += 1
	return count
