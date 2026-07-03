class_name CharacterPreview
extends Control
## Live 3D preview of the local player's roster pick (M8-13): a small
## SubViewport hosting a single CharacterRig (M2-04) so the lobby's
## character select actually shows the character. Idles normally, cheers
## while the player is readied.

const RIG_SCENE := preload("res://src/characters/character_rig.tscn")

var _rig: CharacterRig
var _current_id: StringName = &""
var _viewport: SubViewport


func _ready() -> void:
	var container := SubViewportContainer.new()
	container.name = "PreviewContainer"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	container.add_child(_viewport)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	_viewport.add_child(light)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.2, 2.6)
	camera.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	camera.current = true
	_viewport.add_child(camera)

	_rig = RIG_SCENE.instantiate()
	_rig.name = "PreviewRig"
	# The rig faces +z out of the screen toward the camera.
	_rig.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	_viewport.add_child(_rig)


## Points the preview at a roster entry. Cheap when nothing changed.
func show_character(id: StringName, color: Color, ready := false) -> void:
	if _rig == null:
		return
	if id != _current_id:
		_current_id = id
		_rig.character_scene = CharacterRoster.scene_for(id)
	_rig.player_color = color
	_rig.display_name = ""
	var desired: StringName = &"cheer" if ready else &"idle"
	if _rig.current_action() != desired:
		_rig.play(desired)


func current_character() -> StringName:
	return _current_id
