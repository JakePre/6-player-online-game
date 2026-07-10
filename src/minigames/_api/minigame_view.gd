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

## Owner directive: nameplates off by default (#580). A settings-driven flag
## shared by every view, mirroring PlayerPalette.use_colorblind — set once by
## SettingsStore.apply(). player_name() falls back to the number-only badge
## (the same fallback nameless slots already get) whenever it's off; the
## masquerade mutator's hide_nameplates view flag still force-hides regardless.
static var show_names := false

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

## True once this round's team colors have been applied to PlayerPalette (#820).
## Per-view (a fresh view starts false), and teams are fixed for a round, so the
## palette is rebuilt exactly once — from the first snapshot that carries team
## membership — never every snapshot.
var _team_synced := false


func setup(player_names: Dictionary, local_slot: int) -> void:
	names = player_names
	my_slot = local_slot
	_setup()


## Called for every received snapshot with MinigameBase.get_snapshot() output.
func render(game: Dictionary) -> void:
	_sync_team_palette(game)
	_render(game)


## Team-mode rounds recolor every competitor by their team, not their personal
## pick (#820), so allegiance reads at a glance. Applied once per round from the
## first snapshot carrying team membership — `teams` (Color Clash, Fort Siege,
## Basket Brawl, Wall Builders, Cart Push, Snake Chain, Relay Sprint) or Tug of
## War's team_a/team_b. _exit_tree restores personal identity as the round
## leaves the screen. Solo games carry no team key, so this no-ops for them.
func _sync_team_palette(game: Dictionary) -> void:
	if _team_synced:
		return
	var teams := _teams_in(game)
	if teams.is_empty():
		return
	PlayerPalette.set_team_assignments(teams)
	_team_synced = true
	_on_identity_colors_changed()


## The round's team membership as an array-of-member-arrays, normalizing Tug of
## War's team_a/team_b to the same shape the rest of the roster already emits.
static func _teams_in(game: Dictionary) -> Array:
	var teams: Array = game.get("teams", [])
	if teams.is_empty() and game.has("team_a") and game.has("team_b"):
		return [game["team_a"], game["team_b"]]
	return teams


## Restore personal identity when the round's view leaves the screen (#820), so
## the lobby, standings, podium, and any following solo game read personal picks
## again. Fires on both the production unmount (queue_free) and test autofree.
func _exit_tree() -> void:
	if _team_synced:
		PlayerPalette.clear_team_assignments()


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


## The number badge (e.g. "#3") always shows; the player's own name only
## joins it when show_names is on (#580) — the same look a nameless slot
## already gets, just applied uniformly while the setting is off.
func player_name(slot: int) -> String:
	if not show_names:
		return PlayerPalette.label_for_slot(slot)
	return MatchFormat.player_name(names, slot)


# --- Overridables ------------------------------------------------------------


func _setup() -> void:
	pass


func _render(_game: Dictionary) -> void:
	pass


## Called when the identity palette changes under the view's feet (#820: team
## colors switching on). Views that bake player_color into long-lived nodes at
## build time (the 3D tier's character rigs) re-push it here; views that read
## player_color fresh every render need do nothing.
func _on_identity_colors_changed() -> void:
	pass


func _celebrate(_placements: Array) -> void:
	pass
