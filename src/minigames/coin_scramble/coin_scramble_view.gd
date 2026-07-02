extends MinigameView3D
## Coin Scramble client view (M8-03): renders the replicated arena in the
## shared 2.5D iso-arena (M8-01, MinigameView3D) — players as CharacterRig
## instances (position/facing/walk-idle driven by the snapshot, coin count on
## the nameplate), coins as small gold cylinders. Presentation-tier swap only:
## state storage and the render contract are unchanged from the 2D pass
## (M3-06).

const COIN_COLOR := Color(0.96, 0.79, 0.2)
const COIN_RADIUS := 0.3
const COIN_HEIGHT := 0.12

## Latest replicated state, straight from CoinScramble.get_snapshot().
var players := {}
var coins: Array = []

var _coin_mesh: CylinderMesh
var _coin_nodes: Array[MeshInstance3D] = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


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
		node.position = to_arena(Vector2(coin[0], coin[1]), COIN_HEIGHT / 2.0)
		arena.add_child(node)
		_coin_nodes.append(node)
