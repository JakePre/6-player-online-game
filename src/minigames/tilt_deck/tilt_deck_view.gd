extends MinigameView3D
## Tilt Deck client view (#794): one circular raft over open water that visibly
## LEANS toward the crowd — the whole deck (players, coins, crates riding it)
## rotates with the replicated tilt vector, so the over-correction reads as a
## see-sawing platform. Falling past the rim splashes into the ocean (Thin Ice
## presentation). Renders TiltDeck.get_snapshot() only.

const DECK_TEXTURE := preload("res://assets/generated/textures/wood-court.png")
const DECK_RIM_COLOR := Color(0.38, 0.28, 0.18)
const DECK_THICKNESS := 0.35
const DECK_TEXTURE_TILES := 3.0
const WATER_TEXTURE := preload("res://assets/generated/textures/water-pool.png")
const WATER_Y := -3.5
const CRATE_SCENE := preload("res://assets/environment/kenney_platformer_kit/crate.glb")
## World lean (radians) per unit of tilt magnitude — enough to read clearly
## without launching rigs off the mesh.
const TILT_VISUAL_ANGLE := 0.32
const COIN_COLOR := Color(1.0, 0.85, 0.25)
const COIN_HEIGHT := 0.45
const CARGO_COLOR := Color(0.5, 0.35, 0.2)
## Seagull orbit radius and speed for the circling V-quads.
const SEAGULL_RADIUS := 10.0
const SEAGULL_SPEED := 0.15
## Wave animation amplitude and frequency.
const WAVE_AMP := 0.08
const WAVE_FREQ := 1.2

var tilt := Vector2.ZERO
var players := {}
var coins: Array = []
var cargo: Array = []

## The tilting raft everything rides.
var _deck: Node3D
var _coin_nodes: Array[MeshInstance3D] = []
var _cargo_nodes: Array[Node3D] = []
var _cargo_materials: Array[StandardMaterial3D] = []
## Last-seen board position per slot, so a fall splashes where they slipped off.
var _last_pos := {}
var _fallen_seen := {}

## Water plane for wave animation.
var _water: MeshInstance3D
## Seagull V-quad instances.
var _seagulls: Array[MeshInstance3D] = []
## Accumulated time for wave/seagull animation.
var _time: float = 0.0


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(delta: float) -> void:
	_time += delta
	# Gentle wave motion: sine-wave vertex displacement on the water plane.
	if is_instance_valid(_water):
		var wave_y := WATER_Y + sin(_time * WAVE_FREQ) * WAVE_AMP
		_water.position.y = wave_y
	# Seagulls circle above the water, bobbing gently.
	for i in _seagulls.size():
		var gull := _seagulls[i]
		if not is_instance_valid(gull):
			continue
		var angle := _time * SEAGULL_SPEED + float(i) * TAU / float(_seagulls.size())
		var x := cos(angle) * SEAGULL_RADIUS
		var z := sin(angle) * SEAGULL_RADIUS
		gull.position = Vector3(x, 4.0 + sin(_time * 1.5 + float(i)) * 0.5, z)
		# Face the direction of travel.
		gull.rotation.y = angle + PI / 2.0


func _arena_half() -> float:
	return TiltDeck.DECK_RADIUS + 3.0


func _setup_3d() -> void:
	# The raft is the floor here — hide the base tile floor and float on water.
	var floor_node := arena.get_node_or_null("Floor") as Node3D
	if floor_node != null:
		floor_node.visible = false
	_build_water()
	_build_deck()
	_build_life_preserver()
	_build_seagulls()
	# Reparent the pooled rigs onto the deck so they ride the tilt (the deck is
	# still un-rotated at setup, so this keeps their transforms clean).
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig != null:
			rig.reparent(_deck)


