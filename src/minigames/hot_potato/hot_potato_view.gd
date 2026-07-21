extends MinigameView3D
## Hot Potato client view (M8-05): renders the replicated arena in the shared
## 2.5D iso-arena (M8-01, MinigameView3D) — players as CharacterRig instances,
## the carrier marked by a bomb hovering overhead that pulses faster as the
## fuse runs down (#211), eliminated players collapsed (ko) and dimmed gray.
## Presentation-tier swap only: state storage and the render contract are
## unchanged from the 2D pass (M4-02).
##
## GFX pass (#1138): bomb model is now the Kenney bomb.glb with a fuse ring
## (SAFE→HOT emission), ember-rock floor texture, rim rocks, dark smoke puff
## on each tick, and a panic vignette when the local player holds the bomb.

const ELIMINATED_COLOR := Color(0.42, 0.42, 0.46)
const BOMB_COLOR := Color(0.95, 0.55, 0.15)
const BOMB_ALERT_COLOR := Color(1.0, 0.2, 0.1)
const BOMB_RADIUS := 0.45
const BOMB_HEIGHT := 2.4
## Pulse/tick urgency ramp (#211): calm at a fresh fuse, frantic near zero.
const PULSE_HZ_MIN := 1.5
const PULSE_HZ_MAX := 9.0
const TICK_FUSE_SEC := 6.0
const BLAST_COLOR := Color(1.0, 0.6, 0.2, 0.9)
const BLAST_SEC := 0.45
## Tier 1 GFX (#1138): swap the primitive SphereMesh bomb for the Kenney
## platformer kit bomb model, plus a fuse ring for the emission pulse
## (Bomb Courier convention — don't repaint the shared model's materials).
const BOMB_SCENE := preload("res://assets/environment/kenney_platformer_kit/bomb.glb")
const BOMB_SCALE := 0.65
const FUSE_RING_INNER := 0.3
const FUSE_RING_OUTER := 0.45
## Tier 1 GFX (#1138): ember-rock floor texture for a hot-underfoot feel.
const EMBER_FLOOR := preload("res://assets/generated/textures/ember-rock.png")
## Tier 2 GFX (#1138): rim scenery — rocks around the arena perimeter.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_nature_kit/rock_smallA.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_smallB.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_tallA.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_tallB.glb"),
]
const RIM_PROP_COUNT := 16
const RIM_PROP_SEED := 0xB0B0
## Tier 2 GFX (#1138): dark smoke puff on each tick.
const SMOKE_COLOR := Color(0.25, 0.2, 0.18, 0.6)
const SMOKE_SEC := 0.5
## Tier 2 GFX (#1138): panic vignette max opacity when holding the bomb.
const VIGNETTE_MAX_ALPHA := 0.4

## Latest replicated state, straight from HotPotato.get_snapshot().
var players := {}
var carrier := -1
var fuse := 0.0
var alive: Array = []

var _bomb_node: Node3D
var _bomb_model: Node3D
var _fuse_ring_material: StandardMaterial3D
var _pulse_phase := 0.0
var _tick_accum := 0.0
var _downed := {}  # slot (int) -> true, once the ko pose + dim have been applied
# -1 = unseeded, so a mid-match rejoin does not shake on its first snapshot.
var _edges := EdgeTracker.new()
# Snapshot countdown to the next fuse spark (M13-04).
var _spark_left := 0.0
var _vignette: ColorRect


func _physics_process(_delta: float) -> void:
	send_move_intent()


