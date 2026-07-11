extends GutTest
## Hold-Tab match-log overlay wired into the match chrome (#814): the feed
## accumulates from the events the client already receives, and the hold/release
## input toggles the overlay without pausing the server sim. Companion to
## test_match_screen.gd (kept separate to stay under gdlint's method cap).

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


func _round_results() -> Dictionary:
	return {
		"type": "round_results",
		"round": 1,
		"placements": [[1], [0]],
		"awards": {1: 30, 0: 20},
		"totals": {0: 20, 1: 30},
	}


## The action is registered (Tab / pad Select), so the input map carries it.
func test_match_log_action_is_registered() -> void:
	assert_true(InputMap.has_action(&"match_log"), "the additive input action exists")


## The feed accumulates a line per event — match start, each round intro, each
## round winner — built client-side with no protocol change.
func test_match_log_accumulates_events() -> void:
	NetManager.match_event_received.emit({"type": "match_started"})
	NetManager.match_event_received.emit(_intro_event())
	NetManager.match_event_received.emit(_round_results())
	assert_eq(screen._match_log[0], "▶ Match started")
	assert_string_contains(screen._match_log[1], "Round 1 — Coin Scramble")
	assert_string_contains(screen._match_log[-1], "Bob", "the round winner is logged")


## Match end logs the champion.
func test_match_end_logs_the_winner() -> void:
	NetManager.match_event_received.emit({"type": "match_started"})
	(
		NetManager
		. match_event_received
		. emit(
			{
				"type": "match_ended",
				"standings": [{"slot": 1, "name": "Bob", "score": 5}],
			}
		)
	)
	assert_string_contains(screen._match_log[-1], "Bob wins the match")


## Holding the button overlays the roster + feed; releasing closes it. The
## server sim is never paused (same contract as the pause menu).
func test_hold_match_log_opens_and_releases_closes() -> void:
	NetManager.match_event_received.emit({"type": "match_started"})
	NetManager.match_event_received.emit(_intro_event())
	assert_true(screen._handle_match_log_input(_action(true)), "the press is consumed")
	assert_true(screen._log_overlay.is_open(), "held open")
	assert_gt(screen._log_overlay._feed_list.get_child_count(), 0, "the feed is populated")
	assert_gt(screen._log_overlay._standings_list.get_child_count(), 0, "the roster is populated")
	assert_true(screen._handle_match_log_input(_action(false)), "the release is consumed")
	assert_false(screen._log_overlay.is_open(), "released closes it")


func _action(pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"match_log"
	event.pressed = pressed
	return event
