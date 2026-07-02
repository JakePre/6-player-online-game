class_name IsoCameraRig
extends Node3D
## Fixed orthographic isometric camera rig (M2-04): the "2.5D isometric" look
## is a 3D scene under an orthographic camera at ~35 degree pitch, 45 degree
## yaw (SPEC $2, $10). Place the rig at the point to frame; it can optionally
## smooth-follow a target (e.g. the local player in racing minigames).

@export_range(20.0, 60.0) var pitch_degrees := 35.0:
	set = set_pitch_degrees
@export var yaw_degrees := 45.0:
	set = set_yaw_degrees
## Orthographic size: world units visible vertically.
@export var ortho_size := 12.0:
	set = set_ortho_size
## Back-off distance along the view ray; only affects clipping, not framing.
@export var camera_distance := 30.0:
	set = set_camera_distance
@export var follow_target: Node3D
@export var follow_speed := 6.0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_apply()


func _process(delta: float) -> void:
	if follow_target != null:
		var weight := minf(1.0, follow_speed * delta)
		global_position = global_position.lerp(follow_target.global_position, weight)


func camera() -> Camera3D:
	return _camera


func set_pitch_degrees(value: float) -> void:
	pitch_degrees = value
	_apply()


func set_yaw_degrees(value: float) -> void:
	yaw_degrees = value
	_apply()


func set_ortho_size(value: float) -> void:
	ortho_size = value
	_apply()


func set_camera_distance(value: float) -> void:
	camera_distance = value
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	_camera.size = ortho_size
	_camera.rotation_degrees = Vector3(-pitch_degrees, 0.0, 0.0)
	var pitch := deg_to_rad(pitch_degrees)
	_camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * camera_distance
