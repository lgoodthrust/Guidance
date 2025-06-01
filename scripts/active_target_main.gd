extends Node3D

var HEALTH: float = 100.0

var yaw_drift: float = 90.0
var pitch_drift: float = 10.0
var drift_rate: float = 0.5
var current_drift: Vector2 = Vector2.ZERO
var time: float = 0.0
var radius: float = 100.0

var forward_velocity: float = 50.0
var forward_acc: float = 15.0

# Yaw and pitch targets
var rotation_target_yaw: float = PI
var rotation_target_pitch: float = 0.0
var curr_velocity: Vector3 = Vector3.ZERO
var curr_pos: Vector3 = Vector3.ZERO

@onready var particles: gpu_particle_effects = gpu_particle_effects.new()

@onready var launcher = get_tree().root.get_node("Launcher")

func _process(delta: float) -> void:
	time += delta * drift_rate
	current_drift.x = deg_to_rad(yaw_drift) + (time/radius)*forward_velocity
	current_drift.y = deg_to_rad(pitch_drift) * cos(time*PI)

func _physics_process(delta: float) -> void:
	curr_pos = global_position
	_rotate()
	_move(delta)
	
	if HEALTH <= 0.0:
		_explode_and_remove()

func _explode_and_remove() -> void:
	var kaboom = particles.explotion_01()
	get_tree().current_scene.get_node(".").add_child(kaboom)
	kaboom.global_position = global_transform.origin
	self.hide()
	await get_tree().create_timer(0.05).timeout
	var targs: Array = launcher.LAUCNHER_CHILD_SHARED_DATA["scenes"]["targets"]
	var self_id = targs.find(self)
	launcher.LAUCNHER_CHILD_SHARED_DATA["scenes"]["targets"].pop_at(self_id)
	queue_free()

func _rotate() -> void:
	rotation_target_pitch = clamp(current_drift.y, deg_to_rad(-90), deg_to_rad(90))
	var yaw_quat = Quaternion(Vector3.UP, (current_drift.x + rotation_target_yaw))
	var pitch_quat = Quaternion(Vector3.RIGHT, (rotation_target_pitch + rotation_target_pitch))
	var final_quat = yaw_quat * pitch_quat
	global_basis = Basis(final_quat)

func _move(delta: float) -> void:
	var input_dir = Vector2(0,1)
	var quat_rot = global_basis.get_rotation_quaternion()
	var forward = quat_rot * Vector3.BACK
	var right = quat_rot * Vector3.RIGHT
	var movement_dir = (forward * input_dir.y) + (right * input_dir.x)
	movement_dir = movement_dir.normalized()
	curr_velocity = curr_velocity.lerp(movement_dir * forward_velocity, forward_acc * delta)
	global_position = curr_pos + (curr_velocity * delta)
