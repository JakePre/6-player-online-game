class_name MinigameView
extends Control
## Client half of the Minigame Contract (plan $4): renders the replicated
## `game` snapshot produced by the matching MinigameBase and forwards local
## input intent. Views never simulate — the server state is the truth and
## the framework (match screen) owns mounting, timers, and results chrome.
##
## Convention: a minigame's view scene lives at
## `src/minigames/<id>/<id>_view.tscn` (see MinigameCatalog.view_scene_path)
## with a root script extending this class.

## Juice hook (M6-02): views raise this on impactful moments (KOs, ring-outs)
## and the match screen shakes the play area. Strength is in pixels.
signal shake_requested(strength: float)

var names := {}
var my_slot := -1


func setup(player_names: Dictionary, local_slot: int) -> void:
	names = player_names
	my_slot = local_slot
	_setup()


## Called for every received snapshot with MinigameBase.get_snapshot() output.
func render(game: Dictionary) -> void:
	_render(game)


## Sends the shared WASD/stick move intent; movement minigames call this from
## _physics_process. Safe when disconnected (drops the send) — the engine
## substitutes OfflineMultiplayerPeer when none is set, and RPCing through it
## just logs errors.
func send_move_intent() -> void:
	var peer := NetManager.multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return
	var dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	NetManager.send_match_input({"mx": dir.x, "my": dir.y})


## Juice hook (M6-02): the match screen calls this on round_results while the
## arena stays visible behind the results panel, so views can run winner
## celebrations. `placements` is MinigameResults order: Array of tie groups
## (Arrays of slots), winners first.
func celebrate(placements: Array) -> void:
	_celebrate(placements)


func request_shake(strength: float = 8.0) -> void:
	shake_requested.emit(strength)


func player_color(slot: int) -> Color:
	return PlayerPalette.color_for_slot(slot)


func player_name(slot: int) -> String:
	return MatchFormat.player_name(names, slot)


# --- Overridables ------------------------------------------------------------


func _setup() -> void:
	pass


func _render(_game: Dictionary) -> void:
	pass


func _celebrate(_placements: Array) -> void:
	pass
