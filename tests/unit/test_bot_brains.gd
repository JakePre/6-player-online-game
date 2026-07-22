extends GutTest
## Goal-seeking bot brains (M19, #684): the registry picks the right brain per
## minigame id (random fallback for uncovered games), and each archetype brain
## steers correctly given a crafted snapshot — pure think() calls, no scene.

## A synthetic id, not a real minigame — the fan-out (#686) is heading toward
## full roster coverage, so pinning this to a real-but-currently-uncovered id
## goes stale the moment that game gets a brain (it already happened twice:
## heist_night, then fort_siege). A fake id can never be "claimed".
const UNCOVERED_ID := &"__no_such_minigame__"


func _play_state(id: String, game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": id, "game": game}


func test_registry_picks_dedicated_brains_and_falls_back_to_random() -> void:
	assert_true(BotBrains.brain_for(&"coin_scramble", 0, 1) is CoinScrambleBrain)
	assert_true(BotBrains.brain_for(&"gauntlet", 0, 1) is GauntletBrain)
	assert_true(BotBrains.brain_for(UNCOVERED_ID, 0, 1) is RandomBrain, "uncovered id -> random")
	assert_false(BotBrains.has_brain(UNCOVERED_ID))


func test_random_fallback_still_produces_intents() -> void:
	var brain := BotBrains.brain_for(UNCOVERED_ID, 0, 42)
	var intent := brain.think({}, {})
	assert_true(intent.has("mx"), "fallback keeps the pre-M19 random behavior")


func test_brain_id_for_routes_snapshot_to_the_right_brain() -> void:
	# The shared router the server pump and the client playtest bot both use
	# (#705): a round's minigame id, or gauntlet when the snapshot carries none
	# (the finale shop phase).
	assert_eq(BotBrains.brain_id_for({"minigame": "coin_scramble"}), &"coin_scramble")
	assert_eq(BotBrains.brain_id_for({"minigame": "gauntlet"}), &"gauntlet")
	assert_eq(BotBrains.brain_id_for({}), &"gauntlet", "no minigame id -> the finale brain")


func test_playtest_bot_intent_path_yields_a_brain_decision() -> void:
	# The exact chain the playtest bot's _brain_intent() runs: route the snapshot
	# to a brain and think() — a goal-seeking decision, not a random one. A coin
	# dead ahead means a deterministic run toward it, which random never grants.
	var match_state := _play_state(
		"coin_scramble", {"players": {0: [0.0, 0.0, 0]}, "coins": [[5.0, 0.0]]}
	)
	var brain := BotBrains.brain_for(BotBrains.brain_id_for(match_state), 0, 7)
	var intent := brain.think(match_state, {})
	assert_gt(float(intent.mx), 0.0, "brain steers toward the coin at +5, not a random direction")


func test_coin_scramble_brain_runs_at_the_nearest_coin() -> void:
	var brain := BotBrains.brain_for(&"coin_scramble", 0, 1)
	var intent := brain.think(
		_play_state(
			"coin_scramble", {"players": {0: [0.0, 0.0, 0]}, "coins": [[5.0, 0.0], [-1.0, 0.0]]}
		),
		{}
	)
	assert_lt(float(intent.mx), 0.0, "the coin at -1 is nearer than the one at +5")
	assert_almost_eq(float(intent.my), 0.0, 0.01)


func test_king_of_the_hill_brain_uses_held_item_then_seeks_zone() -> void:
	var brain := BotBrains.brain_for(&"king_of_the_hill", 0, 1)
	var holding := brain.think(
		_play_state(
			"king_of_the_hill",
			{"players": {0: [4.0, 0.0, 0]}, "zone": [0.0, 0.0, 2.0], "items": [], "held": {0: 0}}
		),
		{}
	)
	assert_true(holding.get("use", false), "a held item fires immediately")
	var seeking := brain.think(
		_play_state(
			"king_of_the_hill",
			{"players": {0: [4.0, 0.0, 0]}, "zone": [0.0, 0.0, 2.0], "items": [], "held": {}}
		),
		{}
	)
	assert_lt(float(seeking.mx), 0.0, "outside the zone, head toward its center")


func test_thin_ice_brain_leaves_a_breaking_tile_for_intact_ice() -> void:
	var brain := BotBrains.brain_for(&"thin_ice", 0, 1)
	# 3x3 grid, tile_size 2 -> half 3. Bot at center tile (1,1) which is
	# BREAKING; all others INTACT. It must move, and never return "stay".
	var tiles := [0, 0, 0, 0, 2, 0, 0, 0, 0]
	var intent := brain.think(
		_play_state(
			"thin_ice",
			{
				"grid_size": 3,
				"tile_size": 2.0,
				"tiles": tiles,
				"players": {0: [0.0, 0.0]},
				"fallen": []
			}
		),
		{}
	)
	var direction := Vector2(float(intent.get("mx", 0.0)), float(intent.get("my", 0.0)))
	assert_gt(direction.length(), 0.1, "standing on breaking ice demands movement")


func test_meteor_shower_brain_flees_a_telegraph_it_stands_in() -> void:
	var brain := BotBrains.brain_for(&"meteor_shower", 0, 1)
	var intent := brain.think(
		_play_state(
			"meteor_shower",
			{"players": {0: [3.0, 0.0]}, "zone": [0.0, 0.0, 10.0], "meteors": [[3.5, 0.0, 0.4]]}
		),
		{}
	)
	assert_lt(float(intent.mx), 0.0, "flee away from the meteor at +3.5")


func test_hurdle_dash_brain_jumps_hurdles_and_runs_otherwise() -> void:
	var brain := BotBrains.brain_for(&"hurdle_dash", 0, 1)
	var jumping := brain.think(
		_play_state(
			"hurdle_dash",
			{"players": {0: [10.0, 0, 0.0, false]}, "hurdles": [11.0, 30.0], "course_len": 100.0}
		),
		{}
	)
	assert_true(jumping.get("jump", false), "a hurdle 1.0 ahead demands a jump")
	var running := brain.think(
		_play_state(
			"hurdle_dash",
			{"players": {0: [10.0, 0, 0.0, false]}, "hurdles": [30.0], "course_len": 100.0}
		),
		{}
	)
	assert_gt(float(running.mx), 0.5, "clear track: run")
	var done := brain.think(
		_play_state(
			"hurdle_dash",
			{"players": {0: [100.0, 0, 0.0, true]}, "hurdles": [], "course_len": 100.0}
		),
		{}
	)
	assert_true(done.is_empty(), "finished runners send nothing")


func test_tug_of_war_brain_alternates_pull_phases() -> void:
	var brain := BotBrains.brain_for(&"tug_of_war", 0, 1)
	var first := int(brain.think({}, {}).pull)
	var second := int(brain.think({}, {}).pull)
	var third := int(brain.think({}, {}).pull)
	assert_ne(first, second, "phase flips every think — the sim counts changes")
	assert_eq(first, third)


func test_gauntlet_brain_buys_by_priority_then_confirms() -> void:
	var brain := BotBrains.brain_for(&"gauntlet", 0, 1)
	var rich := {
		"state": MatchController.State.FINALE_SHOP,
		"shop": {"players": {0: {"coins": 120, "items": {}, "confirmed": false}}},
	}
	assert_eq(brain.think(rich, {}).shop.item, "extra_life", "120c: the life comes first")
	var mid := {
		"state": MatchController.State.FINALE_SHOP,
		"shop": {"players": {0: {"coins": 60, "items": {}, "confirmed": false}}},
	}
	assert_eq(brain.think(mid, {}).shop.item, "shield", "60c: shield next")
	var broke := {
		"state": MatchController.State.FINALE_SHOP,
		"shop": {"players": {0: {"coins": 20, "items": {}, "confirmed": false}}},
	}
	assert_eq(brain.think(broke, {}).shop.action, "confirm", "nothing affordable: lock in")
	var confirmed := {
		"state": MatchController.State.FINALE_SHOP,
		"shop": {"players": {0: {"coins": 20, "items": {}, "confirmed": true}}},
	}
	assert_true(brain.think(confirmed, {}).is_empty(), "confirmed bots stay quiet")


func test_gauntlet_brain_flees_hazards_without_leaving_the_platform() -> void:
	var brain := BotBrains.brain_for(&"gauntlet", 0, 1)
	var intent := (
		brain
		. think(
			{
				"state": MatchController.State.FINALE_PLAY,
				"minigame": "gauntlet",
				"game":
				{
					"radius": 10.0,
					"players": {0: [2.0, 0.0, 1, 0.0]},
					"hazards": [[2.5, 0.0, 1.5, 0.8]]
				},
			},
			{}
		)
	)
	assert_lt(float(intent.mx), 0.0, "flee inward, away from the hazard at +2.5")
	var eliminated := (
		brain
		. think(
			{
				"state": MatchController.State.FINALE_PLAY,
				"minigame": "gauntlet",
				"game": {"radius": 10.0, "players": {}, "hazards": []},
			},
			{}
		)
	)
	assert_true(eliminated.is_empty(), "eliminated bots send nothing")


## #584 weapons: an armed bot swings when a rival is in reach; an unarmed bot
## walks to the nearest floor axe when no hazard threatens it.
func test_gauntlet_brain_grabs_axes_and_swings_in_range() -> void:
	var brain := BotBrains.brain_for(&"gauntlet", 0, 1)
	var armed := (
		brain
		. think(
			{
				"state": MatchController.State.FINALE_PLAY,
				"minigame": "gauntlet",
				"game":
				{
					"radius": 10.0,
					"players": {0: [0.0, 0.0, 1, 0.0, 3, 0, 0], 1: [1.0, 0.0, 1, 0.0, 0, 0, 0]},
					"hazards": [],
					"weapons": []
				},
			},
			{}
		)
	)
	assert_true(armed.get("swing", false), "rival 1.0 away is inside SWING_RANGE — swing")
	var unarmed := (
		brain
		. think(
			{
				"state": MatchController.State.FINALE_PLAY,
				"minigame": "gauntlet",
				"game":
				{
					"radius": 10.0,
					"players": {0: [0.0, 0.0, 1, 0.0, 0, 0, 0]},
					"hazards": [],
					"weapons": [[3.0, 0.0]]
				},
			},
			{}
		)
	)
	assert_gt(float(unarmed.get("mx", 0.0)), 0.0, "unarmed: head for the axe at +3")


# --- Hidden / rotating-role batch (M19-02, #686) ------------------------------
# (the_mole's brain tests moved to test_bot_brains_the_mole.gd, #958 — this
# file was at gdlint's public-method cap.)


func test_faulty_wiring_brain_saboteur_cuts_the_best_node_off_cooldown() -> void:
	var brain := BotBrains.brain_for(&"faulty_wiring", 0, 1)
	var game := {
		"phase": FaultyWiring.Phase.WORK,
		"players": {0: [5.0, 5.0]},
		"nodes": [[5.0, 5.0, 0.8, 0], [-5.0, -5.0, 0.1, 0]],
	}
	var intent := brain.think(
		_play_state("faulty_wiring", game), {"role": "saboteur", "cut_cd": 0.0}
	)
	assert_true(bool(intent.get("cut", false)), "cuts the highest-value node it stands on")


## #961: the crew wins the instant all four nodes read full, so a completed
## node is the saboteur's juiciest target — re-cutting it denies the win. The
## old brain skipped full nodes, so once the crew topped one it was
## sabotage-immune; the saboteur must now cut a full node it stands on.
func test_faulty_wiring_brain_saboteur_recuts_a_full_node_to_deny_the_win() -> void:
	var brain := BotBrains.brain_for(&"faulty_wiring", 0, 1)
	var game := {
		"phase": FaultyWiring.Phase.WORK,
		"players": {0: [5.0, 5.0]},
		# The node it stands on is full; another is only partway. The fullest
		# (the full one, denying the win) is the pick — not the partial one.
		"nodes": [[5.0, 5.0, 1.0, 0], [-5.0, -5.0, 0.4, 0]],
	}
	var intent := brain.think(
		_play_state("faulty_wiring", game), {"role": "saboteur", "cut_cd": 0.0}
	)
	assert_true(bool(intent.get("cut", false)), "re-cuts the full node to deny the crew's win")


func test_faulty_wiring_brain_saboteur_holds_cut_on_cooldown() -> void:
	var brain := BotBrains.brain_for(&"faulty_wiring", 0, 1)
	var game := {
		"phase": FaultyWiring.Phase.WORK,
		"players": {0: [5.0, 5.0]},
		"nodes": [[5.0, 5.0, 0.8, 0]],
	}
	var intent := brain.think(
		_play_state("faulty_wiring", game), {"role": "saboteur", "cut_cd": 2.0}
	)
	assert_false(intent.has("cut"), "no cut while the private cooldown is live")


func test_faulty_wiring_brain_crew_moves_to_an_unfinished_node() -> void:
	var brain := BotBrains.brain_for(&"faulty_wiring", 0, 1)
	var game := {
		"phase": FaultyWiring.Phase.WORK,
		"players": {0: [0.0, 0.0]},
		"nodes":
		[[-5.0, -5.0, 0.2, 0], [5.0, -5.0, 1.0, 0], [-5.0, 5.0, 1.0, 0], [5.0, 5.0, 1.0, 0]],
	}
	var intent := brain.think(_play_state("faulty_wiring", game), {})
	assert_lt(float(intent.get("mx", 0.0)), 0.0, "heads to node[0] (unfinished, its sl%count pick)")
	assert_false(intent.has("cut"), "crew never cuts")


func test_faulty_wiring_brain_idle_outside_work() -> void:
	var brain := BotBrains.brain_for(&"faulty_wiring", 0, 1)
	var game := {"phase": FaultyWiring.Phase.REVEAL, "players": {0: [0.0, 0.0]}, "nodes": []}
	assert_eq(brain.think(_play_state("faulty_wiring", game), {}), {}, "no input during the reveal")


func test_trap_corridor_brain_trapper_arms_interior_tiles() -> void:
	var brain := BotBrains.brain_for(&"trap_corridor", 0, 1)
	var game := {
		"phase": TrapCorridor.Phase.TRAPPING,
		"trapper": 0,
		"traps_left": 6,
		"players": {},
		"revealed": []
	}
	var intent := brain.think(_play_state("trap_corridor", game), {})
	assert_true(intent.has("trap"), "the trapper arms a tile")
	var col := int((intent.trap as Array)[0])
	assert_between(col, 1, TrapCorridor.COLS - 2, "never the safe start/finish columns")


func test_trap_corridor_brain_trapper_stops_at_budget() -> void:
	var brain := BotBrains.brain_for(&"trap_corridor", 0, 1)
	var game := {
		"phase": TrapCorridor.Phase.TRAPPING,
		"trapper": 0,
		"traps_left": 0,
		"players": {},
		"revealed": []
	}
	assert_eq(
		brain.think(_play_state("trap_corridor", game), {}), {}, "budget spent: nothing to arm"
	)


func test_trap_corridor_brain_runner_pushes_to_the_finish() -> void:
	var brain := BotBrains.brain_for(&"trap_corridor", 0, 1)
	var game := {
		"phase": TrapCorridor.Phase.RUNNING,
		"trapper": 1,
		"players": {0: [2.0, 0.0]},
		"revealed": []
	}
	var intent := brain.think(_play_state("trap_corridor", game), {})
	assert_almost_eq(float(intent.get("mx", 0.0)), 1.0, 0.001, "runs flat out toward the finish")


func test_trap_corridor_brain_runner_steers_to_a_sprung_safe_lane() -> void:
	var brain := BotBrains.brain_for(&"trap_corridor", 0, 1)
	# A revealed (already-sprung, safe) tile at col 3, row 4, two rows above us.
	var safe_tile := 3 * TrapCorridor.ROWS + 4
	var game := {
		"phase": TrapCorridor.Phase.RUNNING,
		"trapper": 1,
		"players": {0: [2.0, 0.0]},
		"revealed": [safe_tile],
	}
	var intent := brain.think(_play_state("trap_corridor", game), {})
	assert_gt(float(intent.get("my", 0.0)), 0.0, "steers toward the known-safe lane ahead")


func test_trap_corridor_brain_idle_when_not_your_turn_to_trap() -> void:
	var brain := BotBrains.brain_for(&"trap_corridor", 0, 1)
	var game := {
		"phase": TrapCorridor.Phase.TRAPPING,
		"trapper": 1,
		"traps_left": 6,
		"players": {},
		"revealed": []
	}
	assert_eq(
		brain.think(_play_state("trap_corridor", game), {}), {}, "non-trappers wait out TRAPPING"
	)


# --- Aim / reaction / racing batch (M19-02, #686) -----------------------------


func test_quick_draw_brain_never_presses_while_waiting() -> void:
	var brain := BotBrains.brain_for(&"quick_draw", 0, 1)
	# WAITING: pressing forfeits — the brain must stay silent no matter how many
	# ticks pass.
	for i in 20:
		var intent := brain.think(_play_state("quick_draw", {"phase": QuickDraw.Phase.WAITING}), {})
		assert_true(intent.is_empty(), "no press during WAITING (tick %d)" % i)


func test_quick_draw_brain_presses_after_its_reaction_delay_once_live() -> void:
	var brain := BotBrains.brain_for(&"quick_draw", 0, 1)
	var pressed := false
	# LIVE: within a handful of ticks (< REACT_MAX / interval) the brain fires.
	for i in 10:
		var intent := brain.think(_play_state("quick_draw", {"phase": QuickDraw.Phase.LIVE}), {})
		if intent.get("press", false):
			pressed = true
			break
	assert_true(pressed, "the brain reacts to LIVE within its delay window")


func test_target_range_brain_aims_at_the_best_target_and_fires_when_ready() -> void:
	var brain := BotBrains.brain_for(&"target_range", 0, 1)
	# Gold (kind 2, value 5) at +3; standard (kind 0) at +1. Crosshair at gold,
	# cooldown clear -> fire at the gold.
	var game := {
		"targets": [[7, 3.0, 0.0, 0.55, 2], [8, 1.0, 0.0, 0.8, 0]],
		"aims": {0: [3.0, 0.0]},
		"scores": {0: 0},
		"cd": {0: 0.0},
	}
	# Seed the last-position map so the lead term is zero (static target here).
	brain.think(_play_state("target_range", game), {})
	var intent := brain.think(_play_state("target_range", game), {})
	assert_almost_eq(float(intent.ax), 3.0, 0.2, "aims at the gold target")
	assert_true(intent.get("fire", false), "crosshair on target + cd clear -> fire")


func test_target_range_brain_holds_fire_on_cooldown() -> void:
	var brain := BotBrains.brain_for(&"target_range", 0, 1)
	var game := {
		"targets": [[7, 3.0, 0.0, 0.55, 2]],
		"aims": {0: [3.0, 0.0]},
		"scores": {0: 0},
		"cd": {0: 0.5},
	}
	var intent := brain.think(_play_state("target_range", game), {})
	assert_false(intent.get("fire", false), "still cooling down -> no fire")


## Putt Panic bots pace their strokes (#961): they line up every tick but only
## strike on a random ready beat, so drive think() until the bot takes its shot.
func _putt_when_ready(brain: BotBrain, game: Dictionary) -> Dictionary:
	var intent := {}
	for _i in 1000:
		intent = brain.think(_play_state("putt_panic", game), {})
		if intent.get("putt", false):
			break
	return intent


func test_putt_panic_brain_aims_at_the_cup_and_putts_at_rest() -> void:
	var brain := BotBrains.brain_for(&"putt_panic", 0, 1)
	# [x, y, strokes, sunk, aim_x, aim_y, at_rest]; me below the cup at (0, 6.5).
	var game := {
		"players": {0: [0.0, -7.0, 0, 0, 0.0, 1.0, 1]},
		"cup": [0.0, 6.5],
		"bar": [0.0, 0.0],
		"shot_clock": 5.0,
	}
	var intent := _putt_when_ready(brain, game)
	# #715: a seeded per-shot wobble (AIM_JITTER_RAD) now perturbs the once-exact
	# aim, so the tolerance covers the worst case instead of pixel-perfect.
	assert_almost_eq(float(intent.ay), 1.0, 0.02, "aims up the green at the cup, plus wobble")
	assert_almost_eq(float(intent.ax), 0.0, 0.11)
	assert_true(intent.get("putt", false), "at rest -> eventually takes the stroke")
	assert_gt(float(intent.power), 0.0, "with real power")


func test_putt_panic_brain_wobbles_aim_and_power_per_seed() -> void:
	# #715 (classified in #759): every bot instance used to compute identical
	# aim+power from the same remaining distance, so a whole lobby's putts
	# converged near-optimally and simultaneously. Two different seeds facing
	# the same shot must now diverge.
	var game := {
		"players": {0: [0.0, -7.0, 0, 0, 0.0, 1.0, 1]},
		"cup": [0.0, 6.5],
		"bar": [0.0, 0.0],
		"shot_clock": 5.0,
	}
	var a := _putt_when_ready(BotBrains.brain_for(&"putt_panic", 0, 1), game)
	var b := _putt_when_ready(BotBrains.brain_for(&"putt_panic", 0, 99), game)
	assert_true(
		(
			not is_equal_approx(float(a.ax), float(b.ax))
			or not is_equal_approx(float(a.power), float(b.power))
		),
		"different seeds facing an identical shot wobble to different aim/power"
	)


func test_putt_panic_brain_does_not_putt_while_rolling() -> void:
	var brain := BotBrains.brain_for(&"putt_panic", 0, 1)
	var game := {
		"players": {0: [0.0, -7.0, 0, 0, 0.0, 1.0, 0]},  # at_rest = 0
		"cup": [0.0, 6.5],
		"bar": [0.0, 0.0],
		"shot_clock": 5.0,
	}
	var intent := brain.think(_play_state("putt_panic", game), {})
	assert_false(intent.get("putt", false), "ball still rolling -> aim only, no stroke")


func test_bullseye_bowl_brain_rolls_when_the_target_will_land_centered() -> void:
	var brain := BotBrains.brain_for(&"bullseye_bowl", 0, 1)
	# Two ticks establish direction; construct offsets so the predicted landing
	# lands near center. Sweep a full oscillation and require at least one roll.
	var rolled := false
	var period := BullseyeBowl.TARGET_PERIOD_SEC
	var amp := BullseyeBowl.TARGET_AMPLITUDE
	var prev := 0.0
	for i in 40:
		var t := i * NetManager.BOT_INPUT_INTERVAL_SEC
		var offset := amp * sin(TAU * t / period)
		var game := {"players": {0: [0, 5, -1.0, offset]}}
		var intent := brain.think(_play_state("bullseye_bowl", game), {})
		if intent.get("roll", false):
			rolled = true
		prev = offset
	assert_true(rolled, "over a full cycle the brain finds a centered-landing roll")


func test_bullseye_bowl_brain_holds_when_mid_flight_or_out_of_balls() -> void:
	var brain := BotBrains.brain_for(&"bullseye_bowl", 0, 1)
	# Seed a direction sample, then a mid-flight snapshot must never roll.
	brain.think(_play_state("bullseye_bowl", {"players": {0: [0, 5, -1.0, 0.0]}}), {})
	var flying := brain.think(_play_state("bullseye_bowl", {"players": {0: [0, 5, 0.4, 0.0]}}), {})
	assert_false(flying.get("roll", false), "no roll while a ball is in flight")
	var spent := brain.think(_play_state("bullseye_bowl", {"players": {0: [0, 0, -1.0, 0.0]}}), {})
	assert_false(spent.get("roll", false), "no roll with no balls left")


func test_turbo_lap_brain_drives_forward_and_steers_along_the_track() -> void:
	var brain := BotBrains.brain_for(&"turbo_lap", 0, 1)
	# At the rightmost point of the ellipse (start line) facing +y (CCW along
	# the track). bits = 0 (racing). Should throttle forward and steer.
	var game := {
		"players": {0: [TurboLap.TRACK_RX, 0.0, PI / 2.0, 0, 0]},
		"shells": [],
		"oils": [],
		"pads": [],
		"standings": [0],
	}
	var intent := brain.think(_play_state("turbo_lap", game), {})
	assert_eq(float(intent.my), -1.0, "full throttle (my = -throttle)")
	assert_between(float(intent.mx), -1.0, 1.0, "steer stays in range")


func test_turbo_lap_brain_uses_a_held_item_and_idles_when_finished() -> void:
	var brain := BotBrains.brain_for(&"turbo_lap", 0, 1)
	var with_item := {
		"players": {0: [TurboLap.TRACK_RX, 0.0, PI / 2.0, TurboLap.ITEM_BOOST, 0]},
		"shells": [],
		"oils": [],
		"pads": [],
		"standings": [0],
	}
	assert_true(
		brain.think(_play_state("turbo_lap", with_item), {}).get("use", false),
		"a held item is fired"
	)
	var finished := {
		"players": {0: [TurboLap.TRACK_RX, 0.0, PI / 2.0, 0, 8]},  # bit 8 = finished
		"shells": [],
		"oils": [],
		"pads": [],
		"standings": [0],
	}
	assert_true(
		brain.think(_play_state("turbo_lap", finished), {}).is_empty(),
		"finished karts send nothing"
	)


func test_rumble_ring_brain_swings_when_ready_then_tracks_on_cooldown() -> void:
	# #715: spamming "attack" every poll used to drop the movement/facing
	# update for the whole cooldown window (rumble_ring.gd's _handle_input is
	# an if/return chain) — a fresh brain still swings on first contact, but
	# the very next poll (mid-cooldown) must track the rival instead of
	# repeating a swing the sim would silently no-op.
	var brain := BotBrains.brain_for(&"rumble_ring", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 3, 0, 0, 0.0, 1.0, 0.0], 1: [1.0, 0.0, 3, 0, 0, 0.0, -1.0, 0.0]},
		"coins": [],
		"events": [],
	}
	var first := brain.think(_play_state("rumble_ring", game), {})
	assert_true(first.get("attack", false), "fresh brain, in range, off cooldown -> swings")
	var second := brain.think(_play_state("rumble_ring", game), {})
	assert_false(second.get("attack", false), "still cooling down -> no repeat swing")
	assert_gt(float(second.get("mx", 0.0)), 0.0, "keeps tracking the rival on cooldown polls")


