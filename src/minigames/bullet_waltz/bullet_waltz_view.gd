extends MinigameView3D
## Bullet Waltz client view (M10-18): the turret at center, bullets as
## pooled glowing spheres, graze count on nameplates, KO'd rigs hidden.
## Renders the replicated snapshot in the shared iso-arena.

## Waltz Bomb (#959): action_primary spends the once-per-round panic clear. The
## sim reads {bomb = true}; the base's declarative input plumbing (#947) sends it.
const INPUT_ACTIONS := {&"action_primary": "bomb"}

## Real emitter model (#929, MDL-014), base-pivoted (probed AABB: y 0..1.2).
const EMITTER_SCENE := preload("res://assets/generated/models/music-box-emitter.glb")
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
## Waltz Bomb bloom (#959): an elegant radial burst in the same violet as the
## rim glow when the panic clear detonates. Bigger and faster than a graze spark.
const BOMB_BLOOM_COLOR := Color(0.82, 0.72, 1.0)
const BOMB_BLOOM_AMOUNT := 44
const BOMB_BLOOM_SPEED := 9.0
const BOMB_BLOOM_LIFETIME := 0.6
## The dark stage overlay (#208) swallowed the floor edge into the
## background — a bright ring at the arena boundary (#929) sells where the
## stage actually ends.
const RIM_GLOW_COLOR := Color(0.78, 0.68, 0.95)
const RIM_RING_THICKNESS := 0.4
## Ballroom floor (#1126): wood-court grain under the dark overlay — the
## overlay's alpha (0.78) still lets the grain read faintly through it.
const FLOOR_TEXTURE := preload("res://assets/generated/textures/wood-court.png")
const FLOOR_TEXTURE_TILES := 6.0
## Turret scanning beam (#1126): a slow rotating emissive wedge sweeping the
## floor from the turret, selling "this thing is watching the whole arena."
const SCAN_BEAM_COLOR := Color(0.85, 0.72, 1.0, 0.16)
const SCAN_BEAM_SPEED := 0.6

## Latest replicated state, straight from BulletWaltz.get_snapshot().
var players := {}
var bullets: Array = []
var out: Array = []

var _bullet_pool: Array[MeshInstance3D] = []
var _last_grazes := {}  # slot (int) -> graze count already sparked at
## slot (int) -> bool: last-seen Waltz Bomb charge, so a true->false read fires
## the spend bloom exactly once. Defaults to held, so no bloom on a first frame.
var _last_bomb := {}
var _was_out := {}  # slot (int) -> bool (last-seen KO state, for the KO blast)
## Turret readability (#1036): the model otherwise sits as an inert prop with
## no visible tie to the bullets it spawns. Held so _pulse_turret can punch it.
var _turret: Node3D
## Bullets only ever grow by a whole volley at once (_spawn_bullet always
## starts a fresh one at the origin) and shrink one at a time as they expire
## or hit, so a rise here reliably means "a volley just fired."
var _last_bullet_count := 0
## Pivot at the turret (arena origin) for the scanning beam (#1126); rotating
## the pivot sweeps the beam mesh (offset outward as its child) around the
## turret, rather than spinning the mesh in place around its own off-center
## position.
var _scan_pivot: Node3D


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(delta: float) -> void:
	if _scan_pivot != null and not ArenaFX.reduced_motion:
		_scan_pivot.rotation.y += delta * SCAN_BEAM_SPEED


## Elegant violet floor for the bullet-hell weave (#589).
func _floor_tint() -> Color:
	return Color(0.9, 0.85, 1.0)


## Ballroom floor (#1126): the default tile floor gets the wood-court grain,
## still tinted violet (above) — the dark overlay dims it, letting it read
## faintly rather than vanish, per the issue's proposal.
func _build_floor() -> void:
	var floor_node := _dresser.build_floor(_floor_tile_scene(), _floor_tint(), _arena_half())
	if floor_node != null:
		var mat := floor_node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_texture = FLOOR_TEXTURE
			mat.uv1_scale = Vector3(FLOOR_TEXTURE_TILES, FLOOR_TEXTURE_TILES, 1.0)


## formula-twin — must mirror BulletWaltz._setup (scaled _play_half). The sim
## derives _play_half = MinigameScaling.arena_half(ARENA_HALF, slots.size());
## this view re-derives the same value from the lobby count. If the scaling
## formula changes in the sim but not here, the rendered floor/camera will
## mismatch the sim's play area.
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

	_turret = EMITTER_SCENE.instantiate() as Node3D
	_turret.name = "Turret"
	arena.add_child(_turret)

	_build_rim_glow()
	_build_scan_beam()

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


