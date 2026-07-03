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
	assert_eq((list.get_child(0) as Label).text, "1st  Bob  +30")
	assert_eq((list.get_child(1) as Label).text, "2nd  Alice  +20")


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
	assert_eq(panel.get_node("%StandingsSubtitle").text, "Bob wins the match!")
	var list: VBoxContainer = panel.get_node("%StandingsList")
	assert_eq((list.get_child(0) as Label).text, "1st  Bob  50")
	assert_eq((list.get_child(1) as Label).text, "2nd  Alice  40")


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
	assert_eq((feed.get_child(0) as Label).text, "Bob %s" % Emotes.EMOTES[0])
	await wait_seconds(0.4)
	assert_eq(feed.get_child_count(), 0, "toasts expire after emote_lifetime")
