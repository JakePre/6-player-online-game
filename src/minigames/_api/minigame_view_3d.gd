class_name MinigameView3D
extends MinigameView
## Shared 2.5D iso-arena presentation tier (M8-01, `docs/adr/002-iso-arena-rendering.md`):
## embeds a full-rect SubViewport hosting a Node3D arena — an IsoCameraRig,
## a fixed key/fill lighting rig + environment, a floor helper tiled from the
## Kenney platformer-kit (M8-02), and a pooled CharacterRig per player slot
## sourced from CharacterRoster/PlayerPalette/NetManager.my_room_state.
##
## MinigameView's setup/render contract is unchanged. Subclasses override
## _render_3d(game) instead of _draw(), and may override _arena_half() (world
## half-extent, for floor/camera sizing) and _setup_3d() (one-time arena prop
## setup) — both default to no-ops sized for a generic small arena.

const CHARACTER_RIG_SCENE := preload("res://src/characters/character_rig.tscn")
const ISO_CAMERA_RIG_SCENE := preload("res://src/characters/iso_camera_rig.tscn")
const FLOOR_TILE_SCENE := preload("res://assets/environment/kenney_platformer_kit/platform.glb")
## `platform.glb` is a flat 1x1 world-unit tile, ~0.195 units thick (SPEC $10
## kit is on a 1m grid). Tiles are placed so their top surface sits at y=0.
const FLOOR_TILE_SIZE := 1.0
const FLOOR_TILE_THICKNESS := 0.195
## Below this per-snapshot displacement (world units), a rig is treated as
## stationary and plays "idle" instead of "walk".
const MOVE_EPSILON := 0.01
## Snapshot interpolation (M12-04). A jump beyond this distance (respawns,
## round resets) snaps instead of sliding across the arena.
const TELEPORT_SNAP_DISTANCE := 3.0
## Fallback/clamp bounds for the measured inter-snapshot interval, so one
## delayed packet cannot stretch the slide into slow motion.
const SNAPSHOT_INTERVAL := 1.0 / NetConfig.SNAPSHOT_HZ
const MAX_SAMPLE_INTERVAL := 0.25
## Blackout view flag (M9-05): lights-out cadence, mirroring Heist Night's
## LIGHT_SEC/DARK_SEC feel (SPEC-level: reuse the established rhythm).
const BLACKOUT_LIGHT_SEC := 8.0
const BLACKOUT_DARK_SEC := 5.0
const BLACKOUT_DIM := Color(0.0, 0.0, 0.02, 0.88)

## Arena root all per-minigame 3D content (props, extra geometry) should
## parent to; populated by _build_scene_tree() before _setup_3d() runs.
var arena: Node3D

var _banner_layer: CanvasLayer

var _viewport: SubViewport
var _camera_rig: IsoCameraRig
var _rigs := {}  # slot (int) -> CharacterRig
var _rig_last_pos := {}  # slot (int) -> Vector2, for walk/idle + facing
# Slots whose rig has been revealed at least once (#601). Rigs are pooled
# hidden and shown on first update_rig()/reveal_rig(), so a disconnected
# member — present in `names` but never in a round's snapshot — leaves no
# frozen ghost. One-shot, so a game's later deliberate hide (KO, elimination)
# is not fought.
var _rig_revealed := {}
# slot (int) -> {from: Vector2, to: Vector2, at: float, interval: float};
# per-frame interpolation targets (M12-04).
var _rig_samples := {}


func _setup() -> void:
	_build_scene_tree()
	_build_lighting()
	_build_camera()
	_build_floor()
	_build_character_rigs()
	_apply_view_flags()
	set_process_internal(true)
	_setup_3d()


## Mutator view flags (M9-05). Masquerade hides every rig's nameplate;
## Blackout adds a lights-out overlay cycling on the Heist Night cadence via
## a Timer (not _process, which subclasses own for input).
func _apply_view_flags() -> void:
	if has_view_flag(&"hide_nameplates"):
		for rig: CharacterRig in _rigs.values():
			(rig.get_node("Nameplate") as Label3D).visible = false
	if has_view_flag(&"blackout"):
		_build_blackout_overlay()


func _build_blackout_overlay() -> void:
	var overlay := ColorRect.new()
	overlay.name = "BlackoutOverlay"
	overlay.color = BLACKOUT_DIM
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var timer := Timer.new()
	timer.name = "BlackoutTimer"
	timer.one_shot = true
	timer.timeout.connect(
		func() -> void:
			overlay.visible = not overlay.visible
			timer.start(BLACKOUT_DARK_SEC if overlay.visible else BLACKOUT_LIGHT_SEC)
	)
	add_child(timer)
	timer.start(BLACKOUT_LIGHT_SEC)


func _render(game: Dictionary) -> void:
	_render_3d(game)


