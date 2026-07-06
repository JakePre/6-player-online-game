class_name Room
extends RefCounted
## One room: up to NetConfig.MAX_PLAYERS_PER_ROOM members identified by join
## code. Pure logic (no Node dependencies) so it is unit-testable; NetManager
## handles transport.

enum State {
	LOBBY,
	IN_MATCH,
}

var code := ""
var state := State.LOBBY
var members: Array[RoomMember] = []
## Host-chosen number of rounds: Quick 8, Standard 12 (default), Marathon 15
## (SPEC $4).
var round_count := NetConfig.DEFAULT_ROUND_COUNT
## Host-curated mutator pool (M9-02, PHASE2.md $3): MutatorCatalog ids the
## per-round roll (M9-03) may draw from. Empty = mutators off.
var mutator_pool: Array[StringName] = []
## Host-curated exclusion set (#572): MinigameCatalog ids the playlist builder
## must never draw from for this match. Empty = every registered game eligible.
var excluded_game_ids: Array[StringName] = []
## Best-of-N series (M11-01); length 1 leaves it idle.
var series := SeriesTracker.new()
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


## Disconnected members keep their slot reserved, so a room at the cap is
## full even if some of them are currently disconnected.
func is_full() -> bool:
	return members.size() >= NetConfig.MAX_PLAYERS_PER_ROOM


## Lobby controls belong to the oldest still-connected member (SPEC $9).
## Bots are never eligible — the host is always a real peer (#577).
func host() -> RoomMember:
	var best: RoomMember = null
	for member in members:
		if member.is_bot or not member.connected:
			continue
		if best == null or member.join_order < best.join_order:
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


## Server-owned practice bot (#577): a real slot with no peer, auto-ready so
## it never blocks can_start(), named for its slot. Returns null if the room
## is full or not in the lobby. Host-gated at the net layer, not here.
func add_bot() -> RoomMember:
	if is_full() or state != State.LOBBY:
		return null
	var member := RoomMember.new()
	member.slot = _lowest_free_slot()
	member.peer_id = 0
	member.is_bot = true
	member.ready = true
	member.display_name = "Bot %d" % (member.slot + 1)
	member.join_order = _join_counter
	_join_counter += 1
	members.append(member)
	empty_since_ms = -1
	return member


## Removes the most-recently-added bot (the natural "remove a bot" action).
## Returns the removed member, or null if there are no bots. Lobby-only.
func remove_last_bot() -> RoomMember:
	if state != State.LOBBY:
		return null
	for i in range(members.size() - 1, -1, -1):
		if members[i].is_bot:
			var member := members[i]
			members.remove_at(i)
			return member
	return null


func bot_count() -> int:
	var count := 0
	for member in members:
		if member.is_bot:
			count += 1
	return count


func find_by_peer(peer_id: int) -> RoomMember:
	for member in members:
		if member.peer_id == peer_id and member.connected:
			return member
	return null


func find_by_slot(slot: int) -> RoomMember:
	for member in members:
		if member.slot == slot:
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
	# Slots get reused; series points must not transfer to whoever takes
	# this slot next (M11-03).
	series.drop_slot(member.slot)


func mark_disconnected(member: RoomMember, now_ms: int) -> void:
	member.connected = false
	member.peer_id = 0
	if connected_count() == 0:
		empty_since_ms = now_ms


func mark_reconnected(member: RoomMember, peer_id: int) -> void:
	member.connected = true
	member.peer_id = peer_id
	empty_since_ms = -1


## Only lobby settings changes are legal, and only to one of the preset
## values (SPEC $4).
func set_round_count(count: int) -> bool:
	if state != State.LOBBY or not NetConfig.ROUND_COUNT_OPTIONS.has(count):
		return false
	round_count = count
	return true


## Lobby-only, host-validated by the caller; changing the length restarts
## the series from zero (M11-01).
func set_series_length(new_length: int) -> bool:
	if state != State.LOBBY or not NetConfig.SERIES_LENGTH_OPTIONS.has(new_length):
		return false
	series.reset(new_length)
	return true


## Lobby-only, like round count; unknown and duplicate ids are dropped rather
## than rejected so a stale client toggle set cannot wedge the pool.
func set_mutator_pool(pool: Array) -> bool:
	if state != State.LOBBY:
		return false
	var cleaned: Array[StringName] = []
	for id in pool:
		var sid := StringName(String(id))
		if MutatorCatalog.is_registered(sid) and sid not in cleaned:
			cleaned.append(sid)
	mutator_pool = cleaned
	return true


## Lobby-only, like the mutator pool; unknown and duplicate ids are dropped
## rather than rejected so a stale client toggle set cannot wedge the set.
## Unlike the mutator pool, an exclusion set can starve the playlist builder
## entirely, so it is also rejected outright (returning false, leaving the
## previous set untouched) if it would leave zero games eligible at the
## room's current connected player count — MinigameCatalog.build_playlist's
## assert(not eligible.is_empty()) must never be allowed to fire.
func set_excluded_game_ids(ids: Array) -> bool:
	if state != State.LOBBY:
		return false
	var cleaned: Array[StringName] = []
	for id in ids:
		var sid := StringName(String(id))
		if MinigameCatalog.is_registered(sid) and sid not in cleaned:
			cleaned.append(sid)
	if MinigameCatalog.eligible_ids(connected_count(), cleaned).is_empty():
		return false
	excluded_game_ids = cleaned
	return true


## Start gating (M2-02): a match needs at least 2 players and every connected
## member ready. The caller checks that the requester is the host.
func can_start() -> bool:
	if state != State.LOBBY or connected_count() < NetConfig.MIN_PLAYERS_TO_START:
		return false
	for member in members:
		if member.connected and not member.ready:
			return false
	return true


## Flip to IN_MATCH and consume the ready flags so a later return to the
## lobby starts from a clean slate.
func start_match() -> bool:
	if not can_start():
		return false
	state = State.IN_MATCH
	for member in members:
		member.ready = false
	# A finished series restarts fresh at the same length (M11-01).
	if series.is_complete():
		series.reset()
	return true


## Debug-only bypass of can_start()'s player-count/ready gate, for solo dev
## iteration (see net_manager.gd's --debug-rpcs guard, the only caller). Still
## refuses to double-start a room already IN_MATCH.
func force_start_match() -> bool:
	if state != State.LOBBY:
		return false
	state = State.IN_MATCH
	for member in members:
		member.ready = false
	return true


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
		"round_count": round_count,
		"mutator_pool": mutator_pool.duplicate(),
		"excluded_game_ids": excluded_game_ids.duplicate(),
		"series": series.to_dict(),
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
