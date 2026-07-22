extends MinigameView3D
## Musical Platforms client view (M10-02): renders the replicated arena in
## the shared 2.5D iso-arena — players as CharacterRigs (losers collapse and
## dim), platforms as discs that appear when the music stops and light up in
## the claimant's color, and a Control-layer call-out flipping between
## DANCE! and GRAB A PLATFORM! so the phase is readable instantly.

const PLATFORM_FREE_COLOR := Color(0.75, 0.75, 0.8, 0.55)
const PLATFORM_DISC_HEIGHT := 0.12
const ELIMINATED_COLOR := Color(0.42, 0.42, 0.46)
const MUSIC_TEXT := "DANCE!"
const STOP_TEXT := "GRAB A PLATFORM!"
## Sink + fade a KO'd rig into the floor instead of leaving it standing mid-
## round (#930 — memory_match's #784 fall idiom). FALL_HIDE_Y is well below
## the floor plane.
const FALL_SPEED := 7.0
const FALL_HIDE_Y := -6.0
## #1143 GFX: a dance-floor texture, raised platform rims, floating music
## notes, a DJ booth, sweeping stage lights, rim props, a club mood, a gentle
## bob on free platforms, and a ghost ring where a fighter was eliminated.
const FLOOR_TEXTURE := preload("res://assets/generated/textures/wood-court.png")
const FLOOR_TEXTURE_TILES := 8.0
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_platformer_kit/crate.glb"),
	preload("res://assets/environment/kenney_platformer_kit/barrel.glb"),
]
const RIM_PROP_COUNT := 12
const RIM_PROP_SEED := 0x4D51C
const PLATFORM_RIM_COLOR := Color(0.95, 0.9, 0.7, 0.85)
const PLATFORM_RIM_THICKNESS := 0.05
const NOTE_CHARS := ["♪", "♫"]
const NOTE_COLOR := Color(0.85, 0.65, 0.95)
const NOTE_INTERVAL_SEC := 0.55
const NOTE_LIFE_SEC := 1.6
const NOTE_RISE := 2.2
const DJ_BOOTH_COLOR := Color(0.22, 0.16, 0.28)
const DJ_TURNTABLE_COLOR := Color(0.65, 0.55, 0.85)
const STAGE_LIGHT_COLORS := [Color(0.9, 0.3, 0.9), Color(0.3, 0.8, 0.9), Color(0.95, 0.7, 0.2)]
const STAGE_LIGHT_SWEEP_SPEED := 0.6
const GHOST_RING_COLOR := Color(0.6, 0.6, 0.68, 0.35)
const FREE_PLATFORM_BOB_SPEED := 1.4
const FREE_PLATFORM_BOB_HEIGHT := 0.04

## Latest replicated state, straight from MusicalPlatforms.get_snapshot().
var players := {}
var phase: int = MusicalPlatforms.Phase.MUSIC
var platforms: Array = []
var fallen: Array = []

var _platform_pool: Array[MeshInstance3D] = []
var _phase_label: Label
var _downed := {}
## Slots still sinking into the floor after elimination (#930).
var _falling := {}
# pool index -> claimed edge from the previous snapshot (M13-08 claim flashes).
var _claim_edges := EdgeTracker.new()
# Wave tracking for drop-in dust (M13-08): platforms empty last render, and
# whether any render happened yet (rejoin seeding).
var _platforms_were_empty := true
var _rendered_once := false
## Fires only on a rise, so a mid-match rejoin does not shake on its first
## snapshot (#728 the MUSIC -> STOP danger telegraph edge lives on _phase_edges).
var _fallen_edges := EdgeTracker.new()
var _phase_edges := EdgeTracker.new()
## #1143 GFX: time until the next floating music note spawns, and the live
## sweeping stage lights (rotate during MUSIC, freeze during STOP).
var _note_timer := NOTE_INTERVAL_SEC
var _stage_lights: Array[SpotLight3D] = []
var _bob_clock := 0.0


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(delta: float) -> void:
	_advance_falls(delta)
	_advance_notes(delta)
	_advance_stage_lights(delta)
	_advance_platform_bob(delta)


