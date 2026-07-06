class_name TugOfWar
extends MinigameBase
## Tug of War (M4-10, SPEC $7 #11): alternating-key mashing tug between two
## even teams; the first team dragged over the line loses. Server-side
## simulation only — the client renders get_snapshot(). First consumer of the
## team_mode award routing (#41).

## Rope offset at which the losing team is over the line.
const WIN_OFFSET := 10.0
## Rope movement per valid (alternated) pull.
const PULL_STRENGTH := 0.35

## Team A pulls negative, team B positive.
var team_a: Array = []
var team_b: Array = []
var rope := 0.0

## Last pull phase per slot (-1 = none yet); inputs only count when the
## phase alternates, so holding a key does nothing.
var _last_phase := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"tug_of_war",
				"controls": "Alternate LEFT and RIGHT (A / D / left stick) as fast as you can",
				"name": "Tug of War",
				"category": MinigameMeta.Category.TEAM,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 30.0,
				"rules":
				"Mash left and right alternately to pull! Drag the other team over the line.",
			}
		)
	)


func _setup() -> void:
	team_mode = true
	var shuffled := slots.duplicate()
	# Deterministic split from the round seed.
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: int = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = swap
	team_a = shuffled.slice(0, shuffled.size() / 2)
	team_b = shuffled.slice(shuffled.size() / 2)
	for slot: int in slots:
		_last_phase[slot] = -1


## A pull is {"pull": 0} or {"pull": 1}; only alternating phases count.
func _handle_input(slot: int, data: Dictionary) -> void:
	if not data.has("pull"):
		return
	var phase := int(data.pull)
	if phase != 0 and phase != 1:
		return
	if phase == int(_last_phase[slot]):
		return
	_last_phase[slot] = phase
	rope += -_pull_of(team_a) if slot in team_a else _pull_of(team_b)


func _tick(_delta: float) -> void:
	if absf(rope) >= WIN_OFFSET:
		finish(_rank_players())


func get_snapshot() -> Dictionary:
	return {
		"rope": snappedf(rope, 0.01),
		"win_offset": WIN_OFFSET,
		"team_a": team_a.duplicate(),
		"team_b": team_b.duplicate(),
	}


## Handicap for uneven splits (#137): per-player pull strength is normalized
## by team size (relative to an even split), so total pull capacity is equal
## at any split — at 3v2 each pair member pulls 1.25x, each trio member 0.83x.
func _pull_of(own: Array) -> float:
	return PULL_STRENGTH * (slots.size() / 2.0) / float(own.size())


## Teams best-first (team_mode routing applies SPEC $5 team awards). At the
## line the dragging team wins; on timeout rope advantage decides, dead
## level is a tie.
func _rank_players() -> Array:
	if rope < 0.0:
		return [team_a.duplicate(), team_b.duplicate()]
	if rope > 0.0:
		return [team_b.duplicate(), team_a.duplicate()]
	return [slots.duplicate()]