func _build_water() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(80.0, 80.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = WATER_TEXTURE
	mat.uv1_scale = Vector3(10.0, 10.0, 1.0)
	mat.metallic = 0.2
	mat.roughness = 0.4
	mesh.material = mat
	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.mesh = mesh
	_water.position = Vector3(0.0, WATER_Y, 0.0)
	arena.add_child(_water)


func _build_deck() -> void:
	_deck = Node3D.new()
	_deck.name = "Deck"
	arena.add_child(_deck)
	# The structural disc — a short cylinder with a slight taper.
	var mesh := CylinderMesh.new()
	mesh.top_radius = TiltDeck.DECK_RADIUS
	mesh.bottom_radius = TiltDeck.DECK_RADIUS * 0.88
	mesh.height = DECK_THICKNESS
	var mat := StandardMaterial3D.new()
	mat.albedo_color = DECK_RIM_COLOR
	mesh.material = mat
	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	disc.mesh = mesh
	# Seat the top surface at the deck's local y=0 so rigs stand on it.
	disc.position = Vector3(0.0, -DECK_THICKNESS / 2.0, 0.0)
	_deck.add_child(disc)
	# Wood-textured surface plane on top of the disc.
	var surface_mesh := PlaneMesh.new()
	surface_mesh.size = Vector2(TiltDeck.DECK_RADIUS * 2.0, TiltDeck.DECK_RADIUS * 2.0)
	var surface_mat := StandardMaterial3D.new()
	surface_mat.albedo_texture = DECK_TEXTURE
	surface_mat.uv1_scale = Vector3(DECK_TEXTURE_TILES, DECK_TEXTURE_TILES, 1.0)
	surface_mesh.material = surface_mat
	var surface := MeshInstance3D.new()
	surface.name = "DeckSurface"
	surface.mesh = surface_mesh
	surface.position = Vector3(0.0, 0.005, 0.0)
	_deck.add_child(surface)
	# A darker rim ring so the edge (and how close you are to it) reads at a glance.
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = TiltDeck.DECK_RADIUS - 0.25
	rim_mesh.outer_radius = TiltDeck.DECK_RADIUS + 0.15
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = DECK_RIM_COLOR
	rim_mesh.material = rim_mat
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = rim_mesh
	rim.position = Vector3(0.0, 0.02, 0.0)
	_deck.add_child(rim)


func _build_life_preserver() -> void:
	# Ring buoy (TorusMesh, orange/white stripes) on the deck rim.
	var buoy := TorusMesh.new()
	buoy.inner_radius = 0.35
	buoy.outer_radius = 0.55
	buoy.ring_count = 24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	mat.roughness = 0.6
	buoy.material = mat
	var node := MeshInstance3D.new()
	node.name = "LifePreserver"
	node.mesh = buoy
	# Place on the rim, slightly raised.
	var rim_x := TiltDeck.DECK_RADIUS - 0.3
	node.position = Vector3(rim_x, 0.15, 0.0)
	_deck.add_child(node)


func _build_seagulls() -> void:
	# 2-3 simple V-shaped dark quads that circle above the water.
	for i in 3:
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(0.6, 0.4)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.15, 0.15)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mesh.material = mat
		var gull := MeshInstance3D.new()
		gull.name = "Seagull%d" % i
		gull.mesh = mesh
		# Each gull starts at a different angle around the circle.
		var start_angle := float(i) * TAU / 3.0
		gull.position = Vector3(
			cos(start_angle) * SEAGULL_RADIUS, 4.0, sin(start_angle) * SEAGULL_RADIUS
		)
		# Rotate so the V-shape points in the direction of travel.
		gull.rotation.y = start_angle + PI / 2.0
		arena.add_child(gull)
		_seagulls.append(gull)


func _render_3d(game: Dictionary) -> void:
	tilt = _vec(game.get("tilt", []))
	players = game.get("players", {})
	coins = game.get("coins", [])
	cargo = game.get("cargo", [])
	# The raft leans toward the crowd: +tilt.x rolls +x down, +tilt.y pitches +z
	# down (sim y maps to world z via to_arena).
	_deck.rotation = Vector3(tilt.y * TILT_VISUAL_ANGLE, 0.0, -tilt.x * TILT_VISUAL_ANGLE)
	_update_players()
	_update_falls(game.get("fallen", []))
	_update_coins()
	_update_cargo()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var pos := Vector2(float(state[TiltDeck.PS_X]), float(state[TiltDeck.PS_Y]))
		_last_pos[slot] = pos
		if rig_for_slot(slot) == null:
			continue
		update_rig(slot, pos)
		var rig := rig_for_slot(slot)
		rig.display_name = "%s  %d" % [player_name(slot), int(state[TiltDeck.PS_COINS])]


## A slot appearing in `fallen` for the first time slipped off the rim this
## round — splash where it went and drop its rig into the sea.
func _update_falls(fallen: Array) -> void:
	for group: Array in fallen:
		for slot: int in group:
			if _fallen_seen.has(slot):
				continue
			_fallen_seen[slot] = true
			var at: Vector2 = _last_pos.get(slot, Vector2.ZERO)
			fx_splash(at)
			# A ring-out plunge (#728): the shared "gone" read.
			play_sfx(&"splash")
			request_shake(6.0)
			var rig := rig_for_slot(slot)
			if rig != null:
				rig.visible = false


func _update_coins() -> void:
	# Parent the pool onto the deck so coins tilt with it.
	sync_pool(_coin_nodes, coins.size(), _make_coin, _place_coin, _deck)


func _make_coin() -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.35
	mesh.bottom_radius = 0.35
	mesh.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COIN_COLOR
	mat.emission_enabled = true
	mat.emission = COIN_COLOR
	mat.emission_energy_multiplier = 0.35
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node


func _place_coin(node: Node3D, index: int) -> void:
	var coin: Array = coins[index]
	node.position = to_arena(Vector2(float(coin[0]), float(coin[1])), COIN_HEIGHT)


func _update_cargo() -> void:
	sync_pool(_cargo_nodes, cargo.size(), _make_cargo, _place_cargo, _deck)


func _make_cargo() -> Node3D:
	var crate := CRATE_SCENE.instantiate()
	# Find the mesh instance and duplicate its material for fade control.
	var mi := crate.get_child(0) as MeshInstance3D
	if mi != null:
		var mat := mi.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
		_cargo_materials.append(mat)
	return crate


func _place_cargo(node: Node3D, index: int) -> void:
	var crate: Array = cargo[index]
	node.position = to_arena(Vector2(float(crate[TiltDeck.CG_X]), float(crate[TiltDeck.CG_Y])), 0.7)
	# Fade out over the crate's remaining life so its lift-off telegraphs.
	var life := clampf(float(crate[TiltDeck.CG_LIFE]), 0.0, 1.0)
	_cargo_materials[index].albedo_color = Color(CARGO_COLOR, 0.35 + 0.65 * life)


func _vec(raw: Array) -> Vector2:
	if raw.size() < 2:
		return Vector2.ZERO
	return Vector2(float(raw[0]), float(raw[1]))
