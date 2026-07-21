extends MinigameView3D
## Thin Ice client view (M8-06): renders the replicated arena in the shared
## 2.5D iso-arena (M8-01, MinigameView3D) — the tile grid as ice boxes over a
## dark water plane (cracked tiles discolor, gone tiles vanish into the
## water), players as CharacterRig instances; fallen players' rigs disappear
## with their tile. Replaces the default arena floor by overriding
## _build_floor, since vanishing tiles are the game. Presentation-tier swap
## only: state storage and the render contract are unchanged from the 2D pass
## (M4-03).

const INTACT_COLOR := Color(0.55, 0.78, 0.95)
const CRACKED_COLOR := Color(0.75, 0.68, 0.55)
const BREAKING_COLOR := Color(1.0, 0.35, 0.25)
const WATER_COLOR := Color(0.03, 0.05, 0.1)
const INTACT_TEXTURE := preload("res://assets/generated/textures/ice-cracked.png")
const WATER_FLOOR_TEXTURE := preload("res://assets/generated/textures/water-pool.png")
## Under-ice fish: dark silhouettes that drift below the ice, visible through
## cracked/gone tiles (#1157 Tier 2).
const FISH_COLOR := Color(0.12, 0.12, 0.15)
const FISH_COUNT := 4
const FISH_SPEED := 0.3
const FISH_RADIUS := 0.03
const FISH_HEIGHT := 0.12
## Snowfall (#1157 Tier 2): gentle falling particles throughout the match.
const SNOW_COLOR := Color(0.95, 0.95, 1.0, 0.85)
const SNOW_AMOUNT := 40
const SNOW_LIFETIME := 3.0
const SNOW_SPEED := 1.5
## Frost breath (#1157 Tier 2): small white puff from idle rigs.
const FROST_AMOUNT := 6
const FROST_LIFETIME := 0.6
const FROST_SPEED := 0.8
const FROST_BREATH_Y := 0.8
## Ice shard debris (#1157 Tier 2): small prisms that fly out when a tile breaks.
const SHARD_COUNT := 4
const SHARD_SPEED := 4.0
const SHARD_LIFETIME := 0.5
const SHARD_COLOR := Color(0.55, 0.78, 0.95, 0.9)
const TILE_THICKNESS := 0.3
const WATER_DEPTH := 0.45
## Splash ring where a player goes under (#138 follow-up: falls need sound
## and a visible landing spot, not just the rig vanishing).
const SPLASH_COLOR := Color(0.8, 0.9, 1.0, 0.9)
const SPLASH_SEC := 0.5
## Latest replicated state, straight from ThinIce.get_snapshot().
var tiles: Array = []
var players := {}
var fallen: Array = []

var _tile_nodes: Array[MeshInstance3D] = []
var _intact_material: StandardMaterial3D
var _cracked_material: StandardMaterial3D
var _breaking_material: StandardMaterial3D
var _water: MeshInstance3D
## The grid dimension / half-extent the tile nodes are currently built for. The
## setup-time estimate (from names.size()) seeds these; the snapshot's
## authoritative grid_size corrects them on render (#578).
var _view_grid := 0
var _view_half := 0.0
## Previous snapshot's tile states, for crack/collapse SFX on transitions.
var _prev_tiles: Array = []
## Last standing position per slot, so the splash lands where they fell.
var _last_seen_pos := {}
## Rejoin-quiet rising edge on the fallen count (#941): the first snapshot
## seeds and never shakes.
var _edges := EdgeTracker.new()
## Continuous snowfall particles (#1157 Tier 2).
var _snow: CPUParticles3D
## Under-ice fish nodes (#1157 Tier 2).
var _fish: Array[MeshInstance3D] = []
var _fish_angles: Array[float] = []
## Frost breath accumulator per slot (#1157 Tier 2).
var _breath_accum := {}
## Container for tile-break debris so it doesn't pollute the arena child count.
var _debris_container: Node3D


func _physics_process(delta: float) -> void:
	send_move_intent()
	# Under-ice fish drift (#1157 Tier 2).
	_animate_fish(delta)


## Setup-time head-count estimate of the grid dimension, mirroring the sim's
## M15 scaling formula. Only a best-effort seed: names.size() counts held
## (incl. disconnected) members while the sim scales from the active round
## slots, so near a scaling boundary these disagree — the snapshot's
## authoritative grid_size corrects it on render (#578). Equal ThinIce.GRID_SIZE
## at <=6 players.
func _estimate_grid() -> int:
	return roundi(ThinIce.GRID_SIZE * sqrt(MinigameScaling.growth(names.size())))