func test_nom_arena_brain_range_gates_and_cooldown_mirrors_the_lunge() -> void:
	# #715: nom_arena.gd eats on plain proximity contact, so a lunge is only a
	# LUNGE_MASS_COST-costing speed burst — firing from anywhere in
	# REACT_RANGE (6.0) used to pay that cost long before the ~3.74u burst
	# (LUNGE_SPEED * LUNGE_SEC) could possibly connect.
	var in_reach := BotBrains.brain_for(&"nom_arena", 0, 1)
	var near_game := {
		"players": {0: [0.0, 0.0, 10.0, 0], 1: [3.0, 0.0, 5.0, 0]},
		"dots": [],
		"boundary": 12.0,
	}
	var near_intent := in_reach.think(_play_state("nom_arena", near_game), {})
	assert_true(near_intent.get("lunge", false), "prey within the burst's real reach -> lunge")
	assert_gt(float(near_intent.mx), 0.0, "still closes toward the prey")
	# Same instance, same tick's cooldown: an immediate second lunge is denied
	# by the local mirror even though the prey is still in range.
	var repeat_intent := in_reach.think(_play_state("nom_arena", near_game), {})
	assert_false(repeat_intent.get("lunge", false), "local cooldown mirror blocks a repeat lunge")

	var out_of_reach := BotBrains.brain_for(&"nom_arena", 0, 2)
	var far_game := {
		"players": {0: [0.0, 0.0, 10.0, 0], 1: [5.0, 0.0, 5.0, 0]},
		"dots": [],
		"boundary": 12.0,
	}
	var far_intent := out_of_reach.think(_play_state("nom_arena", far_game), {})
	assert_false(far_intent.get("lunge", false), "prey qualifies but is out of the burst's reach")
	assert_gt(float(far_intent.mx), 0.0, "keeps closing the distance instead")


