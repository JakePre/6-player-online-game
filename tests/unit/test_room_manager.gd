extends GutTest

const PROTO := NetConfig.PROTOCOL_VERSION

var manager: RoomManager


func before_each() -> void:
	manager = RoomManager.new(42)


func _create(peer_id: int = 1, name: String = "Host") -> Dictionary:
	return manager.create_room(peer_id, name, PROTO)


func test_create_room_succeeds() -> void:
	var outcome := _create()
	assert_eq(outcome.result, NetConfig.JoinResult.OK)
	assert_true(RoomCodes.is_valid(outcome.room.code))
	assert_eq(outcome.member.slot, 0)
	assert_eq(outcome.room.host(), outcome.member)
	assert_false(outcome.member.session_token.is_empty())


func test_version_mismatch_rejected() -> void:
	assert_eq(
		manager.create_room(1, "Old", PROTO + 1).result, NetConfig.JoinResult.VERSION_MISMATCH
	)
	var created := _create(1)
	assert_eq(
		manager.join_room(2, created.room.code, "Old", PROTO - 1).result,
		NetConfig.JoinResult.VERSION_MISMATCH
	)


func test_join_by_code_is_normalized() -> void:
	var created := _create()
	var lower: String = created.room.code.to_lower() + " "
	var outcome := manager.join_room(2, lower, "Guest", PROTO)
	assert_eq(outcome.result, NetConfig.JoinResult.OK)
	assert_eq(outcome.member.slot, 1)


func test_join_unknown_code() -> void:
	assert_eq(manager.join_room(2, "ZZZZZZ", "Guest", PROTO).result, NetConfig.JoinResult.NOT_FOUND)


func test_join_full_room() -> void:
	var created := _create()
	# The creator holds slot 0; fill every remaining seat up to the cap.
	for i in range(2, NetConfig.MAX_PLAYERS_PER_ROOM + 1):
		assert_eq(
			manager.join_room(i, created.room.code, "P%d" % i, PROTO).result,
			NetConfig.JoinResult.OK
		)
	var late_peer := NetConfig.MAX_PLAYERS_PER_ROOM + 1
	assert_eq(
		manager.join_room(late_peer, created.room.code, "Late", PROTO).result,
		NetConfig.JoinResult.FULL
	)


func test_cannot_be_in_two_rooms() -> void:
	var created := _create()
	assert_eq(
		manager.join_room(1, created.room.code, "Again", PROTO).result,
		NetConfig.JoinResult.ALREADY_IN_ROOM
	)
	assert_eq(manager.create_room(1, "Again", PROTO).result, NetConfig.JoinResult.ALREADY_IN_ROOM)


func test_leave_deletes_empty_room() -> void:
	var created := _create()
	manager.leave_room(1, 1000)
	assert_false(manager.rooms.has(created.room.code))
	assert_null(manager.room_of_peer(1))


## #176: lobby disconnects hold the seat like mid-match ones, so a pre-start
## rejoin always lands back in the lobby instead of dead-ending on BAD_TOKEN.
func test_lobby_disconnect_holds_the_seat_for_rejoin() -> void:
	var created := _create()
	var joined := manager.join_room(2, created.room.code, "Guest", PROTO)
	joined.member.ready = true
	manager.handle_disconnect(2, 1000)
	assert_eq(created.room.members.size(), 2, "lobby seat is held")
	assert_false(joined.member.connected)
	assert_false(joined.member.ready, "held seats come back un-readied")

	var rejoined := manager.rejoin_room(99, created.room.code, joined.member.session_token, PROTO)
	assert_eq(rejoined.result, NetConfig.JoinResult.OK)
	assert_eq(rejoined.member.slot, joined.member.slot, "same seat, same lobby")
	assert_true(rejoined.member.connected)
	assert_eq(created.room.state, Room.State.LOBBY)


func test_explicit_lobby_leave_still_frees_the_seat() -> void:
	var created := _create()
	manager.join_room(2, created.room.code, "Guest", PROTO)
	manager.leave_room(2, 1000)
	assert_eq(created.room.members.size(), 1, "leaving on purpose gives up the slot")


## #1039: leave_room is peer-id-keyed, so it silently no-ops for a
## disconnected target (peer_id resets to 0 and is already gone from
## _peer_rooms). remove_member must work by direct reference instead.
func test_remove_member_frees_a_disconnected_seat() -> void:
	var created := _create()
	var joined := manager.join_room(2, created.room.code, "Guest", PROTO)
	manager.handle_disconnect(2, 1000)
	assert_eq(created.room.members.size(), 2, "disconnect alone holds the seat")

	manager.remove_member(created.room, joined.member, 2000)
	assert_eq(created.room.members.size(), 1, "host kick frees the seat")


func test_remove_member_also_works_on_a_connected_target() -> void:
	var created := _create()
	var joined := manager.join_room(2, created.room.code, "Guest", PROTO)

	manager.remove_member(created.room, joined.member, 1000)
	assert_eq(created.room.members.size(), 1)
	assert_null(manager.room_of_peer(2), "peer routing table is cleaned up too")


