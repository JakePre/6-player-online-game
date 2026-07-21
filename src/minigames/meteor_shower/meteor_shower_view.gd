extends MinigameView3D
## Meteor Shower client view (M10-01 + M13-07 FX): renders the replicated
## arena in the shared 2.5D iso-arena — players as CharacterRigs (knocked-out
## players collapse and dim where the meteor caught them), the safe zone as a
## physical grass platform that sheds a band per shrink stage (#918, Gauntlet
## pattern — outside is gone, not a faint ring; the doomed band reddens for
## SHRINK_WARN_SEC first, #583), telegraphed impact points as red discs that
## grow to full impact size as the meteor closes in — and the meteors
## themselves: rocks with emissive trails streaking down from the sky, their
## height driven by the replicated time-left so the fall is perfectly synced
## with the sim. Landings fire an impact burst + dust; knockdowns burst at
## the rig. Impacts shake the screen.
##
## GFX pass (#1146): ember-rock floor texture, ash particles, lava glow ring,
## camera flash on impact, and pooled crater decals at landing positions.

const ZONE_DISC_HEIGHT := 0.04
## Physical safe-zone platform (#918): keeps the #813 open-grass-field feel as
## a shrinking grass island — its top seats at y=0 so every existing height
## (discs, rigs, meteors) is unchanged. Crumble dust rings the rim it sheds.
const PLATFORM_THICKNESS := 0.4
const PLATFORM_COLOR := Color(0.47, 0.72, 0.36)
## Ember-rock floor texture (#1146): volcanic rock with glowing orange cracks,
## matching the "hot doom from above" theme. UV-scaled to tile naturally on
## the shrinking cylinder platform.
const EMBER_FLOOR := preload("res://assets/generated/textures/ember-rock.png")
const CRUMBLE_PUFFS := 6
## Shrink telegraph (#583, Gauntlet convention): the band about to shed
## reddens as the countdown closes; slow pulse, steady under reduced motion.
const SHRINK_TELEGRAPH_COLOR := Color(0.9, 0.2, 0.15)
const SHRINK_TELEGRAPH_MIN_ALPHA := 0.35
const SHRINK_TELEGRAPH_MAX_ALPHA := 0.85
const SHRINK_TELEGRAPH_PULSE_SEC := 0.6
const TELEGRAPH_COLOR := Color(0.9, 0.2, 0.12, 0.5)
const TELEGRAPH_POOL := 12
const ELIMINATED_COLOR := Color(0.42, 0.42, 0.46)
## Falling rocks (M13-07): spawn height and look. The rock itself is the
## MDL-009 generated meteor (#918) — scorched crust, painted-on lava
## fissures; the emissive trail still carries the glow.
const METEOR_SCENE := preload("res://assets/generated/models/meteor.glb")
const METEOR_DROP_HEIGHT := 14.0
const METEOR_TRAIL_COLOR := Color(1.0, 0.55, 0.15, 0.7)
## Ash particle system (#1146): gentle falling ash throughout the match,
## building the volcanic atmosphere. Dark grey quads, slow descent.
const ASH_COLOR := Color(0.35, 0.33, 0.3, 0.25)
const ASH_AMOUNT := 40
const ASH_FALL_SPEED := 1.2
const ASH_LIFETIME := 6.0
## Lava glow ring (#1146): a warm orange-red glow from below the platform rim,
## giving the safe zone a volcanic underlight and reinforcing "danger below."
const LAVA_GLOW_COLOR := Color(0.9, 0.25, 0.08, 0.18)
## Screen flash (#1146): brief white alpha overlay on meteor impact, adding
## visceral punch to the "hot doom from above" feel.
const FLASH_COLOR := Color(1.0, 0.95, 0.85, 0.35)
const FLASH_DECAY_SEC := 0.25
## Crater decal pool size (#1146): dark scorched discs left where meteors land,
## fading over several seconds so the battlefield tells a story.
const CRATER_POOL := 20
const CRATER_FADE_SEC := 6.0
const CRATER_COLOR := Color(0.15, 0.1, 0.06, 0.6)
const IMPACT_BURST_COLOR := Color(1.0, 0.5, 0.1)

## Latest replicated state, straight from MeteorShower.get_snapshot().
var players := {}
var zone: Array = []
var meteors: Array = []
var fallen: Array = []

