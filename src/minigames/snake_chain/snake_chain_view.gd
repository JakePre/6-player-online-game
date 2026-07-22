extends MinigameView3D
## Snake Chain client view (M10-11): the head is your CharacterRig, the
## chain is a trail of glowing ring segments in your color, pellets dot
## the floor, invulnerable heads shimmer.
##
## Visual enhancements (#1156): diamond ring segments, connecting links,
## Kenney Food Kit pellet models, arena border wall, boost flame FX,
## rim props, team color, invulnerability ring.

## Tail Burn (#950): action_primary held boosts and burns tail — the sim toggles
## it on press/release; the base's declarative input (#947) sends the edges.
const INPUT_ACTIONS := {&"action_primary": {"key": "boost", "held": true}}
## Pellet models from Kenney Food Kit (#1156): small food items that read as
## edible pickups for the snake chain.
const PELLET_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_food_kit/candy-bar.glb"),
	preload("res://assets/environment/kenney_food_kit/cookie-chocolate.glb"),
	preload("res://assets/environment/kenney_food_kit/donut-sprinkles.glb"),
	preload("res://assets/environment/kenney_food_kit/muffin.glb"),
	preload("res://assets/environment/kenney_food_kit/strawberry.glb"),
	preload("res://assets/environment/kenney_food_kit/lollypop.glb"),
]
const PELLET_SCALE := 0.35
const SEGMENT_POOL_PER_PLAYER := 24
const SEGMENT_HEIGHT := 0.3
## Boost trail (#950): a color-flecked spark off a boosting head, staggered per
## slot so a boosting pack doesn't haze; ArenaFX is silent under reduced motion.
const BOOST_FX_EVERY := 2
## Chain ring segment (#1156): a TorusMesh ring reads as a chain link instead
## of a string of spheres.
const SEGMENT_RING_INNER_RATIO := 0.5
const SEGMENT_RING_OUTER_RATIO := 1.0
## Connecting link (#1156): thin emissive cylinder between consecutive segments.
const CONNECTOR_RADIUS := 0.06
## Arena border wall (#1156): an emissive translucent wall at the edge so the
## boundary reads clearly during the chase.
const BORDER_COLOR := Color(0.3, 0.5, 0.3, 0.35)
const BORDER_HEIGHT := 1.5
const BORDER_THICKNESS := 0.15
## Boost flame (#1156): a particle cloud behind a boosting head, replacing the
## old sparkle-only trail.
const BOOST_FLAME_COLOR := Color(1.0, 0.6, 0.1)
const BOOST_FLAME_HEIGHT := 0.15
## Rim props (#1156): grass-and-nature scenery around the grassy arena perimeter.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_nature_kit/rock_smallA.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_smallB.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_tallA.glb"),
	preload("res://assets/environment/kenney_platformer_kit/flowers.glb"),
	preload("res://assets/environment/kenney_platformer_kit/flowers-tall.glb"),
	preload("res://assets/environment/kenney_platformer_kit/mushrooms.glb"),
	preload("res://assets/environment/kenney_platformer_kit/grass.glb"),
]
const RIM_PROP_COUNT := 20
const RIM_PROP_SEED := 0x5A1C
## Invulnerability ring (#1156): a pulsing ring under the invulnerable player.
const INVULN_RING_COLOR := Color(0.8, 0.9, 1.0, 0.45)
const INVULN_RING_RADIUS := 0.8
const INVULN_RING_HEIGHT := 0.04

## Latest replicated state, straight from SnakeChain.get_snapshot().
var players := {}
var trails := {}
var pellets: Array = []
var teams: Array = []

var _segment_pools := {}
var _pellet_pool: Array[Node3D] = []
## Connector pool (#1156): thin cylinders linking consecutive segments.
var _connector_pools := {}
## Invulnerability ring node (#1156).
var _invuln_ring: MeshInstance3D
var _invuln_seen := {}
var _counts_seen := {}
## Snapshot counter driving the staggered boost-trail cadence (#950).
var _pulse := 0


func _physics_process(_delta: float) -> void:
	send_move_intent()


