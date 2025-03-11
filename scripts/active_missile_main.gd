extends RigidBody3D  # Vector up = missile forward

@export var thrust_force: float = 10000.0
@export var min_speed: float = 50.0
@export var lifetime: float = 10.0
@export var max_range = 3000.0
@export var seeker_fov = 30.0
@export var motor_delay = 0.1
@export var fuel_block_duration = 2.0
@export var launch_charge_force = 100.0

var launcher
var blocks = []
var life := 0.0
var ao

var centers = {
	"mass": Vector3.ZERO,
	"pressure": Vector3.ZERO,
	"thrust": Vector3.ZERO
}

var properties = {
	"fuel": 0,
	"mass": 0.0,
	"has_ir_seeker": false,
	"total_lift": 0.0
}

@onready var pidx = PID.new()
@onready var pidy = PID.new()

func _ready() -> void:
	launcher = get_parent().get_parent()
	load_missile_blocks()
	calculate_centers()
	
	# Minimal physics setup
	freeze = false
	gravity_scale = 0.0
	linear_damp = 0.0
	angular_damp = 2.0
	mass = max(1.0, properties["mass"])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centers["mass"]
	
	# Small impulse at spawn
	apply_impulse(global_transform.basis.y.normalized() * launch_charge_force)

func load_missile_blocks() -> void:
	for child in get_children():
		if child.get_class() == "Node3D" and child.DATA.has("NAME"):
			blocks.append(child)

func calculate_centers() -> void:
	var total_mass = 0.0
	var lift_blocks = 0
	var thrust_blocks = 0
	
	for block:Node3D in blocks:
		var block_pos = block.to_global(Vector3.ZERO)
		if block.DATA.has("TYPE"):
			if block.DATA["TYPE"] == 1:
				properties["has_ir_seeker"] = true
	
			if block.DATA["TYPE"] == 4 or block.DATA["TYPE"] == 5 or block.DATA["TYPE"] == 6:
				centers["pressure"] += block_pos
				lift_blocks += 1
				properties["total_lift"] += block.DATA["LIFT"]
	
			if block.DATA["TYPE"] == 7:
				properties["fuel"] += fuel_block_duration
	
			if block.DATA["TYPE"] == 8:
				centers["thrust"] += block_pos
				thrust_blocks += 1
		
		if block.DATA.has("MASS"):
			centers["mass"] += block_pos * block.DATA["MASS"]
			total_mass += block.DATA["MASS"]
	
	properties["mass"] = total_mass
	
	# Average out centers if needed
	if total_mass > 0:
		centers["mass"] /= total_mass
	if lift_blocks > 0:
		centers["pressure"] /= lift_blocks
	if thrust_blocks > 0:
		centers["thrust"] /= thrust_blocks

func _physics_process(delta: float) -> void:
	life += delta
	
	if life >= lifetime:
		var missile_list = launcher.LAUCNHER_CHILD_SHARED_DATA["world"]["missiles"]
		if missile_list:
			missile_list.pop_back()
			launcher.LAUCNHER_CHILD_SHARED_DATA["world"]["missiles"] = missile_list
		queue_free()
	
	var forward_dir = global_transform.basis.y.normalized()
	
	# Apply thrust if there's still "fuel" time
	if properties["fuel"] > life and lifetime > motor_delay:
		apply_force(forward_dir * thrust_force, centers["thrust"])

	# Apply weight force
	apply_central_force(Vector3.DOWN * 9.80665 * properties["mass"])
	
	# If moving faster than a certain speed
	if linear_velocity.length() > min_speed:
		# apply aerodynamic alignment (dir toward missile)
		var inv_vel_dir = linear_velocity.normalized()
		var inv_axis = inv_vel_dir.cross(forward_dir)
		var inv_angle = inv_vel_dir.angle_to(forward_dir)
		if inv_axis.length() > 0.001 and inv_angle > 0.001:
			inv_axis = inv_axis.normalized()
			var inv_torque = inv_axis * inv_angle
			apply_torque(inv_torque * linear_velocity.length_squared())
		
		# apply aerodynamic alignment (missile toward dir)
		var vel_dir = linear_velocity.normalized()
		var axis = forward_dir.cross(vel_dir)
		var angle = forward_dir.angle_to(vel_dir)
		if axis.length() > 0.001 and angle > 0.001:
			axis = axis.normalized()
			var torque = axis * angle
			apply_torque(torque * linear_velocity.length_squared())
		
		aim_and_torque_at_target(delta)

