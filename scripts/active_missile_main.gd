extends Node3D

var yaw_drift = 1.0
var pitch_drift = 1.0
var current_drift: Vector2 = Vector2(0,0)
var time = 0.0
var forward_velocity = 150.0
var forward_acceleration = 25.0
var rotation_target_object
var rotation_target
var current_velocity

var start_pos: Vector3

func _ready():
	start_pos = global_position

func _process(delta: float) -> void:
	time += delta
	current_drift.x = sin(yaw_drift * PI)
	current_drift.y = sin(pitch_drift * PI)
	set_rotation_target(current_drift)

func _physics_process(delta: float) -> void:
		move_player(delta)
		rotate_player(delta)

func set_rotation_target(motion : Vector2):
	rotation_target_object += -motion.x
	rotation_target += -motion.y
	rotation_target = clamp(rotation_target, deg_to_rad(-90), deg_to_rad(90))
	
func rotate_player(_delta):
	quaternion = Quaternion(Vector3.UP, rotation_target_object)
	self.quaternion = Quaternion(Vector3.RIGHT, rotation_target)

func move_player(delta):
	var input_dir = [0,1]
	
	var speed = forward_velocity
	var accel = forward_acceleration
	# Get current camera rotation as a quaternion
	var camera_quat = self.global_transform.basis.get_rotation_quaternion()
	# Get movement directions based on camera quaternion
	var forward = camera_quat * Vector3.BACK
	var right = camera_quat * Vector3.RIGHT
	# Compute movement direction in 3D space
	var movement_dir = (forward * input_dir.y) + (right * input_dir.x)
	if movement_dir.length() > 0.0:
		movement_dir = movement_dir.normalized()
	# Apply movement using lerp for smooth acceleration
	current_velocity = current_velocity.lerp(movement_dir * speed, accel * delta)
	# Directly move the player in noclip (bypassing physics)
	global_transform.origin += current_velocity * delta
