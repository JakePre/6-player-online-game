extends MinigameView3D
## Bullet Waltz client view (M10-18): the turret at center, bullets as
## pooled glowing spheres, graze count on nameplates, KO'd rigs hidden.
## Renders the replicated snapshot in the shared iso-arena.

const TURRET_COLOR := Color(0.35, 0.32, 0.4)
const BULLET_COLOR := Color(1.0, 0.45, 0.3)
const BULLET_HEIGHT := 0.6
## Pool size covers the densest late-game pattern overlap.
const BULLET_POOL := 96

## Latest replicated state, straight from BulletWaltz.get_snapshot().
var players := {}
var bullets: Array = []
var out: Array = []

var _bullet_pool: Array[MeshInstance3D] = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _arena_half() -> float:
	return BulletWaltz.ARENA_HALF


func _setup_3d() -> void:
	var turret_mesh := CylinderMesh.new()
	turret_mesh.top_radius = 0.5
	turret_mesh.bottom_radius = 0.7
	turret_mesh.height = 1.2
	var turret_material := StandardMaterial3D.new()
	turret_material.albedo_color = TURRET_COLOR
	turret_mesh.material = turret_material
	var turret := MeshInstance3D.new()
	turret.name = "Turret"
	turret.mesh = turret_mesh
	turret.position = Vector3(0.0, 0.6, 0.0)
	arena.add_child(turret)

	var bullet_mesh := SphereMesh.new()
	bullet_mesh.radius = BulletWaltz.BULLET_RADIUS
	bullet_mesh.height = BulletWaltz.BULLET_RADIUS * 2.0
	var bullet_material := StandardMaterial3D.new()
	bullet_material.albedo_color = BULLET_COLOR
	bullet_material.emission_enabled = true
	bullet_material.emission = BULLET_COLOR
	bullet_material.emission_energy_multiplier = 0.8
	bullet_mesh.material = bullet_material
	for i in BULLET_POOL:
		var node := MeshInstance3D.new()
		node.mesh = bullet_mesh
		node.visible = false
		arena.add_child(node)
		_bullet_pool.append(node)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	bullets = game.get("bullets", [])
	out = game.get("out", [])
	for i in _bullet_pool.size():
		var node := _bullet_pool[i]
		if i < bullets.size():
			var bullet: Array = bullets[i]
			node.position = to_arena(Vector2(float(bullet[0]), float(bullet[1])), BULLET_HEIGHT)
			node.visible = true
		else:
			node.visible = false
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		if not players.has(slot):
			rig.visible = false
			continue
		rig.visible = true
		var state: Array = players[slot]
		update_rig(slot, Vector2(state[0], state[1]))
		var grazes := int(state[2])
		rig.display_name = (
			"%s  ✦%d" % [player_name(slot), grazes] if grazes > 0 else player_name(slot)
		)
