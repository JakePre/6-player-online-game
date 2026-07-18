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

## make_status_label's top band clears the match-chrome header (HudBar renders
## to ~90px in match_screen.tscn) instead of drawing under it (#924).
const CHROME_CLEARANCE_Y := 110.0

## The dusk base tone the party-stadium shell (#939) tints from, before the
## per-game _floor_tint() nudge — a warm-dark "arena at night" mood.
const STAGE_MOOD_BASE := Color(0.16, 0.13, 0.2)

## Arena root all per-minigame 3D content (props, extra geometry) should
## parent to; populated by _build_scene_tree() before _setup_3d() runs.
var arena: Node3D
## The shared party-stadium backdrop shell (#939), built in _setup().
var _stage_shell: StageShell
## Arena-dressing helper (#948): owns floor-building + rim props. Created once
## `arena` exists, in _setup().
var _dresser: ArenaDresser

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
	_dresser = ArenaDresser.new(arena)
	_build_lighting()
	_build_camera()
	_build_stage_shell()
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


## Decorative rim props (#813): scatter non-interactive scenery — trees, rocks,
## fences from the in-repo Kenney kits — in a ring just outside the play area
## so it can never touch gameplay. The dressing logic lives in ArenaDresser
## (#948); this forwards the view's _arena_half() into it. Seeded off
## `prop_seed` for a reproducible layout — call once from _setup_3d(), e.g.
##   scatter_rim_props([preload("…/tree_pineRoundA.glb")], 16, 7)
func scatter_rim_props(scenes: Array[PackedScene], count: int, prop_seed: int = 0) -> Node3D:
	return _dresser.scatter_rim_props(scenes, count, prop_seed, _arena_half())


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
## `force_animate` (#800) lets a caller protect a one-shot reaction/flourish
## animation from being cut short while the player is stationary, without
## ever stalling movement: a caller passes false while such an animation
## owns the rig, but moving still always wins — the walk switch fires
## regardless of `force_animate` the instant real displacement is detected,
## so "the item-use animation freezes you in place" can't happen. Position,
## facing, and interpolation are unaffected either way.
func update_rig(
	slot: int, world_pos: Vector2, height: float = 0.0, force_animate: bool = true
) -> void:
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
	# A rig playing a protected one-shot pose (#942, CharacterRig.play_protected)
	# keeps it while stationary — but movement always wins (#800), so a real
	# displacement switches to walk regardless. This makes the per-game
	# `force_animate = not flourishing` idiom structural: callers no longer pass
	# the flag; the rig's own hold state does it.
	if (force_animate and not rig.is_pose_protected()) or moving:
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
		# Party-stadium ambiance (#939): the spotlight sweep + crowd sway hold
		# still under reduced motion (M12-03), leaving the shell a calm pose.
		if _stage_shell != null and not ArenaFX.reduced_motion:
			_stage_shell.update(get_process_delta_time())


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
func make_banner(banner_name: StringName, font_size := PartyTheme.SIZE_OVERLAY_BODY) -> Label:
	var label := _new_overlay_label(banner_name, font_size)
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.position.y -= 120.0
	# #576: a bottom-center anchor with the label's zero-size starting rect
	# defaults to growing right+down as text arrives, so long banners (role
	# text, vote prompts) ran off the right edge and under the emote band.
	# Grow outward from center and upward from the bottom anchor instead.
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_attach_overlay_label(label)
	return label