var _platform: MeshInstance3D
var _platform_mesh: CylinderMesh
var _last_radius := 0.0
var _shrink_in := MeteorShower.SHRINK_STAGE_SEC
var _shrink_telegraph: MeshInstance3D
var _shrink_telegraph_mesh: TorusMesh
var _shrink_telegraph_mat: StandardMaterial3D
var _shrink_base_alpha := SHRINK_TELEGRAPH_MIN_ALPHA
var _telegraph_pool: Array[MeshInstance3D] = []
var _meteor_pool: Array[Node3D] = []
var _ash_particles: CPUParticles3D
var _lava_glow: MeshInstance3D
var _lava_glow_mesh: TorusMesh
var _flash_overlay: ColorRect
var _flash_alpha := 0.0
var _crater_pool: Array[MeshInstance3D] = []
var _active_craters: Array[Dictionary] = []
# [x, y, left] rows from the previous snapshot, to spot landings.
var _meteors_seen: Array = []
var _downed := {}  # slot (int) -> true, once the ko pose + dim have been applied
## Rejoin-quiet rising edge on the fallen count (#941): the first snapshot
## seeds and never shakes.
var _edges := EdgeTracker.new()


func _physics_process(_delta: float) -> void:
	send_move_intent()


## The floor IS the safe zone now (#918): a grass island that sheds a band per
## shrink stage, replacing the #813 square field + faint ring. Now textured
## with ember-rock and ringed by a lava glow (#1146). Own floor, no tiled base
## (the thin_ice/memory_match pattern; no super call).
func _build_floor() -> void:
	var start_radius := MinigameScaling.arena_half(MeteorShower.ZONE_START_RADIUS, names.size())
	_last_radius = start_radius
	_platform_mesh = CylinderMesh.new()
	_platform_mesh.height = PLATFORM_THICKNESS
	_platform_mesh.top_radius = start_radius
	_platform_mesh.bottom_radius = start_radius
	var material := StandardMaterial3D.new()
	material.albedo_texture = EMBER_FLOOR
	material.albedo_color = Color(0.85, 0.7, 0.55)
	material.uv1_scale = Vector3(3.0, 3.0, 1.0)
	_platform_mesh.material = material
	_platform = MeshInstance3D.new()
	_platform.name = "ZonePlatform"
	_platform.mesh = _platform_mesh
	# Top seats at y=0, like the tiled floor it replaces.
	_platform.position = Vector3(0.0, -PLATFORM_THICKNESS / 2.0, 0.0)
	arena.add_child(_platform)

	# Lava glow ring below the platform bottom (#1146).
	_lava_glow_mesh = TorusMesh.new()
	_lava_glow_mesh.inner_radius = start_radius * 0.85
	_lava_glow_mesh.outer_radius = start_radius * 1.02
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.albedo_color = LAVA_GLOW_COLOR
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(LAVA_GLOW_COLOR, 1.0)
	glow_mat.emission_energy_multiplier = 2.0
	_lava_glow_mesh.material = glow_mat
	_lava_glow = MeshInstance3D.new()
	_lava_glow.name = "LavaGlow"
	_lava_glow.mesh = _lava_glow_mesh
	# Just below the platform's bottom face.
	_lava_glow.position = Vector3(0.0, -PLATFORM_THICKNESS - 0.05, 0.0)
	arena.add_child(_lava_glow)

	_shrink_telegraph_mesh = TorusMesh.new()
	_shrink_telegraph_mesh.inner_radius = maxf(start_radius - 0.1, 0.05)
	_shrink_telegraph_mesh.outer_radius = start_radius
	_shrink_telegraph_mat = StandardMaterial3D.new()
	_shrink_telegraph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shrink_telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shrink_telegraph_mat.albedo_color = SHRINK_TELEGRAPH_COLOR
	_shrink_telegraph_mat.emission_enabled = true
	_shrink_telegraph_mat.emission = SHRINK_TELEGRAPH_COLOR
	_shrink_telegraph_mesh.material = _shrink_telegraph_mat
	_shrink_telegraph = MeshInstance3D.new()
	_shrink_telegraph.name = "ShrinkTelegraph"
	_shrink_telegraph.mesh = _shrink_telegraph_mesh
	# TorusMesh is already flat (axis Y) — no rotation, per the #693 lesson.
	_shrink_telegraph.position = Vector3(0.0, 0.03, 0.0)
	_shrink_telegraph.visible = false
	arena.add_child(_shrink_telegraph)


