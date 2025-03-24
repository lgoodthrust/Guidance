extends RigidBody3D

# Main missile parameters
@export var thrust_force: float = 300.0
@export var lifetime: float = 25.0
@export var launch_charge_force: float = 25.0
@export var motor_delay: float = 0.35
@export var fuel_duration: float = 1.75  # How long thrust lasts
@export var proximity_detonation_radius: float = 10.0

# Seeker parameters
@export var max_range: float = 3500.0
@export var seeker_fov: float = 40.0
@export var unlocked_detonation_delay: float = 1.5

# Guidance PID gains
@export var YAW_KP: float = 1.0
@export var YAW_KI: float = 0
@export var YAW_KD: float = 0.75
@export var PITCH_KP: float = 1.0
@export var PITCH_KI: float = 0
@export var PITCH_KD: float = 0.75

@export var GAIN_0: float = 1.0
@export var GAIN_1: float = 1.0
@export var GAIN_2: float = 1.0

# Flags (set these as desired in the Inspector)
var has_motor: bool = true
var has_warhead: bool = true
var has_seeker: bool = true

# Internal state
var life: float = 0.0
var unlocked_life: float = 0.0
var smoking: bool = false
var dist = 100.0
var target: Node3D

# PID controllers for yaw and pitch
@onready var pidx = PID.new()
@onready var pidy = PID.new()
@onready var pidx1 = PID.new()
@onready var pidy1 = PID.new()
@onready var pidx2 = PID.new()
@onready var pidy2 = PID.new()

func _ready() -> void:
	# Basic physics settings
	freeze = false
	gravity_scale = 0.0
	linear_damp = 0.005
	angular_damp = 0.01
	mass = 92.0
	inertia = Vector3(1, 1, 1)
	
	# Assume mass is set by the Inspector
	
	target = get_tree().current_scene.get_node_or_null("World/Active_Target")
	
	# Apply an initial impulse in our "forward" (local Y) direction.
	#apply_central_force(-global_basis.z * launch_charge_force * mass)

var prev_vel: Vector3 = Vector3.ZERO
func _physics_process(delta: float) -> void:
	life += delta
	if life >= lifetime:
		_remove_missile()
		return
	
	# Thrust: Apply force along forward direction if within fuel duration.
	if has_motor and life > motor_delay and life < fuel_duration:
		#apply_central_force(global_transform.basis.y * thrust_force * mass)
		# Optionally trigger smoke effect here.
		if not smoking:
			smoking = true
	
	# Gravity: Apply a downward force.
	#apply_central_force(Vector3.DOWN * 9.80665 * mass)
	
	var A = 0.0 # val > 0 = +aim -flight, val < 0 = -aim +flight
	
	# Apply aerodynamic alignment (forward flight toward missile's forward direction)
	var afd = (global_transform.basis.y - linear_velocity.normalized()).normalized()
	var afm = global_transform.basis.y.angle_to(linear_velocity.normalized()) * linear_velocity.length()
	#apply_central_force(afd * afm * (1.0-A))
	
	# counteract unwanted de-acceleration forces from alignment forces
	var cur_accel = linear_velocity - prev_vel
	var anti_drag = -cur_accel * 1.25
	#apply_central_force(anti_drag * global_transform.basis.y * clamp(A,0,1))
	
	# apply aerodynamic alignment (missile toward foward flight)
	var axis = global_transform.basis.y.cross(linear_velocity.normalized())
	var angle = global_transform.basis.y.angle_to(linear_velocity.normalized())
	if axis.length() > 0.005 and angle > 0.005:
		var torque = axis.normalized() * angle
		#apply_torque(torque * clamp(linear_velocity.length(), 1.0, 30.0) * (1.0+A))
	
	if target:
		dist = global_transform.origin.distance_to(target.global_transform.origin)
	
	# Guidance: If a seeker is active, steer toward the target.
	if has_seeker:
			# Proximity detonation: Explode if too close.
			if dist <= proximity_detonation_radius and has_warhead:
				_explode_and_remove()
				return
			
			# If within range, steer toward the target.
			if dist < max_range:
				var angles = _get_target_angles(target)
				if angles != Vector2.ZERO:
					var pid_output = _pid_steering(angles, delta)
					_apply_pitch_yaw_torque(pid_output)
	
	prev_vel = linear_velocity

