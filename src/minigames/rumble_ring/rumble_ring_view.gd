extends MinigameView3D
## Rumble Ring client view (M10-17): rigs with hit/KO reactions, swing and
## smash flashes from the event stream, scattered coins, and a local
## guard/charge banner. Renders the replicated snapshot in the iso-arena.

const COIN_COLOR := Color(0.96, 0.79, 0.2)
const SMASH_RING_COLOR := Color(1.0, 0.5, 0.2, 0.6)
const GUARD_TINT := Color(0.6, 0.8, 1.0)
const REACTION_HOLD_SEC := 0.6

## Latest replicated state, straight from RumbleRing.get_snapshot().
var players := {}
var coins: Array = []

var _coin_mesh: CylinderMesh
var _coin_nodes: Array[MeshInstance3D] = []
## slot -> msec until which hit/ko reactions own the rig's animation.
var _reaction_hold := {}
var _banner: Label
var _guard_since := -1.0


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	if event.is_action_pressed(&"action_primary"):
		NetManager.send_match_input({"attack": true})
	elif event.is_action_pressed(&"action_secondary"):
		_guard_since = Time.get_ticks_msec() / 1000.0
		NetManager.send_match_input({"guard": true})
	elif event.is_action_released(&"action_secondary"):
		_guard_since = -1.0
		NetManager.send_match_input({"guard": false})


func _arena_half() -> float:
	return RumbleRing.ARENA_HALF


func _setup_3d() -> void:
	_coin_mesh = CylinderMesh.new()
	_coin_mesh.top_radius = 0.3
	_coin_mesh.bottom_radius = 0.3
	_coin_mesh.height = 0.12
	var material := StandardMaterial3D.new()
	material.albedo_color = COIN_COLOR
	material.metallic = 0.6
	_coin_mesh.material = material
	_banner = Label.new()
	_banner.name = "GuardBanner"
	_banner.add_theme_font_size_override(&"font_size", 24)
	_banner.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_banner.position.y -= 48.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_banner)


func _process(_delta: float) -> void:
	if _guard_since < 0.0:
		_banner.text = ""
		return
	var held := Time.get_ticks_msec() / 1000.0 - _guard_since
	if held >= RumbleRing.SMASH_CHARGE_SEC:
		_banner.text = "SMASH CHARGED — release!"
		_banner.modulate = Color(1.0, 0.6, 0.2)
	else:
		_banner.text = "GUARDING (%d%%)" % int(held / RumbleRing.SMASH_CHARGE_SEC * 100.0)
		_banner.modulate = GUARD_TINT


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	coins = game.get("coins", [])
	for event: Dictionary in game.get("events", []):
		_play_event(event)
	_update_players()
	_update_coins()


func _play_event(event: Dictionary) -> void:
	var rig := rig_for_slot(int(event.get("slot", -1)))
	if rig == null:
		return
	match String(event.type):
		"hit":
			rig.play(&"hit")
			_hold_reaction(event.slot)
			play_sfx(&"error")
		"ko":
			rig.play(&"ko")
			_hold_reaction(event.slot)
			play_sfx(&"round_lose")
		"swing":
			rig.play(&"interact")
		"smash":
			play_sfx(&"confirm")


func _hold_reaction(slot: int) -> void:
	_reaction_hold[slot] = Time.get_ticks_msec() + int(REACTION_HOLD_SEC * 1000.0)


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		if Time.get_ticks_msec() < int(_reaction_hold.get(slot, 0)):
			# A hit/ko reaction owns the rig: move it, don't re-animate it.
			rig.position = to_arena(Vector2(state[0], state[1]))
		else:
			update_rig(slot, Vector2(state[0], state[1]))
		var invuln := float(state[5]) > 0.0
		rig.visible = true
		rig.player_color = (
			GUARD_TINT if int(state[4]) == 1 else PlayerPalette.color_for_slot(slot)
		)
		var caption := "%s  ♥%d ⚔%d" % [player_name(slot), int(state[2]), int(state[3])]
		if invuln:
			caption += "  ✨"
		rig.display_name = caption


func _update_coins() -> void:
	for node in _coin_nodes:
		node.queue_free()
	_coin_nodes.clear()
	for coin: Array in coins:
		var node := MeshInstance3D.new()
		node.mesh = _coin_mesh
		node.position = to_arena(Vector2(coin[0], coin[1]), 0.06)
		arena.add_child(node)
		_coin_nodes.append(node)
