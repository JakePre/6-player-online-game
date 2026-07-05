extends GutTest
## Match chrome smoke tests (M3-04): instantiate the scene and drive it with
## the same NetManager signals the live client receives.

const ROOM_STATE := {
	"code": "TEST42",
	"state": Room.State.IN_MATCH,
	"host_slot": 0,
	"round_count": 8,
	"members":
	[
		{"slot": 0, "name": "Alice", "score": 0, "connected": true, "ready": false},
		{"slot": 1, "name": "Bob", "score": 0, "connected": true, "ready": false},
	],
}

var screen: Control


func before_each() -> void:
	NetManager.my_room_state = {}
	screen = (load("res://src/match/match_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	NetManager.room_updated.emit(ROOM_STATE)


func after_all() -> void:
	NetManager.my_room_state = {}


func _intro_event() -> Dictionary:
	return {
		"type": "round_intro",
		"round": 1,
		"rounds": 8,
		"minigame":
		{
			"id": "coin_scramble",
			"name": "Coin Scramble",
			"category": MinigameMeta.Category.FFA,
			"duration_sec": 60.0,
			"rules": "Grab the coins!",
		},
	}


func test_waits_hidden_until_first_event() -> void:
	assert_false(screen.get_node("%IntroCard").visible)
	assert_false(screen.get_node("%ResultsPanel").visible)
	assert_false(screen.get_node("%StandingsPanel").visible)
	assert_true(screen.get_node("%PlayArea").visible)


func test_intro_card_shows_minigame() -> void:
	NetManager.match_event_received.emit(_intro_event())
	assert_true(screen.get_node("%IntroCard").visible)
	assert_false(screen.get_node("%PlayArea").visible)
	assert_eq(screen.get_node("%IntroTitle").text, "Coin Scramble")
	assert_eq(screen.get_node("%IntroCategory").text, "Free-for-all")
	assert_eq(screen.get_node("%IntroRules").text, "Grab the coins!")
	assert_eq(screen.get_node("%RoundLabel").text, "Round 1/8")


## M6-04: the intro card shows the game's control hints; the row hides when a
## (older) server sends no controls key.
func test_intro_card_shows_control_hints_when_present() -> void:
	var event := _intro_event()
	event.minigame["controls"] = "Move — WASD / left stick"
	NetManager.match_event_received.emit(event)
	var controls: Label = screen.get_node("%IntroControls")
	assert_true(controls.visible)
	assert_eq(controls.text, "Move — WASD / left stick")
	NetManager.match_event_received.emit(_intro_event())
	assert_false(controls.visible, "no controls key hides the hint row")


## M9-03: the rolled mutator is announced on the intro card; unmutated rounds
## hide the row.
func test_intro_card_announces_mutator() -> void:
	var event := _intro_event()
	event["mutator"] = {"id": "double", "name": "Double Coins", "blurb": "All awards doubled."}
	NetManager.match_event_received.emit(event)
	var label: Label = screen.get_node("%IntroMutator")
	assert_true(label.visible)
	assert_string_contains(label.text, "Double Coins")
	assert_string_contains(label.text, "All awards doubled.")
	NetManager.match_event_received.emit(_intro_event())
	assert_false(label.visible)


func test_skip_votes_label_updates() -> void:
	NetManager.match_event_received.emit(_intro_event())
	NetManager.match_event_received.emit({"type": "skip_votes", "votes": 1, "needed": 2})
	assert_eq(screen.get_node("%SkipVotesLabel").text, "Skip votes: 1/2")


func test_round_started_swaps_to_play_area() -> void:
	NetManager.match_event_received.emit(_intro_event())
	NetManager.match_event_received.emit({"type": "round_started", "round": 1})
	assert_true(screen.get_node("%PlayArea").visible)
	assert_false(screen.get_node("%IntroCard").visible)


func test_results_render_placement_lines() -> void:
	(
		NetManager
		. match_event_received
		. emit(
			{
				"type": "round_results",
				"round": 1,
				"placements": [[1], [0]],
				"awards": {1: 30, 0: 20},
				"totals": {0: 20, 1: 30},
			}
		)
	)
	assert_true(screen.get_node("%ResultsPanel").visible)
	assert_eq(screen.get_node("%ResultsTitle").text, "Round 1 results")
	var list: VBoxContainer = screen.get_node("%ResultsList")
	assert_eq(list.get_child_count(), 2)
	assert_eq((list.get_child(0) as Label).text, "1st  P2 Bob  +30")
	assert_eq((list.get_child(1) as Label).text, "2nd  P1 Alice  +20")


func test_snapshot_updates_timer_and_recovers_play_state() -> void:
	NetManager.match_event_received.emit(_intro_event())
	(
		NetManager
		. snapshot_received
		. emit(
			{
				"tick": 1,
				"match":
				{"state": MatchController.State.PLAY, "round": 0, "rounds": 8, "time_left": 42.4},
			}
		)
	)
	assert_eq(screen.get_node("%TimerLabel").text, "0:43")
	assert_true(screen.get_node("%PlayArea").visible, "replicated PLAY state overrides intro")


func test_match_ended_shows_final_standings() -> void:
	(
		NetManager
		. match_event_received
		. emit(
			{
				"type": "match_ended",
				"standings":
				[
					{"slot": 1, "name": "Bob", "score": 50},
					{"slot": 0, "name": "Alice", "score": 40}
				],
			}
		)
	)
	var panel: StandingsPanel = screen.get_node("%StandingsPanel")
	assert_true(panel.visible)
	assert_eq(panel.get_node("%StandingsTitle").text, "Final standings")
	assert_eq(panel.get_node("%StandingsSubtitle").text, "P2 Bob wins the match!")
	var list: VBoxContainer = panel.get_node("%StandingsList")
	assert_eq((list.get_child(0) as Label).text, "1st  P2 Bob  50")
	assert_eq((list.get_child(1) as Label).text, "2nd  P1 Alice  40")


func _play_snapshot(game: Dictionary) -> Dictionary:
	return {
		"tick": 2,
		"match":
		{
			"state": MatchController.State.PLAY,
			"round": 0,
			"rounds": 8,
			"time_left": 30.0,
			"minigame": "coin_scramble",
			"game": game,
		},
	}


func _mounted_view() -> MinigameView:
	for child in screen.get_node("%PlayArea").get_children():
		if child is MinigameView and not child.is_queued_for_deletion():
			return child
	return null


func test_round_started_mounts_the_view_and_snapshots_reach_it() -> void:
	NetManager.match_event_received.emit(_intro_event())
	NetManager.match_event_received.emit({"type": "round_started", "round": 1})
	var view := _mounted_view()
	assert_not_null(view, "coin_scramble view must mount on round start")
	assert_false(screen.get_node("%PlayPlaceholder").visible)
	NetManager.snapshot_received.emit(
		_play_snapshot({"players": {0: [1.0, 2.0, 3]}, "coins": [[0.5, -0.5]]})
	)
	assert_eq(view.players[0], [1.0, 2.0, 3])
	assert_eq(view.coins.size(), 1)


func _results_event() -> Dictionary:
	return {
		"type": "round_results",
		"round": 1,
		"placements": [[0], [1]],
		"awards": {0: 30, 1: 20},
		"totals": {0: 30, 1: 20},
	}


## M6-02: the arena stays mounted and visible behind the results panel so the
## winners' celebration plays; it unmounts on the next phase event instead.
func test_round_results_keep_view_visible_for_celebration() -> void:
	NetManager.match_event_received.emit(_intro_event())
	NetManager.match_event_received.emit({"type": "round_started", "round": 1})
	var view := _mounted_view()
	NetManager.match_event_received.emit(_results_event())
	assert_false(view.is_queued_for_deletion())
	assert_not_null(_mounted_view())
	assert_true(screen.get_node("%PlayArea").visible, "arena visible behind results")
	assert_true(screen.get_node("%ResultsPanel").visible)


func test_leaderboard_unmounts_the_view() -> void:
	NetManager.match_event_received.emit(_intro_event())
	NetManager.match_event_received.emit({"type": "round_started", "round": 1})
	var view := _mounted_view()
	NetManager.match_event_received.emit(_results_event())
	NetManager.match_event_received.emit({"type": "leaderboard", "totals": {0: 30, 1: 20}})
	assert_true(view.is_queued_for_deletion())
	assert_null(_mounted_view())


func test_results_fly_coin_chips_toward_totals() -> void:
	NetManager.match_event_received.emit(_results_event())
	var alice_coin: Label = screen.get_node_or_null("CoinFly0")
	var bob_coin: Label = screen.get_node_or_null("CoinFly1")
	assert_not_null(alice_coin)
	assert_not_null(bob_coin)
	assert_eq(alice_coin.text, "+30")
	assert_eq(bob_coin.text, "+20")


func test_mounted_view_shake_jiggles_play_area_and_settles() -> void:
	NetManager.match_event_received.emit(_intro_event())
	NetManager.match_event_received.emit({"type": "round_started", "round": 1})
	var view := _mounted_view()
	var play_area: Control = screen.get_node("%PlayArea")
	var origin := play_area.position
	view.request_shake(10.0)
	assert_not_null(screen._shake_tween, "a shake tween starts on request")
	assert_true(screen._shake_tween.is_running())
	# A second impact mid-shake must not drift the rest position.
	view.request_shake(10.0)
	assert_eq(screen._shake_origin, origin)
	await get_tree().create_timer(0.5).timeout
	assert_almost_eq(play_area.position.x, origin.x, 0.01, "shake settles back")
	assert_almost_eq(play_area.position.y, origin.y, 0.01)


func test_rejoiner_snapshot_mounts_view_without_events() -> void:
	NetManager.snapshot_received.emit(_play_snapshot({"players": {}, "coins": []}))
	assert_not_null(_mounted_view(), "replicated PLAY state alone must mount the view")


func test_emote_bar_has_one_button_per_emote() -> void:
	var bar: HBoxContainer = screen.get_node("%EmoteBar")
	assert_eq(bar.get_child_count(), Emotes.EMOTES.size())
	assert_eq((bar.get_child(5) as Button).text, "GG")


func test_emote_feed_shows_and_expires_toasts() -> void:
	screen.emote_lifetime = 0.1
	NetManager.emote_received.emit(1, 0)
	var feed: VBoxContainer = screen.get_node("%EmoteFeed")
	assert_eq(feed.get_child_count(), 1)
	assert_eq((feed.get_child(0) as Label).text, "P2 Bob %s" % Emotes.EMOTES[0])
	await wait_seconds(0.4)
	assert_eq(feed.get_child_count(), 0, "toasts expire after emote_lifetime")


## #181: the running game's name stays on the HUD bar during play so
## playtesters can take notes without waiting for the next intro card.
func test_game_name_shows_on_hud_from_intro_through_play() -> void:
	NetManager.match_event_received.emit(_intro_event())
	var label: Label = screen.get_node("%GameNameLabel")
	assert_eq(label.text, "Coin Scramble")
	NetManager.match_event_received.emit({"type": "round_started"})
	assert_eq(label.text, "Coin Scramble")
	NetManager.match_event_received.emit({"type": "leaderboard", "totals": {}})
	assert_eq(label.text, "", "cleared once the round view unmounts")


## M15-06: the totals HUD wraps chips instead of overflowing at 24 players.
func test_totals_row_wraps_for_large_lobbies() -> void:
	assert_true(screen._totals_row is HFlowContainer, "totals row uses a wrapping container")


## Coin chips fly to a grid that stays within the screen width at any count.
func test_coin_grid_stays_within_screen_width() -> void:
	var width := 1152.0
	for i in 24:
		var offset: Vector2 = screen._coin_grid_offset(i, 24, width)
		assert_between(offset.x, 0.0, width - float(screen.COIN_GRID_SPACING.x))


## A small lobby's coins stay on one row (no needless wrapping).
func test_coin_grid_single_row_for_small_lobbies() -> void:
	for i in 6:
		assert_almost_eq(float(screen._coin_grid_offset(i, 6, 1152.0).y), 0.0, 0.001)


## Results pack into at most RESULTS_MAX_ROWS rows for large lobbies; small
## lobbies are unchanged (one entry per row).
func test_results_condense_for_large_lobbies() -> void:
	var many: Array[String] = []
	for i in 24:
		many.append("place %d" % i)
	var packed: Array[String] = screen._fit_result_lines(many)
	assert_true(packed.size() <= 12, "24 players pack into <=12 rows, got %d" % packed.size())
	var few: Array[String] = ["1st", "2nd", "3rd"]
	assert_eq(screen._fit_result_lines(few), few, "small lobbies unchanged")


## M16-07: the intro card's key-art slot stays hidden (styled text fallback) when
## no art file has been delivered for the round's minigame.
func test_intro_key_art_hidden_without_art() -> void:
	NetManager.match_event_received.emit(_intro_event())
	var key_art: TextureRect = screen.get_node("%IntroKeyArt")
	assert_false(key_art.visible, "no art on disk -> the text lockup is the fallback")
	assert_null(key_art.texture)


## M16-07 / M12-03: each countdown digit punches in, but reduced motion shows it
## at rest.
func test_countdown_pop_respects_reduced_motion() -> void:
	var saved := ArenaFX.reduced_motion
	ArenaFX.reduced_motion = false
	screen._countdown_label.scale = Vector2.ONE
	screen._pop_countdown()
	assert_gt(screen._countdown_label.scale.x, 1.0, "the digit pops in")
	ArenaFX.reduced_motion = true
	screen._countdown_label.scale = Vector2.ONE
	screen._pop_countdown()
	assert_eq(screen._countdown_label.scale, Vector2.ONE, "reduced motion holds it still")
	ArenaFX.reduced_motion = saved


## M16-07 / M12-03: the between-rounds wipe plays normally, and does nothing at
## all under reduced motion.
func test_transition_wipe_respects_reduced_motion() -> void:
	var saved := ArenaFX.reduced_motion
	var wipe: ColorRect = screen.get_node("%TransitionWipe")
	ArenaFX.reduced_motion = true
	wipe.visible = false
	screen._play_transition_wipe()
	assert_false(wipe.visible, "reduced motion skips the wipe entirely")
	ArenaFX.reduced_motion = false
	screen._play_transition_wipe()
	assert_true(wipe.visible, "the wipe sweeps in normally")
	ArenaFX.reduced_motion = saved


## M16-13 / M12-03: coin chips are pure decoration (totals are correct before
## the flight), so reduced motion spawns no chips at all.
func test_coin_fly_respects_reduced_motion() -> void:
	var saved := ArenaFX.reduced_motion
	ArenaFX.reduced_motion = true
	NetManager.match_event_received.emit(_results_event())
	assert_null(screen.get_node_or_null("CoinFly0"), "reduced motion skips the flight")
	assert_null(screen.get_node_or_null("CoinFly1"))
	ArenaFX.reduced_motion = saved


# --- Finale flow (SPEC $6, #554) ----------------------------------------------


func test_finale_shop_event_shows_shop_panel() -> void:
	NetManager.match_event_received.emit(_intro_event())
	NetManager.match_event_received.emit({"type": "finale_shop", "time": 30.0, "totals": {}})
	var panel: PanelContainer = screen.get_node("%ShopPanel")
	assert_true(panel.visible, "the buy-in shop appears")
	assert_null(_mounted_view(), "no arena behind the shop")


func test_finale_started_mounts_the_gauntlet_view() -> void:
	NetManager.match_event_received.emit({"type": "finale_shop", "time": 30.0, "totals": {}})
	NetManager.match_event_received.emit(
		{"type": "finale_started", "minigame": Gauntlet.make_meta().to_dict()}
	)
	assert_false((screen.get_node("%ShopPanel") as PanelContainer).visible)
	var view := _mounted_view()
	assert_not_null(view, "the finale mounts outside the catalog path")
	assert_eq(screen._game_name_label.text, "The Gauntlet")


func test_finale_shop_snapshot_renders_for_rejoiners() -> void:
	NetManager.my_slot = 0
	(
		NetManager
		. snapshot_received
		. emit(
			{
				"tick": 2,
				"match":
				{
					"state": MatchController.State.FINALE_SHOP,
					"round": 8,
					"rounds": 8,
					"time_left": 12.0,
					"shop":
					{
						"players":
						{
							0: {"coins": 90, "items": {&"shield": 1}, "confirmed": false},
							1: {"coins": 0, "items": {}, "confirmed": true},
						}
					},
				},
			}
		)
	)
	var panel: ShopPanel = screen.get_node("%ShopPanel")
	assert_true(panel.visible, "replicated shop state alone shows the panel")
	assert_eq((panel.get_node("%ShopCoinsLabel") as Label).text, "Your coins: 90")
	assert_eq((panel.get_node("%ShopConfirmedLabel") as Label).text, "1/2 locked in")
	NetManager.my_slot = -1


func test_finale_play_snapshot_mounts_gauntlet_for_rejoiners() -> void:
	(
		NetManager
		. snapshot_received
		. emit(
			{
				"tick": 3,
				"match":
				{
					"state": MatchController.State.FINALE_PLAY,
					"round": 8,
					"rounds": 8,
					"time_left": 90.0,
					"minigame": "gauntlet",
					"game": {"radius": 10.0, "players": {}, "hazards": []},
				},
			}
		)
	)
	assert_not_null(_mounted_view(), "replicated FINALE_PLAY alone mounts the finale view")