func aim_and_torque_at_target(delta):
	var target = get_tree().current_scene.get_node_or_null("World/Active_Target")
	if not target:
		return
	
	var target_distance = global_transform.origin.distance_to(target.global_transform.origin)
	
	# If in range and we have IR seeker, we attempt to steer
	if target_distance < max_range and properties.has_ir_seeker:
		var input_angles = _get_target_angles_in_degrees(target)
		var guidance_output = guidance_control_law(input_angles, delta)
		
		_apply_pitch_yaw_torque(guidance_output)

# ----------------------------------------------------------
#  CUSTOM GUIDANCE LAW
# ----------------------------------------------------------
var prev_relative_angles = Vector2.ZERO
func guidance_control_law(relative_angles: Vector2, delta) -> Vector2:
	var xval = -relative_angles.x # x angle of target
	var yval = relative_angles.y # y angle of target
	var xval_d = xval - prev_relative_angles.x # rate of x angle of target
	var yval_d = yval - prev_relative_angles.y # rate of x angle of target
	var vel = global_transform.basis.y.length() # forward velocity
	
	var kp = 1.0
	var ki = 0.0
	var kd = 0.0
	
	 # pid.update(delta time, target, current, kp, ki, kd)
	var horizontal = pidx.update(delta, xval, xval_d, kp, ki, kd)
	var vertical = pidy.update(delta, yval, yval_d, kp, ki, kd)
	
	# ignore
	var pitch_cmd = clamp(vertical, -90, 90.0)
	var yaw_cmd   = clamp(horizontal, -90.0, 90.0)
	var output = Vector2(pitch_cmd, yaw_cmd)
	prev_relative_angles = output
	return output

# ----------------------------------------------------------
#   HELPER: Compute horizontal & vertical angles (in degrees)
#   from missile forward direction to the target
# ----------------------------------------------------------
func _get_target_angles_in_degrees(target: Node3D) -> Vector2:
	var forward_dir = global_transform.basis.y
	var to_target = (target.global_transform.origin - global_transform.origin).normalized()
	
	# Horizontal angle (yaw-like):
	var right_dir = global_transform.basis.x
	var horizontal_angle_radians = atan2(
		to_target.dot(right_dir),
		to_target.dot(forward_dir)
	)
	var horizontal_angle_degrees = rad_to_deg(horizontal_angle_radians)
	
	# Vertical angle (pitch-like):
	var up_dir = global_transform.basis.z
	var vertical_angle_radians = atan2(
		to_target.dot(up_dir),
		to_target.dot(forward_dir)
	)
	var vertical_angle_degrees = rad_to_deg(vertical_angle_radians)
	
	# if the missile can see the target, it can see the target
	if vertical_angle_degrees > seeker_fov or horizontal_angle_degrees > seeker_fov:
		vertical_angle_degrees = 0
		horizontal_angle_degrees = 0
	
	return Vector2(horizontal_angle_degrees, vertical_angle_degrees)

# ----------------------------------------------------------
#   HELPER: Apply the pitch/yaw torque in degrees
# ----------------------------------------------------------
func _apply_pitch_yaw_torque(guidance_output: Vector2) -> void:
	var pitch_rad = deg_to_rad(guidance_output.x)
	var yaw_rad   = deg_to_rad(guidance_output.y)
	
	var local_x = global_transform.basis.x.normalized()
	var local_z = global_transform.basis.z.normalized()
	
	var pitch_torque = local_x * pitch_rad
	var yaw_torque   = local_z * yaw_rad
	
	apply_torque((pitch_torque + yaw_torque) * linear_velocity.length_squared())