## A real grass field for the serpentine chase (#813): the Kenney grass block
## replaces the grey platform and carries its own color, so the old pastel
## tint (#589) approximating one is gone.
func _floor_tile_scene() -> PackedScene:
	return preload("res://assets/environment/kenney_platformer_kit/block-grass.glb")


func _arena_half() -> float:
	# Frame the scaled arena (ADR 003) — `names` is set before setup runs.
	return SnakeChain.arena_half_for(names.size())


func _build_floor() -> void:
	# The grass-block floor is already correct for the serpentine chase (#813).
	# No texture override needed — the block-grass tile carries its own look.
	var floor_node := _dresser.build_floor(_floor_tile_scene(), _floor_tint(), _arena_half())


func _setup_3d() -> void:
	_build_pellet_pool()
	_build_segment_pools()
	_build_connector_pools()
	_build_border_wall()
	_build_invulnerability_ring()
	# Grass-and-flowers arena edge (#1156): rocks, flowers, mushrooms, grass
	# ring the grass field so the arena sits in a lush meadow.
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)


## Pellet model swap (#1156): replace the spherical glow pickup with a random
## Kenney Food Kit model so pellets read as edible items on the grass field.
func _build_pellet_pool() -> void:
	var pool_size := SnakeChain.max_pellets_for(names.size()) + SnakeChain.SPILL_HEADROOM
	for i in pool_size:
		var scene := PELLET_SCENES[i % PELLET_SCENES.size()]
		var node := scene.instantiate() as Node3D
		if node == null:
			# Fallback: a simple sphere if the scene fails to load.
			var fallback := MeshInstance3D.new()
			fallback.mesh = SphereMesh.new()
			fallback.mesh.radius = 0.25
			fallback.mesh.height = 0.5
			node = fallback
		node.scale = Vector3.ONE * PELLET_SCALE
		node.visible = false
		arena.add_child(node)
		_pellet_pool.append(node)


## Chain segment shape (#1156): replace SphereMesh with TorusMesh rings so the
## chain reads as a real chain instead of a string of pearls. Each ring is
## emissive in the player's color.
func _build_segment_pools() -> void:
	for slot: int in names:
		var color := player_color(slot)
		var pool: Array[MeshInstance3D] = []
		# Build one mesh per slot for the pool.
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = SnakeChain.SEGMENT_RADIUS * SEGMENT_RING_INNER_RATIO
		ring_mesh.outer_radius = SnakeChain.SEGMENT_RADIUS * SEGMENT_RING_OUTER_RATIO
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = 0.6
		material.roughness = 0.35
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.35
		ring_mesh.material = material
		for i in SEGMENT_POOL_PER_PLAYER:
			var node := MeshInstance3D.new()
			node.mesh = ring_mesh
			node.visible = false
			# Lay the ring flat on the floor plane.
			node.rotation.x = PI / 2.0
			arena.add_child(node)
			pool.append(node)
		_segment_pools[slot] = pool


## Connecting lines between consecutive chain segments (#1156): a thin emissive
## cylinder linking each pair of sequential trail points so the chain reads as
## a continuous line rather than disconnected rings.
func _build_connector_pools() -> void:
	for slot: int in names:
		var color := player_color(slot).darkened(0.15)
		var pool: Array[MeshInstance3D] = []
		var conn_mesh := CylinderMesh.new()
		conn_mesh.top_radius = CONNECTOR_RADIUS
		conn_mesh.bottom_radius = CONNECTOR_RADIUS
		conn_mesh.height = 1.0  # stretched in render by scale
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.2
		conn_mesh.material = material
		# One fewer connector than segments.
		for i in SEGMENT_POOL_PER_PLAYER - 1:
			var node := MeshInstance3D.new()
			node.mesh = conn_mesh
			node.visible = false
			arena.add_child(node)
			pool.append(node)
		_connector_pools[slot] = pool


