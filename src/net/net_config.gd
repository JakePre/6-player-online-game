class_name NetConfig
extends RefCounted
## Shared protocol constants. Bump PROTOCOL_VERSION on any breaking RPC change;
## the server rejects mismatched clients at join time (SPEC $9).

enum JoinResult {
	OK,
	NOT_FOUND,
	FULL,
	BAD_TOKEN,
	VERSION_MISMATCH,
	ALREADY_IN_ROOM,
}

const PROTOCOL_VERSION := 11
const DEFAULT_PORT := 7777
## ADR 003 (M15-01): rooms hold up to 24 players. Per-game eligibility still
## comes from each MinigameMeta.max_players — the room cap only bounds the
## lobby; the start gate refuses a match when no game fits the head count.
const MAX_PLAYERS_PER_ROOM := 24
const MIN_PLAYERS_TO_START := 2
# Quick / Standard / Marathon (SPEC $4).
const ROUND_COUNT_OPTIONS: Array[int] = [8, 12, 15]
## Best-of-N series lengths (M11-01): 1 = a plain single match.
const SERIES_LENGTH_OPTIONS: Array[int] = [1, 3, 5]
const DEFAULT_ROUND_COUNT := 12
const SNAPSHOT_HZ := 30
const ROOM_CODE_LENGTH := 6
# Unambiguous alphabet: no 0/O/1/I (SPEC $9).
const ROOM_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ROOM_EXPIRY_MS := 5 * 60 * 1000


static func join_result_name(result: int) -> String:
	return JoinResult.keys()[result]