## A bright ring at the arena boundary (#929) — the dark stage overlay
## otherwise swallows the floor edge into the background.
func _build_rim_glow() -> void:
	var half := _arena_half()
	var mesh := TorusMesh.new()
	mesh.inner_radius = half - RIM_RING_THICKNESS
	mesh.outer_radius = half
	var material := StandardMaterial3D.new()
	material.albedo_color = RIM_GLOW_COLOR
	material.emission_enabled = true
	material.emission = RIM_GLOW_COLOR
	material.emission_energy_multiplier = 1.4
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "RimGlow"
	node.mesh = mesh
	node.rotation.x = PI / 2.0
	node.position.y = 0.03
	arena.add_child(node)


## A slow-sweeping emissive wedge from the turret (#1126): a flat beam mesh
## offset outward as a child of a pivot at the turret's position, so rotating
## the pivot each frame (_process) sweeps the beam around the arena like a
## searchlight — without needing a real spotlight/shadow pass.
func _build_scan_beam() -> void:
	var half := _arena_half()
	_scan_pivot = Node3D.new()
	_scan_pivot.name = "ScanPivot"
	arena.add_child(_scan_pivot)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(half, 0.02, half * 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = SCAN_BEAM_COLOR
	material.emission_enabled = true
	material.emission = Color(SCAN_BEAM_COLOR.r, SCAN_BEAM_COLOR.g, SCAN_BEAM_COLOR.b)
	material.emission_energy_multiplier = 0.8
	mesh.material = material
	var beam := MeshInstance3D.new()
	beam.name = "ScanBeam"
	beam.mesh = mesh
	beam.position = Vector3(half * 0.5, 0.05, 0.0)
	_scan_pivot.add_child(beam)


## A visible punch + flash the instant a volley fires (#1036): the model's
## position already matches the true spawn point, but nothing ever showed it
## — a static prop reads as decoration, not the thing shooting at you.
func _pulse_turret() -> void:
	fx_burst(Vector2.ZERO, BULLET_COLOR, 0.8)
	if ArenaFX.reduced_motion:
		return
	_turret.scale = Vector3.ONE * 1.2
	var tween := create_tween()
	tween.set_trans(PartyTheme.TRANS_OVERSHOOT).set_ease(PartyTheme.EASE_DEFAULT)
	tween.tween_property(_turret, "scale", Vector3.ONE, PartyTheme.DUR_MED)


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
	# A fresh volley just fired (#1036): punch the turret so it visibly reads
	# as the thing bullets come from, instead of an inert floating prop.
	if bullets.size() > _last_bullet_count:
		_pulse_turret()
	_last_bullet_count = bullets.size()
	for i in _bullet_pool.size():
		var node := _bullet_pool[i]
		if i < bullets.size():
			var bullet: Array = bullets[i]
			var xz := Vector2(float(bullet[BulletWaltz.BU_X]), float(bullet[BulletWaltz.BU_Y]))
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
		update_rig(slot, Vector2(state[BulletWaltz.PS_X], state[BulletWaltz.PS_Y]))
		var grazes := int(state[BulletWaltz.PS_GRAZE])
		# Graze shimmer: a spark when a bullet skims past for a fresh graze.
		if grazes > int(_last_grazes.get(slot, 0)):
			fx_sparkle(Vector2(rig.position.x, rig.position.z), GRAZE_COLOR, 1.0)
			if slot == my_slot:
				# `pop`'s vocabulary entry names "graze coin" as its example use.
				play_sfx(&"pop")
		_last_grazes[slot] = grazes
		# Waltz Bomb (#959): a still-held charge shows a ◈ pip; the frame it drops
		# to spent, an elegant radial bloom clears the storm around the dancer.
		# Only acts when the row actually carries the bomb slot, so a legacy
		# 3-field snapshot never blooms from an absent field reading as spent.
		var has_bomb := false
		if state.size() > BulletWaltz.PS_BOMB:
			has_bomb = int(state[BulletWaltz.PS_BOMB]) == 1
			if bool(_last_bomb.get(slot, true)) and not has_bomb:
				(
					ArenaFX
					. burst(
						arena,
						to_arena(Vector2(rig.position.x, rig.position.z), 0.6),
						BOMB_BLOOM_COLOR,
						BOMB_BLOOM_AMOUNT,
						BOMB_BLOOM_SPEED,
						BOMB_BLOOM_LIFETIME,
					)
				)
				play_sfx(&"explosion")
			_last_bomb[slot] = has_bomb
		var label := player_name(slot)
		if grazes > 0:
			label += "  ✦%d" % grazes
		if has_bomb:
			label += "  ◈"
		rig.display_name = label