## The bomb rides the carrier's interpolated rig (snapshot-rate positioning
## made it lag and jitter) and pulses color/scale at a fuse-driven rate, with
## an accelerating tick once the fuse enters its final seconds (#211).
func _process(delta: float) -> void:
	if _bomb_node == null or not _bomb_node.visible:
		return
	var rig := rig_for_slot(carrier)
	if rig != null:
		_bomb_node.position = Vector3(rig.position.x, BOMB_HEIGHT, rig.position.z)
	var urgency := 1.0 - clampf(fuse / HotPotato.FUSE_MAX_SEC, 0.0, 1.0)
	var hz := lerpf(PULSE_HZ_MIN, PULSE_HZ_MAX, urgency)
	_pulse_phase = fmod(_pulse_phase + delta * hz, 1.0)
	var pulse := 0.5 + 0.5 * sin(_pulse_phase * TAU)
	_fuse_ring_material.emission = BOMB_COLOR.lerp(BOMB_ALERT_COLOR, urgency)
	_fuse_ring_material.emission_energy_multiplier = lerpf(0.4, 2.5, pulse)
	_bomb_node.scale = Vector3.ONE * lerpf(1.0, 1.0 + 0.25 * pulse, urgency)
	if fuse < TICK_FUSE_SEC:
		_tick_accum += delta
		var interval := clampf(fuse / TICK_FUSE_SEC, 0.18, 1.0)
		if _tick_accum >= interval:
			_tick_accum = 0.0
			play_sfx(&"tick")
			_spawn_smoke_puff()
	_update_vignette(urgency)


## Warm panicked-red floor for the passing bomb (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.82, 0.75)


func _arena_half() -> float:
	return HotPotato.ARENA_HALF


## Ember-rock floor (#1138): override the default tiled floor with a single
## textured plane using the ember-rock texture, reinforcing the hot-underfoot
## tension.
func _build_floor() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(_arena_half() * 2.0, _arena_half() * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = EMBER_FLOOR
	material.albedo_color = Color(0.85, 0.75, 0.6)
	mesh.material = material
	var floor_node := MeshInstance3D.new()
	floor_node.name = "Floor"
	floor_node.mesh = mesh
	floor_node.position.y = -0.01
	arena.add_child(floor_node)


## Hot cavern mood (#1138): pushes the party-stadium shell toward a warm
## orange-brown atmosphere, matching the ember-rock floor.
func _mood() -> Color:
	return Color(0.3, 0.15, 0.1)


func _setup_3d() -> void:
	# Kenney bomb.glb model + a fuse ring for the emission pulse (#1138),
	# following Bomb Courier's convention: the ring carries the SAFE→HOT
	# color, leaving the shared model's materials untouched.
	_bomb_node = Node3D.new()
	_bomb_node.name = "Bomb"
	_bomb_node.visible = false
	_bomb_model = BOMB_SCENE.instantiate()
	_bomb_model.scale = Vector3.ONE * BOMB_SCALE
	_bomb_node.add_child(_bomb_model)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = FUSE_RING_INNER
	ring_mesh.outer_radius = FUSE_RING_OUTER
	_fuse_ring_material = StandardMaterial3D.new()
	_fuse_ring_material.emission_enabled = true
	_fuse_ring_material.emission = BOMB_COLOR
	ring_mesh.material = _fuse_ring_material
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.rotation.x = PI / 2.0
	ring.position.y = 0.05
	_bomb_node.add_child(ring)
	arena.add_child(_bomb_node)
	# Rim props (#1138): scatter rocks around the arena perimeter.
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)
	# Panic vignette (#1138): screen-edge red overlay when holding the bomb.
	_vignette = ColorRect.new()
	_vignette.name = "PanicVignette"
	_vignette.color = Color(1.0, 0.0, 0.0, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_vignette)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	carrier = int(game.get("carrier", -1))
	fuse = float(game.get("fuse", 0.0))
	alive = game.get("alive", [])
	# _update_players marks them downed.
	if _edges.fell(&"alive", alive.size()):
		request_shake(12.0)
		# A bomb going off is this vocabulary's textbook explosion (#728).
		play_sfx(&"explosion")
		for slot: int in players:
			if slot not in alive and not _downed.has(slot):
				var state: Array = players[slot]
				var at := Vector2(state[HotPotato.PS_X], state[HotPotato.PS_Y])
				_spawn_blast(at)
				# Debris + dust under the shockwave (M13-04).
				fx_burst(at, BLAST_COLOR, 1.0)
				fx_dust(at)
	_update_players()
	_update_bomb()
	_trail_sparks()


