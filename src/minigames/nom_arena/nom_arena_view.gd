extends MinigameView3D
## Nom Arena client view (M14-10): the blob is the avatar, so the humanoid
## rigs are hidden and each player renders as a flat, player-colored disc
## scaled by its mass, with a name+mass label. Dense dots (Kenney Food Kit
## models — the single biggest visual upgrade in the repo), the closing
## seeded maze walls (#1027), a lunge streak, an eaten-puff — and the #954 Power Pellet
## (pulsing MDL-017 model; the eater's disc glows gold, rivals tint
## frightened-blue with a fear icon), plus an eating-particle burst, a food trail
## behind moving blobs, and food-themed rim props. Renders get_snapshot() only.

const DISC_HEIGHT := 0.25
const DOT_COLOR := Color(0.95, 0.85, 0.4)
const WALL_COLOR := Color(0.25, 0.3, 0.75)
const WALL_HEIGHT := 0.9
const LUNGE_COLOR := Color(1.0, 1.0, 1.0, 0.8)
## Power Pellet (#954): the landed MDL-017 model ("unmistakably the special
## one"); its ledger contract says the view pulses scale/emission — done in
## _process, steady under reduced motion.
const PELLET_SCENE := preload("res://assets/generated/models/power-pellet.glb")
const PELLET_PULSE_SEC := 1.1
const PELLET_PULSE_AMOUNT := 0.14
## Frenzy (#954): the eater's disc glows gold; every rival tints
## frightened-blue AND gets the fear icon in its label — the icon carries the
## meaning alone for colorblind players, per the design.
const FRENZY_GLOW_COLOR := Color(1.0, 0.85, 0.3)
const FRIGHTENED_COLOR := Color(0.35, 0.5, 0.95)
const FEAR_ICON := "😱"
## Food model dot pool (#1145): Kenney Food Kit models for the 42 dots.
const FOOD_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_food_kit/apple.glb"),
	preload("res://assets/environment/kenney_food_kit/banana.glb"),
	preload("res://assets/environment/kenney_food_kit/bread.glb"),
	preload("res://assets/environment/kenney_food_kit/broccoli.glb"),
	preload("res://assets/environment/kenney_food_kit/carrot.glb"),
	preload("res://assets/environment/kenney_food_kit/cheese.glb"),
	preload("res://assets/environment/kenney_food_kit/cherries.glb"),
	preload("res://assets/environment/kenney_food_kit/cookie.glb"),
	preload("res://assets/environment/kenney_food_kit/croissant.glb"),
	preload("res://assets/environment/kenney_food_kit/donut.glb"),
	preload("res://assets/environment/kenney_food_kit/egg.glb"),
	preload("res://assets/environment/kenney_food_kit/grapes.glb"),
	preload("res://assets/environment/kenney_food_kit/lemon.glb"),
	preload("res://assets/environment/kenney_food_kit/muffin.glb"),
	preload("res://assets/environment/kenney_food_kit/orange.glb"),
	preload("res://assets/environment/kenney_food_kit/pancakes.glb"),
	preload("res://assets/environment/kenney_food_kit/strawberry.glb"),
	preload("res://assets/environment/kenney_food_kit/taco.glb"),
	preload("res://assets/environment/kenney_food_kit/waffle.glb"),
	preload("res://assets/environment/kenney_food_kit/watermelon.glb"),
]
## Food trail (#1145): how many trailing particles per blob, how far apart.
const TRAIL_COUNT := 3
const TRAIL_SPACING := 0.5
const TRAIL_ALPHA := 0.35
## Eating burst (#1145): mass increase threshold that triggers a food-crumb burst.
const EAT_MASS_THRESHOLD := 0.4
## Rim props (#1145): food-themed decorations around the arena perimeter.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_food_kit/bowl.glb"),
	preload("res://assets/environment/kenney_food_kit/plate-dinner.glb"),
	preload("res://assets/environment/kenney_food_kit/plate-deep.glb"),
	preload("res://assets/environment/kenney_food_kit/cup.glb"),
	preload("res://assets/environment/kenney_food_kit/glass.glb"),
	preload("res://assets/environment/kenney_food_kit/soda-can.glb"),
	preload("res://assets/environment/kenney_food_kit/bottle-ketchup.glb"),
	preload("res://assets/environment/kenney_food_kit/barrel.glb"),
	preload("res://assets/environment/kenney_food_kit/can.glb"),
	preload("res://assets/environment/kenney_food_kit/utensil-fork.glb"),
	preload("res://assets/environment/kenney_food_kit/utensil-knife.glb"),
	preload("res://assets/environment/kenney_food_kit/utensil-spoon.glb"),
]
const RIM_PROP_COUNT := 20
const RIM_PROP_SEED := 1145
## Food-crumb burst (#1145): small colored spheres used as "crumbs" on eat.
const CRUMB_COUNT := 8
const CRUMB_SPEED := 3.0
const CRUMB_LIFETIME := 0.6
const CRUMB_SIZE := 0.08

