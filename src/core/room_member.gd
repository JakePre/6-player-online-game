class_name RoomMember
extends RefCounted
## One player slot inside a Room. Survives disconnects: the slot, score and
## session token are kept so the player can rejoin mid-match (SPEC $9).

var slot: int = -1
var peer_id: int = 0
var display_name := ""
var session_token := ""
var score := 0
var connected := true
var join_order := 0
## Lobby ready-up flag (M2-02). Only meaningful while the room is in LOBBY;
## cleared when a match starts.
var ready := false


func to_dict() -> Dictionary:
	return {
		"slot": slot,
		"name": display_name,
		"score": score,
		"connected": connected,
		"ready": ready,
	}
