extends MinigameView3D
## Hot Potato client view (M8-05): renders the replicated arena in the shared
## 2.5D iso-arena (M8-01, MinigameView3D) — players as CharacterRig instances,
## the carrier marked by a bomb hovering overhead that pulses faster as the
## fuse runs down (#211), eliminated players collapsed (ko) and dimmed gray.
## Presentation-tier swap only: state storage and the render contract are
## unchanged from the 2D pass (M4-02).

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

## Latest replicated state, straight from HotPotato.get_snapshot().
var players := {}
var carrier := -1
var fuse := 0.0
var alive: Array = []

var _bomb_node: MeshInstance3D
var _bomb_material: StandardMaterial3D
var _pulse_phase := 0.0
var _tick_accum := 0.0
var _downed := {}  # slot (int) -> true, once the ko pose + dim have been applied
# -1 = unseeded, so a mid-match rejoin does not shake on its first snapshot.
var _edges := EdgeTracker.new()
# Snapshot countdown to the next fuse spark (M13-04).
var _spark_left := 0.0


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
	_bomb_material.albedo_color = BOMB_COLOR.lerp(BOMB_ALERT_COLOR, urgency)
	_bomb_material.emission = _bomb_material.albedo_color
	_bomb_material.emission_energy_multiplier = lerpf(0.4, 2.5, pulse)
	_bomb_node.scale = Vector3.ONE * lerpf(1.0, 1.0 + 0.25 * pulse, urgency)
	if fuse < TICK_FUSE_SEC:
		_tick_accum += delta
		var interval := clampf(fuse / TICK_FUSE_SEC, 0.18, 1.0)
		if _tick_accum >= interval:
			_tick_accum = 0.0
			play_sfx(&"tick")


## Warm panicked-red floor for the passing bomb (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.82, 0.75)


func _arena_half() -> float:
	return HotPotato.ARENA_HALF


func _setup_3d() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = BOMB_RADIUS
	mesh.height = BOMB_RADIUS * 2.0
	_bomb_material = StandardMaterial3D.new()
	_bomb_material.albedo_color = BOMB_COLOR
	_bomb_material.emission_enabled = true
	_bomb_material.emission = BOMB_COLOR
	_bomb_material.emission_energy_multiplier = 0.5
	mesh.material = _bomb_material
	_bomb_node = MeshInstance3D.new()
	_bomb_node.name = "Bomb"
	_bomb_node.mesh = mesh
	_bomb_node.visible = false
	arena.add_child(_bomb_node)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	carrier = int(game.get("carrier", -1))
	fuse = float(game.get("fuse", 0.0))
	alive = game.get("alive", [])
	# The bomb going off is the game's big impact (M6-02): shake plus a blast
	# flash and sound where the eliminated carrier stood (#211). Diffed before
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