var players := {}

var _blobs := {}  # slot -> MeshInstance3D (scaled disc)
var _labels := {}  # slot -> Label3D
var _dot_pool: Array[Node3D] = []
var _walls_built := false
var _pellet: Node3D
var _mass_seen := {}
var _lunge_seen := {}
var _my_frenzy_seen := false
## Food trail (#1145): slot -> [Vector2, ...] previous positions for trail.
var _trail_positions := {}
## Food trail (#1145): slot -> [Node3D, ...] trail particle nodes.
var _trail_particles := {}
## RNG for random food model selection per dot.
var _rng := RandomNumberGenerator.new()


func _physics_process(_delta: float) -> void:
	send_move_intent()
	if Input.is_action_just_pressed(&"action_primary"):
		# Carry the current heading with the lunge (#783) so the sim aims it along
		# where you're steering, not a default direction.
		var dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		NetManager.send_match_input({"lunge": true, "mx": dir.x, "my": dir.y})


## Warm food-yellow floor (#589).
func _floor_tint() -> Color:
	return Color(0.98, 0.96, 0.78)


func _arena_half() -> float:
	return NomArena.ARENA_HALF + 1.0


func _setup_3d() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig != null:
			rig.visible = false  # the blob is the avatar
		_blobs[slot] = _build_blob(slot)
		_labels[slot] = _build_label()
		# Food trail (#1145): init empty position and particle arrays per slot.
		_trail_positions[slot] = []
		_trail_particles[slot] = []
	_build_dots()
	_pellet = PELLET_SCENE.instantiate() as Node3D
	_pellet.name = "PowerPellet"
	_pellet.visible = false
	arena.add_child(_pellet)
	# Rim props (#1145): food-themed bowls, plates, utensils around the perimeter.
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	if not _walls_built and game.has("walls"):
		_build_walls(game.walls)
	_update_dots(game.get("dots", []))
	_update_pellet(game.get("pellet", []))
	# One pass to learn whether anyone is frenzied, so every OTHER blob can
	# wear the frightened treatment.
	var frenzied_slot := -1
	for slot: int in players:
		if _frenzy_of(slot) > 0.0:
			frenzied_slot = slot
			break
	for slot: int in players:
		_update_blob(slot, frenzied_slot)
	# Signature cue (#728): heard only by the player whose frenzy just began.
	var my_frenzied := _frenzy_of(my_slot) > 0.0 if players.has(my_slot) else false
	if my_frenzied and not _my_frenzy_seen:
		play_sfx(&"powerup")
	_my_frenzy_seen = my_frenzied


## Guarded read: rows without the #954 slot (old snapshots) mean "not frenzied".
func _frenzy_of(slot: int) -> float:
	var state: Array = players.get(slot, [])
	if state.size() <= NomArena.PS_FRENZY:
		return 0.0
	return float(state[NomArena.PS_FRENZY])


func _update_pellet(pellet: Array) -> void:
	_pellet.visible = pellet.size() == 2
	if _pellet.visible:
		_pellet.position = to_arena(Vector2(float(pellet[0]), float(pellet[1])), 0.0)


## The MDL-017 ledger contract: the view pulses the pellet's scale. Steady
## under reduced motion (M13 telegraph convention).
func _process(_delta: float) -> void:
	if _pellet == null or not _pellet.visible or ArenaFX.reduced_motion:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 1.0 + PELLET_PULSE_AMOUNT * sin(TAU * t / PELLET_PULSE_SEC)
	_pellet.scale = Vector3.ONE * pulse


