class_name CharacterRig
extends Node3D
## Shared character rendering kit (M2-04): wraps any KayKit character scene
## behind a semantic animation proxy and applies the player identity layer —
## colored outline, through-wall silhouette, and an always-readable nameplate
## (SPEC $8, $11). All 9 imported characters share one rig and animation set,
## so this single proxy serves every roster entry (M2-03 supplies the roster).

## Emitted when a non-looping action's animation finishes (e.g. "ko", "hit").
signal action_finished(action: StringName)

## Semantic action -> KayKit animation. Gameplay code uses actions, never raw
## animation names, so replacing the asset pack stays a one-file change.
const ACTIONS := {
	&"idle": {"anim": &"Idle", "loop": true},
	&"run": {"anim": &"Running_A", "loop": true},
	&"walk": {"anim": &"Walking_A", "loop": true},
	&"jump_start": {"anim": &"Jump_Start", "loop": false},
	&"jump_idle": {"anim": &"Jump_Idle", "loop": true},
	&"jump_land": {"anim": &"Jump_Land", "loop": false},
	&"hit": {"anim": &"Hit_A", "loop": false},
	&"ko": {"anim": &"Death_A", "loop": false},
	&"cheer": {"anim": &"Cheer", "loop": true},
	&"interact": {"anim": &"Interact", "loop": false},
	&"pickup": {"anim": &"PickUp", "loop": false},
	# Weapon swing (#584): the radial spin, present on all 9 shipped characters.
	&"attack": {"anim": &"2H_Melee_Attack_Spin", "loop": false},
	# Battleaxe side swing: the horizontal two-handed slice from the base pack.
	&"attack_side": {"anim": &"2H_Melee_Attack_Slice", "loop": false},
	# Whirlwind: the looping variant of the spin — hold to keep spinning.
	&"whirlwind": {"anim": &"2H_Melee_Attack_Spinning", "loop": true},
	# Duck: crouch-and-hold, authored by the asset pipeline and injected into
	# every roster GLB (rig_tools.py in the generating-assets workspace).
	&"duck": {"anim": &"Duck", "loop": true},
}

## Base nameplate font size from the scene; scaled by the nameplate_scale
## setting (#143).
const NAMEPLATE_BASE_FONT := 48
## Plate declutter (#216): rigs whose ground positions are within this many
## world units of each other count as one cluster, and their plates stagger
## vertically by PLATE_STACK_STEP so the labels never render on top of each
## other. Plates closer to the camera stay lower (nearest the owner's head).
const PLATE_CLUSTER_RADIUS := 1.7
const PLATE_STACK_STEP := 0.55
## Every plate renders inside the same maximum text width (#180): names and
## captions longer than this shrink to fit instead of dwarfing everyone
## else's. Measured in font pixels at the base size.
const NAMEPLATE_MAX_WIDTH := 320.0

const OUTLINE_SHADER := preload("res://src/characters/player_outline.gdshader")
const XRAY_SHADER := preload("res://src/characters/player_xray.gdshader")
const XRAY_ALPHA := 0.12

## All rigs alive in the tree, so each can stagger its plate against the
## others sharing its viewport (#216).
static var _live_rigs: Array = []

@export var character_scene: PackedScene:
	set = set_character_scene
@export var player_color := Color.WHITE:
	set = set_player_color
@export var display_name := "":
	set = set_display_name
## KayKit scenes ship optional weapon/shield props on BoneAttachment3D nodes.
## Hidden by default: clean silhouettes are an identity requirement (SPEC $3).
@export var show_props := false:
	set = set_show_props
## Plate declutter (#216): higher priority keeps the lower (most readable)
## spot in a cluster — views give the local player 1 so their own plate
## stays glued to their head while others stagger upward.
@export var nameplate_priority := 0

var _character_root: Node3D
var _anim_player: AnimationPlayer
var _current_action: StringName = &""
var _outline_material: ShaderMaterial
var _xray_material: ShaderMaterial
var _base_font_size := NAMEPLATE_BASE_FONT
var _plate_base_y := 0.0
## Held-weapon state (#584): {mesh, bone, offset} while armed, empty otherwise.
## Kept as data so a character swap (_rebuild_character) re-arms the new body.
var _held_weapon := {}
var _held_weapon_node: BoneAttachment3D
## Msec (Time.get_ticks_msec) through which this rig's one-shot pose is
## protected from update_rig's stationary walk/idle overwrite (#942).
var _pose_protected_until := 0

