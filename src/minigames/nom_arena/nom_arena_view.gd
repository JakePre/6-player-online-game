extends MinigameView3D
## Nom Arena client view (M14-10): the blob is the avatar, so the humanoid
## rigs are hidden and each player renders as a flat, player-colored disc
## scaled by its mass, with a name+mass label. Dense dots, the closing
## boundary ring, a lunge streak, an eaten-puff — and the #954 Power Pellet
## (pulsing MDL-017 model; the eater's disc glows gold, rivals tint
## frightened-blue with a fear icon). Renders get_snapshot() only.

const DISC_HEIGHT := 0.25
const DOT_COLOR := Color(0.95, 0.85, 0.4)
const RING_COLOR := Color(0.95, 0.35, 0.3, 0.7)
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

var players := {}

var _blobs := {}  # slot -> MeshInstance3D (scaled disc)
var _labels := {}  # slot -> Label3D
var _dot_pool: Array[MeshInstance3D] = []
var _ring: MeshInstance3D
var _pellet: Node3D
var _mass_seen := {}
var _lunge_seen := {}
var _my_frenzy_seen := false


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
	_build_dots()
	_build_ring()
	_pellet = PELLET_SCENE.instantiate() as Node3D
	_pellet.name = "PowerPellet"
	_pellet.visible = false
	arena.add_child(_pellet)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	var boundary := float(game.get("boundary", NomArena.ARENA_HALF))
	_update_ring(boundary)
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
	for i in NomArena.DOT_COUNT:
		var mesh := SphereMesh.new()
		mesh.radius = 0.18
		mesh.height = 0.36
		var material := StandardMaterial3D.new()
		material.albedo_color = DOT_COLOR
		material.emission_enabled = true
		material.emission = DOT_COLOR
		material.emission_energy_multiplier = 0.5
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.visible = false
		arena.add_child(node)
		_dot_pool.append(node)


func _build_ring() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.94
	mesh.outer_radius = 1.0
	var material := StandardMaterial3D.new()
	material.albedo_color = RING_COLOR
	material.emission_enabled = true
	material.emission = RING_COLOR
	material.emission_energy_multiplier = 0.8
	mesh.material = material
	_ring = MeshInstance3D.new()
	_ring.name = "Boundary"
	_ring.mesh = mesh
	arena.add_child(_ring)


func _update_ring(boundary: float) -> void:
	_ring.scale = Vector3(boundary, 1.0, boundary)
	_ring.position = to_arena(Vector2.ZERO, 0.05)


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
	_mass_seen[slot] = mass
	# Lunge onset sparkles.
	var lunging := int(state[NomArena.PS_LUNGING]) == 1
	if lunging and not bool(_lunge_seen.get(slot, false)):
		fx_sparkle(pos, LUNGE_COLOR, 0.4)
		# Signature cue (#728): heard only by the lunging player.
		if slot == my_slot:
			play_sfx(&"dash")
	_lunge_seen[slot] = lunging
