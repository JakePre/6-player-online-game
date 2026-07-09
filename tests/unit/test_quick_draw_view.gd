extends GutTest
## Quick Draw client view (M8-08): renders replicated snapshots in the shared
## iso-arena without simulating anything locally.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/quick_draw/quick_draw_view.tscn")

var view: MinigameView
var _saved_show_names := false


func before_each() -> void:
	_saved_show_names = MinigameView.show_names
	MinigameView.show_names = true  # #580: names off by default; this suite tests the name itself
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func after_each() -> void:
	MinigameView.show_names = _saved_show_names


func test_setup_lines_up_rigs_with_lamp_and_labels() -> void:
	assert_not_null(view.arena.get_node("SignalLamp"))
	assert_not_null(view.get_node("SignalLabel"))
	assert_not_null(view.get_node("RoundLabel"))
	var alice: CharacterRig = view.rig_for_slot(0)
	var bob: CharacterRig = view.rig_for_slot(1)
	assert_almost_eq(alice.position.x, -1.0, 0.001, "two duelists straddle the center")
	assert_almost_eq(bob.position.x, 1.0, 0.001)


## Regression (#780): rigs are pooled hidden (#601); this stationary view
## places them once and never calls update_rig, so a snapshot must reveal the
## round's participants or the duelists never render at all.
func test_render_reveals_the_duelist_rigs() -> void:
	assert_false(view.rig_for_slot(0).visible, "rigs start hidden until a snapshot reveals them")
	view.render({"phase": QuickDraw.Phase.WAITING, "round": 0, "wins": {0: 0, 1: 0}})
	assert_true(view.rig_for_slot(0).visible, "the round's participants become visible")
	assert_true(view.rig_for_slot(1).visible)


func test_waiting_phase_shows_red_wait() -> void:
	view.render({"phase": QuickDraw.Phase.WAITING, "round": 0, "wins": {0: 0, 1: 0}})
	var label: Label = view.get_node("SignalLabel")
	assert_eq(label.text, "WAIT...")
	assert_eq(view._lamp_material.albedo_color, view.WAITING_COLOR)
	assert_string_contains(view.get_node("RoundLabel").text, "Round 1")


func test_live_phase_shows_green_draw() -> void:
	view.render({"phase": QuickDraw.Phase.LIVE, "round": 2, "wins": {0: 1, 1: 1}})
	var label: Label = view.get_node("SignalLabel")
	assert_eq(label.text, "DRAW!")
	assert_eq(view._lamp_material.albedo_color, view.LIVE_COLOR)


## #302 FX: going live pops the screen flash and flares the lamp; the flash
## overlay exists and is transparent at rest.
func test_go_signal_flashes_the_screen_and_flares_the_lamp() -> void:
	var flash: ColorRect = view.get_node("DrawFlash")
	assert_almost_eq(flash.color.a, 0.0, 0.001, "no flash before the draw")
	view.render({"phase": QuickDraw.Phase.WAITING, "round": 0, "wins": {0: 0, 1: 0}})
	view.render({"phase": QuickDraw.Phase.LIVE, "round": 0, "wins": {0: 0, 1: 0}})
	assert_gt(flash.color.a, 0.0, "the go signal flashes the screen")
	view._update_lamp()
	assert_gt(view._lamp_material.emission_energy_multiplier, 1.0, "and the lamp flares bright")


func test_round_over_winner_cheers_and_tallies() -> void:
	view.render(
		{
			"phase": QuickDraw.Phase.ROUND_OVER,
			"round": 1,
			"wins": {0: 2, 1: 0},
			"false_started": {1: true},
			"winner": 0
		}
	)
	assert_eq(view.rig_for_slot(0).current_action(), &"cheer")
	assert_eq(view.rig_for_slot(1).current_action(), &"hit")
	assert_string_contains(view.rig_for_slot(0).display_name, "2")
	assert_string_contains(view.rig_for_slot(1).display_name, "false start")
	assert_string_contains(view.get_node("SignalLabel").text, "Alice wins")


## Signature cues (#728): the go signal fires `laser`, and a duel win fires
## `bell` — never the shared round_win/round_lose, which are chrome's
## per-match-round stingers, not this per-duel sub-round's (the #591 class of
## meaning collision).
func test_go_signal_plays_laser() -> void:
	watch_signals(view)
	view.render({"phase": QuickDraw.Phase.WAITING, "round": 0, "wins": {0: 0, 1: 0}})
	view.render({"phase": QuickDraw.Phase.LIVE, "round": 0, "wins": {0: 0, 1: 0}})
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"laser"], "the go signal")


func test_duel_winner_plays_bell_not_the_shared_round_jingle() -> void:
	watch_signals(view)
	view.render(
		{
			"phase": QuickDraw.Phase.ROUND_OVER,
			"round": 1,
			"wins": {0: 2, 1: 0},
			"false_started": {},
			"winner": 0
		}
	)
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"bell"], "a duel win")
	assert_signal_emit_count(
		view, "sfx_requested", 1, "only the bell cue fires — not also the shared round_win jingle"
	)


func test_next_round_returns_everyone_to_idle() -> void:
	view.render(
		{
			"phase": QuickDraw.Phase.ROUND_OVER,
			"round": 1,
			"wins": {0: 2, 1: 0},
			"false_started": {},
			"winner": 0
		}
	)
	view.render({"phase": QuickDraw.Phase.WAITING, "round": 2, "wins": {0: 2, 1: 0}})
	assert_eq(view.rig_for_slot(0).current_action(), &"idle")
	assert_eq(view.rig_for_slot(1).current_action(), &"idle")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view._phase, QuickDraw.Phase.WAITING)
	assert_eq(view._winner, -1)
	assert_eq(view.get_node("SignalLabel").text, "WAIT...")


## M15-07: a 24-duelist crowd wraps into staggered ranks instead of one
## impossible 46-unit row; small line-ups keep the classic single row.
func test_crowd_wraps_into_ranks() -> void:
	var crowd := {}
	for slot in 24:
		crowd[slot] = "P%d" % (slot + 1)
	var big: MinigameView3D = VIEW_SCENE.instantiate()
	add_child_autofree(big)
	big.setup(crowd, 0)
	var depths := {}
	var widest := 0.0
	for slot in 24:
		var rig: CharacterRig = big.rig_for_slot(slot)
		depths[snappedf(rig.position.z, 0.01)] = true
		widest = maxf(widest, absf(rig.position.x))
	assert_eq(depths.size(), 3, "24 duelists stand in three ranks")
	assert_lte(widest, 8.0 + 0.001, "no rank overflows the front row's width")
	assert_gt(big._arena_half(), 6.0, "the floor/camera grow to fit the wider, deeper formation")
	assert_gte(big._arena_half(), widest, "the scaled arena actually contains the widest rank")


## M15: at the 6-player baseline the arena is unchanged.
func test_arena_half_unchanged_at_baseline() -> void:
	assert_almost_eq(view._arena_half(), 6.0, 0.001)
