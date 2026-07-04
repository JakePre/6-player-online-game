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
## Previous snapshot's tile states, for crack/collapse SFX on transitions.
var _prev_tiles: Array = []
## Last standing position per slot, so the splash lands where they fell.
var _last_seen_pos := {}
# -1 = unseeded, so a mid-match rejoin does not shake on its first snapshot.
var _fallen_seen := -1


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _arena_half() -> float:
	return ThinIce.HALF_EXTENT


## The ice grid IS the floor: a dark water plane below, one box per tile with
## its top surface at y=0 so rigs stand on the ice.
func _build_floor() -> void:
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2.ONE * ThinIce.HALF_EXTENT * 2.5
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = WATER_COLOR
	water_mesh.material = water_material
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = water_mesh
	water.position.y = -WATER_DEPTH
	arena.add_child(water)

	_intact_material = StandardMaterial3D.new()
	_intact_material.albedo_color = INTACT_COLOR
	_intact_material.roughness = 0.2
	_cracked_material = StandardMaterial3D.new()
	_cracked_material.albedo_color = CRACKED_COLOR
	_breaking_material = StandardMaterial3D.new()
	_breaking_material.albedo_color = BREAKING_COLOR
	_breaking_material.emission_enabled = true
	_breaking_material.emission = BREAKING_COLOR
	_breaking_material.emission_energy_multiplier = 0.6
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(ThinIce.TILE_SIZE, TILE_THICKNESS, ThinIce.TILE_SIZE)

	for y in ThinIce.GRID_SIZE:
		for x in ThinIce.GRID_SIZE:
			var node := MeshInstance3D.new()
			node.name = "Tile_%d_%d" % [x, y]
			node.mesh = tile_mesh
			node.material_override = _intact_material
			node.position = Vector3(
				-ThinIce.HALF_EXTENT + (x + 0.5) * ThinIce.TILE_SIZE,
				-TILE_THICKNESS / 2.0,
				-ThinIce.HALF_EXTENT + (y + 0.5) * ThinIce.TILE_SIZE
			)
			arena.add_child(node)
			_tile_nodes.append(node)


func _render_3d(game: Dictionary) -> void:
	tiles = game.get("tiles", [])
	players = game.get("players", {})
	fallen = game.get("fallen", [])
	_update_tiles()
	_update_players()
	_shake_on_new_falls()


## Someone crashing through the ice is the game's big impact (M6-02): screen
## shake plus a splash ring and sound where they went under (#138).
func _shake_on_new_falls() -> void:
	var fallen_count := 0
	for group: Array in fallen:
		fallen_count += group.size()
	if _fallen_seen >= 0 and fallen_count > _fallen_seen:
		request_shake(10.0)
		play_sfx(&"error")
		for group: Array in fallen:
			for slot: int in group:
				if _last_seen_pos.has(slot):
					_spawn_splash(_last_seen_pos[slot])
					# Droplets on top of the ring: the body going under (M13-05).
					fx_splash(_last_seen_pos[slot])
					_last_seen_pos.erase(slot)
	_fallen_seen = fallen_count


## Expanding, fading ring at the water surface where a player went under.
func _spawn_splash(world_pos: Vector2) -> void:
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


func _update_tiles() -> void:
	var cracked_now := false
	var breaking_now := false
	for idx in _tile_nodes.size():
		var state: int = tiles[idx] if idx < tiles.size() else ThinIce.TileState.INTACT
		var prev: int = _prev_tiles[idx] if idx < _prev_tiles.size() else ThinIce.TileState.INTACT
		if state != prev:
			cracked_now = cracked_now or state == ThinIce.TileState.CRACKED
			breaking_now = breaking_now or state == ThinIce.TileState.BREAKING
			# Ice chips as it cracks, splashes as it gives way (M13-05); the
			# seeding snapshot stays silent like the sounds below.
			if not _prev_tiles.is_empty():
				if state == ThinIce.TileState.CRACKED:
					fx_dust(_tile_center(idx))
				elif state == ThinIce.TileState.GONE:
					fx_splash(_tile_center(idx))
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
	if not _prev_tiles.is_empty():
		if cracked_now:
			play_sfx(&"tick")
		if breaking_now:
			play_sfx(&"click")
	_prev_tiles = tiles.duplicate()


## The snapshot only carries players still standing; fallen rigs sink out of
## sight with their tile. `fallen` groups simultaneous falls (see
## ThinIce._flush_falls), so it flattens one level.
func _tile_center(idx: int) -> Vector2:
	var x := idx % ThinIce.GRID_SIZE
	var y := int(floorf(float(idx) / ThinIce.GRID_SIZE))
	return Vector2(
		-ThinIce.HALF_EXTENT + (x + 0.5) * ThinIce.TILE_SIZE,
		-ThinIce.HALF_EXTENT + (y + 0.5) * ThinIce.TILE_SIZE
	)


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		rig.visible = true
		var pos := Vector2(state[0], state[1])
		_last_seen_pos[slot] = pos
		update_rig(slot, pos)
	for group: Array in fallen:
		for slot: int in group:
			var rig := rig_for_slot(slot)
			if rig != null:
				rig.visible = false
