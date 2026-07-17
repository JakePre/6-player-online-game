class_name RoomManager
extends RefCounted
## Server-side registry of all rooms. Pure logic with explicit timestamps so
## expiry and rejoin behaviour are unit-testable without a running server.
##
## All mutating methods return a result Dictionary:
##   { "result": NetConfig.JoinResult, "room": Room or null, "member": RoomMember or null }

## A lobby seat whose owner dropped (Alt+F4, crash) more than this ago is reaped
## so it doesn't linger forever (#1040). Long enough that a brief-flap reconnect
## still reclaims the seat (the reconnect overlay's early retries land well
## inside it, #176/#1031); short enough that an abandoned name clears promptly.
const LOBBY_GHOST_GRACE_MS := 30_000

var rooms := {}

var _peer_rooms := {}
var _rng := RandomNumberGenerator.new()
var _crypto := Crypto.new()


func _init(rng_seed: int = -1) -> void:
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()


func create_room(peer_id: int, display_name: String, protocol: int) -> Dictionary:
	if protocol != NetConfig.PROTOCOL_VERSION:
		return _failure(NetConfig.JoinResult.VERSION_MISMATCH)
	if _peer_rooms.has(peer_id):
		return _failure(NetConfig.JoinResult.ALREADY_IN_ROOM)
	var room := Room.new()
	room.code = _unique_code()
	rooms[room.code] = room
	return _admit(room, peer_id, display_name)


func join_room(peer_id: int, raw_code: String, display_name: String, protocol: int) -> Dictionary:
	if protocol != NetConfig.PROTOCOL_VERSION:
		return _failure(NetConfig.JoinResult.VERSION_MISMATCH)
	if _peer_rooms.has(peer_id):
		return _failure(NetConfig.JoinResult.ALREADY_IN_ROOM)
	var code := RoomCodes.normalize(raw_code)
	var room: Room = rooms.get(code)
	if room == null:
		return _failure(NetConfig.JoinResult.NOT_FOUND)
	if room.is_full():
		return _failure(NetConfig.JoinResult.FULL)
	return _admit(room, peer_id, display_name)


## Reclaim a reserved slot with the session token issued at join time.
## Restores slot and score; match logic (M3) holds rejoiners out of the
## round in progress.
func rejoin_room(peer_id: int, raw_code: String, token: String, protocol: int) -> Dictionary:
	if protocol != NetConfig.PROTOCOL_VERSION:
		return _failure(NetConfig.JoinResult.VERSION_MISMATCH)
	var code := RoomCodes.normalize(raw_code)
	var room: Room = rooms.get(code)
	if room == null:
		return _failure(NetConfig.JoinResult.NOT_FOUND)
	var member := room.find_by_token(token)
	if member == null:
		return _failure(NetConfig.JoinResult.BAD_TOKEN)
	if member.connected:
		# The old connection is a zombie (e.g. network flap): the token proves
		# identity, so the new peer takes the slot over.
		_peer_rooms.erase(member.peer_id)
	room.mark_reconnected(member, peer_id)
	_peer_rooms[peer_id] = room.code
	return {"result": NetConfig.JoinResult.OK, "room": room, "member": member}


## Explicit leave: the member gives up their slot entirely.
func leave_room(peer_id: int, now_ms: int) -> Room:
	var room := room_of_peer(peer_id)
	if room == null:
		return null
	var member := room.find_by_peer(peer_id)
	if member != null:
		room.remove_member(member)
	_peer_rooms.erase(peer_id)
	_cleanup_room(room, now_ms)
	return room


## Host kick (#1039): removes a specific member by direct reference, unlike
## leave_room which is peer-id-keyed and is a no-op for a disconnected target
## (peer_id resets to 0 and is already gone from _peer_rooms at disconnect
## time — a disconnected member can never be found via room_of_peer/leave_room).
func remove_member(room: Room, member: RoomMember, now_ms: int) -> void:
	if member.connected and member.peer_id != 0:
		_peer_rooms.erase(member.peer_id)
	room.remove_member(member)
	_cleanup_room(room, now_ms)


## Connection dropped. The seat (slot, name, character, score, token) is held
## in every state so rejoin always lands somewhere sensible (#176): back in
## the lobby pre-start, sitting out the round mid-match (SPEC $9). Abandoned
## rooms are reaped by the 5-minute expiry; an explicit leave_room still
## frees the seat immediately.
func handle_disconnect(peer_id: int, now_ms: int) -> Room:
	var room := room_of_peer(peer_id)
	if room == null:
		return null
	var member := room.find_by_peer(peer_id)
	if member != null:
		room.mark_disconnected(member, now_ms)
		# A held lobby seat comes back un-readied; the returning player
		# confirms again rather than the room starting under them.
		member.ready = false
	_peer_rooms.erase(peer_id)
	_cleanup_room(room, now_ms)
	return room


func room_of_peer(peer_id: int) -> Room:
	var code: Variant = _peer_rooms.get(peer_id)
	if code == null:
		return null
	return rooms.get(code)


## Reap ghost lobby seats (#1040): in a room still in the LOBBY, a member who
## disconnected more than LOBBY_GHOST_GRACE_MS ago (and never rejoined) is
## dropped so an Alt+F4/crash name doesn't sit in the list forever. Only LOBBY
## rooms — a mid-match disconnect keeps its seat so the player can rejoin the
## running round (SPEC $9). Returns the rooms that changed so the caller can
## re-broadcast their lobby; a room emptied by the reap is deleted, not returned.
func expire_lobby_ghosts(now_ms: int) -> Array[Room]:
	var changed: Array[Room] = []
	var cutoff := now_ms - LOBBY_GHOST_GRACE_MS
	for code: String in rooms.keys():
		var room: Room = rooms[code]
		if room.state != Room.State.LOBBY:
			continue
		var ghosts: Array[RoomMember] = []
		for member: RoomMember in room.members:
			if not member.connected and member.disconnected_at_ms >= 0:
				if member.disconnected_at_ms <= cutoff:
					ghosts.append(member)
		if ghosts.is_empty():
			continue
		for member: RoomMember in ghosts:
			room.remove_member(member)
		_cleanup_room(room, now_ms)
		if rooms.has(code):
			changed.append(room)
	return changed


## Drop rooms whose last connected member left more than ROOM_EXPIRY_MS ago.
## Returns the removed codes (for logging).
func expire_rooms(now_ms: int) -> Array[String]:
	var removed: Array[String] = []
	for code: String in rooms.keys():
		var room: Room = rooms[code]
		if room.is_expired(now_ms):
			rooms.erase(code)
			removed.append(code)
	return removed


func _admit(room: Room, peer_id: int, display_name: String) -> Dictionary:
	var token := _crypto.generate_random_bytes(16).hex_encode()
	var member := room.add_member(peer_id, _sanitize_name(display_name), token)
	_peer_rooms[peer_id] = room.code
	return {"result": NetConfig.JoinResult.OK, "room": room, "member": member}


func _cleanup_room(room: Room, _now_ms: int) -> void:
	# A room with no members at all can never be rejoined (tokens die with the
	# members), so it is deleted immediately rather than waiting for expiry.
	if room.members.is_empty():
		rooms.erase(room.code)


func _unique_code() -> String:
	var code := RoomCodes.generate(_rng)
	while rooms.has(code):
		code = RoomCodes.generate(_rng)
	return code


func _sanitize_name(raw: String) -> String:
	var name := raw.strip_edges().substr(0, 16)
	return name if not name.is_empty() else "Player"


func _failure(result: int) -> Dictionary:
	return {"result": result, "room": null, "member": null}