## Arena border wall (#1156): a translucent emissive wall at the arena edge so
## players can see the boundary during the fast chase. Four BoxMesh panels
## forming a rectangle at the climbing limit.
func _build_border_wall() -> void:
	var half := _arena_half()
	var wall_mat := StandardMaterial3D.new()
	wall_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall_mat.albedo_color = BORDER_COLOR
	wall_mat.emission_enabled = true
	wall_mat.emission = Color(0.2, 0.5, 0.2)
	wall_mat.emission_energy_multiplier = 0.3
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for wall_dir in [
		{"x": 0.0, "z": half, "size": Vector3(half * 2.0, BORDER_HEIGHT, BORDER_THICKNESS)},
		{"x": 0.0, "z": -half, "size": Vector3(half * 2.0, BORDER_HEIGHT, BORDER_THICKNESS)},
		{"x": half, "z": 0.0, "size": Vector3(BORDER_THICKNESS, BORDER_HEIGHT, half * 2.0)},
		{"x": -half, "z": 0.0, "size": Vector3(BORDER_THICKNESS, BORDER_HEIGHT, half * 2.0)},
	]:
		var mesh := BoxMesh.new()
		mesh.size = wall_dir.size
		var mat := wall_mat.duplicate() as StandardMaterial3D
		mesh.material = mat
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = Vector3(wall_dir.x, BORDER_HEIGHT * 0.5, wall_dir.z)
		arena.add_child(node)


## Invulnerability ring (#1156): a glowing translucent ring under the
## invulnerable player, pulsing with the shield cadence. Replaces the old
## purely-color-based shimmer.
func _build_invulnerability_ring() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = INVULN_RING_RADIUS * 0.7
	mesh.outer_radius = INVULN_RING_RADIUS
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = INVULN_RING_COLOR
	material.emission_enabled = true
	material.emission = Color(INVULN_RING_COLOR, 1.0)
	material.emission_energy_multiplier = 0.6
	mesh.material = material
	_invuln_ring = MeshInstance3D.new()
	_invuln_ring.name = "InvulnRing"
	_invuln_ring.mesh = mesh
	_invuln_ring.rotation.x = PI / 2.0
	_invuln_ring.visible = false
	arena.add_child(_invuln_ring)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	trails = game.get("trails", {})
	pellets = game.get("pellets", [])
	teams = game.get("teams", [])
	_pulse += 1
	_update_pellets()
	_update_invulnerability_ring()
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[SnakeChain.PS_X], state[SnakeChain.PS_Y]))
		var invulnerable := float(state[SnakeChain.PS_INVULN]) > 0.0
		# Boost flame (#1156): a flame particle burst behind a boosting head.
		# Replaces the old sparkle-only trail for a more visible boost cue.
		if int(state[SnakeChain.PS_BOOSTING]) == 1:
			_spawn_boost_flame(slot, state)
		# Invulnerability: the old color-lightened shimmer stays as a secondary
		# cue, but the primary visual is now the ring.
		rig.player_color = (
			player_color(slot).lightened(0.5) if invulnerable else player_color(slot)
		)
		var count := int(state[SnakeChain.PS_COUNT_EATEN])
		var caption := "%s  ●%d" % [player_name(slot), count]
		if invulnerable:
			caption += "  ✨"
		rig.display_name = caption
		if slot == my_slot:
			# Pickup ping and a personal note when a crash grants fresh invuln.
			if _counts_seen.has(slot) and count > int(_counts_seen[slot]):
				# A growth pickup (#728, docs/AUDIO_GUIDE.md — Survival & chase).
				play_sfx(&"powerup")
			if invulnerable and not bool(_invuln_seen.get(slot, false)):
				play_sfx(&"error")
		_counts_seen[slot] = count
		_invuln_seen[slot] = invulnerable
		_update_segments(slot, trails.get(slot, []))


## Pellet render (#1156): food models at floor level, each with a slight random
## yaw for visual variety.
func _update_pellets() -> void:
	for i in _pellet_pool.size():
		var node := _pellet_pool[i]
		if i < pellets.size():
			var pellet: Array = pellets[i]
			node.position = to_arena(Vector2(float(pellet[0]), float(pellet[1])), 0.1)
			# Random yaw per pellet so the food models don't all face the same way.
			node.rotation.y = float(i) * 1.3
			node.visible = true
		else:
			node.visible = false


