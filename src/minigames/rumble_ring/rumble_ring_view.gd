extends MinigameView3D
## Rumble Ring client view (M10-17): rigs with hit/KO reactions, swing and
## smash flashes from the event stream, scattered coins, and a local
## guard/charge banner. Renders the replicated snapshot in the iso-arena.

const COIN_COLOR := Color(0.96, 0.79, 0.2)
const SMASH_RING_COLOR := Color(1.0, 0.5, 0.2, 0.6)
const GUARD_TINT := Color(0.6, 0.8, 1.0)
const REACTION_HOLD_SEC := 0.6
const SWING_ARC_COLOR := Color(1.0, 0.95, 0.7, 0.7)
const SWING_ARC_SEC := 0.18
## The ring itself (#237): the sim clamps to a square, so the boundary is a
## glowing rope box at the clamp edge with corner posts — otherwise the
## knockback edge is invisible.
const ROPE_COLOR := Color(0.95, 0.3, 0.3)
const ROPE_HEIGHT := 0.9
const ROPE_THICKNESS := 0.09
const POST_COLOR := Color(0.85, 0.85, 0.9)

## Latest replicated state, straight from RumbleRing.get_snapshot().
var players := {}
var coins: Array = []

var _coin_mesh: CylinderMesh
var _coin_nodes: Array[MeshInstance3D] = []
## slot -> msec until which hit/ko reactions own the rig's animation.
var _reaction_hold := {}
var _banner: Label
var _guard_since := -1.0
## Short-lived swing arcs, {node: TorusMesh slice} -> expiry msec.
var _swing_arcs := {}


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
	_build_ring()
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


## Ropes on all four sides at the movement clamp, plus corner posts and a
## faint edge line on the floor — where the arena ends must be readable at
## a glance (#237).
func _build_ring() -> void:
	var half := RumbleRing.ARENA_HALF
	var rope_material := StandardMaterial3D.new()
	rope_material.albedo_color = ROPE_COLOR
	rope_material.emission_enabled = true
	rope_material.emission = ROPE_COLOR
	rope_material.emission_energy_multiplier = 0.5
	var post_material := StandardMaterial3D.new()
	post_material.albedo_color = POST_COLOR
	for side in 4:
		var along_x := side % 2 == 0
		var offset := half if side < 2 else -half
		var rope_mesh := BoxMesh.new()
		rope_mesh.size = (
			Vector3(half * 2.0, ROPE_THICKNESS, ROPE_THICKNESS)
			if along_x
			else Vector3(ROPE_THICKNESS, ROPE_THICKNESS, half * 2.0)
		)
		rope_mesh.material = rope_material
		var rope := MeshInstance3D.new()
		rope.name = "Rope%d" % side
		rope.mesh = rope_mesh
		rope.position = (
			Vector3(0.0, ROPE_HEIGHT, offset) if along_x else Vector3(offset, ROPE_HEIGHT, 0.0)
		)
		arena.add_child(rope)
		# Floor edge line under each rope, so the clamp reads even when the
		# camera crops the ropes.
		var line_mesh := BoxMesh.new()
		line_mesh.size = (
			Vector3(half * 2.0, 0.04, 0.18) if along_x else Vector3(0.18, 0.04, half * 2.0)
		)
		line_mesh.material = rope_material
		var line := MeshInstance3D.new()
		line.mesh = line_mesh
		line.position = Vector3(rope.position.x, 0.03, rope.position.z)
		arena.add_child(line)
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.14
	post_mesh.bottom_radius = 0.18
	post_mesh.height = ROPE_HEIGHT + 0.3
	post_mesh.material = post_material
	for corner: Vector2 in [
		Vector2(-half, -half), Vector2(half, -half), Vector2(-half, half), Vector2(half, half)
	]:
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.position = Vector3(corner.x, (ROPE_HEIGHT + 0.3) / 2.0, corner.y)
		arena.add_child(post)


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
	_expire_swing_arcs()
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
			_spawn_swing_arc(int(event.slot))
			if int(event.slot) == my_slot:
				play_sfx(&"click")
		"smash":
			play_sfx(&"confirm")


func _hold_reaction(slot: int) -> void:
	_reaction_hold[slot] = Time.get_ticks_msec() + int(REACTION_HOLD_SEC * 1000.0)


## A visible slash fan in the attacker's facing so reach reads (#257).
func _spawn_swing_arc(slot: int) -> void:
	var state: Array = players.get(slot, [])
	if state.size() < 8:
		return
	var mesh := TorusMesh.new()
	mesh.inner_radius = RumbleRing.SWING_RANGE * 0.55
	mesh.outer_radius = RumbleRing.SWING_RANGE
	mesh.ring_segments = 24
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = SWING_ARC_COLOR
	material.emission_enabled = true
	material.emission = SWING_ARC_COLOR
	material.emission_energy_multiplier = 0.6
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = to_arena(Vector2(float(state[0]), float(state[1])), 0.6)
	node.rotation.y = atan2(float(state[6]), float(state[7]))
	node.scale = Vector3(1.0, 0.15, 1.0)
	arena.add_child(node)
	_swing_arcs[node] = Time.get_ticks_msec() + int(SWING_ARC_SEC * 1000.0)


func _expire_swing_arcs() -> void:
	var now := Time.get_ticks_msec()
	for node: MeshInstance3D in _swing_arcs.keys():
		if now >= int(_swing_arcs[node]):
			node.queue_free()
			_swing_arcs.erase(node)


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
