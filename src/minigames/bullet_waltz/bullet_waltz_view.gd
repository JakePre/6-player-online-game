extends MinigameView3D
## Bullet Waltz client view (M10-18): the turret at center, bullets as
## pooled glowing spheres, graze count on nameplates, KO'd rigs hidden.
## Renders the replicated snapshot in the shared iso-arena.

const TURRET_COLOR := Color(0.35, 0.32, 0.4)
const BULLET_COLOR := Color(1.0, 0.45, 0.3)
const BULLET_HEIGHT := 0.6
## Pool size covers the densest late-game pattern overlap.
const BULLET_POOL := 96
## Drawn a touch larger than the sim hitbox (bullet-hell convention: the
## visual should never be smaller than what kills you).
const BULLET_VIEW_RADIUS := 0.32
## Bullet-hell needs a dark stage (#208): the default orange-brick floor sat
## right on the bullets' hue, so a translucent night overlay dims it and the
## emissive bullets glow against it instead of vanishing.
const FLOOR_DIM_COLOR := Color(0.04, 0.05, 0.1, 0.78)
## FX pass (M13-29): bullets stretch into tracer streaks, grazes shimmer, KOs
## blast. Tracer length approximates travel as radially-outward from the turret
## (how the volleys fan out), so no per-bullet history is needed at pool scale.
const TRACER_STRETCH := 2.6
const TRACER_MIN_RADIUS := 0.5
const GRAZE_COLOR := Color(0.55, 0.9, 1.0)

## Latest replicated state, straight from BulletWaltz.get_snapshot().
var players := {}
var bullets: Array = []
var out: Array = []

var _bullet_pool: Array[MeshInstance3D] = []
var _last_grazes := {}  # slot (int) -> graze count already sparked at
var _was_out := {}  # slot (int) -> bool (last-seen KO state, for the KO blast)


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Elegant violet floor for the bullet-hell weave (#589).
func _floor_tint() -> Color:
	return Color(0.9, 0.85, 1.0)


func _arena_half() -> float:
	# Grow the framed floor with the lobby to match the sim's scaled play area
	# (M15, ADR 003 F4); at <=6 players this is the tuned BulletWaltz.ARENA_HALF.
	return MinigameScaling.arena_half(BulletWaltz.ARENA_HALF, names.size())


func _setup_3d() -> void:
	var dim_mesh := PlaneMesh.new()
	dim_mesh.size = Vector2.ONE * _arena_half() * 2.5
	var dim_material := StandardMaterial3D.new()
	dim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dim_material.albedo_color = FLOOR_DIM_COLOR
	dim_mesh.material = dim_material
	var dim := MeshInstance3D.new()
	dim.name = "FloorDim"
	dim.mesh = dim_mesh
	dim.position.y = 0.02
	arena.add_child(dim)

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
	bullet_mesh.radius = BULLET_VIEW_RADIUS
	bullet_mesh.height = BULLET_VIEW_RADIUS * 2.0
	var bullet_material := StandardMaterial3D.new()
	bullet_material.albedo_color = BULLET_COLOR
	bullet_material.emission_enabled = true
	bullet_material.emission = BULLET_COLOR
	bullet_material.emission_energy_multiplier = 1.2
	bullet_mesh.material = bullet_material
	for i in BULLET_POOL:
		var node := MeshInstance3D.new()
		node.mesh = bullet_mesh
		node.visible = false
		arena.add_child(node)
		_bullet_pool.append(node)


## Stretches a bullet into a short tracer streak pointing the way it travels,
## approximated as radially outward from the center turret. Round near the
## muzzle (direction is undefined there); elongates as it flies out.
func _streak_bullet(node: MeshInstance3D, xz: Vector2) -> void:
	if xz.length() < TRACER_MIN_RADIUS:
		node.rotation = Vector3.ZERO
		node.scale = Vector3.ONE
		return
	var outward := to_arena(xz)  # horizontal direction from the origin turret
	node.look_at_from_position(node.position, node.position + outward, Vector3.UP)
	node.scale = Vector3(1.0, 1.0, TRACER_STRETCH)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	bullets = game.get("bullets", [])
	out = game.get("out", [])
	for i in _bullet_pool.size():
		var node := _bullet_pool[i]
		if i < bullets.size():
			var bullet: Array = bullets[i]
			var xz := Vector2(float(bullet[0]), float(bullet[1]))
			node.position = to_arena(xz, BULLET_HEIGHT)
			node.visible = true
			_streak_bullet(node, xz)
		else:
			node.visible = false
	# `out` is ko_order: groups of slots eliminated together, newest group last.
	var out_set := {}
	for group: Array in out:
		for slot in group:
			out_set[int(slot)] = true
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		# KO blast: a burst at the dancer the instant they drop out (rig still
		# holds its last position before we hide it).
		var is_out: bool = out_set.has(slot)
		if is_out and not _was_out.get(slot, false):
			fx_burst(Vector2(rig.position.x, rig.position.z), BULLET_COLOR, 1.0)
			# The shared elimination cue (#728), replacing the local-only
			# generic `error`.
			play_sfx(&"ko")
		_was_out[slot] = is_out
		if not players.has(slot):
			rig.visible = false
			continue
		rig.visible = true
		var state: Array = players[slot]
		update_rig(slot, Vector2(state[0], state[1]))
		var grazes := int(state[2])
		# Graze shimmer: a spark when a bullet skims past for a fresh graze.
		if grazes > int(_last_grazes.get(slot, 0)):
			fx_sparkle(Vector2(rig.position.x, rig.position.z), GRAZE_COLOR, 1.0)
			if slot == my_slot:
				# `pop`'s vocabulary entry names "graze coin" as its example use.
				play_sfx(&"pop")
		_last_grazes[slot] = grazes
		rig.display_name = (
			"%s  ✦%d" % [player_name(slot), grazes] if grazes > 0 else player_name(slot)
		)