## Free platforms bob gently in place (#1143) — claimed ones stay put so the
## claim itself still reads as the thing that changed.
func _advance_platform_bob(delta: float) -> void:
	_bob_clock += delta
	for i in _platform_pool.size():
		var node := _platform_pool[i]
		if not node.visible or i >= platforms.size():
			continue
		var state: Array = platforms[i]
		if int(state[MusicalPlatforms.PT_CLAIMED_BY]) != -1:
			continue
		var base := to_arena(
			Vector2(state[MusicalPlatforms.PT_X], state[MusicalPlatforms.PT_Y]),
			PLATFORM_DISC_HEIGHT / 2.0
		)
		node.position.y = (
			base.y + sin(_bob_clock * FREE_PLATFORM_BOB_SPEED + float(i)) * FREE_PLATFORM_BOB_HEIGHT
		)


## Floating music notes (#1143): only during MUSIC, on an interval, so the
## dance phase reads as musical without a data change to the sim.
func _advance_notes(delta: float) -> void:
	if phase != MusicalPlatforms.Phase.MUSIC:
		return
	_note_timer -= delta
	if _note_timer <= 0.0:
		_note_timer = NOTE_INTERVAL_SEC
		_spawn_music_note()


func _spawn_music_note() -> void:
	if ArenaFX.reduced_motion:
		return
	var half := _arena_half()
	var label := Label3D.new()
	label.text = NOTE_CHARS[randi() % NOTE_CHARS.size()]
	label.modulate = NOTE_COLOR
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.no_depth_test = true
	var start := Vector3(randf_range(-half, half), 0.4, randf_range(-half, half))
	label.position = start
	arena.add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", start.y + NOTE_RISE, NOTE_LIFE_SEC)
	tween.tween_property(label, "modulate:a", 0.0, NOTE_LIFE_SEC)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)


## Sink downed rigs into the floor (#930); each hides once below it.
func _advance_falls(delta: float) -> void:
	for slot: int in _falling.keys():
		var rig := rig_for_slot(slot)
		if rig == null:
			_falling.erase(slot)
			continue
		rig.position.y -= FALL_SPEED * delta
		if rig.position.y <= FALL_HIDE_Y:
			rig.visible = false
			_falling.erase(slot)


## Soft lavender floor for the musical whimsy (#589).
func _floor_tint() -> Color:
	return Color(0.92, 0.88, 1.0)


## Club-purple mood (#1143) — a deeper nudge than the default dusk-lerp gives,
## so the dance-floor theme reads even with the stage shell off.
func _mood() -> Color:
	return Color(0.25, 0.08, 0.32)


## Dance-floor texture (#1143), Tier 1: wood-court under the platforms.
func _build_floor() -> void:
	var floor_node := _dresser.build_floor(_floor_tile_scene(), _floor_tint(), _arena_half())
	if floor_node != null:
		var mat := floor_node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_texture = FLOOR_TEXTURE
			mat.uv1_scale = Vector3(FLOOR_TEXTURE_TILES, FLOOR_TEXTURE_TILES, 1.0)


func _arena_half() -> float:
	# Grow the framed floor with the lobby to match the sim's scaled play area
	# (M15, ADR 003 F4); at <=6 players this is the tuned MusicalPlatforms.ARENA_HALF.
	return MinigameScaling.arena_half(MusicalPlatforms.ARENA_HALF, names.size())


