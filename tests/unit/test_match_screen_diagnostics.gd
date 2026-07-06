extends GutTest
## Match chrome diagnostics wiring (M18-07, #632): view mount/unmount are part
## of the client diagnostics catalog. Split from test_match_screen.gd to keep
## that file under gdlint's public-method cap (same precedent as
## test_net_manager_emote_rate_limit.gd living apart from the main net tests).

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


func after_each() -> void:
	NetManager.my_room_state = {}
	DiagnosticsLog._close()
	var dir := DirAccess.open(DiagnosticsLog.LOG_DIR)
	if dir != null:
		for name in dir.get_files():
			dir.remove(name)


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


func test_view_mount_and_unmount_are_logged() -> void:
	DiagnosticsLog.configure("test", DiagnosticsLog.Level.INFO, "matchscreendiag")
	NetManager.match_event_received.emit(_intro_event())
	NetManager.match_event_received.emit({"type": "round_started", "round": 1})
	DiagnosticsLog.flush()
	var mounts := _log_events("view_mount")
	assert_eq(mounts.size(), 1)
	assert_eq(String(mounts[0].game), "coin_scramble")
	NetManager.match_event_received.emit({"type": "leaderboard", "totals": {}})
	DiagnosticsLog.flush()
	var unmounts := _log_events("view_unmount")
	assert_eq(unmounts.size(), 1)
	assert_eq(String(unmounts[0].game), "coin_scramble")


func _log_events(ev: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(DiagnosticsLog.current_path(), FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line.is_empty():
			continue
		var obj: Dictionary = JSON.parse_string(line)
		if String(obj.get("ev", "")) == ev:
			out.append(obj)
	return out