func _arena_half() -> float:
	# Sim and view derive the same play size from the lobby count via the
	# shared base const, so the rendered floor/camera match the scaled arena.
	return MinigameScaling.arena_half(MeteorShower.ARENA_HALF, names.size())


## Warm-dark volcanic mood (#1146): pushes the party-stadium shell toward a
## hot-orange atmosphere, matching the ember-rock floor and meteor theme.
func _mood() -> Color:
	return Color(0.3, 0.15, 0.1)


func _setup_3d() -> void:
	for i in TELEGRAPH_POOL:
		var marker := _build_disc("Telegraph%d" % i, TELEGRAPH_COLOR)
		marker.visible = false
		_telegraph_pool.append(marker)
		_meteor_pool.append(_build_meteor(i))

	# Ash particle system (#1146): gentle falling ash throughout the match.
	_ash_particles = CPUParticles3D.new()
	_ash_particles.name = "AshParticles"
	_ash_particles.one_shot = false
	_ash_particles.emitting = false
	_ash_particles.amount = ASH_AMOUNT
	_ash_particles.lifetime = ASH_LIFETIME
	_ash_particles.color = ASH_COLOR
	_ash_particles.direction = Vector3.DOWN
	_ash_particles.spread = 45.0
	_ash_particles.gravity = Vector3(0.0, -ASH_FALL_SPEED, 0.0)
	_ash_particles.initial_velocity_min = 0.3
	_ash_particles.initial_velocity_max = 0.6
	_ash_particles.scale_amount_min = 0.5
	_ash_particles.scale_amount_max = 1.5
	_ash_particles.orbit_velocity = 0.2
	var ash_mesh := QuadMesh.new()
	ash_mesh.size = Vector2(0.08, 0.08)
	_ash_particles.mesh = ash_mesh
	# Emit from a wide disc above the arena.
	_ash_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_ash_particles.emission_sphere_radius = _arena_half() * 1.2
	_ash_particles.position.y = _arena_half() * 0.6
	arena.add_child(_ash_particles)

	# Camera flash overlay (#1146): full-rect ColorRect, initially transparent.
	_flash_overlay = ColorRect.new()
	_flash_overlay.name = "ImpactFlash"
	_flash_overlay.color = Color(FLASH_COLOR, 0.0)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash_overlay)

	# Crater decal pool (#1146): pre-build dark discs for reuse.
	for i in CRATER_POOL:
		var disc := _build_disc("Crater%d" % i, CRATER_COLOR)
		disc.visible = false
		_crater_pool.append(disc)


## A falling rock: the MDL-009 meteor model with a stretched emissive trail
## above it.
func _build_meteor(index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Meteor%d" % index
	# The GLB pivot is at its base — wrap it in a spinner with the model
	# offset down by half its height, so the tumble spins about the visual
	# center (like the old centered sphere) instead of wobbling on the base.
	var rock := Node3D.new()
	rock.name = "Rock"
	var model := METEOR_SCENE.instantiate() as Node3D
	model.position.y = -0.62
	rock.add_child(model)
	root.add_child(rock)
	var trail := MeshInstance3D.new()
	trail.name = "Trail"
	var trail_mesh := CylinderMesh.new()
	trail_mesh.top_radius = 0.05
	trail_mesh.bottom_radius = 0.3
	trail_mesh.height = 3.0
	var trail_material := StandardMaterial3D.new()
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.albedo_color = METEOR_TRAIL_COLOR
	trail_material.emission_enabled = true
	trail_material.emission = Color(METEOR_TRAIL_COLOR, 1.0)
	trail_material.emission_energy_multiplier = 1.0
	trail_mesh.material = trail_material
	trail.mesh = trail_mesh
	trail.position.y = 1.8
	root.add_child(trail)
	root.visible = false
	arena.add_child(root)
	return root


func _build_disc(disc_name: String, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = ZONE_DISC_HEIGHT
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color, 1.0)
	material.emission_energy_multiplier = 0.3
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = disc_name
	node.mesh = mesh
	arena.add_child(node)
	return node


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	zone = game.get("zone", [])
	_shrink_in = float(game.get("shrink_in", MeteorShower.SHRINK_STAGE_SEC))
	meteors = game.get("meteors", [])
	fallen = game.get("fallen", [])
	_update_players()
	_update_platform()
	_update_shrink_telegraph()
	_update_telegraphs()
	_update_falling_meteors()
	_burst_on_landings()
	_shake_on_new_downs()
	# Start ash emission once the match is running.
	if not _ash_particles.emitting:
		_ash_particles.emitting = true


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[MeteorShower.PS_X], state[MeteorShower.PS_Y]))
	for group: Array in fallen:
		for slot: int in group:
			_down_rig(slot)


