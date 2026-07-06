class_name ShredSession
extends MinigameBase
## Shred Session (M14-04): a 4-lane rhythm highway. A seeded note chart streams
## down four lanes at the round-loop tempo; hit each lane's note as it crosses
## the line for points. A tight window scores a PERFECT (double), a looser one a
## GOOD (single), and a clean streak multiplies the take. No elimination — the
## highest score when the ~60 s song ends wins.
##
## The server owns the whole chart timeline (elapsed-based) and every judgment;
## the client only visualizes the replicated clock. Latency is absorbed by
## deliberately generous windows, NOT compensated — party honesty over esports
## precision. Everyone plays the same seeded chart, so the round is deterministic
## across server and clients (spec §8 Genre Hop; owner ruling #546).

## Echoed per player so the view can flash the right lane on the right beat.
enum Judgment { NONE, PERFECT, GOOD, MISS }

const LANES := 4
## Nominal tempo of the M6-01 round loop ("Pixel Peeker Polka - faster", Kevin
## MacLeod) — a brisk polka around 130 BPM. Declared once; tune by ear against
## assets/audio/incompetech/round_loop.mp3 if the notes drift off the music.
const BPM := 130.0
const BEAT_SEC := 60.0 / BPM
## Lead-in before the first note so the highway fills before anything is hittable.
const LEAD_IN_SEC := 2.0
## Judgment windows around a note's cross time. Generous on purpose (see above).
const PERFECT_SEC := 0.12
const GOOD_SEC := 0.25
const PERFECT_POINTS := 2
const GOOD_POINTS := 1
## Streak multiplier tiers: x2 from the 8th clean hit, x3 from the 16th (capped).
const STREAK_X2 := 8
const STREAK_X3 := 16
## How far ahead the snapshot advertises upcoming notes (the visible highway).
const LOOKAHEAD_SEC := 4.0

## The chart: time-sorted array of {time: float, lane: int}. Seeded, so identical
## on every peer.
var chart: Array = []

var score := {}
var streak := {}
var best_streak := {}
var last_judgment := {}
var last_lane := {}
## Bumped on every judgment (hit, whiff, or miss) so the view can tell a fresh
## verdict from a stale sticky one.
var event_count := {}

## slot -> {note_index -> true}: notes this player has already scored, so a lane
## press can't double-dip and _tick can mark the un-hit ones a miss.
var _hit := {}
## Chart index up to which every note has closed (fully past its GOOD window).
var _miss_cursor := 0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"shred_session",
				"name": "Shred Session",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 62.0,
				"rules":
				(
					"Hit each lane's note as it crosses the line! "
					+ "Nail the beat for double, keep a streak for a multiplier."
				),
				"controls":
				"Strum the four lanes — ◀ ▶ ▲ / action (left stick / pad A), on the beat",
				"control_hints":  # Device-aware (#608); stick lanes stay literal (axis-bound).
				[
					"Strum the four lanes — ◀ ▶ ▲ / action (left stick / ",
					{"action": &"action_primary"},
					"), on the beat",
				],
			}
		)
	)


func _setup() -> void:
	for slot: int in slots:
		score[slot] = 0
		streak[slot] = 0
		best_streak[slot] = 0
		last_judgment[slot] = Judgment.NONE
		last_lane[slot] = -1
		event_count[slot] = 0
		_hit[slot] = {}
	_build_chart()


## Seeded chart generation: one candidate beat per BEAT_SEC, its spawn odds and
## the odds of a second simultaneous note both ramping across the song like
## Bullet Waltz's escalation, so it opens sparse and finishes dense.
func _build_chart() -> void:
	var song_end := effective_duration() - 1.0
	var beat := 0
	var t := LEAD_IN_SEC
	while t < song_end:
		var progress := clampf((t - LEAD_IN_SEC) / maxf(song_end - LEAD_IN_SEC, 0.01), 0.0, 1.0)
		if rng.randf() < lerpf(0.55, 0.95, progress):
			var lane := rng.randi_range(0, LANES - 1)
			chart.append({"time": t, "lane": lane})
			if rng.randf() < lerpf(0.0, 0.35, progress):
				var lane2 := (lane + rng.randi_range(1, LANES - 1)) % LANES
				chart.append({"time": t, "lane": lane2})
		beat += 1
		t = LEAD_IN_SEC + beat * BEAT_SEC


