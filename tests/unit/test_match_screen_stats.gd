extends GutTest
## Local stats recording (M20-03, #712): match_screen folds round_results and
## match_ended events into StatsStore, client-side only. Split from
## test_match_screen.gd to stay under gdlint's public-method cap (same
## precedent as test_match_screen_diagnostics.gd).

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
	NetManager.my_slot = 0
	screen = (load("res://src/match/match_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	NetManager.room_updated.emit(ROOM_STATE)


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(StatsStore.PATH))


func after_all() -> void:
	NetManager.my_room_state = {}


func _intro_event(id: String) -> Dictionary:
	return {
		"type": "round_intro",
		"round": 1,
		"rounds": 8,
		"minigame":
		{
			"id": id,
			"name": id.capitalize(),
			"category": MinigameMeta.Category.FFA,
			"duration_sec": 60.0,
			"rules": "Play!",
		},
	}


func _results_event(placements: Array) -> Dictionary:
	return {
		"type": "round_results",
		"round": 1,
		"placements": placements,
		"awards": {0: 30, 1: 20},
		"totals": {0: 30, 1: 20},
	}


func test_round_results_records_my_placement_into_round_history() -> void:
	NetManager.match_event_received.emit(_intro_event("coin_scramble"))
	NetManager.match_event_received.emit({"type": "round_started", "round": 1})
	NetManager.match_event_received.emit(_results_event([[0], [1]]))
	assert_eq(screen._round_history, [{"game_id": "coin_scramble", "placement": 1}])


func test_round_results_skips_history_when_my_slot_is_not_in_any_group() -> void:
	NetManager.match_event_received.emit(_intro_event("coin_scramble"))
	NetManager.match_event_received.emit({"type": "round_started", "round": 1})
	NetManager.match_event_received.emit(_results_event([[1]]))
	assert_eq(screen._round_history, [], "slot 0 never appears in the placements")


func test_match_ended_saves_stats_with_the_final_placement() -> void:
	NetManager.match_event_received.emit(_intro_event("coin_scramble"))
	NetManager.match_event_received.emit({"type": "round_started", "round": 1})
	NetManager.match_event_received.emit(_results_event([[0], [1]]))
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
	var stats := StatsStore.load_stats()
	assert_eq(stats.matches, 1)
	assert_eq(stats.wins, 0, "Alice (slot 0) placed 2nd this match")
	assert_eq(stats.podiums, 1)
	assert_eq(stats.recent[0].placement, 2)
	assert_eq(stats.recent[0].standout_game, "coin_scramble", "the only round we won")
	assert_eq(stats.recent[0].standout_placement, 1)


func test_match_ended_skips_recording_when_my_slot_is_not_in_standings() -> void:
	NetManager.match_event_received.emit(
		{"type": "match_ended", "standings": [{"slot": 1, "name": "Bob", "score": 50}]}
	)
	assert_eq(StatsStore.load_stats(), StatsStore.DEFAULTS, "slot 0 never appears in standings")
