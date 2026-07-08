extends GutTest
## Timing / pad-selection bot brains (M19-02, #686): beat_bounce, simon_stomp,
## count_quick, shred_session, ro_sham_bo — steering/pressing assertions on
## crafted snapshots. Split from test_bot_brains.gd per gdlint's public-method
## cap (same precedent as test_match_controller_finale_only.gd).


func _play_state(id: String, game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": id, "game": game}


# --- beat_bounce ----------------------------------------------------------------


func test_beat_bounce_brain_remembers_the_sequence_during_watch() -> void:
	var brain := BotBrains.brain_for(&"beat_bounce", 0, 1)
	var watch := {
		"phase": BeatBounce.Phase.WATCH,
		"sequence": [2, 0, 3],
		"alive": {0: true},
		"step": 0,
		"next_in": 0.9,
		"interval": 0.9,
	}
	assert_eq(brain.think(_play_state("beat_bounce", watch), {}), {}, "no input while watching")


func test_beat_bounce_brain_presses_the_current_step_right_after_a_beat() -> void:
	var brain := BotBrains.brain_for(&"beat_bounce", 0, 1)
	(
		brain
		. think(
			_play_state(
				"beat_bounce",
				{
					"phase": BeatBounce.Phase.WATCH,
					"sequence": [2, 0, 3],
					"alive": {0: true},
					"step": -1,
					"next_in": 0.9,
					"interval": 0.9,
				}
			),
			{}
		)
	)
	# Beat just fired (since_last_beat = interval - next_in = 0.05, inside the
	# HIT_WINDOW): press the flagged step's remembered pad.
	var repeat := {
		"phase": BeatBounce.Phase.REPEAT,
		"sequence": [],
		"alive": {0: true},
		"step": 0,
		"next_in": 0.85,
		"interval": 0.9,
	}
	var intent := brain.think(_play_state("beat_bounce", repeat), {})
	assert_eq(int(intent.get("pad", -1)), 2, "presses remembered[0]")


func test_beat_bounce_brain_presses_early_for_the_next_step() -> void:
	var brain := BotBrains.brain_for(&"beat_bounce", 0, 1)
	(
		brain
		. think(
			_play_state(
				"beat_bounce",
				{
					"phase": BeatBounce.Phase.WATCH,
					"sequence": [2, 0, 3],
					"alive": {0: true},
					"step": -1,
					"next_in": 0.9,
					"interval": 0.9,
				}
			),
			{}
		)
	)
	# Next beat imminent (next_in inside HIT_WINDOW): early-press step+1.
	var repeat := {
		"phase": BeatBounce.Phase.REPEAT,
		"sequence": [],
		"alive": {0: true},
		"step": 0,
		"next_in": 0.05,
		"interval": 0.9,
	}
	var intent := brain.think(_play_state("beat_bounce", repeat), {})
	assert_eq(int(intent.get("pad", -1)), 0, "presses remembered[1] early")


func test_beat_bounce_brain_stays_quiet_mid_window() -> void:
	var brain := BotBrains.brain_for(&"beat_bounce", 0, 1)
	(
		brain
		. think(
			_play_state(
				"beat_bounce",
				{
					"phase": BeatBounce.Phase.WATCH,
					"sequence": [2, 0, 3],
					"alive": {0: true},
					"step": -1,
					"next_in": 0.9,
					"interval": 0.9,
				}
			),
			{}
		)
	)
	var repeat := {
		"phase": BeatBounce.Phase.REPEAT,
		"sequence": [],
		"alive": {0: true},
		"step": 0,
		"next_in": 0.45,
		"interval": 0.9,
	}
	assert_eq(brain.think(_play_state("beat_bounce", repeat), {}), {}, "no window is open")


func test_beat_bounce_brain_eliminated_sends_nothing() -> void:
	var brain := BotBrains.brain_for(&"beat_bounce", 0, 1)
	var game := {
		"phase": BeatBounce.Phase.REPEAT,
		"sequence": [],
		"alive": {0: false},
		"step": 0,
		"next_in": 0.05,
		"interval": 0.9,
	}
	assert_eq(brain.think(_play_state("beat_bounce", game), {}), {})


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


# --- ro_sham_bo ---------------------------------------------------------------


func test_ro_sham_bo_brain_walks_toward_a_pad_when_undecided() -> void:
	var brain := BotBrains.brain_for(&"ro_sham_bo", 0, 1)
	var game := {
		"phase": RoShamBo.Phase.THROW,
		"players": {0: [0.0, 0.0, 1, 0]},
		"sudden_death": false,
		"target_shape": -1,
	}
	var intent := brain.think(_play_state("ro_sham_bo", game), {})
	var heading := Vector2(float(intent.get("mx", 0.0)), float(intent.get("my", 0.0)))
	assert_gt(heading.length(), 0.5, "commits to walking toward some pad")


func test_ro_sham_bo_brain_sudden_death_pick_is_cached_across_ticks() -> void:
	# #715: the sim's own rule is "exactly one" counter-throw wins — a shared
	# correct throw is still a tie. The pick (counter or blind guess) must be
	# decided once and held, not re-rolled every tick (which would jitter the
	# heading and could even flip after committing to walk one way).
	var brain := BotBrains.brain_for(&"ro_sham_bo", 0, 1)
	var game := {
		"phase": RoShamBo.Phase.THROW,
		"players": {0: [0.0, 0.0, 1, 0]},
		"sudden_death": true,
		"target_shape": RoShamBo.Shape.ROCK,
	}
	var first := brain.think(_play_state("ro_sham_bo", game), {})
	var second := brain.think(_play_state("ro_sham_bo", game), {})
	assert_eq(first, second, "the sudden-death pick doesn't change tick to tick")


func test_ro_sham_bo_brain_sudden_death_does_not_always_counter() -> void:
	# The old always-counter policy meant two counter-reading bots threw the
	# identical correct shape every single sudden-death round -- a shared
	# correct throw is still a tie (per the sim), so that was an infinite
	# mirror-tie loop. Across many independent seeds, some must NOT counter.
	var target := RoShamBo.Shape.ROCK
	var saw_non_counter := false
	for seed_value in range(50):
		var brain := BotBrains.brain_for(&"ro_sham_bo", 0, seed_value)
		var game := {
			"phase": RoShamBo.Phase.THROW,
			"players": {0: [0.0, 0.0, 1, 0]},
			"sudden_death": true,
			"target_shape": target,
		}
		var intent := brain.think(_play_state("ro_sham_bo", game), {})
		var counter_pos := RoShamBo.pad_position(RoShamBo.Shape.PAPER)
		var heading := Vector2(float(intent.get("mx", 0.0)), float(intent.get("my", 0.0)))
		if heading.dot(counter_pos.normalized()) <= 0.5:
			saw_non_counter = true
			break
	assert_true(saw_non_counter, "at least one seed must blind-guess instead of countering")


func test_ro_sham_bo_brains_do_not_always_mirror_in_sudden_death() -> void:
	# The regression this fixes: two brains with different seeds facing the
	# same target_shape must not throw the identical counter 100% of the
	# time, or sudden death can never resolve between them.
	var target := RoShamBo.Shape.SCISSORS
	var mirrored := 0
	var trials := 40
	for i in trials:
		var brain_a := BotBrains.brain_for(&"ro_sham_bo", 0, i * 2)
		var brain_b := BotBrains.brain_for(&"ro_sham_bo", 1, i * 2 + 1)
		var game := {
			"phase": RoShamBo.Phase.THROW,
			"players": {0: [0.0, 0.0, 1, 0], 1: [0.0, 0.0, 1, 0]},
			"sudden_death": true,
			"target_shape": target,
		}
		var a := brain_a.think(_play_state("ro_sham_bo", game), {})
		var b := brain_b.think(_play_state("ro_sham_bo", game), {})
		if Vector2(float(a.get("mx", 0.0)), float(a.get("my", 0.0))).is_equal_approx(
			Vector2(float(b.get("mx", 0.0)), float(b.get("my", 0.0)))
		):
			mirrored += 1
	assert_lt(mirrored, trials, "not every trial can mirror, or sudden death never resolves")


func test_ro_sham_bo_brain_holds_still_once_thrown() -> void:
	var brain := BotBrains.brain_for(&"ro_sham_bo", 0, 1)
	var game := {
		"phase": RoShamBo.Phase.THROW,
		"players": {0: [0.0, -6.0, 1, 1]},
		"sudden_death": false,
		"target_shape": -1,
	}
	assert_eq(brain.think(_play_state("ro_sham_bo", game), {}), {})


func test_ro_sham_bo_brain_eliminated_votes_a_living_rival() -> void:
	var brain := BotBrains.brain_for(&"ro_sham_bo", 0, 1)
	var game := {
		"phase": RoShamBo.Phase.THROW,
		"players": {0: [0.0, 0.0, 0, 0], 1: [1.0, 1.0, 1, 0], 2: [2.0, 2.0, 0, 0]},
		"sudden_death": false,
		"target_shape": -1,
	}
	var intent := brain.think(_play_state("ro_sham_bo", game), {})
	assert_eq(int(intent.get("vote", -1)), 1, "the only living rival gets the vote")