func _build_blob(slot: int) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = DISC_HEIGHT
	var material := StandardMaterial3D.new()
	material.albedo_color = player_color(slot)
	material.emission_enabled = true
	material.emission = player_color(slot)
	material.emission_energy_multiplier = 0.25
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "Blob%d" % slot
	node.mesh = mesh
	arena.add_child(node)
	return node


func _build_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	# STYLE_GUIDE Label3D rule: pixel_size stays fixed, apparent size comes from
	# font_size (#783 "player names too big" is handled by font_size, not pixel_size).
	label.pixel_size = 0.002
	label.font_size = 44
	label.outline_size = 12
	label.modulate = Color.WHITE
	arena.add_child(label)
	return label


func _build_dots() -> void:
	_rng.randomize()
	for i in NomArena.DOT_COUNT:
		var scene := FOOD_SCENES[_rng.randi() % FOOD_SCENES.size()]
		var node := scene.instantiate() as Node3D
		if node == null:
			continue
		# Scale food models to match the ~0.36u sphere size.
		node.scale = Vector3.ONE * 0.35
		node.visible = false
		arena.add_child(node)
		_dot_pool.append(node)


## The seeded maze (#1027), built from the first snapshot that carries it —
## Pac-Man-blue box walls matching the sim's geometry exactly.
func _build_walls(wall_list: Array) -> void:
	_walls_built = true
	var material := StandardMaterial3D.new()
	material.albedo_color = WALL_COLOR
	material.emission_enabled = true
	material.emission = WALL_COLOR
	material.emission_energy_multiplier = 0.3
	for wall: Array in wall_list:
		if wall.size() < 4:
			continue
		var mesh := BoxMesh.new()
		mesh.size = Vector3(float(wall[2]) * 2.0, WALL_HEIGHT, float(wall[3]) * 2.0)
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = to_arena(Vector2(float(wall[0]), float(wall[1])), WALL_HEIGHT / 2.0)
		arena.add_child(node)


func _update_dots(dot_list: Array) -> void:
	for i in _dot_pool.size():
		var node := _dot_pool[i]
		if i < dot_list.size():
			var dot: Array = dot_list[i]
			node.position = to_arena(
				Vector2(float(dot[NomArena.DT_X]), float(dot[NomArena.DT_Y])), 0.18
			)
			node.visible = true
		else:
			node.visible = false


func _update_blob(slot: int, frenzied_slot: int) -> void:
	var state: Array = players[slot]
	var mass := float(state[NomArena.PS_MASS])
	var radius := sqrt(mass) * NomArena.RADIUS_K
	var pos := Vector2(float(state[NomArena.PS_X]), float(state[NomArena.PS_Y]))
	var blob: MeshInstance3D = _blobs[slot]
	blob.position = to_arena(pos, DISC_HEIGHT * 0.5)
	blob.scale = Vector3(radius, 1.0, radius)
	# Frenzy dressing (#954): the frenzied disc glows gold; everyone else
	# tints frightened-blue while a frenzy is live. Identity comes back the
	# moment it ends (materials are per-blob, built in _build_blob).
	var material := (blob.mesh as CylinderMesh).material as StandardMaterial3D
	var frightened := frenzied_slot != -1 and slot != frenzied_slot
	if slot == frenzied_slot:
		material.albedo_color = player_color(slot)
		material.emission = FRENZY_GLOW_COLOR
		material.emission_energy_multiplier = 1.4
	elif frightened:
		material.albedo_color = FRIGHTENED_COLOR
		material.emission = FRIGHTENED_COLOR
		material.emission_energy_multiplier = 0.25
	else:
		material.albedo_color = player_color(slot)
		material.emission = player_color(slot)
		material.emission_energy_multiplier = 0.25
	var label: Label3D = _labels[slot]
	var prefix := FEAR_ICON + " " if frightened else ""
	label.text = "%s%s  %d" % [prefix, player_name(slot), roundi(mass)]
	label.position = to_arena(pos, 1.0 + radius * 0.2)
	# A sharp mass drop means this blob was just swallowed and respawned small.
	var last_mass := float(_mass_seen.get(slot, mass))
	if mass < last_mass * 0.6:
		fx_burst(pos, player_color(slot), 0.5)
		request_shake(3.0)
		# Signature cue (#728): heard only by the swallowed blob.
		if slot == my_slot:
			play_sfx(&"powerdown")
	# Eating particle effect (#1145): a sharp mass increase means this blob
	# just ate another blob or a dot — spawn a food-crumb burst.
	if mass > last_mass + EAT_MASS_THRESHOLD:
		_spawn_crumb_burst(pos, player_color(slot))
	_mass_seen[slot] = mass
	# Lunge onset sparkles.
	var lunging := int(state[NomArena.PS_LUNGING]) == 1
	if lunging and not bool(_lunge_seen.get(slot, false)):
		fx_sparkle(pos, LUNGE_COLOR, 0.4)
		# Signature cue (#728): heard only by the lunging player.
		if slot == my_slot:
			play_sfx(&"dash")
	_lunge_seen[slot] = lunging
	# Food trail (#1145): track position history and spawn trail particles.
	_update_trail(slot, pos, radius)


