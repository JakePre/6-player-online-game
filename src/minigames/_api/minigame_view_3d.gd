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

## Arena root all per-minigame 3D content (props, extra geometry) should
## parent to; populated by _build_scene_tree() before _setup_3d() runs.
var arena: Node3D

var _viewport: SubViewport
var _camera_rig: IsoCameraRig
var _rigs := {}  # slot (int) -> CharacterRig
var _rig_last_pos := {}  # slot (int) -> Vector2, for walk/idle + facing


func _setup() -> void:
	_build_scene_tree()
	_build_lighting()
	_build_camera()
	_build_floor()
	_build_character_rigs()
	_setup_3d()


func _render(game: Dictionary) -> void:
	_render_3d(game)


## Converts a minigame's top-down world-unit position onto the arena's X/Z
## plane; `height` lifts it above the floor surface (world units).
func to_arena(pos: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(pos.x, height, pos.y)


func rig_for_slot(slot: int) -> CharacterRig:
	return _rigs.get(slot)


## Moves the slot's rig to `world_pos` (top-down world units) and switches
## between "walk"/"idle" + faces the movement direction, based on the
## displacement since the last call. No-op for slots without a pooled rig.
func update_rig(slot: int, world_pos: Vector2) -> void:
	var rig: CharacterRig = _rigs.get(slot)
	if rig == null:
		return
	var last: Vector2 = _rig_last_pos.get(slot, world_pos)
	var delta := world_pos - last
	rig.position = to_arena(world_pos)
	var moving := delta.length() > MOVE_EPSILON
	if moving:
		rig.rotation.y = atan2(delta.x, delta.y)
	var desired: StringName = &"walk" if moving else &"idle"
	if rig.current_action() != desired:
		rig.play(desired)
	_rig_last_pos[slot] = world_pos


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
	var container := SubViewportContainer.new()
	container.name = "Arena3DContainer"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.name = "Arena3DViewport"
	_viewport.own_world_3d = true
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
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.06, 0.08)
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
		arena.add_child(rig)
		_rigs[slot] = rig


func _character_ids_by_slot() -> Dictionary:
	var out := {}
	for member: Dictionary in NetManager.my_room_state.get("members", []):
		out[int(member.slot)] = member.character_id
	return out