@onready var _nameplate: Label3D = $Nameplate


func _enter_tree() -> void:
	_live_rigs.append(self)


func _exit_tree() -> void:
	_live_rigs.erase(self)


## Restaggers the plate every frame: positions change under snapshot
## interpolation, so cluster membership does too.
func _process(_delta: float) -> void:
	_update_plate_stack()


func _ready() -> void:
	_plate_base_y = _nameplate.position.y
	_base_font_size = int(
		NAMEPLATE_BASE_FONT * float(SettingsStore.load_settings().nameplate_scale)
	)
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_xray_material = ShaderMaterial.new()
	_xray_material.shader = XRAY_SHADER
	_outline_material.next_pass = _xray_material
	_rebuild_character()
	_apply_player_color()
	_fit_nameplate()


## Plays a semantic action (see ACTIONS). Returns false for unknown actions
## or when the loaded character lacks the animation.
func play(action: StringName) -> bool:
	if _anim_player == null or not ACTIONS.has(action):
		return false
	var entry: Dictionary = ACTIONS[action]
	var anim_name: StringName = entry.anim
	if not _anim_player.has_animation(anim_name):
		push_warning("CharacterRig: missing animation %s for action %s" % [anim_name, action])
		return false
	var animation := _anim_player.get_animation(anim_name)
	var loops: bool = entry.loop
	animation.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	_current_action = action
	_anim_player.play(anim_name)
	return true


func current_action() -> StringName:
	return _current_action


## Plays a one-shot action and protects its pose for `hold_sec` (#942): while
## the hold is active AND the rig is stationary, MinigameView3D.update_rig
## won't overwrite the pose with idle — but the walk switch still fires the
## instant the rig actually moves, so movement never stalls (#800). This is
## the msec-expiry idiom four views (fort_siege/king_of_the_hill/memory_match/
## sumo_smash) each hand-rolled with a private `_*_hold` dict. Returns play()'s
## result (false if the action is unknown / unavailable — no hold is set then).
func play_protected(action: StringName, hold_sec: float) -> bool:
	var played := play(action)
	if played:
		_pose_protected_until = Time.get_ticks_msec() + int(hold_sec * 1000.0)
	return played


## Whether play_protected()'s hold is still active. update_rig consults this to
## keep the pose while stationary; views that drive the rig by hand during a
## hold query it directly.
func is_pose_protected() -> bool:
	return Time.get_ticks_msec() < _pose_protected_until


func set_character_scene(scene: PackedScene) -> void:
	character_scene = scene
	if is_node_ready():
		_rebuild_character()
		_apply_player_color()


func set_player_color(color: Color) -> void:
	player_color = color
	if is_node_ready():
		_apply_player_color()


func set_display_name(value: String) -> void:
	display_name = value
	if is_node_ready():
		_fit_nameplate()


## Uniform plate width (#180): text wider than NAMEPLATE_MAX_WIDTH (at the
## base size, so the nameplate_scale setting still applies) shrinks its font
## to fit; shorter text keeps the base size. The outline scales along so the
## through-walls silhouette stays proportional.
func _fit_nameplate() -> void:
	_nameplate.text = display_name
	var font := _nameplate.font
	if font == null:
		font = ThemeDB.fallback_font
	var text_width := (
		font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, NAMEPLATE_BASE_FONT).x
	)
	var factor := minf(1.0, NAMEPLATE_MAX_WIDTH / maxf(text_width, 1.0))
	_nameplate.font_size = maxi(1, int(_base_font_size * factor))
	_nameplate.outline_size = maxi(1, int(20 * factor))


func set_show_props(value: bool) -> void:
	show_props = value
	if is_node_ready():
		_apply_prop_visibility()


## Puts `mesh` in the character's hand (#584): attached to `bone` (all KayKit
## rigs share "handslot.r") with `offset` relative to it, so it follows every
## animation — swing an axe with play(&"attack"). Survives character swaps.
func set_held_weapon(
	mesh: Mesh, bone: String = "handslot.r", offset: Transform3D = Transform3D()
) -> void:
	_held_weapon = {"mesh": mesh, "bone": bone, "offset": offset}
	_apply_held_weapon()