## Food-crumb burst (#1145): spawn CRUMB_COUNT small colored spheres that fly
## outward from the eating position, fading and shrinking over CRUMB_LIFETIME.
func _spawn_crumb_burst(pos: Vector2, color: Color) -> void:
	if ArenaFX.reduced_motion:
		return
	for i in CRUMB_COUNT:
		var mesh := SphereMesh.new()
		mesh.radius = CRUMB_SIZE
		mesh.height = CRUMB_SIZE * 2.0
		var material := StandardMaterial3D.new()
		var crumb_color := Color(
			color.r * (0.6 + randf() * 0.4),
			color.g * (0.6 + randf() * 0.4),
			color.b * (0.6 + randf() * 0.4),
			1.0
		)
		material.albedo_color = crumb_color
		material.emission_enabled = true
		material.emission = crumb_color
		material.emission_energy_multiplier = 0.5
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		var angle := randf() * TAU
		var speed := CRUMB_SPEED * (0.5 + randf() * 0.5)
		var velocity := Vector3(cos(angle), 0.5, sin(angle)) * speed
		node.position = to_arena(pos, 0.3)
		arena.add_child(node)
		# Tween the crumb: fly outward, fade, shrink, then free.
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(node, "position", node.position + velocity, CRUMB_LIFETIME)
		tween.tween_property(node, "scale", Vector3.ZERO, CRUMB_LIFETIME)
		tween.tween_property(
			node.mesh.material,
			"albedo_color",
			Color(crumb_color.r, crumb_color.g, crumb_color.b, 0.0),
			CRUMB_LIFETIME
		)
		tween.finished.connect(node.queue_free)


## Food trail (#1145): maintain TRAIL_COUNT small particles behind each moving
## blob. A new trail particle spawns when the blob has moved TRAIL_SPACING from
## the last recorded position.
func _update_trail(slot: int, pos: Vector2, radius: float) -> void:
	if ArenaFX.reduced_motion:
		return
	var positions: Array = _trail_positions.get(slot, [])
	positions.append(pos)
	# Only keep one position beyond TRAIL_COUNT so we can detect new movement.
	if positions.size() > TRAIL_COUNT + 1:
		positions.pop_front()
	_trail_positions[slot] = positions
	# Check if we have enough history and the blob moved enough to spawn a trail.
	if positions.size() < 2:
		return
	var prev := positions[-2] as Vector2
	if prev.distance_to(pos) < TRAIL_SPACING:
		return
	# Spawn a trail particle at the previous position.
	var particles: Array = _trail_particles.get(slot, [])
	var trail := _build_trail_particle(slot, prev, radius)
	particles.append(trail)
	# Garbage-collect old trail particles beyond TRAIL_COUNT.
	while particles.size() > TRAIL_COUNT:
		var old := particles.pop_front() as Node3D
		if is_instance_valid(old):
			old.queue_free()
	_trail_particles[slot] = particles


## A single trail particle: a small semi-transparent sphere at the given
## position, which fades out over ~0.5 s.
func _build_trail_particle(slot: int, pos: Vector2, radius: float) -> Node3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	var material := StandardMaterial3D.new()
	var color := player_color(slot)
	color.a = TRAIL_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = player_color(slot)
	material.emission_energy_multiplier = 0.6
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = to_arena(pos, 0.1)
	arena.add_child(node)
	# Fade out and free.
	var tween := create_tween()
	tween.tween_property(
		node.mesh.material, "albedo_color", Color(color.r, color.g, color.b, 0.0), 0.5
	)
	tween.finished.connect(node.queue_free)
	return node
