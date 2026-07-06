extends GutTest
## #688: practice bots hold peer_id 0, and rpc_id(0) is BROADCAST-TO-ALL in
## Godot — so any per-member send loop that only checks `connected` multiplies
## every event/snapshot to every client and leaks per-recipient private
## payloads (#254). _is_rpc_target is the single guard all four loops use.


func _human(peer_id: int) -> RoomMember:
	var member := RoomMember.new()
	member.peer_id = peer_id
	member.connected = true
	return member


func test_humans_are_rpc_targets() -> void:
	assert_true(NetManager._is_rpc_target(_human(42)))


func test_bots_are_never_rpc_targets() -> void:
	var room := Room.new()
	var bot := room.add_bot()
	assert_not_null(bot, "fixture: fresh lobby accepts a bot")
	assert_true(bot.connected, "bots read as connected members (seat, roster, sim)")
	assert_eq(bot.peer_id, 0, "the transport truth this bug hinged on")
	assert_false(NetManager._is_rpc_target(bot), "rpc_id(0) would broadcast to all — never")


func test_disconnected_members_are_not_rpc_targets() -> void:
	var member := _human(42)
	member.connected = false
	assert_false(NetManager._is_rpc_target(member))


## Belt-and-braces: nothing plausible produces a negative peer id, but the
## guard is transport-truth (> 0), not bot-flag, so it covers that too.
func test_nonpositive_peer_ids_are_never_targets() -> void:
	assert_false(NetManager._is_rpc_target(_human(-1)))


## The guard must live in every per-member send loop — a new broadcast loop
## that forgets it reintroduces the bug. Source-level regression: every
## rpc_id(member/target.peer_id) site sits within a few lines of the guard.
func test_every_per_member_rpc_site_uses_the_guard() -> void:
	var source := FileAccess.get_file_as_string("res://src/net/net_manager.gd")
	var lines := source.split("\n")
	for i in lines.size():
		var line := lines[i]
		if not (line.contains("rpc_id(member.peer_id") or line.contains("rpc_id(target.peer_id")):
			continue
		# Scan back to the enclosing per-member `for` loop head; the guard
		# must appear somewhere between it and the send.
		var guarded := false
		for back in range(i - 1, maxi(0, i - 20), -1):
			if lines[back].contains("_is_rpc_target"):
				guarded = true
				break
			if lines[back].strip_edges().begins_with("for "):
				break
		assert_true(guarded, "unguarded per-member rpc_id at net_manager.gd:%d" % (i + 1))