func _remove_missile() -> void:
	queue_free()

func _explode_and_remove() -> void:
	# Optionally instantiate explosion effects here.
	queue_free()

#------------------------------------------------------------------
# Helpers – using only the RigidBody's orientation.
#------------------------------------------------------------------
# Get the angles (yaw and pitch) between our forward direction and the target.
func _get_target_angles(target_node: Node3D) -> Vector2:
	var forward = global_transform.basis.y
	var to_target = (target_node.global_transform.origin - global_transform.origin).normalized()
	
	# Yaw: rotation about the missile's up axis (local Z).
	var right = global_basis.x
	var yaw_angle = atan2(to_target.dot(right), to_target.dot(forward))
	
	# Pitch: rotation about the missile's right axis (local X).
	var up = global_basis.z
	var pitch_angle = atan2(to_target.dot(up), to_target.dot(forward))
	
	# If the angles exceed the seeker field-of-view, return ZERO (lock lost).
	var limit = deg_to_rad(seeker_fov)
	if abs(yaw_angle) > limit or abs(pitch_angle) > limit:
		return Vector2.ZERO
	
	return Vector2(yaw_angle, pitch_angle)

# Simple PID-based steering.
# New and improved CB/DR guidance now with LR accel
var prev_angles = Vector2.ZERO
var prev_rate_angles = Vector2.ZERO
func _pid_steering(angles: Vector2, delta: float) -> Vector2:
	print()
	angles *= GAIN_0
	print("raw: ", angles)
	
	# First derivative: angular rate (LOS rate)
	var rate_angles = (angles - prev_angles) * GAIN_0 / delta
	rate_angles *= GAIN_2
	print("rate: ", rate_angles)
	
	# Second derivative: angular acceleration (LOS jerk)
	var jerk_angles = (rate_angles - prev_rate_angles) * GAIN_1 / delta
	jerk_angles *= GAIN_2
	print("jerk: ", jerk_angles)

	# Apply PID using LOS jerk as the 'error' input
	var yaw_cmd_0 = pidx.update(delta, 0.0, angles.x, YAW_KP, YAW_KI, YAW_KD)
	var pitch_cmd_0 = pidy.update(delta, 0.0, -angles.y, PITCH_KP, PITCH_KI, PITCH_KD)
	
	var yaw_cmd_1 = pidx1.update(delta, 0.0, rate_angles.x, YAW_KP, YAW_KI, YAW_KD)
	var pitch_cmd_1 = pidy1.update(delta, 0.0, -rate_angles.y, PITCH_KP, PITCH_KI, PITCH_KD)
	
	var yaw_cmd_2 = pidx2.update(delta, 0.0, rate_angles.x, YAW_KP, YAW_KI, YAW_KD)
	var pitch_cmd_2 = pidy2.update(delta, 0.0, -rate_angles.y, PITCH_KP, PITCH_KI, PITCH_KD)

	# Clamp to seeker FOV
	var yaw_cmd = clamp(yaw_cmd_0, -1, 1)
	var pitch_cmd = clamp(pitch_cmd_0, -1, 1)

	# Update state history
	prev_angles = angles
	prev_rate_angles = rate_angles

	# Output is final command vector
	return Vector2(yaw_cmd, pitch_cmd)


# Apply torque based on PID output.
# We interpret cmd.x as yaw and cmd.y as pitch.
func _apply_pitch_yaw_torque(cmd: Vector2) -> void:
	var yaw_rad = cmd.x
	var pitch_rad = cmd.y
	var right = global_basis.x
	var up = global_basis.z
	var forward = -global_basis.y
	var pitch_torque = right * pitch_rad
	var yaw_torque = up * yaw_rad
	var anti_roll_torque = -forward.cross(right)
	
	# Scale the torque by the square of the speed (clamped) for responsiveness.
	var speed = clamp(linear_velocity.length(), 1.0, 30.0)
	
	# Combine torque vectors and apply it as force
	var forces = ((pitch_torque + yaw_torque) * speed)
	apply_torque(forces)
