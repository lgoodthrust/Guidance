extends RigidBody3D  # Vector up = missile forward

var launcher
var blocks = []

# Configuration parameters grouped by function
@export_group("Physics")
@export var thrust_force: float = 50.0
@export var air_density_sea_level: float = 1.225
@export var min_effective_speed: float = 15.0
@export var gravity: float = 9.80665

@export_group("Aerodynamics")
@export var max_lift_coef: float = 2.0
@export var stall_angle: float = 15.0

@export_group("Structure")
@export var static_margin: float = 0.125
@export var roll_damping: float = 2.0
@export var missile_length: float = 5.0
@export var missile_diameter: float = 0.2

@export_group("Guidance")
@export var proximity_radius: float = 15.0
@export var fov: Vector2 = Vector2(30.0, 30.0)  # horizontal, vertical
@export var max_range: float = 2500.0
@export var lifetime: float = 15.0
@export var motor_delay: float = 0.1
@export var pid_values: Vector3 = Vector3(1.0, 0.0, 0.01)  # P, I, D

# Missile properties
var centers = {
	"mass": Vector3.ZERO,    # Center of mass
	"pressure": Vector3.ZERO,  # Center of pressure
	"thrust": Vector3.ZERO    # Center of thrust
}

var properties = {
	"fuel": 0,
	"mass": 0.0,
	"has_ir_seeker": false,
	"total_lift": 0.0,
	"burn_time": 0.0,
	"elapsed_time": 0.0,
}

var targeting = {
	"active": false,
	"target": null
}

var pidx
var pidy
var pidz


func _ready():
	launcher = get_parent().get_parent()
	pidx = PID.new()
	pidy = PID.new()
	pidz = PID.new()
	# Initialize missile
	load_missile_blocks()
	calculate_centers()
	setup_physics()


func setup_physics():
	freeze = false
	gravity_scale = 0
	linear_damp = 0
	angular_damp = 0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centers["mass"]
	
	# Set physical properties
	mass = max(1.0, properties["mass"])
	
	# Calculate realistic inertia tensor (for a missile treated as a cylinder)
	var inertia_xx = mass * (3 * pow(missile_diameter/2, 2) + pow(missile_length, 2)) / 12
	var inertia_yy = inertia_xx  # Same for symmetrical missile
	var inertia_zz = mass * pow(missile_diameter/2, 2) / 2
	
	inertia = Vector3(inertia_xx, inertia_yy, inertia_zz)


func load_missile_blocks():
	for block in get_children():
		if block.get_class() == "Node3D" and block.DATA.has("NAME"):
			blocks.append(block)


func calculate_centers():
	var total_mass = 0.0
	var lift_blocks = 0
	var thrust_blocks = 0
	
	for block:Node3D in blocks:
		var block_pos = block.to_global(Vector3.ZERO)  
		if block.DATA.has("TYPE"):
			if block.DATA["TYPE"] == 1:
				properties["has_ir_seeker"] = true
			if block.DATA["TYPE"] == 4 or block.DATA["TYPE"] == 5 or block.DATA["TYPE"] == 6:
				centers["pressure"] += block_pos  # Now storing center of pressure
				lift_blocks += 1
				properties["total_lift"] += block.DATA["LIFT"]
			if block.DATA["TYPE"] == 7:
				properties["fuel"] += 1
			if block.DATA["TYPE"] == 8:
				centers["thrust"] += block_pos
				thrust_blocks += 1
		
		if block.DATA.has("MASS"):
			centers["mass"] += block_pos * block.DATA["MASS"]
			total_mass += block.DATA["MASS"]
	
	properties["mass"] = total_mass
	
	# Finalize centers
	if total_mass > 0:
		centers.mass /= total_mass
	if lift_blocks > 0:
		centers.pressure /= lift_blocks
	if thrust_blocks > 0:
		centers.thrust /= thrust_blocks
	
	# Adjust center of pressure for stability
	if lift_blocks > 0:
		var direction = centers.mass.direction_to(centers.pressure)
		centers.pressure = centers.mass + direction * missile_length * static_margin
	
	# Approximate burn time assuming 3s per fuel block
	properties.burn_time = properties.fuel * 3.0


func _physics_process(delta: float) -> void:
	properties.elapsed_time += delta
	
	# Check if missile lifetime exceeded
	if properties.elapsed_time >= lifetime:
		destroy_missile()
		return
	
	# Calculate forces
	var forces = {
		"thrust": calculate_thrust(),
		"aerodynamic": Vector3.ZERO,
		"gravity": Vector3.DOWN * gravity
	}
	
	var torques = {
		"guidance": Vector3.ZERO,
		"stabilization": calculate_roll_stabilization(),
		"alignment": align_to_velocity()
	}
	
	# Apply guidance if target exists
	targeting.target = get_tree().current_scene.get_node_or_null("World/Active_Target")
	if targeting.target and properties.has_ir_seeker:
		torques.guidance = calculate_guidance_torque(delta)
	
	# Apply forces with multi-step integration for stability
	apply_physics_forces(forces, torques, delta)


