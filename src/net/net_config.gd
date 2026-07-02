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

const PROTOCOL_VERSION := 2
const DEFAULT_PORT := 7777
const MAX_PLAYERS_PER_ROOM := 6
const MIN_PLAYERS_TO_START := 2
# Quick / Standard / Marathon (SPEC $4).
const ROUND_COUNT_OPTIONS: Array[int] = [8, 12, 15]
const DEFAULT_ROUND_COUNT := 12
const SNAPSHOT_HZ := 30
const ROOM_CODE_LENGTH := 6
# Unambiguous alphabet: no 0/O/1/I (SPEC $9).
const ROOM_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ROOM_EXPIRY_MS := 5 * 60 * 1000


static func join_result_name(result: int) -> String:
	return JoinResult.keys()[result]
