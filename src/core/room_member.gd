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
## Server-owned practice bot (#577), not backed by a real peer. Auto-ready,
## counts for caps/scoreboards like any member, and the server synthesizes
## its match inputs. Never eligible to be host.
var is_bot := false
## Lobby ready-up flag (M2-02). Only meaningful while the room is in LOBBY;
## cleared when a match starts.
var ready := false
## Selected roster character (M2-03, SPEC $8). Persists across rounds and
## rejoin, unlike `ready`; duplicate picks across members are allowed.
var character_id: StringName = CharacterRoster.DEFAULT_ID
## Chosen player color as a palette index (#581), or -1 for the slot default.
## Unlike character, colors are server-validated unique within the room.
## Persists across rounds and rejoin like character_id.
var color_index: int = -1


func to_dict() -> Dictionary:
	return {
		"slot": slot,
		"name": display_name,
		"score": score,
		"connected": connected,
		"ready": ready,
		"character_id": character_id,
		"color_index": color_index,
		"is_bot": is_bot,
	}
