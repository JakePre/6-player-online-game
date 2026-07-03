extends MinigameView3D
## Hot Potato client view (M8-05): renders the replicated arena in the shared
## 2.5D iso-arena (M8-01, MinigameView3D) — players as CharacterRig instances,
## the carrier marked by an orange bomb hovering overhead with the fuse
## countdown on their nameplate, eliminated players collapsed (ko) and dimmed
## gray. Presentation-tier swap only: state storage and the render contract
## are unchanged from the 2D pass (M4-02).

const ELIMINATED_COLOR := Color(0.42, 0.42, 0.46)
const BOMB_COLOR := Color(0.95, 0.55, 0.15)
const BOMB_RADIUS := 0.28
const BOMB_HEIGHT := 2.3

## Latest replicated state, straight from HotPotato.get_snapshot().
var players := {}
var carrier := -1
var fuse := 0.0
var alive: Array = []

var _bomb_node: MeshInstance3D
var _downed := {}  # slot (int) -> true, once the ko pose + dim have been applied
# -1 = unseeded, so a mid-match rejoin does not shake on its first snapshot.
var _alive_seen := -1


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _arena_half() -> float:
	return HotPotato.ARENA_HALF


func _setup_3d() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = BOMB_RADIUS
	mesh.height = BOMB_RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = BOMB_COLOR
	material.emission_enabled = true
	material.emission = BOMB_COLOR
	material.emission_energy_multiplier = 0.5
	mesh.material = material
	_bomb_node = MeshInstance3D.new()
	_bomb_node.name = "Bomb"
	_bomb_node.mesh = mesh
	_bomb_node.visible = false
	arena.add_child(_bomb_node)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	carrier = int(game.get("carrier", -1))
	fuse = float(game.get("fuse", 0.0))
	alive = game.get("alive", [])
	_update_players()
	_update_bomb()
	# The bomb going off is the game's big impact (M6-02).
	if _alive_seen >= 0 and alive.size() < _alive_seen:
		request_shake(12.0)
	_alive_seen = alive.size()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		if slot in alive:
			update_rig(slot, Vector2(state[0], state[1]))
			var caption := player_name(slot)
			if slot == carrier:
				caption += "  %.1f" % fuse
			rig.display_name = caption
		else:
			_down_rig(slot, rig, Vector2(state[0], state[1]))


## Eliminated players hold their last spot in the ko pose, dimmed gray; skip
## update_rig so its walk/idle logic never overrides the pose.
func _down_rig(slot: int, rig: CharacterRig, world_pos: Vector2) -> void:
	rig.position = to_arena(world_pos)
	if _downed.has(slot):
		return
	_downed[slot] = true
	rig.play(&"ko")
	rig.player_color = ELIMINATED_COLOR
	rig.display_name = player_name(slot)


func _update_bomb() -> void:
	var carrier_state: Array = players.get(carrier, [])
	_bomb_node.visible = carrier in alive and carrier_state.size() >= 2
	if not _bomb_node.visible:
		return
	_bomb_node.position = to_arena(Vector2(carrier_state[0], carrier_state[1]), BOMB_HEIGHT)