func test_hot_potato_brain_flees_directly_then_slides_along_a_wall() -> void:
	# #715: fleeing used to aim straight away from the carrier with no regard
	# for the arena edge, so a bot already pinned at the boundary (chased by
	# a 10%-faster carrier) could get cornered with no legal escape vector.
	var in_open := BotBrains.brain_for(&"hot_potato", 0, 1)
	var open_game := {
		"players": {0: [0.0, 0.0], 1: [-3.0, 0.0]},
		"carrier": 1,
		"fuse": 5.0,
		"alive": [0, 1],
		"holds": {},
	}
	var open_intent := in_open.think(_play_state("hot_potato", open_game), {})
	assert_almost_eq(float(open_intent.mx), 1.0, 0.01, "flees directly away from the carrier")
	assert_almost_eq(float(open_intent.my), 0.0, 0.01)

	var cornered := BotBrains.brain_for(&"hot_potato", 0, 2)
	var corner_game := {
		"players": {0: [8.5, 0.0], 1: [0.0, 0.0]},  # me pinned on the +x wall
		"carrier": 1,
		"fuse": 5.0,
		"alive": [0, 1],
		"holds": {},
	}
	var corner_intent := cornered.think(_play_state("hot_potato", corner_game), {})
	assert_almost_eq(
		float(corner_intent.get("mx", 0.0)), 0.0, 0.05, "the wall-hugging axis is zeroed"
	)
	assert_gt(
		absf(float(corner_intent.get("my", 0.0))), 0.9, "slides tangentially instead of freezing"
	)