## Converts a minigame's top-down world-unit position onto the arena's X/Z
## plane; `height` lifts it above the floor surface (world units).
func to_arena(pos: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(pos.x, height, pos.y)


func rig_for_slot(slot: int) -> CharacterRig:
	return _rigs.get(slot)


## Reveals a pooled rig the first time a round actually uses its slot (#601),
## so a disconnected member's rig never appears. One-shot: after the first
## reveal the game owns the rig's visibility (deliberate KO/elimination hides
## are not fought). Stationary-rig views that never call update_rig (e.g.
## Bullseye Bowl) call this directly for the slots in their snapshot.
func reveal_rig(slot: int) -> void:
	if slot in _rig_revealed:
		return
	var rig: CharacterRig = _rigs.get(slot)
	if rig == null:
		return
	_rig_revealed[slot] = true
	rig.visible = true


# --- One-shot FX (M13-01): fire-and-forget wrappers over ArenaFX --------------


func fx_burst(world_pos: Vector2, color: Color, height: float = 0.5) -> void:
	ArenaFX.burst(arena, to_arena(world_pos, height), color)


func fx_sparkle(world_pos: Vector2, color: Color, height: float = 0.5) -> void:
	ArenaFX.sparkle(arena, to_arena(world_pos, height), color)


func fx_splash(world_pos: Vector2) -> void:
	ArenaFX.splash(arena, to_arena(world_pos, 0.05))


func fx_dust(world_pos: Vector2) -> void:
	ArenaFX.dust(arena, to_arena(world_pos, 0.05))


## Moves the slot's rig to `world_pos` (top-down world units) and switches
## between "walk"/"idle" + faces the movement direction, based on the
## displacement since the last call. No-op for slots without a pooled rig.
## `height` lifts the rig above (or below) the floor plane — e.g. swimming on
## a water surface vs diving to the seabed (M10-04) — and interpolates like
## the rest of the position.
func update_rig(slot: int, world_pos: Vector2, height: float = 0.0) -> void:
	var rig: CharacterRig = _rigs.get(slot)
	if rig == null:
		return
	reveal_rig(slot)
	var last: Vector2 = _rig_last_pos.get(slot, world_pos)
	var delta := world_pos - last
	_record_rig_sample(slot, rig, to_arena(world_pos, height))
	var moving := delta.length() > MOVE_EPSILON
	if moving:
		rig.rotation.y = atan2(delta.x, delta.y)
	var desired: StringName = &"walk" if moving else &"idle"
	if rig.current_action() != desired:
		rig.play(desired)
	_rig_last_pos[slot] = world_pos


# --- Snapshot interpolation (M12-04) ------------------------------------------


## 30 Hz snapshots land as per-slot samples; an internal-process pass slides
## each rig from where it is on screen to the newest sample every frame, so
## motion stays smooth at any display rate. Internal process is used so
## subclasses keep _process/_physics_process for their own input. The first
## sample for a slot snaps (the rig spawns in place), as do teleport-sized
## jumps.
func _record_rig_sample(slot: int, rig: CharacterRig, target: Vector3) -> void:
	var now := _now_sec()
	var sample: Dictionary = _rig_samples.get(slot, {})
	if sample.is_empty() or target.distance_to(sample.to) > TELEPORT_SNAP_DISTANCE:
		_rig_samples[slot] = {
			"from": target, "to": target, "at": now, "interval": SNAPSHOT_INTERVAL
		}
		rig.position = target
		return
	var interval := clampf(now - sample.at, SNAPSHOT_INTERVAL, MAX_SAMPLE_INTERVAL)
	_rig_samples[slot] = {
		# Start from the on-screen position, so jittery snapshot timing never
		# pops the rig backwards.
		"from": _sample_position(sample, now),
		"to": target,
		"at": now,
		"interval": interval,
	}


func _sample_position(sample: Dictionary, now: float) -> Vector3:
	var t := clampf((now - float(sample.at)) / float(sample.interval), 0.0, 1.0)
	return (sample.from as Vector3).lerp(sample.to, t)


func _interpolate_rigs(now: float) -> void:
	for slot: int in _rig_samples:
		var rig: CharacterRig = _rigs.get(slot)
		if rig == null or not rig.visible:
			continue
		rig.position = _sample_position(_rig_samples[slot], now)


func _now_sec() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_INTERNAL_PROCESS:
		_interpolate_rigs(_now_sec())


## Victory dance (M6-02): the round's winners (first tie group) cheer while
## the arena idles behind the results panel. Views with their own celebration
## logic can override _celebrate further.
func _celebrate(placements: Array) -> void:
	if placements.is_empty():
		return
	for slot: int in placements[0]:
		var rig: CharacterRig = _rigs.get(int(slot))
		if rig != null and rig.visible:
			rig.play(&"cheer")


## Gameplay-critical screen text (dash bars, charge banners, held-item
## prompts) must never hide behind the arena or the emote chrome (#258):
## banners live on a high CanvasLayer, bottom-center, above the emote band.
func make_banner(banner_name: StringName, font_size := 24) -> Label:
	if _banner_layer == null:
		_banner_layer = CanvasLayer.new()
		_banner_layer.name = "BannerLayer"
		_banner_layer.layer = 5
		add_child(_banner_layer)
	var label := Label.new()
	label.name = banner_name
	label.add_theme_font_size_override(&"font_size", font_size)
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.position.y -= 120.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# #576: a bottom-center anchor with the label's zero-size starting rect
	# defaults to growing right+down as text arrives, so long banners (role
	# text, vote prompts) ran off the right edge and under the emote band.
	# Grow outward from center and upward from the bottom anchor instead.
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_banner_layer.add_child(label)
	return label


# --- Overridables ------------------------------------------------------------


## World half-extent of the arena floor/camera framing. Override to match the
## minigame's own arena size (e.g. CoinScramble.ARENA_HALF).
func _arena_half() -> float:
	return 10.0


func _setup_3d() -> void:
	pass


func _render_3d(_game: Dictionary) -> void:
	pass


# --- Arena construction -------------------------------------------------------


func _build_scene_tree() -> void:
	# The liked drifting-blob field (M16-03/#590) sits behind the arena
	# viewport instead of the old flat grey — added first so it renders
	# behind the container, and shows through wherever the 3D scene's own
	# transparent background (see _build_lighting) doesn't cover the frame.
	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)

	var container := SubViewportContainer.new()
	container.name = "Arena3DContainer"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.name = "Arena3DViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	container.add_child(_viewport)

	arena = Node3D.new()
	arena.name = "Arena"
	_viewport.add_child(arena)


