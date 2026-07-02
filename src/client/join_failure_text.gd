class_name JoinFailureText
extends RefCounted
## Human-readable messages for NetConfig.JoinResult codes (SPEC $9), shared by
## the main menu's inline errors, the toast layer, and the reconnect overlay
## (M6-03) so the wording stays consistent everywhere.

const TEXT := {
	NetConfig.JoinResult.NOT_FOUND: "Room not found. Check the code and try again.",
	NetConfig.JoinResult.FULL: "That room is full.",
	NetConfig.JoinResult.BAD_TOKEN: "Rejoin expired. Join with the room code instead.",
	NetConfig.JoinResult.VERSION_MISMATCH: "Your game version does not match the server.",
	NetConfig.JoinResult.ALREADY_IN_ROOM: "You are already in a room.",
}


static func describe(reason: int) -> String:
	return TEXT.get(reason, NetConfig.join_result_name(reason))
