extends MinigameView3D
## Coin Scramble client view (M8-03): renders the replicated arena in the
## shared 2.5D iso-arena (M8-01, MinigameView3D) — players as CharacterRig
## instances (position/facing/walk-idle driven by the snapshot, coin count on
## the nameplate), coins as upright glowing gold discs that spin and bob so
## they read at camera distance (#209). Presentation-tier swap only: state
## storage and the render contract are unchanged from the 2D pass (M3-06).

const COIN_COLOR := Color(1.0, 0.84, 0.25)
const COIN_RADIUS := 0.38
const COIN_HEIGHT := 0.1
const COIN_HOVER := 0.45
const COIN_SPIN_HZ := 0.8
const COIN_BOB := 0.08

## Latest replicated state, straight from CoinScramble.get_snapshot().
var players := {}
var coins: Array = []

var _coin_mesh: CylinderMesh
var _coin_nodes: Array[MeshInstance3D] = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Spin and bob the coins; phase comes from wall time so the per-snapshot
## node rebuild in _update_coins never resets the motion.
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var spin := now * TAU * COIN_SPIN_HZ
	for i in _coin_nodes.size():
		var node := _coin_nodes[i]
		node.rotation = Vector3(PI / 2.0, spin + i, 0.0)
		node.position.y = COIN_HOVER + sin(now * 2.0 + i) * COIN_BOB


func _arena_half() -> float:
	return CoinScramble.ARENA_HALF


func _setup_3d() -> void:
	_coin_mesh = CylinderMesh.new()
	_coin_mesh.top_radius = COIN_RADIUS
	_coin_mesh.bottom_radius = COIN_RADIUS
	_coin_mesh.height = COIN_HEIGHT
	var material := StandardMaterial3D.new()
	material.albedo_color = COIN_COLOR
	material.metallic = 0.6
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = COIN_COLOR
	material.emission_energy_multiplier = 0.9
	_coin_mesh.material = material


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	coins = game.get("coins", [])
	_update_players()
	_update_coins()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
		rig.display_name = "%s  %d" % [player_name(slot), int(state[2])]


func _update_coins() -> void:
	for node in _coin_nodes:
		node.queue_free()
	_coin_nodes.clear()
	for coin: Array in coins:
		var node := MeshInstance3D.new()
		node.mesh = _coin_mesh
		node.position = to_arena(Vector2(coin[0], coin[1]), COIN_HOVER)
		node.rotation.x = PI / 2.0
		arena.add_child(node)
		_coin_nodes.append(node)