func _arena_half() -> float:
	return _view_half if _view_half > 0.0 else _estimate_grid() * ThinIce.TILE_SIZE / 2.0


## The ice grid IS the floor: a dark water plane below, one box per tile with
## its top surface at y=0 so rigs stand on the ice. Materials + water are made
## once; the tile grid itself is (re)built by _build_ice_grid so a snapshot with
## a different authoritative grid_size can rebuild it (#578).
func _build_floor() -> void:
	var water_mesh := PlaneMesh.new()
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = WATER_COLOR
	water_material.albedo_texture = WATER_FLOOR_TEXTURE
	water_material.uv1_scale = Vector3(8.0, 8.0, 1.0)
	water_material.metallic = 0.1
	water_material.roughness = 0.6
	water_mesh.material = water_material
	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.mesh = water_mesh
	_water.position.y = -WATER_DEPTH
	arena.add_child(_water)

	_intact_material = StandardMaterial3D.new()
	_intact_material.albedo_color = INTACT_COLOR
	_intact_material.albedo_texture = INTACT_TEXTURE
	_intact_material.roughness = 0.2
	_cracked_material = StandardMaterial3D.new()
	_cracked_material.albedo_color = CRACKED_COLOR
	_breaking_material = StandardMaterial3D.new()
	_breaking_material.albedo_color = BREAKING_COLOR
	_breaking_material.emission_enabled = true
	_breaking_material.emission = BREAKING_COLOR
	_breaking_material.emission_energy_multiplier = 0.6

	_build_ice_grid(_estimate_grid())


## (Re)builds the grid_size x grid_size tile nodes over a matching arena half.
## Frees any prior nodes first (removed from the tree immediately, not just
## queue_free) so a rebuild leaves no stale tiles and node names stay free.
func _build_ice_grid(grid_size: int) -> void:
	_view_grid = grid_size
	_view_half = grid_size * ThinIce.TILE_SIZE / 2.0
	_water.mesh.size = Vector2.ONE * _view_half * 2.5
	for node in _tile_nodes:
		arena.remove_child(node)
		node.queue_free()
	_tile_nodes.clear()
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(ThinIce.TILE_SIZE, TILE_THICKNESS, ThinIce.TILE_SIZE)
	for y in grid_size:
		for x in grid_size:
			var node := MeshInstance3D.new()
			node.name = "Tile_%d_%d" % [x, y]
			node.mesh = tile_mesh
			node.material_override = _intact_material
			node.position = Vector3(
				-_view_half + (x + 0.5) * ThinIce.TILE_SIZE,
				-TILE_THICKNESS / 2.0,
				-_view_half + (y + 0.5) * ThinIce.TILE_SIZE
			)
			arena.add_child(node)
			_tile_nodes.append(node)


## One-time arena prop setup (#1157): snowfall particles and under-ice fish.
func _setup_3d() -> void:
	# Debris container so tile-break shards don't pollute the arena child count.
	_debris_container = Node3D.new()
	_debris_container.name = "Debris"
	arena.add_child(_debris_container)
	# Snowfall: gentle falling particles throughout the match.
	_snow = CPUParticles3D.new()
	_snow.name = "Snowfall"
	_snow.one_shot = false
	_snow.emitting = true
	_snow.amount = SNOW_AMOUNT
	_snow.lifetime = SNOW_LIFETIME
	_snow.color = SNOW_COLOR
	_snow.direction = Vector3.DOWN
	_snow.spread = 45.0
	_snow.initial_velocity_min = SNOW_SPEED * 0.5
	_snow.initial_velocity_max = SNOW_SPEED
	_snow.gravity = Vector3(0.0, -0.5, 0.0)
	_snow.scale_amount_min = 1.0
	_snow.scale_amount_max = 3.0
	_snow.flatness = 0.5
	var snow_mesh := SphereMesh.new()
	snow_mesh.radius = 0.03
	snow_mesh.height = 0.06
	_snow.mesh = snow_mesh
	_snow.position.y = 4.0
	_snow.visibility_aabb = AABB(Vector3(-6.0, 0.0, -6.0), Vector3(12.0, 8.0, 12.0))
	arena.add_child(_snow)
	# Under-ice fish: dark silhouettes drifting below the cracked surface.
	for i in FISH_COUNT:
		var fish_mesh := PrismMesh.new()
		fish_mesh.left_to_right = 0.5
		fish_mesh.size = Vector3(FISH_RADIUS * 4.0, FISH_HEIGHT, FISH_RADIUS * 2.0)
		var fish_mat := StandardMaterial3D.new()
		fish_mat.albedo_color = FISH_COLOR
		fish_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fish_mesh.material = fish_mat
		var fish := MeshInstance3D.new()
		fish.name = "Fish_%d" % i
		fish.mesh = fish_mesh
		# Spread fish in a ring under the ice, at water depth.
		var angle := TAU * i / FISH_COUNT
		var radius := 2.0 + (i % 3) * 1.5
		fish.position = Vector3(cos(angle) * radius, -WATER_DEPTH * 0.6, sin(angle) * radius)
		arena.add_child(fish)
		_fish.append(fish)
		_fish_angles.append(angle)