## Render chain segments as rings plus connecting links (#1156).
func _update_segments(slot: int, trail: Array) -> void:
	var pool: Array = _segment_pools.get(slot, [])
	var conn_pool: Array = _connector_pools.get(slot, [])
	for i in pool.size():
		var segment: MeshInstance3D = pool[i]
		if i < trail.size():
			var point: Array = trail[i]
			segment.position = to_arena(
				Vector2(float(point[SnakeChain.TR_X]), float(point[SnakeChain.TR_Y])),
				SEGMENT_HEIGHT
			)
			segment.visible = true
		else:
			segment.visible = false
	# Connecting links between consecutive segments.
	for i in conn_pool.size():
		var connector: MeshInstance3D = conn_pool[i]
		if i + 1 < trail.size():
			var a: Array = trail[i]
			var b: Array = trail[i + 1]
			var pos_a := Vector2(float(a[SnakeChain.TR_X]), float(a[SnakeChain.TR_Y]))
			var pos_b := Vector2(float(b[SnakeChain.TR_X]), float(b[SnakeChain.TR_Y]))
			var mid := (pos_a + pos_b) * 0.5
			var dist := pos_a.distance_to(pos_b)
			if dist > 0.01:
				connector.position = to_arena(mid, SEGMENT_HEIGHT)
				connector.scale = Vector3(1.0, dist, 1.0)
				connector.rotation.y = atan2(pos_a.x - pos_b.x, pos_a.y - pos_b.y)
				connector.visible = true
			else:
				connector.visible = false
		else:
			connector.visible = false


## Boost flame effect (#1156): a small flame particle cluster behind the
## boosting head, complementing the tail-sparkle trail. One-shot fire-and-forget
## like the sparkle, using a CPUParticles3D burst.
func _spawn_boost_flame(slot: int, state: Array) -> void:
	if ArenaFX.reduced_motion:
		return
	var pos := Vector2(float(state[SnakeChain.PS_X]), float(state[SnakeChain.PS_Y]))
	# Spawn only on the cadence, same as the sparkle trail.
	if (_pulse + slot) % BOOST_FX_EVERY != 0:
		return
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = true
	particles.amount = 6
	particles.lifetime = 0.35
	particles.explosiveness = 0.8
	particles.initial_velocity_min = 0.3
	particles.initial_velocity_max = 0.8
	particles.orbit_velocity_min = 0.0
	particles.orbit_velocity_max = 0.0
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 60.0
	particles.gravity = Vector3(0.0, -0.5, 0.0)
	particles.angle_min = 0.0
	particles.angle_max = 360.0
	particles.scale_amount_min = 0.08
	particles.scale_amount_max = 0.15
	particles.color = BOOST_FLAME_COLOR
	particles.color_ramp = null
	# Color fades from orange to transparent.
	particles.color_initial_ramp = Gradient.new()
	particles.color_initial_ramp.add_point(0.0, Color(1.0, 0.7, 0.2, 0.9))
	particles.color_initial_ramp.add_point(0.5, Color(1.0, 0.4, 0.05, 0.5))
	particles.color_initial_ramp.add_point(1.0, Color(1.0, 0.2, 0.0, 0.0))
	particles.position = to_arena(pos, BOOST_FLAME_HEIGHT)
	# Offset slightly behind the head's facing direction.
	arena.add_child(particles)
	# Self-free after the burst completes.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(particles.queue_free)
	timer.timeout.connect(timer.queue_free)
	arena.add_child(timer)


## Invulnerability ring (#1156): follows the invulnerable player, pulsing
## with a protective glow. Visible only while someone has invulnerability.
func _update_invulnerability_ring() -> void:
	var invuln_slot := -1
	for slot: int in players:
		var state: Array = players[slot]
		if state.size() > SnakeChain.PS_INVULN and float(state[SnakeChain.PS_INVULN]) > 0.0:
			invuln_slot = slot
			break
	if invuln_slot >= 0:
		var state: Array = players[invuln_slot]
		_invuln_ring.position = to_arena(
			Vector2(float(state[SnakeChain.PS_X]), float(state[SnakeChain.PS_Y])),
			INVULN_RING_HEIGHT
		)
		_invuln_ring.visible = true
		# Pulse the ring with the snapshot cadence.
		var throb := 1.0 + 0.15 * sin(_pulse * TAU / 10.0)
		_invuln_ring.scale = Vector3(throb, 1.0, throb)
	else:
		_invuln_ring.visible = false
