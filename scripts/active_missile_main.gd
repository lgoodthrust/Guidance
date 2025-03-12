extends RigidBody3D  # Vector up = missile forward

@export var thrust_force: float = 30000.0
@export var min_speed: float = 30.0
@export var lifetime: float = 15.0
@export var max_range = 3500.0
@export var seeker_fov = 30.0
@export var motor_delay = 0.25
@export var fuel_block_duration = 0.75
@export var launch_charge_force = 1000.0

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
	"total_lift": 0.0,
	"has_ir_seeker": false,
	"has_front_cannard": false,
	"has_back_cannard": false,
	"has_fin": false,
	"has_motor": false
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
	linear_damp = 0.001
	angular_damp = 2.0
	mass = max(1.0, properties["mass"])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centers["mass"]

func load_missile_blocks() -> void:
	for child in get_children():
		if child.get_class() == "Node3D" and child.DATA.has("NAME"):
			blocks.append(child)

func calculate_centers() -> void:
	var lift_blocks = 0
	var thrust_blocks = 0
	
	for block:Node3D in blocks:
		var block_pos = block.to_global(Vector3.ZERO)
		if block.DATA.has("TYPE"):
			if block.DATA["TYPE"] == 1:
				properties["has_ir_seeker"] = true
	
			if block.DATA["TYPE"] == 4:
				properties["has_fin"] = true
				centers["pressure"] += block_pos
				lift_blocks += 1
				properties["total_lift"] += block.DATA["LIFT"]
			
			if block.DATA["TYPE"] == 5:
				properties["has_front_cannard"] = true
				centers["pressure"] += block_pos
				lift_blocks += 1
				properties["total_lift"] += block.DATA["LIFT"]
			
			if block.DATA["TYPE"] == 6:
				properties["has_back_cannard"] = true
				centers["pressure"] += block_pos
				lift_blocks += 1
				properties["total_lift"] += block.DATA["LIFT"]
			
			if block.DATA["TYPE"] == 7:
				properties["fuel"] += fuel_block_duration
			
			if block.DATA["TYPE"] == 8:
				properties["has_motor"] = true
				centers["thrust"] += block_pos
				thrust_blocks += 1
		
		if block.DATA.has("MASS"):
			centers["mass"] += block_pos * block.DATA["MASS"]
			properties["mass"] += block.DATA["MASS"]
	
	# Average out centers if needed
	if properties["mass"] > 0:
		centers["mass"] /= properties["mass"]
	if lift_blocks > 0:
		centers["pressure"] /= lift_blocks
	if thrust_blocks > 0:
		centers["thrust"] /= thrust_blocks

func _physics_process(delta: float) -> void:
	if life < 0.01:
		# Small impulse at spawn
		apply_impulse(global_transform.basis.y.normalized() * launch_charge_force)
	
	life += delta
	
	if life >= lifetime:
		var missile_list = launcher.LAUCNHER_CHILD_SHARED_DATA["world"]["missiles"]
		if missile_list:
			missile_list.pop_back()
			launcher.LAUCNHER_CHILD_SHARED_DATA["world"]["missiles"] = missile_list
		queue_free()
	
	var forward_dir = global_transform.basis.y.normalized()
	
	# Apply thrust if there's still "fuel" time
	if properties["fuel"] > life and lifetime > motor_delay and properties["has_motor"]:
		apply_force(forward_dir * thrust_force, centers["thrust"])

	# Apply weight force
	apply_central_force(Vector3.DOWN * 9.80665 * properties["mass"])
	
	# If moving faster than a certain speed
	if linear_velocity.length() > min_speed:
		# Apply aerodynamic alignment (forward flight toward missile's forward direction)
		var vel_dir = linear_velocity.normalized()
		var afd = (forward_dir - vel_dir).normalized()
		var afm = forward_dir.angle_to(vel_dir) * linear_velocity.length_squared()
		apply_central_force(afd * afm * 0.8)
		
		# apply aerodynamic alignment (missile toward foward flight)
		var axis = forward_dir.cross(vel_dir)
		var angle = forward_dir.angle_to(vel_dir)
		if axis.length() > 0.001 and angle > 0.001:
			var torque = axis.normalized() * angle
			apply_torque(torque * linear_velocity.length_squared() * 1.2)
		
		aim_and_torque_at_target(delta)

func aim_and_torque_at_target(delta):
	var target = get_tree().current_scene.get_node_or_null("World/Active_Target")
	if not target:
		return
	
	var target_distance = global_transform.origin.distance_to(target.global_transform.origin)
	
	# If in range and we have IR seeker, we attempt to steer
	if target_distance < max_range and properties["has_ir_seeker"] and properties["has_motor"]:
		var input_angles = _get_target_angles_in_degrees(target)
		var guidance_output = guidance_control_law(input_angles, delta)
		
		_apply_pitch_yaw_torque(guidance_output)

# ----------------------------------------------------------
#  CUSTOM GUIDANCE LAW
# ----------------------------------------------------------
var prev_angles = Vector2.ZERO  # store angles from previous frame
var p_tick := 8
var p_tick_cur := 0
func guidance_control_law(relative_angles: Vector2, delta: float) -> Vector2:
	p_tick_cur += 1
	# `relative_angles.x` => horizontal angle (degrees) from forward
	# `relative_angles.y` => vertical angle   (degrees) from forward
	
	# Convert to local variables, flipping sign if needed for your coordinate system
	var xval = -relative_angles.x
	var yval =  relative_angles.y

	# Calculate LOS angle rates (deg/s)
	var d_xval = (xval - prev_angles.x) / delta
	var d_yval = (yval - prev_angles.y) / delta
	
	# Missile speed along forward axis (approx "closing speed" if target is in front).
	var vel = linear_velocity.length()

	# *** Basic ProNav-like command:  turn_rate ~ N * vel * LOS_rate
	# We keep it in degrees for simplicity. 
	# If your angles are small and you want more subtle control, reduce the scale or N.
	var kp = 1.0
	var ki = 0.5 * (vel/100.0)
	var kd = 0.0
	
	 # pid.update(delta time, target, current, kp, ki, kd)
	var cmd_x = pidx.update(delta, xval, 0, kp, ki, kd)
	var cmd_y = pidy.update(delta, yval, 0, kp, ki, kd)
	
	if p_tick_cur >= p_tick:
		print()
		print("angle x: ", cmd_x)
		print("angle y: ", cmd_y)
		p_tick_cur = 0

	# Clamp commands and update prev_angles for next frame
	cmd_x = clamp(cmd_x, -90.0, 90.0)
	cmd_y   = clamp(cmd_y,   -90.0, 90.0)
	prev_angles = Vector2(xval, yval)
	return Vector2(cmd_y, cmd_x)

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
	if abs(vertical_angle_degrees) > seeker_fov or abs(horizontal_angle_degrees) > seeker_fov:
		return Vector2.ZERO
	
	return Vector2(horizontal_angle_degrees, vertical_angle_degrees)

# ----------------------------------------------------------
#   HELPER: Apply the pitch/yaw torque in degrees
# ----------------------------------------------------------
func _apply_pitch_yaw_torque(guidance_output: Vector2) -> void:
	var pitch_rad = deg_to_rad(guidance_output.x)/PI
	var yaw_rad   = deg_to_rad(guidance_output.y)/PI
	
	var local_x = global_transform.basis.x.normalized()
	var local_z = global_transform.basis.z.normalized()
	
	var pitch_torque = local_x * pitch_rad * 10.0
	var yaw_torque   = local_z * yaw_rad * 10.0
	
	apply_torque((pitch_torque + yaw_torque) * linear_velocity.length_squared())
