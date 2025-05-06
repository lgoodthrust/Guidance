extends Node3D

var launcher: Node

var yaw_drift: float = 90.0
var pitch_drift: float = 10.0
var drift_rate: float = 0.5
var current_drift: Vector2 = Vector2.ZERO
var time: float = 0.0
var radius: float = 10.0

var forward_velocity: float = 100.0
var forward_acceleration: float = 15.0

# Yaw and pitch targets
var rotation_target_yaw: float = PI
var rotation_target_pitch: float = 0.0
var curr_velocity: Vector3 = Vector3.ZERO

func _ready():
	launcher = get_tree().root.get_node("./Launcher")

func _process(delta: float) -> void:
	time += delta * drift_rate
	current_drift.x = deg_to_rad(yaw_drift) + (time*PI/radius)*PI
	current_drift.y = deg_to_rad(pitch_drift) * cos(time*PI)

func _physics_process(delta: float) -> void:
	_rotate()
	_move(delta)

func _rotate() -> void:
	rotation_target_pitch = clamp(current_drift.y, deg_to_rad(-90), deg_to_rad(90))
	var yaw_quat = Quaternion(Vector3.UP, (current_drift.x + rotation_target_yaw))
	var pitch_quat = Quaternion(Vector3.RIGHT, (rotation_target_pitch + rotation_target_pitch))
	var final_quat = yaw_quat * pitch_quat
	global_transform.basis = Basis(final_quat)

func _move(delta: float) -> void:
	var input_dir = Vector2(0,1)
	var camera_quat = global_transform.basis.get_rotation_quaternion()
	var forward = camera_quat * Vector3.BACK
	var right = camera_quat * Vector3.RIGHT
	var movement_dir = (forward * input_dir.y) + (right * input_dir.x)
	movement_dir = movement_dir.normalized()
	curr_velocity = curr_velocity.lerp(movement_dir * forward_velocity, forward_acceleration * delta)
	global_transform.origin += curr_velocity * delta

func LAUCNHER_CHILD_SHARE_SET(scene, key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data

func LAUCNHER_CHILD_SHARE_GET(scene, key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key]
		return data