func _setup_3d() -> void:
	# Pool sized to the worst case for this lobby: "players - 1" platforms
	# spawn on the very first STOP round, and it only shrinks from there — a
	# fixed pool (previously 5, the <=6-player max) silently dropped
	# platforms past that once the cap grew (M15, ADR 003; #457).
	var pool_size := maxi(names.size() - 1, 1)
	for i in pool_size:
		var mesh := CylinderMesh.new()
		mesh.top_radius = MusicalPlatforms.PLATFORM_RADIUS
		mesh.bottom_radius = MusicalPlatforms.PLATFORM_RADIUS
		mesh.height = PLATFORM_DISC_HEIGHT
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = PLATFORM_FREE_COLOR
		mesh.material = material
		var node := MeshInstance3D.new()
		node.name = "Platform%d" % i
		node.mesh = mesh
		node.visible = false
		# Raised rim (#1143): a TorusMesh lip so the disc reads as a physical
		# platform rather than a flat painted circle.
		var rim := MeshInstance3D.new()
		rim.name = "Rim"
		var torus := TorusMesh.new()
		torus.inner_radius = MusicalPlatforms.PLATFORM_RADIUS - PLATFORM_RIM_THICKNESS
		torus.outer_radius = MusicalPlatforms.PLATFORM_RADIUS + PLATFORM_RIM_THICKNESS
		var rim_material := StandardMaterial3D.new()
		rim_material.albedo_color = PLATFORM_RIM_COLOR
		torus.material = rim_material
		rim.mesh = torus
		rim.position.y = PLATFORM_DISC_HEIGHT / 2.0
		node.add_child(rim)
		arena.add_child(node)
		_platform_pool.append(node)
	_phase_label = make_status_label(&"PhaseLabel")
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)
	_build_dj_booth()
	_build_stage_lights()


## A small booth at the arena edge — where the music comes from (#1143).
func _build_dj_booth() -> void:
	var half := _arena_half()
	var booth := MeshInstance3D.new()
	booth.name = "DjBooth"
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 1.0, 0.8)
	var booth_material := StandardMaterial3D.new()
	booth_material.albedo_color = DJ_BOOTH_COLOR
	box.material = booth_material
	booth.mesh = box
	booth.position = Vector3(0.0, 0.5, -half * 0.92)
	arena.add_child(booth)
	var turntable := MeshInstance3D.new()
	turntable.name = "Turntable"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.08
	var disc_material := StandardMaterial3D.new()
	disc_material.albedo_color = DJ_TURNTABLE_COLOR
	disc.material = disc_material
	turntable.mesh = disc
	turntable.position = Vector3(0.0, 0.54, 0.0)
	booth.add_child(turntable)


## Sweeping colored spotlights (#1143): rotate during MUSIC, freeze on STOP —
## a custom stand-in since the shared StageShell's spots are off (#1119).
func _build_stage_lights() -> void:
	var half := _arena_half()
	for i in STAGE_LIGHT_COLORS.size():
		var light := SpotLight3D.new()
		light.name = "StageLight%d" % i
		light.light_color = STAGE_LIGHT_COLORS[i]
		light.light_energy = 2.0
		light.spot_range = half * 2.2
		light.spot_angle = 22.0
		light.position = Vector3(0.0, half * 1.4, -half * 0.85)
		light.rotation_degrees = Vector3(-70.0, 0.0, 0.0)
		arena.add_child(light)
		_stage_lights.append(light)


## Rotates the stage lights' yaw during MUSIC; STOP freezes them in place —
## the danger telegraph reads in the lights too, not just the phase label.
func _advance_stage_lights(delta: float) -> void:
	if phase != MusicalPlatforms.Phase.MUSIC:
		return
	for i in _stage_lights.size():
		var light := _stage_lights[i]
		var direction := 1.0 if i % 2 == 0 else -1.0
		light.rotation.y += STAGE_LIGHT_SWEEP_SPEED * direction * delta


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	phase = int(game.get("phase", MusicalPlatforms.Phase.MUSIC))
	platforms = game.get("platforms", [])
	fallen = game.get("fallen", [])
	_phase_label.text = STOP_TEXT if phase == MusicalPlatforms.Phase.STOP else MUSIC_TEXT
	# The music actually STOPPING is the whole game (#804): pause the round loop
	# for the scramble, resume when players roam again. Set from the phase every
	# render (not just the edge) so a mid-STOP rejoiner also lands on silence;
	# _celebrate and _exit_tree guarantee the shared loop never stays paused once
	# this game is done.
	AudioManager.set_music_paused(phase == MusicalPlatforms.Phase.STOP)
	# Signature cue (#728, docs/AUDIO_GUIDE.md — Tiles & ice): the music
	# stopping is the danger telegraph — scramble now.
	var was_music := int(_phase_edges.peek(&"phase", -1)) == MusicalPlatforms.Phase.MUSIC
	if was_music and phase == MusicalPlatforms.Phase.STOP:
		play_sfx(&"alarm")
	_phase_edges.changed(&"phase", phase)
	_update_players()
	_update_platforms()
	_shake_on_new_downs()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[MusicalPlatforms.PS_X], state[MusicalPlatforms.PS_Y]))
	for group: Array in fallen:
		for slot: int in group:
			_down_rig(slot)


