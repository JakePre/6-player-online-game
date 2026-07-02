class_name Room
extends RefCounted
## One room: up to 6 members identified by join code. Pure logic (no Node
## dependencies) so it is unit-testable; NetManager handles transport.

enum State {
	LOBBY,
	IN_MATCH,
}

var code := ""
var state := State.LOBBY
var members: Array[RoomMember] = []
## Milliseconds timestamp of the moment the last connected member dropped,
## or -1 while anyone is still connected. Drives the 5-minute expiry.
var empty_since_ms := -1

var _join_counter := 0


func connected_count() -> int:
	var count := 0
	for member in members:
		if member.connected:
			count += 1
	return count


## Disconnected members keep their slot reserved, so a room with 6 members
## is full even if some of them are currently disconnected.
func is_full() -> bool:
	return members.size() >= NetConfig.MAX_PLAYERS_PER_ROOM


## Lobby controls belong to the oldest still-connected member (SPEC $9).
func host() -> RoomMember:
	var best: RoomMember = null
	for member in members:
		if member.connected and (best == null or member.join_order < best.join_order):
			best = member
	return best


func add_member(peer_id: int, display_name: String, token: String) -> RoomMember:
	var member := RoomMember.new()
	member.slot = _lowest_free_slot()
	member.peer_id = peer_id
	member.display_name = display_name
	member.session_token = token
	member.join_order = _join_counter
	_join_counter += 1
	members.append(member)
	empty_since_ms = -1
	return member


func find_by_peer(peer_id: int) -> RoomMember:
	for member in members:
		if member.peer_id == peer_id and member.connected:
			return member
	return null


func find_by_token(token: String) -> RoomMember:
	if token.is_empty():
		return null
	for member in members:
		if member.session_token == token:
			return member
	return null


func remove_member(member: RoomMember) -> void:
	members.erase(member)


func mark_disconnected(member: RoomMember, now_ms: int) -> void:
	member.connected = false
	member.peer_id = 0
	if connected_count() == 0:
		empty_since_ms = now_ms


func mark_reconnected(member: RoomMember, peer_id: int) -> void:
	member.connected = true
	member.peer_id = peer_id
	empty_since_ms = -1


func is_expired(now_ms: int) -> bool:
	if members.is_empty():
		return true
	if empty_since_ms < 0:
		return false
	return now_ms - empty_since_ms >= NetConfig.ROOM_EXPIRY_MS


## Snapshot of everything clients may know about the room. Never include
## session tokens here: they are per-player secrets.
func to_state_dict() -> Dictionary:
	var member_dicts: Array[Dictionary] = []
	for member in members:
		member_dicts.append(member.to_dict())
	var host_member := host()
	return {
		"code": code,
		"state": state,
		"host_slot": host_member.slot if host_member != null else -1,
		"members": member_dicts,
	}


func _lowest_free_slot() -> int:
	var taken := {}
	for member in members:
		taken[member.slot] = true
	for slot in NetConfig.MAX_PLAYERS_PER_ROOM:
		if not taken.has(slot):
			return slot
	return -1