func calculate_thrust() -> Vector3:
	# No thrust before motor delay or after burn time
	if properties.elapsed_time < motor_delay or properties.elapsed_time > properties.burn_time:
		return Vector3.ZERO
	
	var thrust_dir = global_transform.basis.y.normalized()
	
	# Calculate thrust modifiers
	var altitude_factor = exp(-get_altitude() / 15000.0)
	
	# Thrust profile (simplified bell curve)
	var norm_burn_time = (properties.elapsed_time - motor_delay) / (properties.burn_time - motor_delay)
	var thrust_profile = 1.0
	
	if norm_burn_time <= 0.2:  # Ramp up
		thrust_profile = norm_burn_time / 0.2
	elif norm_burn_time >= 0.8:  # Ramp down
		thrust_profile = 1.0 - (norm_burn_time - 0.8) / 0.2
	
	var combined_force = thrust_dir * thrust_force * altitude_factor * thrust_profile
	
	return combined_force


func get_altitude() -> float:
	# Simple altitude estimation - could be improved with actual terrain data
	return global_position.y


func get_aoa_aos() -> Vector2:
	var velocity = linear_velocity
	var speed = velocity.length()
	
	if speed < min_effective_speed:
		return Vector2.ZERO
	
	var missile_forward = global_transform.basis.y.normalized()
	var velocity_dir = velocity.normalized()
	
	# Angle of attack (pitch)
	var dot_product = missile_forward.dot(velocity_dir)
	var aoa = acos(clamp(dot_product, -1.0, 1.0))
	
	# Angle of slip (yaw)
	var missile_right = global_transform.basis.x.normalized()
	var side_component = velocity_dir.dot(missile_right)
	var aos = asin(clamp(side_component, -1.0, 1.0))
	
	return Vector2(aoa, aos)


func calculate_roll_stabilization() -> Vector3:
	var roll_rate = angular_velocity.z
	return Vector3(0, 0, -roll_rate * roll_damping)


func align_to_velocity() -> Vector3:
	var velocity = linear_velocity
	if velocity.length() < min_effective_speed:
		return Vector3.ZERO
	
	# returns scaled velocity as a vector
	var desired_dir = velocity.normalized()
	var current_dir = global_transform.basis.y.normalized()
	
	var rotation_axis = current_dir.cross(desired_dir)
	var angle = acos(clamp(current_dir.dot(desired_dir), -1, 1))
	
	if angle > 0.01:  
		return rotation_axis.normalized() * angle * 0.5 * mass * properties.total_lift
	
	return Vector3.ZERO


func calculate_guidance_torque(_delta: float) -> Vector3:
	if not targeting.target:
		return Vector3.ZERO
	
	var speed = linear_velocity.length()
	if speed < min_effective_speed:
		return Vector3.ZERO
	
	# Calculate direction to target
	var to_target = targeting.target.global_position - global_position
	var desired_dir = to_target.normalized()
	var current_dir = global_transform.basis.y.normalized()
	
	# Calculate error angle and axis
	var dot_val = clamp(current_dir.dot(desired_dir), -1.0, 1.0)
	var error_angle = acos(dot_val)
	
	var error_axis = current_dir.cross(desired_dir)
	if error_axis.length() < 0.001:
		return Vector3.ZERO  # Already aligned
	
	error_axis = error_axis.normalized()
	
	# Calculate guidance torque based on speed and total lift authority
	var gain = properties.total_lift
	var speed_scale = clamp(speed / min_effective_speed, 0.0, max_lift_coef)
	
	return error_axis * (error_angle * gain * speed_scale)


func apply_physics_forces(forces, torques, delta):
	var substeps = 3
	var _sub_delta = delta / substeps
	
	for _i in range(substeps):
		# Combine all forces
		var total_force = forces.thrust + forces.gravity
		
		# Combine all torques
		var total_torque = torques.guidance + torques.stabilization + torques.alignment
		
		# Scale torque using proper inertia
		var inverse_inertia = Vector3(
			1.0 / max(0.05, inertia.x),
			1.0 / max(0.05, inertia.y),
			1.0 / max(0.05, inertia.z)
		)
		
		var scaled_torque = Vector3(
			total_torque.x * inverse_inertia.x,
			total_torque.y * inverse_inertia.y,
			total_torque.z * inverse_inertia.z
		)
		
		# Apply limits to prevent instability
		var clamped_force = total_force.limit_length(100000.0)
		var clamped_torque = scaled_torque.limit_length(10000.0)
		
		apply_force(clamped_force / substeps, centers["thrust"])
		
		var angles = get_aoa_aos()
		var total_angle = rad_to_deg(angles.x) + rad_to_deg(angles.y)
		
		if total_angle > stall_angle:
			apply_torque((clamped_torque / substeps) / total_angle)
		else:
			apply_torque((clamped_torque / substeps))


func destroy_missile():
	var missile_list = LAUCNHER_CHILD_SHARE_GET("world", "missiles")
	if missile_list:
		missile_list.pop_back()
		LAUCNHER_CHILD_SHARE_SET("world", "missiles", missile_list)
	queue_free()


func LAUCNHER_CHILD_SHARE_SET(scene, key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data

func LAUCNHER_CHILD_SHARE_GET(scene, key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key]
		return data