func _build_lighting() -> void:
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	key.light_energy = 1.1
	arena.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-20.0, 150.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.75, 0.82, 1.0)
	arena.add_child(fill)

	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	var environment := Environment.new()
	# Transparent background (#590): lets the Backdrop control show through
	# instead of the old flat grey. Ambient lighting is set independently
	# below (AMBIENT_SOURCE_COLOR), so this changes what shows behind the
	# arena, not how anything in it is lit.
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.3, 0.32, 0.36)
	environment.ambient_light_energy = 0.6
	world_env.environment = environment
	arena.add_child(world_env)


func _build_camera() -> void:
	_camera_rig = ISO_CAMERA_RIG_SCENE.instantiate()
	_camera_rig.name = "IsoCameraRig"
	_camera_rig.ortho_size = _arena_half() * 2.4
	arena.add_child(_camera_rig)
	# _camera_rig.camera() reads an @onready var that's still null here — setup()
	# runs before match_screen.gd adds this view to the tree, so IsoCameraRig's
	# own _ready() hasn't fired yet. get_node() walks the already-instantiated
	# scene structure directly, so it works regardless of _ready() timing.
	(_camera_rig.get_node("Camera3D") as Camera3D).current = true


func _build_floor() -> void:
	var tile := FLOOR_TILE_SCENE.instantiate()
	var tile_meshes := tile.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (tile_meshes[0] as MeshInstance3D).mesh if not tile_meshes.is_empty() else null
	tile.free()
	if mesh == null:
		return

	var tiles_per_side := int(ceil(_arena_half() * 2.0 / FLOOR_TILE_SIZE))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = tiles_per_side * tiles_per_side

	var start := -_arena_half() + FLOOR_TILE_SIZE * 0.5
	var i := 0
	for x in tiles_per_side:
		for z in tiles_per_side:
			var pos := Vector3(
				start + x * FLOOR_TILE_SIZE, -FLOOR_TILE_THICKNESS, start + z * FLOOR_TILE_SIZE
			)
			multimesh.set_instance_transform(i, Transform3D(Basis(), pos))
			i += 1

	var floor_node := MultiMeshInstance3D.new()
	floor_node.name = "Floor"
	floor_node.multimesh = multimesh
	arena.add_child(floor_node)


func _build_character_rigs() -> void:
	var character_ids := _character_ids_by_slot()
	var slots: Array = names.keys()
	slots.sort()
	for slot: int in slots:
		var rig: CharacterRig = CHARACTER_RIG_SCENE.instantiate()
		rig.name = "PlayerRig%d" % slot
		rig.character_scene = CharacterRoster.scene_for(
			character_ids.get(slot, CharacterRoster.DEFAULT_ID)
		)
		rig.player_color = player_color(slot)
		rig.display_name = player_name(slot)
		rig.nameplate_priority = 1 if slot == my_slot else 0
		# Pooled hidden (#601): revealed on the slot's first update_rig() /
		# reveal_rig(). Slots never present in a round's snapshot stay invisible.
		rig.visible = false
		arena.add_child(rig)
		_rigs[slot] = rig


func _character_ids_by_slot() -> Dictionary:
	var out := {}
	for member: Dictionary in NetManager.my_room_state.get("members", []):
		out[int(member.slot)] = member.character_id
	return out