## Drift the under-ice fish in a slow circle (#1157 Tier 2).
func _animate_fish(delta: float) -> void:
	for i in _fish.size():
		_fish_angles[i] = _fish_angles[i] + FISH_SPEED * delta
		var radius := 2.0 + (i % 3) * 1.5
		_fish[i].position = Vector3(
			cos(_fish_angles[i]) * radius, -WATER_DEPTH * 0.6, sin(_fish_angles[i]) * radius
		)
		_fish[i].rotation.y = _fish_angles[i] + PI / 2.0


## Periodic frost breath puff from idle rigs (#1157 Tier 2).
func _tick_frost_breath(slot: int, rig: CharacterRig) -> void:
	if ArenaFX.reduced_motion:
		return
	_breath_accum[slot] = _breath_accum.get(slot, 0.0) + get_process_delta_time()
	if _breath_accum[slot] < 2.0:
		return
	_breath_accum[slot] = 0.0
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = FROST_AMOUNT
	particles.lifetime = FROST_LIFETIME
	particles.color = SNOW_COLOR
	particles.direction = Vector3.UP
	particles.spread = 25.0
	particles.initial_velocity_min = FROST_SPEED * 0.5
	particles.initial_velocity_max = FROST_SPEED
	particles.gravity = Vector3(0.0, 0.3, 0.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	particles.mesh = mesh
	particles.position = rig.position + Vector3(0.0, FROST_BREATH_Y, 0.0)
	arena.add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


## Honor the sim's authoritative grid dimension (#578): if it disagrees with the
## setup-time estimate, rebuild the tile grid to match so the flat `tiles` array
## maps onto the right nodes (else a GONE tile renders on the wrong square and a
## player drops over ice that still looks intact). Drops the transition baseline
## so a stale-width delta never lights the wrong tiles, and re-fits the camera.
func _adopt_snapshot_grid(grid_size: int) -> void:
	if grid_size <= 0 or grid_size == _view_grid:
		return
	_build_ice_grid(grid_size)
	_prev_tiles = []
	if _camera_rig != null:
		_camera_rig.ortho_size = _view_half * 2.4


func _render_3d(game: Dictionary) -> void:
	tiles = game.get("tiles", [])
	players = game.get("players", {})
	fallen = game.get("fallen", [])
	# Match the sim's authoritative grid before mapping tiles onto nodes (#578).
	if game.has("grid_size"):
		_adopt_snapshot_grid(int(game["grid_size"]))
	_update_tiles()
	_update_players()
	_shake_on_new_falls()


## Someone crashing through the ice is the game's big impact (M6-02): screen
## shake plus a splash ring and sound where they went under (#138).
func _shake_on_new_falls() -> void:
	var fallen_count := 0
	for group: Array in fallen:
		fallen_count += group.size()
	if _edges.rose(&"fallen", fallen_count):
		request_shake(10.0)
		# Signature cues (#711 pilot): the body hitting the water plus the
		# shared elimination cue, replacing the generic UI `error`.
		play_sfx(&"splash")
		play_sfx(&"ko")
		for group: Array in fallen:
			for slot: int in group:
				if _last_seen_pos.has(slot):
					_spawn_splash(_last_seen_pos[slot])
					# Droplets on top of the ring: the body going under (M13-05).
					fx_splash(_last_seen_pos[slot])
					_last_seen_pos.erase(slot)


## Expanding, fading ring at the water surface where a player went under.
func _spawn_splash(world_pos: Vector2) -> void:
	if ArenaFX.reduced_motion:
		return
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.35
	mesh.outer_radius = 0.5
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = SPLASH_COLOR
	mesh.material = material
	var splash := MeshInstance3D.new()
	splash.mesh = mesh
	splash.position = to_arena(world_pos, -WATER_DEPTH + 0.05)
	arena.add_child(splash)
	var tween := splash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(splash, "scale", Vector3(2.5, 1.0, 2.5), SPLASH_SEC)
	tween.tween_property(material, "albedo_color:a", 0.0, SPLASH_SEC)
	tween.chain().tween_callback(splash.queue_free)


## Spawn flying ice shards when a tile breaks through (#1157 Tier 2).
func _spawn_ice_shards(tile_idx: int) -> void:
	if ArenaFX.reduced_motion or _debris_container == null:
		return
	var center := _tile_center(tile_idx)
	for i in SHARD_COUNT:
		var shard_mesh := PrismMesh.new()
		shard_mesh.size = Vector3(0.08, 0.04, 0.06)
		var shard_mat := StandardMaterial3D.new()
		shard_mat.albedo_color = SHARD_COLOR
		shard_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shard_mesh.material = shard_mat
		var shard := MeshInstance3D.new()
		shard.mesh = shard_mesh
		shard.position = to_arena(center, -TILE_THICKNESS / 2.0)
		_debris_container.add_child(shard)
		var angle := TAU * i / SHARD_COUNT
		var dir := Vector3(cos(angle), 0.3 + randf() * 0.5, sin(angle)) * SHARD_SPEED
		var tween := shard.create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position", shard.position + dir * 0.5, SHARD_LIFETIME)
		tween.tween_property(shard, "rotation:y", randf() * TAU, SHARD_LIFETIME)
		tween.tween_property(shard_mat, "albedo_color:a", 0.0, SHARD_LIFETIME)
		tween.chain().tween_callback(shard.queue_free)


func _update_tiles() -> void:
	var cracked_now := false
	var breaking_now := false
	var gone_now := false
	for idx in _tile_nodes.size():
		var state: int = tiles[idx] if idx < tiles.size() else ThinIce.TileState.INTACT
		var prev: int = _prev_tiles[idx] if idx < _prev_tiles.size() else ThinIce.TileState.INTACT
		if state != prev:
			cracked_now = cracked_now or state == ThinIce.TileState.CRACKED
			breaking_now = breaking_now or state == ThinIce.TileState.BREAKING
			gone_now = gone_now or state == ThinIce.TileState.GONE
			# Ice chips as it cracks, splashes as it gives way (M13-05); the
			# seeding snapshot stays silent like the sounds below.
			if not _prev_tiles.is_empty():
				if state == ThinIce.TileState.CRACKED:
					fx_dust(_tile_center(idx))
				elif state == ThinIce.TileState.GONE:
					fx_splash(_tile_center(idx))
					_spawn_ice_shards(idx)
		var node := _tile_nodes[idx]
		node.visible = state != ThinIce.TileState.GONE
		if node.visible:
			node.material_override = (
				_breaking_material
				if state == ThinIce.TileState.BREAKING
				else (_cracked_material if state == ThinIce.TileState.CRACKED else _intact_material)
			)
	# One sound per snapshot, however many tiles changed together; the seeding
	# snapshot stays silent so mid-match rejoiners aren't greeted with cracks.
	# Signature cues (#711 pilot, docs/AUDIO_GUIDE.md): the fracture escalation
	# ladder — `crack` (first warning) -> `alarm` (about to give, the shared
	# danger telegraph) -> `shatter` (the tile drops) — replacing the UI
	# `tick`/`click` that used to stand in for ice.
	if not _prev_tiles.is_empty():
		if cracked_now:
			play_sfx(&"crack")
		if breaking_now:
			play_sfx(&"alarm")
		if gone_now:
			play_sfx(&"shatter")
	_prev_tiles = tiles.duplicate()


## The snapshot only carries players still standing; fallen rigs sink out of
## sight with their tile. `fallen` groups simultaneous falls (see
## ThinIce._flush_falls), so it flattens one level.
func _tile_center(idx: int) -> Vector2:
	var x := idx % _view_grid
	var y := int(floorf(float(idx) / _view_grid))
	return Vector2(
		-_view_half + (x + 0.5) * ThinIce.TILE_SIZE, -_view_half + (y + 0.5) * ThinIce.TILE_SIZE
	)


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		rig.visible = true
		var pos := Vector2(state[ThinIce.PS_X], state[ThinIce.PS_Y])
		_last_seen_pos[slot] = pos
		update_rig(slot, pos)
		# Frost breath (#1157 Tier 2): periodic puff when standing still.
		_tick_frost_breath(slot, rig)
	for group: Array in fallen:
		for slot: int in group:
			var rig := rig_for_slot(slot)
			if rig != null:
				rig.visible = false