## #1040: a lobby seat whose owner dropped and never came back is reaped after
## the grace window, so an Alt+F4/crash name doesn't linger in the list forever.
func test_lobby_ghost_is_reaped_after_the_grace_window() -> void:
	var created := _create()
	var joined := manager.join_room(2, created.room.code, "Ghost", PROTO)
	manager.handle_disconnect(2, 1000)
	assert_eq(created.room.members.size(), 2, "held right after the drop")

	# Still within grace: kept (a brief-flap reconnect could still reclaim it).
	var within := 1000 + RoomManager.LOBBY_GHOST_GRACE_MS - 1
	assert_eq(manager.expire_lobby_ghosts(within), [], "not yet — still inside the grace")
	assert_eq(created.room.members.size(), 2)

	# Past grace: reaped, and the room is reported changed so its lobby refreshes.
	var past := 1000 + RoomManager.LOBBY_GHOST_GRACE_MS + 1
	assert_eq(manager.expire_lobby_ghosts(past), [created.room] as Array[Room])
	assert_eq(created.room.members.size(), 1, "the ghost seat is gone")
	assert_null(created.room.find_by_slot(joined.member.slot))


## Connected members and bots are never ghosts, whatever the clock says.
func test_ghost_reaper_leaves_connected_members_and_bots_alone() -> void:
	var created := _create()
	manager.join_room(2, created.room.code, "Live", PROTO)
	created.room.add_bot()
	assert_eq(manager.expire_lobby_ghosts(9_999_999), [], "nobody disconnected")
	assert_eq(created.room.members.size(), 3)


## A mid-match disconnect keeps its seat regardless of the grace — rejoin into
## the running round must still work (SPEC $9); only LOBBY seats are reaped.
func test_ghost_reaper_never_touches_a_mid_match_seat() -> void:
	var created := _create()
	manager.join_room(2, created.room.code, "Guest", PROTO)
	created.room.state = Room.State.IN_MATCH
	manager.handle_disconnect(2, 1000)
	assert_eq(manager.expire_lobby_ghosts(1000 + RoomManager.LOBBY_GHOST_GRACE_MS * 10), [])
	assert_eq(created.room.members.size(), 2, "the match seat is held for rejoin")


## The grace really is a grace (#176/#1031): a member who reconnects within it
## keeps their seat and is never reaped afterward — mark_reconnected clears the
## drop stamp, so the reaper no longer sees them as a ghost.
func test_reconnect_within_grace_saves_the_seat_from_the_reaper() -> void:
	var created := _create()
	var joined := manager.join_room(2, created.room.code, "Flappy", PROTO)
	manager.handle_disconnect(2, 1000)
	manager.rejoin_room(88, created.room.code, joined.member.session_token, PROTO)
	assert_eq(manager.expire_lobby_ghosts(1000 + RoomManager.LOBBY_GHOST_GRACE_MS * 10), [])
	assert_eq(created.room.members.size(), 2, "the reconnected member is safe")


func test_match_disconnect_keeps_slot_and_score_for_rejoin() -> void:
	var created := _create()
	var joined := manager.join_room(2, created.room.code, "Guest", PROTO)
	created.room.state = Room.State.IN_MATCH
	joined.member.score = 175
	manager.handle_disconnect(2, 1000)
	assert_eq(created.room.members.size(), 2, "match slot is reserved")
	assert_false(joined.member.connected)

	var rejoined := manager.rejoin_room(99, created.room.code, joined.member.session_token, PROTO)
	assert_eq(rejoined.result, NetConfig.JoinResult.OK)
	assert_eq(rejoined.member.slot, joined.member.slot)
	assert_eq(rejoined.member.score, 175)
	assert_eq(rejoined.member.peer_id, 99)
	assert_true(rejoined.member.connected)


func test_rejoin_with_bad_token() -> void:
	var created := _create()
	created.room.state = Room.State.IN_MATCH
	assert_eq(
		manager.rejoin_room(2, created.room.code, "forged", PROTO).result,
		NetConfig.JoinResult.BAD_TOKEN
	)


func test_rejoin_takes_over_zombie_connection() -> void:
	var created := _create()
	created.room.state = Room.State.IN_MATCH
	# Peer 1's connection flapped; the client reconnects as peer 55 while the
	# server has not yet noticed the old peer is gone.
	var outcome := manager.rejoin_room(55, created.room.code, created.member.session_token, PROTO)
	assert_eq(outcome.result, NetConfig.JoinResult.OK)
	assert_eq(outcome.member.peer_id, 55)
	assert_null(manager.room_of_peer(1))
	assert_eq(manager.room_of_peer(55), created.room)


func test_room_expires_five_minutes_after_last_disconnect() -> void:
	var created := _create()
	manager.join_room(2, created.room.code, "Guest", PROTO)
	created.room.state = Room.State.IN_MATCH
	manager.handle_disconnect(1, 1000)
	manager.handle_disconnect(2, 5000)
	assert_eq(manager.expire_rooms(5000 + NetConfig.ROOM_EXPIRY_MS - 1).size(), 0)
	var removed := manager.expire_rooms(5000 + NetConfig.ROOM_EXPIRY_MS)
	assert_eq(removed, [created.room.code] as Array[String])
	assert_false(manager.rooms.has(created.room.code))


func test_rejoin_resets_expiry() -> void:
	var created := _create()
	created.room.state = Room.State.IN_MATCH
	manager.handle_disconnect(1, 1000)
	manager.rejoin_room(2, created.room.code, created.member.session_token, PROTO)
	assert_eq(manager.expire_rooms(1000 + NetConfig.ROOM_EXPIRY_MS * 10).size(), 0)


func test_generated_codes_are_unique_per_manager() -> void:
	var seen := {}
	for i in 50:
		var outcome := manager.create_room(1000 + i, "P", PROTO)
		assert_false(seen.has(outcome.room.code), "duplicate room code issued")
		seen[outcome.room.code] = true
