extends MinigameView3D
## Shock Tag client view (M10-03): renders the replicated arena in the shared
## 2.5D iso-arena — players as CharacterRigs with coin counts on nameplates,
## the electrified player marked by a crackling emissive ring underfoot. Tags
## (the zap changing hands) shake the screen.

const RING_COLOR := Color(1.0, 0.9, 0.25, 0.6)
const RING_HEIGHT := 0.05

## Latest replicated state, straight from ShockTag.get_snapshot().
var players := {}
var zapped := -1

var _ring: MeshInstance3D
# -1 = unseeded, so a mid-match rejoin does not shake on its first snapshot.
var _zapped_seen := -1


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _arena_half() -> float:
	return ShockTag.ARENA_HALF


func _setup_3d() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = ShockTag.PLAYER_RADIUS * 1.4
	mesh.outer_radius = ShockTag.PLAYER_RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = RING_COLOR
	material.emission_enabled = true
	material.emission = Color(RING_COLOR, 1.0)
	material.emission_energy_multiplier = 0.8
	mesh.material = material
	_ring = MeshInstance3D.new()
	_ring.name = "ZapRing"
	_ring.mesh = mesh
	_ring.visible = false
	arena.add_child(_ring)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	zapped = int(game.get("zapped", -1))
	_update_players()
	_update_ring()
	if _zapped_seen >= 0 and zapped != _zapped_seen:
		request_shake(9.0)
	_zapped_seen = zapped


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
		var caption := "%s  %d" % [player_name(slot), int(state[2])]
		if slot == zapped:
			caption += "  ZAP!"
		rig.display_name = caption


func _update_ring() -> void:
	var state: Array = players.get(zapped, [])
	_ring.visible = state.size() >= 2
	if _ring.visible:
		_ring.position = to_arena(Vector2(state[0], state[1]), RING_HEIGHT)