## Knocked-out players collapse and dim where the meteor (or the zone edge)
## caught them; the snapshot stops carrying their position. The hit itself
## bursts at the rig (M13-07).
func _down_rig(slot: int) -> void:
	if _downed.has(slot):
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	_downed[slot] = true
	rig.play(&"ko")
	rig.player_color = ELIMINATED_COLOR
	fx_burst(Vector2(rig.position.x, rig.position.z), IMPACT_BURST_COLOR)


## The rocks themselves (M13-07): height rides the replicated time-left, so
## every client sees the same fall the sim is timing.
func _update_falling_meteors() -> void:
	for i in _meteor_pool.size():
		var rock := _meteor_pool[i]
		rock.visible = i < meteors.size()
		if not rock.visible:
			continue
		var state: Array = meteors[i]
		var progress := clampf(
			float(state[MeteorShower.MT_LEFT]) / MeteorShower.METEOR_TELEGRAPH_SEC, 0.0, 1.0
		)
		rock.position = to_arena(
			Vector2(state[MeteorShower.MT_X], state[MeteorShower.MT_Y]),
			METEOR_DROP_HEIGHT * progress + 0.5
		)
		# Tumble driven by the replicated timer (not per-frame accumulation),
		# so every client sees the same spin and rejoin stays deterministic.
		var body := rock.get_node("Rock") as Node3D
		body.rotation = Vector3(progress * 5.0, float(i) * 1.3, progress * 2.0)


## A meteor that left the snapshot with its timer nearly spent just landed:
## impact burst + dust + screen flash + crater decal at its last position.
func _burst_on_landings() -> void:
	for old: Array in _meteors_seen:
		if float(old[MeteorShower.MT_LEFT]) > 0.2:
			continue
		var still_falling := false
		for current: Array in meteors:
			if (
				absf(float(current[MeteorShower.MT_X]) - float(old[MeteorShower.MT_X])) < 0.01
				and absf(float(current[MeteorShower.MT_Y]) - float(old[MeteorShower.MT_Y])) < 0.01
			):
				still_falling = true
				break
		if not still_falling:
			var at := Vector2(float(old[MeteorShower.MT_X]), float(old[MeteorShower.MT_Y]))
			fx_burst(at, IMPACT_BURST_COLOR)
			fx_dust(at)
			# Camera flash (#1146): brief white overlay.
			_flash_alpha = FLASH_COLOR.a
			# Crater decal (#1146): place a dark disc at the impact point.
			_place_crater(at)
			# Signature cue (#728, docs/AUDIO_GUIDE.md — Bombs & blasts): a
			# heavy object landing — the vocabulary's literal meteor example.
			play_sfx(&"thud")
	_meteors_seen = meteors.duplicate(true)


## Place a dark scorched disc at `world_pos` that fades over CRATER_FADE_SEC.
func _place_crater(world_pos: Vector2) -> void:
	# Reuse a pooled disc or skip if the pool is exhausted.
	var disc: MeshInstance3D = _crater_pool.pop_front()
	if disc == null:
		return
	disc.visible = true
	disc.position = to_arena(world_pos, ZONE_DISC_HEIGHT * 0.5)
	disc.scale = Vector3(MeteorShower.METEOR_RADIUS * 2.0, 1.0, MeteorShower.METEOR_RADIUS * 2.0)
	# Return to back of pool for fade tracking.
	_crater_pool.append(disc)
	_active_craters.append({"disc": disc, "alpha": 1.0})


## The platform tracks the replicated zone radius; each stage shed crumbles
## dust off the rim it just lost. The lava glow ring follows the radius.
func _update_platform() -> void:
	if zone.size() != MeteorShower.ZN_COUNT:
		return
	var radius := maxf(float(zone[MeteorShower.ZN_RADIUS]), 0.001)
	_platform_mesh.top_radius = radius
	_platform_mesh.bottom_radius = radius
	# Lava glow tracks the platform rim (#1146).
	_lava_glow_mesh.inner_radius = radius * 0.85
	_lava_glow_mesh.outer_radius = radius * 1.02
	if radius < _last_radius - 0.01:
		for k in CRUMBLE_PUFFS:
			var angle := TAU * k / CRUMBLE_PUFFS
			fx_dust(Vector2(cos(angle), sin(angle)) * _last_radius)
	_last_radius = radius


