class_name CharacterPreview
extends Control
## Live 3D preview of the local player's roster pick (M8-13): a small
## SubViewport hosting a single CharacterRig (M2-04) so the lobby's
## character select actually shows the character. Idles normally, cheers
## while the player is readied. M16-05: a brief scale-pop "confirm flourish"
## plays whenever the pick actually changes — no-op under reduced motion.

const RIG_SCENE := preload("res://src/characters/character_rig.tscn")
## Slow turntable so the whole character is visible (issue #133).
const TURNTABLE_RAD_PER_SEC := 0.6
## Confirm-flourish pop scale (the rig briefly grows, then settles).
const FLOURISH_SCALE := 1.15

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
	# KayKit rigs face -z natively, which is straight at the +z camera; a slow
	# turntable shows the whole character (owner: #133 shipped facing away).
	_viewport.add_child(_rig)


func _process(delta: float) -> void:
	if _rig != null:
		_rig.rotation.y = wrapf(_rig.rotation.y + TURNTABLE_RAD_PER_SEC * delta, -PI, PI)


## Points the preview at a roster entry. Cheap when nothing changed.
func show_character(id: StringName, color: Color, ready := false) -> void:
	if _rig == null:
		return
	if id != _current_id:
		_current_id = id
		_rig.character_scene = CharacterRoster.scene_for(id)
		_play_confirm_flourish()
	_rig.player_color = color
	_rig.display_name = ""
	var desired: StringName = &"cheer" if ready else &"idle"
	if _rig.current_action() != desired:
		_rig.play(desired)


## A brief pop when the pick actually changes, so swapping characters reads
## as a confirmed choice rather than a silent swap (M16-05).
func _play_confirm_flourish() -> void:
	if ArenaFX.reduced_motion:
		return
	_rig.scale = Vector3.ONE * FLOURISH_SCALE
	var tween := create_tween()
	tween.set_trans(PartyTheme.TRANS_OVERSHOOT).set_ease(PartyTheme.EASE_DEFAULT)
	tween.tween_property(_rig, "scale", Vector3.ONE, PartyTheme.DUR_MED)


func current_character() -> StringName:
	return _current_id
