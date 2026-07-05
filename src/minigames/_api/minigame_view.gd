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

## Fired alongside every play_sfx() call (#486), so tests can verify a
## snapshot transition triggered the expected sound the same way
## shake_requested already lets them verify a shake — watch_signals(view) +
## assert_signal_emitted(view, "sfx_requested"), no AudioManager mocking.
signal sfx_requested(name: StringName)

var names := {}
var my_slot := -1
## The round mutator's view flags (M9-05), assigned by the match screen
## before setup() so _setup() sees them. Ids may arrive as String over the
## wire — check with has_view_flag().
var view_flags: Array = []
## This client's private per-player state (#254), set by the match screen
## from the personal snapshot before each render(). Hidden-role game views
## read it to show the local player their own secret role; it never carries
## another player's secrets.
var private_state: Dictionary = {}


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


## Impacts ask the match screen for a decaying screen shake (M6-02). Suppressed
## under the reduced-motion accessibility toggle (M12-03) — the shared
## ArenaFX flag doubles as the motion-sensitivity switch, so a request simply
## does not emit.
func request_shake(strength: float = 8.0) -> void:
	if ArenaFX.reduced_motion:
		return
	shake_requested.emit(strength)


func has_view_flag(flag: StringName) -> bool:
	for candidate in view_flags:
		if StringName(String(candidate)) == flag:
			return true
	return false


## Per-minigame SFX hook (M6-01): fire a semantic AudioManager sound from
## view code (e.g. on pickup/hit snapshots). Unknown names no-op.
func play_sfx(name: StringName) -> void:
	AudioManager.play_sfx(name)
	sfx_requested.emit(name)


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
