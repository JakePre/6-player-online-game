extends GutTest
## Timing / pad-selection bot brains (M19-02, #686): simon_stomp, count_quick,
## shred_session — steering/pressing assertions on crafted snapshots. Split from
## test_bot_brains.gd per gdlint's public-method cap (same precedent as
## test_match_controller_finale_only.gd). (ro_sham_bo's brain retired with the
## game in #791; beat_bounce's retired with the Tilt Deck remake in #794 —
## tilt_deck has its own brain test.)


func _play_state(id: String, game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": id, "game": game}


# --- simon_stomp ------------------------------------------------------------------


func test_simon_stomp_brain_remembers_and_plays_back_in_order() -> void:
	var brain := BotBrains.brain_for(&"simon_stomp", 0, 1)
	brain.think(
		_play_state(
			"simon_stomp", {"phase": SimonStomp.Phase.SHOW, "sequence": [1, 3], "alive": {0: true}}
		),
		{}
	)
	var first := (
		brain
		. think(
			_play_state(
				"simon_stomp",
				{
					"phase": SimonStomp.Phase.INPUT,
					"alive": {0: true},
					"progress": {0: 0},
					"round_cleared": {},
					"round_failed": {},
				}
			),
			{}
		)
	)
	assert_eq(int(first.get("pad", -1)), 1, "presses remembered[0]")
	var second := (
		brain
		. think(
			_play_state(
				"simon_stomp",
				{
					"phase": SimonStomp.Phase.INPUT,
					"alive": {0: true},
					"progress": {0: 1},
					"round_cleared": {},
					"round_failed": {},
				}
			),
			{}
		)
	)
	assert_eq(int(second.get("pad", -1)), 3, "server's own progress count picks step 2")


func test_simon_stomp_brain_stops_once_cleared() -> void:
	var brain := BotBrains.brain_for(&"simon_stomp", 0, 1)
	var game := {
		"phase": SimonStomp.Phase.INPUT,
		"alive": {0: true},
		"progress": {0: 2},
		"round_cleared": {0: true},
		"round_failed": {},
	}
	assert_eq(brain.think(_play_state("simon_stomp", game), {}), {})


# --- count_quick --------------------------------------------------------------


func test_count_quick_brain_counts_the_swarm_then_runs_to_its_pad() -> void:
	var brain := BotBrains.brain_for(&"count_quick", 0, 1)
	(
		brain
		. think(
			_play_state(
				"count_quick",
				{
					"phase": CountQuick.Phase.FLASH,
					"players": {0: [0.0, 0.0, 0, 0]},
					"swarm": [[1.0, 1.0], [2.0, 2.0], [3.0, 3.0]],
				}
			),
			{}
		)
	)
	var intent := (
		brain
		. think(
			_play_state(
				"count_quick",
				{
					"phase": CountQuick.Phase.ANSWER,
					"players": {0: [0.0, 0.0, 0, 0]},
					"pads": [[6.0, -6.0, 2], [6.0, 6.0, 3], [-6.0, 6.0, 4], [-6.0, -6.0, 5]],
				}
			),
			{}
		)
	)
	assert_gt(float(intent.get("mx", 0.0)), 0.0, "the 3-pad sits at +x")
	assert_gt(float(intent.get("my", 0.0)), 0.0, "the 3-pad sits at +y")


func test_count_quick_brain_holds_once_locked() -> void:
	var brain := BotBrains.brain_for(&"count_quick", 0, 1)
	var game := {
		"phase": CountQuick.Phase.ANSWER,
		"players": {0: [6.0, -6.0, 2, 1]},
		"pads": [[6.0, -6.0, 3]],
	}
	assert_eq(brain.think(_play_state("count_quick", game), {}), {})


# --- shred_session ------------------------------------------------------------


func test_shred_session_brain_presses_the_note_inside_the_good_window() -> void:
	var brain := BotBrains.brain_for(&"shred_session", 0, 1)
	var game := {"elapsed": 10.0, "notes": [[10.05, 2], [12.0, 1]]}
	var intent := brain.think(_play_state("shred_session", game), {})
	assert_eq(int(intent.get("lane", -1)), 2, "the note 0.05s away is in the GOOD window")


func test_shred_session_brain_never_represses_the_same_note() -> void:
	var brain := BotBrains.brain_for(&"shred_session", 0, 1)
	var game := {"elapsed": 10.0, "notes": [[10.05, 2]]}
	var first := brain.think(_play_state("shred_session", game), {})
	assert_eq(int(first.get("lane", -1)), 2)
	# The note lingers in the upcoming list (miss_cursor is chart-wide, not
	# per-player); a second poll at the same instant must stay quiet.
	var second := brain.think(_play_state("shred_session", game), {})
	assert_eq(second, {}, "already pressed this note — no re-press")


func test_shred_session_brain_ignores_notes_outside_the_window() -> void:
	var brain := BotBrains.brain_for(&"shred_session", 0, 1)
	var game := {"elapsed": 10.0, "notes": [[11.0, 1]]}
	assert_eq(brain.think(_play_state("shred_session", game), {}), {})