func clear_held_weapon() -> void:
	_held_weapon = {}
	_apply_held_weapon()


func has_held_weapon() -> bool:
	return not _held_weapon.is_empty()


func _apply_held_weapon() -> void:
	if _held_weapon_node != null and is_instance_valid(_held_weapon_node):
		# Freed immediately, not queued: a character swap rebuilds in the same
		# frame and must not leave the old body's axe visible for a frame.
		_held_weapon_node.get_parent().remove_child(_held_weapon_node)
		_held_weapon_node.free()
	_held_weapon_node = null
	if _held_weapon.is_empty() or _character_root == null:
		return
	var skeletons := _character_root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton: Skeleton3D = skeletons[0]
	if skeleton.find_bone(_held_weapon.bone) == -1:
		push_warning("CharacterRig: no bone %s to hold a weapon" % _held_weapon.bone)
		return
	_held_weapon_node = BoneAttachment3D.new()
	_held_weapon_node.name = "HeldWeapon"
	skeleton.add_child(_held_weapon_node)
	_held_weapon_node.bone_name = _held_weapon.bone
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = _held_weapon.mesh
	mesh_node.transform = _held_weapon.offset
	# The identity outline/silhouette layer covers the weapon too.
	mesh_node.material_overlay = _outline_material
	_held_weapon_node.add_child(mesh_node)


func _rebuild_character() -> void:
	_current_action = &""
	if _character_root != null:
		_character_root.queue_free()
		_character_root = null
	_anim_player = null
	if character_scene == null:
		return
	_character_root = character_scene.instantiate()
	add_child(_character_root)
	var players := _character_root.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim_player = players[0]
		_anim_player.animation_finished.connect(_on_animation_finished)
	for mesh: MeshInstance3D in _character_root.find_children("*", "MeshInstance3D", true, false):
		mesh.material_overlay = _outline_material
	_apply_prop_visibility()
	_apply_held_weapon()  # a character swap mid-hold re-arms the new body (#584)
	play(&"idle")


func _apply_prop_visibility() -> void:
	if _character_root == null:
		return
	for node: Node in _character_root.find_children("*", "BoneAttachment3D", true, false):
		(node as BoneAttachment3D).visible = show_props


func _apply_player_color() -> void:
	_outline_material.set_shader_parameter("outline_color", player_color)
	var ghost := player_color
	ghost.a = XRAY_ALPHA
	_xray_material.set_shader_parameter("silhouette_color", ghost)
	_nameplate.modulate = player_color


func _on_animation_finished(_anim_name: StringName) -> void:
	if _current_action != &"":
		var finished := _current_action
		_current_action = &""
		action_finished.emit(finished)


## Counts the cluster mates ranked ahead of this rig and lifts the plate one
## step per rig below it. Rank: priority first (local player lowest), then
## camera depth (nearer stays lower — its head already renders lower on
## screen), then instance id as the deterministic tiebreak.
func _update_plate_stack() -> void:
	if _nameplate == null or not visible or not is_inside_tree():
		return
	var below := 0
	for entry: Variant in _live_rigs:
		var other := entry as CharacterRig
		if other == self or other == null or not other.visible or not other.is_inside_tree():
			continue
		if other.get_viewport() != get_viewport():
			continue
		var offset := other.global_position - global_position
		if Vector2(offset.x, offset.z).length() > PLATE_CLUSTER_RADIUS:
			continue
		if _ranks_ahead(other):
			below += 1
	var target_y := _plate_base_y + below * PLATE_STACK_STEP
	if not is_equal_approx(_nameplate.position.y, target_y):
		_nameplate.position.y = target_y


func _ranks_ahead(other: CharacterRig) -> bool:
	if other.nameplate_priority != nameplate_priority:
		return other.nameplate_priority > nameplate_priority
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var forward := -camera.global_transform.basis.z
		var own_depth := forward.dot(global_position - camera.global_position)
		var other_depth := forward.dot(other.global_position - camera.global_position)
		if not is_equal_approx(own_depth, other_depth):
			return other_depth < own_depth
	return other.get_instance_id() < get_instance_id()