func _down_rig(slot: int) -> void:
	if _downed.has(slot):
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	_downed[slot] = true
	rig.play(&"ko")
	rig.player_color = ELIMINATED_COLOR
	# Dust where they drop (M13-08).
	fx_dust(Vector2(rig.position.x, rig.position.z))
	# A flat ghost ring marks the elimination spot for the rest of the round
	# (#1143), left behind once the rig itself sinks out of view.
	_build_ghost_ring(rig.position.x, rig.position.z)
	# Sink out of view instead of lying in the field mid-round (#930).
	_falling[slot] = true


func _build_ghost_ring(x: float, z: float) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "GhostRing"
	var torus := TorusMesh.new()
	torus.inner_radius = MusicalPlatforms.PLATFORM_RADIUS * 0.7
	torus.outer_radius = MusicalPlatforms.PLATFORM_RADIUS * 0.85
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = GHOST_RING_COLOR
	torus.material = material
	ring.mesh = torus
	ring.position = Vector3(x, 0.03, z)
	arena.add_child(ring)


## Free platforms are neutral gray; claimed ones take the claimant's color so
## "which are still up for grabs" reads at a glance.
func _update_platforms() -> void:
	for i in _platform_pool.size():
		var node := _platform_pool[i]
		node.visible = i < platforms.size()
		if not node.visible:
			continue
		var state: Array = platforms[i]
		node.position = to_arena(
			Vector2(state[MusicalPlatforms.PT_X], state[MusicalPlatforms.PT_Y]),
			PLATFORM_DISC_HEIGHT / 2.0
		)
		var claimant := int(state[MusicalPlatforms.PT_CLAIMED_BY])
		var material: StandardMaterial3D = (node.mesh as CylinderMesh).material
		if claimant == -1:
			material.albedo_color = PLATFORM_FREE_COLOR
		else:
			var color := player_color(claimant)
			color.a = 0.75
			material.albedo_color = color
		# Claim flash (M13-08): the moment a pad flips from free to owned,
		# sparkle in the claimant's color; a fresh wave of platforms puffs
		# dust as it drops in (skipped on the client's very first render, so
		# rejoiners aren't greeted with a dust storm).
		var at := Vector2(state[MusicalPlatforms.PT_X], state[MusicalPlatforms.PT_Y])
		if _platforms_were_empty and _rendered_once:
			fx_dust(at)
		if _claim_edges.rose(i, claimant != -1):
			fx_sparkle(at, player_color(claimant))
			if claimant == my_slot:
				# Landing a platform is a positive checkpoint, not a generic
				# UI accept.
				play_sfx(&"bell")
	_platforms_were_empty = platforms.is_empty()
	_rendered_once = true
	# Platforms clearing with the music resets the per-round claim tracking.
	if platforms.is_empty():
		_claim_edges.clear()


func _shake_on_new_downs() -> void:
	var fallen_count := 0
	for group: Array in fallen:
		fallen_count += group.size()
	if _fallen_edges.rose(&"fallen", fallen_count):
		request_shake(9.0)
		play_sfx(&"ko")


## The round can end mid-scramble (a winner emerges while the music is stopped),
## so resume the shared loop before the results celebration rather than leaving
## it silent (#804). Winners still cheer via the base.
func _celebrate(placements: Array) -> void:
	AudioManager.set_music_paused(false)
	super(placements)


## Never strand the shared round music paused when this view unmounts mid-STOP
## (game over, leaderboard, a wipe) — the next round would start silent (#804).
func _exit_tree() -> void:
	super()  # keep the base's identity-palette restore (#820)
	AudioManager.set_music_paused(false)
