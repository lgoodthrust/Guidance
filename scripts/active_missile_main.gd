extends Node3D

var yaw_drift: float = 1.0
var pitch_drift: float = 1.0
var drift_rate: float = 1.0
var current_drift: Vector2 = Vector2.ZERO
var time: float = 0.0

var forward_velocity: float = 10.0
var forward_acceleration: float = 1.0

# Yaw and pitch targets
var rotation_target_yaw: float = 0.0
var rotation_target_pitch: float = 0.0

var curr_velocity: Vector3 = Vector3.ZERO

@onready var Seeker


func _process(delta: float) -> void:
	# Accumulate time so drift changes each frame
	time += delta * drift_rate
	
	# Let the drift oscillate using sine over time
	current_drift.x = sin(time * yaw_drift * PI)/90
	current_drift.y = cos(time * pitch_drift * PI)/180


func _physics_process(delta: float) -> void:
	rotate_player(delta)
	move_player(delta)


func rotate_player(_delta: float) -> void:
	rotation_target_pitch = clamp(current_drift.y, deg_to_rad(-90), deg_to_rad(90))
	# Create quaternions from the two angles:
	#  - rotation around the Y axis for yaw
	#  - rotation around the X axis for pitch
	var yaw_quat = Quaternion(Vector3.UP, current_drift.x)
	var pitch_quat = Quaternion(Vector3.RIGHT, rotation_target_pitch)
	
	# Combine them to get the final orientation
	var final_quat = yaw_quat * pitch_quat
	
	# Apply the combined rotation as a quaternion
	global_transform.basis = Basis(final_quat)


func move_player(delta: float) -> void:
	# Currently there's no real input, but we define a Vector2 for demonstration
	var input_dir = Vector2(0,1)
	
	# Use the node's current rotation to figure out forward/right vectors
	var camera_quat = global_transform.basis.get_rotation_quaternion()
	var forward = camera_quat * Vector3.BACK
	var right = camera_quat * Vector3.RIGHT
	
	# Movement direction
	var movement_dir = (forward * input_dir.y) + (right * input_dir.x)
	if movement_dir.length() > 0.0:
		movement_dir = movement_dir.normalized()
	
	# Smooth acceleration using lerp
	curr_velocity = curr_velocity.lerp(movement_dir * forward_velocity, forward_acceleration * delta)
	
	# Noclip-style movement (directly adjust transform)
	global_transform.origin += curr_velocity * delta