## Top-center phase/status headline ("WATCH", "ROUND 3", role reveals) —
## the counterpart to make_banner (#831): every view used to hand-roll this
## with drifting sizes and no outline. Same never-hidden CanvasLayer, plus an
## outline so it stays readable over bright arenas.
func make_status_label(label_name: StringName, font_size := PartyTheme.SIZE_OVERLAY_TITLE) -> Label:
	var label := _new_overlay_label(label_name, font_size)
	# Full-width top band, not a center point: a long status line (memory_match's
	# round + objective + safe count) at 40px overflowed both screen edges under
	# the old CENTER_TOP anchor. Anchored wide with autowrap, long text wraps to
	# a second centered line instead of spilling off-screen (#831 spot-check).
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Below the match-chrome header (HudBar renders to ~90px), not under it
	# (#924 — the old y=16 default drew status text straight over the game
	# name/timer whenever a game showed one).
	label.position.y += CHROME_CLEARANCE_Y
	label.grow_vertical = Control.GROW_DIRECTION_END
	label.add_theme_constant_override(&"outline_size", 6)
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	_attach_overlay_label(label)
	return label


## Shared overlay-label plumbing for make_banner/make_status_label, split into
## build + attach: anchors/offsets must be fully configured BEFORE the label
## enters the tree — set_anchors_preset on an in-tree control can resolve
## against a not-yet-laid-out (zero-size) parent rect and pin the label to the
## wrong spot (caught by the #576 centering regression test).
func _new_overlay_label(label_name: StringName, font_size: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.add_theme_font_size_override(&"font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	return label


func _attach_overlay_label(label: Label) -> void:
	if _banner_layer == null:
		_banner_layer = CanvasLayer.new()
		_banner_layer.name = "BannerLayer"
		_banner_layer.layer = 5
		add_child(_banner_layer)
	_banner_layer.add_child(label)


# --- Pooled transient entity nodes (#709) -------------------------------------


## Reconcile a persistent pool of transient entity nodes (coins, bombs, hazards,
## floor markers…) to `count` visible instances instead of freeing and
## recreating them on every snapshot render (up to 30 Hz). New nodes are built
## with `factory` only when the pool must grow; the surplus is HIDDEN, never
## freed — so dense-entity games stop churning MeshInstance3D/StandardMaterial3D
## allocations and RenderingServer objects at 24 players.
##
## - `pool`: the view's persistent node array; grown in place (passed by ref).
## - `count`: how many entities to show this frame.
## - `factory` (`func() -> Node3D`): builds ONE node — put per-node static setup
##   (mesh, rotation, material) here; it runs once per node's lifetime, not per
##   frame.
## - `update` (`func(node: Node3D, index: int) -> void`): positions/updates the
##   node for entity `index` (0..count-1) this frame; close over the entity data.
## - `parent`: where new nodes are added; defaults to `arena`.
##
## Spawn/despawn FX diffing (keyed data sets like `_last_hazard_keys`) is
## unaffected — it diffs snapshot data, not these nodes.
func sync_pool(
	pool: Array, count: int, factory: Callable, update: Callable, parent: Node3D = null
) -> void:
	reconcile_pool(pool, count, factory, update, parent if parent != null else arena)


## The pure reconciliation `sync_pool` wraps (kept static + parent-explicit so
## the pool math is unit-testable without standing up a whole arena view).
static func reconcile_pool(
	pool: Array, count: int, factory: Callable, update: Callable, parent: Node3D
) -> void:
	while pool.size() < count:
		var fresh := factory.call() as Node3D
		parent.add_child(fresh)
		pool.append(fresh)
	for i in pool.size():
		var node: Node3D = pool[i]
		var active := i < count
		node.visible = active
		if active:
			update.call(node, i)


# --- Cooldown ring chrome (#945) ---------------------------------------------
# The shrinking "ability on cooldown" ring under a rig (#792/#808 idiom),
# copied verbatim across fort_siege and memory_match before this. Build one
# per rig, key it in a caller-owned pool, and drive it each render.


## Builds the flat cooldown ring — an unshaded torus in `color`, seated just
## above the floor. Parent it under a rig, then drive it with
## update_cooldown_ring().
func make_cooldown_ring(color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.3
	mesh.outer_radius = 0.7
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.name = "CooldownRing"
	node.mesh = mesh
	node.position = Vector3(0.0, 0.06, 0.0)
	return node


## Drives a lazily-built, rig-parented cooldown ring from `fraction` (1 = just
## used, 0 = ready). Builds and parents the ring under `rig` on first need,
## keyed by `slot` in the caller's `rings` pool; shows and shrinks its outer
## radius while cooling, hides it the instant it's ready. No-op (and builds
## nothing) while `fraction <= 0` and no ring exists yet.
func update_cooldown_ring(
	rings: Dictionary, slot: int, rig: Node3D, fraction: float, color: Color
) -> void:
	var ring: MeshInstance3D = rings.get(slot)
	if ring == null:
		if fraction <= 0.0:
			return
		ring = make_cooldown_ring(color)
		rig.add_child(ring)
		rings[slot] = ring
	ring.visible = fraction > 0.0
	if ring.visible:
		(ring.mesh as TorusMesh).outer_radius = 0.35 + 0.35 * fraction


# --- Overridables ------------------------------------------------------------


## World half-extent of the arena floor/camera framing. Override to match the
## minigame's own arena size (e.g. CoinScramble.ARENA_HALF).
func _arena_half() -> float:
	return 10.0


## Per-game floor tint (#589), multiplied over the native Kenney tile color so
## each arena can have its own hue instead of every game reusing the identical
## grey platform. Default white = the neutral shared look; override with a
## gentle tint (keep it near white so the tile texture still reads) to give a
## game character. A one-liner per game — no scene work.
func _floor_tint() -> Color:
	return Color.WHITE


## Per-game mood color for the party-stadium shell (#939): the warm-dark base
## the shared StageShell tints its dome, ring, crowd and spotlights from.
## Defaults to a dusk tone nudged by the game's own _floor_tint(), so every
## arena gets a coherent backdrop with no per-game code; override for a
## distinct mood (bullet_waltz dark/elegant, treasure_divers poolside, …).
func _mood() -> Color:
	return STAGE_MOOD_BASE.lerp(_floor_tint(), 0.25)


## Per-game floor tile mesh (#813): override to tile the arena with a different
## in-repo Kenney block — `block-grass.glb`, `block-snow.glb`, etc. — instead of
## the default grey `platform.glb`. Any flat 1x1 block from the kits works: the
## builder measures the mesh's AABB and seats its top surface at y=0, so blocks
## of any thickness sit right without a per-game offset. A one-liner per game;
## combine with a matching (or absent) _floor_tint. Games that build their own
## floor (thin_ice, memory_match override _build_floor) ignore this.
func _floor_tile_scene() -> PackedScene:
	return FLOOR_TILE_SCENE


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


## The shared party-stadium backdrop (#939): mounted once, framing the arena
## at its extent and themed from _mood(). Pure presentation — no per-game code.
func _build_stage_shell() -> void:
	_stage_shell = StageShell.new()
	_stage_shell.build(arena, _arena_half(), _mood())


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


## Overridable floor hook (#813): the default dresses the arena with a tinted
## tile floor via ArenaDresser (#948), seated by the tile's own top surface so
## any block thickness sits flush. Games with a floor that IS the gameplay
## (thin_ice's vanishing tiles, memory_match's grid) override this to build
## their own — they don't call super.
func _build_floor() -> void:
	_dresser.build_floor(_floor_tile_scene(), _floor_tint(), _arena_half())


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


## Rigs bake player_color at build time (before any snapshot), so when a team
## round flips identity to team colors (#820) the pooled rigs must be re-pushed —
## outline, through-wall silhouette, and nameplate all recolor from this.
func _on_identity_colors_changed() -> void:
	for slot: int in _rigs:
		(_rigs[slot] as CharacterRig).player_color = player_color(slot)


func _character_ids_by_slot() -> Dictionary:
	var out := {}
	for member: Dictionary in NetManager.my_room_state.get("members", []):
		out[int(member.slot)] = member.character_id
	return out
