extends MinigameView3D
## Snake Chain client view (M10-11): the head is your CharacterRig, the
## chain is a trail of glowing segments in your color, pellets dot the
## floor, invulnerable heads shimmer.

const PELLET_COLOR := Color(0.55, 0.95, 0.5)
const SEGMENT_POOL_PER_PLAYER := 24
const SEGMENT_HEIGHT := 0.3

## Latest replicated state, straight from SnakeChain.get_snapshot().
var players := {}
var trails := {}
var pellets: Array = []
var teams: Array = []

var _segment_pools := {}
var _pellet_pool: Array[MeshInstance3D] = []
var _counts_seen := {}
var _invuln_seen := {}


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


func _setup_3d() -> void:
	var pellet_mesh := SphereMesh.new()
	pellet_mesh.radius = 0.25
	pellet_mesh.height = 0.5
	var pellet_material := StandardMaterial3D.new()
	pellet_material.albedo_color = PELLET_COLOR
	# #796: metallic + roughness give the sphere a real specular highlight
	# instead of reading as a flat, shadeless disc (the coin_scramble/
	# treasure_divers convention for small glowing pickups).
	pellet_material.metallic = 0.6
	pellet_material.roughness = 0.35
	pellet_material.emission_enabled = true
	pellet_material.emission = PELLET_COLOR
	pellet_material.emission_energy_multiplier = 0.5
	pellet_mesh.material = pellet_material
	# Pool covers the scaled steady-state supply plus the crash-spill headroom.
	for i in SnakeChain.max_pellets_for(names.size()) + SnakeChain.SPILL_HEADROOM:
		var node := MeshInstance3D.new()
		node.mesh = pellet_mesh
		node.visible = false
		arena.add_child(node)
		_pellet_pool.append(node)
	for slot: int in names:
		var mesh := SphereMesh.new()
		mesh.radius = SnakeChain.SEGMENT_RADIUS
		mesh.height = SnakeChain.SEGMENT_RADIUS * 2.0
		var material := StandardMaterial3D.new()
		var color := player_color(slot)
		material.albedo_color = color
		material.metallic = 0.6
		material.roughness = 0.35
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.35
		mesh.material = material
		var pool: Array[MeshInstance3D] = []
		for i in SEGMENT_POOL_PER_PLAYER:
			var node := MeshInstance3D.new()
			node.mesh = mesh
			node.visible = false
			arena.add_child(node)
			pool.append(node)
		_segment_pools[slot] = pool


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	trails = game.get("trails", {})
	pellets = game.get("pellets", [])
	teams = game.get("teams", [])
	for i in _pellet_pool.size():
		var node := _pellet_pool[i]
		if i < pellets.size():
			var pellet: Array = pellets[i]
			node.position = to_arena(Vector2(float(pellet[0]), float(pellet[1])), 0.25)
			node.visible = true
		else:
			node.visible = false
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[SnakeChain.PS_X], state[SnakeChain.PS_Y]))
		var invulnerable := float(state[SnakeChain.PS_INVULN]) > 0.0
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
		var pool: Array = _segment_pools.get(slot, [])
		var trail: Array = trails.get(slot, [])
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