## The lit fuse sheds sparks over the carrier (M13-04), faster as it runs
## down - cadenced off snapshots so every client sees the same trail.
func _trail_sparks() -> void:
	var carrier_state: Array = players.get(carrier, [])
	if carrier not in alive or carrier_state.size() < HotPotato.PS_COUNT:
		return
	_spark_left -= SNAPSHOT_INTERVAL
	if _spark_left > 0.0:
		return
	var urgency := 1.0 - clampf(fuse / HotPotato.FUSE_MAX_SEC, 0.0, 1.0)
	_spark_left = lerpf(0.6, 0.2, urgency)
	fx_sparkle(
		Vector2(carrier_state[HotPotato.PS_X], carrier_state[HotPotato.PS_Y]),
		BOMB_COLOR,
		BOMB_HEIGHT
	)


## Expanding, fading orange shockwave sphere at the blast spot.
func _spawn_blast(world_pos: Vector2) -> void:
	if ArenaFX.reduced_motion:
		return
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = BLAST_COLOR
	mesh.material = material
	var blast := MeshInstance3D.new()
	blast.mesh = mesh
	blast.position = to_arena(world_pos, 0.8)
	arena.add_child(blast)
	var tween := blast.create_tween()
	tween.set_parallel(true)
	tween.tween_property(blast, "scale", Vector3.ONE * 4.0, BLAST_SEC)
	tween.tween_property(material, "albedo_color:a", 0.0, BLAST_SEC)
	tween.chain().tween_callback(blast.queue_free)


## Dark smoke puff on each fuse tick (#1138): a small SphereMesh that fades
## and expands in the bomb's current position, complementing the spark trail.
func _spawn_smoke_puff() -> void:
	if ArenaFX.reduced_motion:
		return
	var rig := rig_for_slot(carrier)
	if rig == null:
		return
	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = SMOKE_COLOR
	mesh.material = material
	var puff := MeshInstance3D.new()
	puff.mesh = mesh
	puff.position = Vector3(rig.position.x, BOMB_HEIGHT - 0.2, rig.position.z)
	arena.add_child(puff)
	var tween := puff.create_tween()
	tween.set_parallel(true)
	tween.tween_property(puff, "scale", Vector3.ONE * 2.0, SMOKE_SEC)
	tween.tween_property(material, "albedo_color:a", 0.0, SMOKE_SEC)
	tween.chain().tween_callback(puff.queue_free)


## Panic vignette (#1138): screen-edge red overlay that scales with fuse
## urgency when the local player holds the bomb. Fully transparent otherwise.
func _update_vignette(urgency: float) -> void:
	if _vignette == null:
		return
	if carrier == my_slot and carrier in alive:
		_vignette.color.a = urgency * VIGNETTE_MAX_ALPHA
		_vignette.visible = true
	else:
		_vignette.visible = false


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		if slot in alive:
			update_rig(slot, Vector2(state[HotPotato.PS_X], state[HotPotato.PS_Y]))
			var caption := player_name(slot)
			if slot == carrier:
				caption += "  %.1f" % fuse
			rig.display_name = caption
		else:
			_down_rig(slot, rig, Vector2(state[HotPotato.PS_X], state[HotPotato.PS_Y]))


## Eliminated players hold their last spot in the ko pose, dimmed gray; skip
## update_rig so its walk/idle logic never overrides the pose.
func _down_rig(slot: int, rig: CharacterRig, world_pos: Vector2) -> void:
	rig.position = to_arena(world_pos)
	if _downed.has(slot):
		return
	_downed[slot] = true
	rig.play(&"ko")
	rig.player_color = ELIMINATED_COLOR
	rig.display_name = player_name(slot)


func _update_bomb() -> void:
	var carrier_state: Array = players.get(carrier, [])
	_bomb_node.visible = carrier in alive and carrier_state.size() >= HotPotato.PS_COUNT
	if not _bomb_node.visible:
		return
	_bomb_node.position = to_arena(
		Vector2(carrier_state[HotPotato.PS_X], carrier_state[HotPotato.PS_Y]), BOMB_HEIGHT
	)