## #583 band telegraph: the strip between the current rim and the next stage's
## radius reddens for SHRINK_WARN_SEC before it sheds, alpha rising with
## urgency (steady under reduced motion; _process adds the pulse otherwise).
func _update_shrink_telegraph() -> void:
	if _shrink_telegraph == null or zone.size() != MeteorShower.ZN_COUNT:
		return
	var radius := float(zone[MeteorShower.ZN_RADIUS])
	var zone_min := MinigameScaling.arena_half(MeteorShower.ZONE_MIN_RADIUS, names.size())
	var zone_start := MinigameScaling.arena_half(MeteorShower.ZONE_START_RADIUS, names.size())
	var doomed := radius > zone_min + 0.01 and _shrink_in <= MeteorShower.SHRINK_WARN_SEC
	_shrink_telegraph.visible = doomed
	if not doomed:
		return
	var step := (zone_start - zone_min) / float(MeteorShower.SHRINK_STAGES)
	_shrink_telegraph_mesh.inner_radius = maxf(radius - step, zone_min)
	_shrink_telegraph_mesh.outer_radius = radius
	var urgency := 1.0 - clampf(_shrink_in / MeteorShower.SHRINK_WARN_SEC, 0.0, 1.0)
	_shrink_base_alpha = lerpf(SHRINK_TELEGRAPH_MIN_ALPHA, SHRINK_TELEGRAPH_MAX_ALPHA, urgency)
	if ArenaFX.reduced_motion:
		_shrink_telegraph_mat.albedo_color.a = _shrink_base_alpha


func _process(delta: float) -> void:
	if _shrink_telegraph == null or not _shrink_telegraph.visible or ArenaFX.reduced_motion:
		pass  # Skip shrink pulse if not needed, but still do flash/crater fade.
	else:
		var t := Time.get_ticks_msec() / 1000.0
		var pulse := 0.75 + 0.25 * sin(TAU * t / SHRINK_TELEGRAPH_PULSE_SEC)
		_shrink_telegraph_mat.albedo_color.a = _shrink_base_alpha * pulse

	# Screen flash decay (#1146).
	if _flash_alpha > 0.0:
		_flash_alpha -= delta / FLASH_DECAY_SEC
		if _flash_alpha <= 0.0:
			_flash_alpha = 0.0
		_flash_overlay.color = Color(FLASH_COLOR, _flash_alpha)

	# Crater decal fade (#1146).
	var i := 0
	while i < _active_craters.size():
		var entry: Dictionary = _active_craters[i]
		entry.alpha -= delta / CRATER_FADE_SEC
		if entry.alpha <= 0.0:
			entry.disc.visible = false
			_active_craters.remove_at(i)
		else:
			var mat = entry.disc.mesh.material as StandardMaterial3D
			mat.albedo_color.a = CRATER_COLOR.a * entry.alpha
			i += 1


## Telegraph discs grow from half to full impact size as the timer runs out,
## so "how urgent" is readable at a glance.
func _update_telegraphs() -> void:
	for i in _telegraph_pool.size():
		var marker := _telegraph_pool[i]
		marker.visible = i < meteors.size()
		if not marker.visible:
			continue
		var state: Array = meteors[i]
		var urgency := (
			1.0
			- clampf(
				float(state[MeteorShower.MT_LEFT]) / MeteorShower.METEOR_TELEGRAPH_SEC, 0.0, 1.0
			)
		)
		var radius := MeteorShower.METEOR_RADIUS * lerpf(0.5, 1.0, urgency)
		marker.position = to_arena(
			Vector2(state[MeteorShower.MT_X], state[MeteorShower.MT_Y]), ZONE_DISC_HEIGHT
		)
		marker.scale = Vector3(radius, 1.0, radius)


func _shake_on_new_downs() -> void:
	var fallen_count := 0
	for group: Array in fallen:
		fallen_count += group.size()
	if _edges.rose(&"fallen", fallen_count):
		request_shake(11.0)
		# The shared elimination cue, replacing the generic UI `error`.
		play_sfx(&"ko")
