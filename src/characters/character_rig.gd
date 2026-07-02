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
}

const OUTLINE_SHADER := preload("res://src/characters/player_outline.gdshader")
const XRAY_SHADER := preload("res://src/characters/player_xray.gdshader")
const XRAY_ALPHA := 0.12

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

var _character_root: Node3D
var _anim_player: AnimationPlayer
var _current_action: StringName = &""
var _outline_material: ShaderMaterial
var _xray_material: ShaderMaterial

@onready var _nameplate: Label3D = $Nameplate


func _ready() -> void:
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_xray_material = ShaderMaterial.new()
	_xray_material.shader = XRAY_SHADER
	_outline_material.next_pass = _xray_material
	_rebuild_character()
	_apply_player_color()
	_nameplate.text = display_name


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
		_nameplate.text = value


func set_show_props(value: bool) -> void:
	show_props = value
	if is_node_ready():
		_apply_prop_visibility()


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