## Close every note whose GOOD window has fully elapsed; any player who never
## scored it just missed, breaking their streak.
func _tick(_delta: float) -> void:
	while _miss_cursor < chart.size() and float(chart[_miss_cursor].time) + GOOD_SEC < elapsed:
		var lane := int(chart[_miss_cursor].lane)
		for slot: int in slots:
			if not _is_hit(slot, _miss_cursor):
				_register(slot, Judgment.MISS, lane)
		_miss_cursor += 1


## A lane press scores the nearest un-hit note in that lane still inside the GOOD
## window; a press with nothing in range is a whiff. Either way the streak and
## last-judgment state update for the view.
func _handle_input(slot: int, data: Dictionary) -> void:
	var lane := int(data.get("lane", -1))
	if lane < 0 or lane >= LANES:
		return
	var best_i := -1
	var best_dt := GOOD_SEC + 1.0
	for i in range(_miss_cursor, chart.size()):
		var note_time := float(chart[i].time)
		if note_time - elapsed > GOOD_SEC:
			break  # sorted by time — nothing further is in the window yet
		if int(chart[i].lane) != lane or _is_hit(slot, i):
			continue
		var dt := absf(note_time - elapsed)
		if dt <= GOOD_SEC and dt < best_dt:
			best_dt = dt
			best_i = i
	if best_i == -1:
		_register(slot, Judgment.MISS, lane)
		return
	(_hit[slot] as Dictionary)[best_i] = true
	var perfect := best_dt <= PERFECT_SEC
	streak[slot] = int(streak[slot]) + 1
	best_streak[slot] = maxi(int(best_streak[slot]), int(streak[slot]))
	var base_points := PERFECT_POINTS if perfect else GOOD_POINTS
	score[slot] = int(score[slot]) + base_points * _multiplier(slot)
	_register(slot, Judgment.PERFECT if perfect else Judgment.GOOD, lane, false)


## Records a judgment: a miss/whiff breaks the streak; every judgment bumps the
## event counter and remembers the lane so the view flashes correctly.
func _register(slot: int, judgment: Judgment, lane: int, break_streak := true) -> void:
	if break_streak and judgment == Judgment.MISS:
		streak[slot] = 0
	last_judgment[slot] = judgment
	last_lane[slot] = lane
	event_count[slot] = int(event_count[slot]) + 1


func _multiplier(slot: int) -> int:
	var current := int(streak[slot])
	if current >= STREAK_X3:
		return 3
	if current >= STREAK_X2:
		return 2
	return 1


func _is_hit(slot: int, note_index: int) -> bool:
	return (_hit[slot] as Dictionary).has(note_index)


func get_snapshot() -> Dictionary:
	var upcoming: Array = []
	for i in range(_miss_cursor, chart.size()):
		var note_time := float(chart[i].time)
		if note_time - elapsed > LOOKAHEAD_SEC:
			break
		upcoming.append([snappedf(note_time, 0.01), int(chart[i].lane)])
	var players := {}
	for slot: int in slots:
		players[slot] = [
			int(score[slot]),
			int(streak[slot]),
			int(last_judgment[slot]),
			int(last_lane[slot]),
			int(event_count[slot]),
		]
	return {
		"elapsed": snappedf(elapsed, 0.01),
		"lanes": LANES,
		"song_end": snappedf(effective_duration(), 0.01),
		"notes": upcoming,
		"players": players,
	}


## Score descending, ties grouped (spec §5).
func _rank_players() -> Array:
	var groups := {}
	for slot: int in slots:
		var key := int(score[slot])
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
