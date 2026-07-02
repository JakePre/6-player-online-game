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
	assert_false(screen.get_node("%InterstitialPanel").visible)
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
	assert_true(screen.get_node("%InterstitialPanel").visible)
	assert_eq(screen.get_node("%InterstitialTitle").text, "Final standings")
	var list: VBoxContainer = screen.get_node("%InterstitialList")
	assert_eq((list.get_child(0) as Label).text, "1st  Bob  50")
	assert_eq((list.get_child(1) as Label).text, "2nd  Alice  40")
