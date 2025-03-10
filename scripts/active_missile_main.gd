extends RigidBody3D  # Vector up = missile forward

var papa: Node3D
var launcher = Node # FOR DATA SHARE

@export_subgroup("PHYSICS")
@export var thrust_force: float = 10000.0
@export var air_density_sea_level: float = 1.225  # kg/m^3 at sea level
@export var min_effective_speed: float = 15.0
@export var reference_area: float = 0.05  # m^2, frontal area

# Aerodynamic coefficients
@export_subgroup("AERODYNAMICS")
@export var zero_lift_drag_coef: float = 0.04  # Cd0, drag at zero lift
@export var induced_drag_factor: float = 0.1  # K, induced drag factor
@export var lift_curve_slope: float = 3.0  # Cl_alpha, lift per angle of attack
@export var max_lift_coef: float = 1.2  # Maximum lift coefficient
@export var stall_angle: float = 15.0  # Degrees
@export var form_factor: float = 1.1  # Shape factor for drag

# Flight dynamics
@export_subgroup("FLIGHT DYNAMICS")
@export var static_margin: float = 0.05  # Distance between CG and CP as fraction of length
@export var roll_damping: float = 2.0  # Damping coefficient for roll
@export var pitch_damping: float = 1.5  # Damping coefficient for pitch
@export var yaw_damping: float = 1.5  # Damping coefficient for yaw
@export var missile_length: float = 5.0  # Length in meters
@export var missile_diameter: float = 0.2  # Diameter in meters

@export_subgroup("MAIN")
@export var prox_det_radius: float = 15.0
@export var horizontal_fov: float = 30.0
@export var vertical_fov: float = 30.0
@export var max_range: float = 2500.0
@export var msl_lifetime: float = 10.0
@export var motor_delay: float = 0.0
@export var P = 1.0
@export var I = 0.0
@export var D = 1.0

var COM: Vector3 = Vector3.ZERO  # Center of mass
var CP: Vector3 = Vector3.ZERO   # Center of pressure
var COT: Vector3 = Vector3.ZERO  # Center of thrust

var blocks := []
var fuel: int = 0
var has_ir_seeker: bool = true
var TLA: float = 0.0
var burn_time = 0.0

var msl_life: float = 0.0
var XY: Vector2 = Vector2.ZERO
var TARGETING: bool = false
var target_node: Node3D = null
var current_angular_velocity

var pidX
var pidY

# Cached values for performance
var previous_velocity := Vector3.ZERO
var current_acceleration := Vector3.ZERO
var current_mach_number := 0.0
var current_reynolds_number := 0.0
var current_dynamic_pressure := 0.0
var current_altitude := 0.0

# Variables for custom integrator
var accumulated_force := Vector3.ZERO
var accumulated_torque := Vector3.ZERO

func _ready():
	papa = get_parent()
	launcher = papa.get_parent() # FOR DATA SHARE
	self.global_position = self.global_position
	self.freeze = false
	self.gravity_scale = 0
	self.linear_damp = 0
	self.angular_damp = 0
	self.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	
	for block in get_children():
		if block.get_class() == "Node3D":
			if block.DATA.has("NAME"):
				blocks.append(block)
	
	var total_mass := 0.0
	var lift_blocks: int = 0
	var thrust_blocks: int = 0
	
	for block:Node3D in blocks:
		var block_pos = block.to_global(Vector3.ZERO)  
		if block.DATA.has("TYPE"):
			if block.DATA["TYPE"] == 1:
				has_ir_seeker = true
			if block.DATA["TYPE"] == 4 or block.DATA["TYPE"] == 5 or block.DATA["TYPE"] == 6:
				CP += block_pos  # Now storing center of pressure
				lift_blocks += 1
				TLA += block.DATA["LIFT"]
			if block.DATA["TYPE"] == 7:
				fuel += 1
			if block.DATA["TYPE"] == 8:
				COT += block_pos
				thrust_blocks += 1
		
		if block.DATA.has("MASS"):
			COM += block_pos * block.DATA["MASS"]
			total_mass += block.DATA["MASS"]
	
	COM /= max(1, total_mass)
	CP /= max(1, lift_blocks)
	
	# Adjust CP to be behind COM for stability
	var direction = COM.direction_to(CP)
	CP = COM + direction * missile_length * static_margin
	
	COT /= max(1, thrust_blocks)
	
	self.mass = max(1.0, total_mass)
	
	# More realistic inertia tensor based on missile shape
	var inertia_xx = self.mass * (3 * pow(missile_diameter/2, 2) + pow(missile_length, 2)) / 12
	var inertia_yy = self.mass * (3 * pow(missile_diameter/2, 2) + pow(missile_length, 2)) / 12
	var inertia_zz = self.mass * pow(missile_diameter/2, 2) / 2
	
	self.inertia = Vector3(inertia_xx, inertia_yy, inertia_zz)
	self.center_of_mass = COM#Vector3(0, 0.0, 0)
	
	burn_time = fuel * 1.5
	
	pidX = PID.new()
	pidY = PID.new()


# --------------------
# THRUST
# --------------------
func calculate_thrust() -> Vector3:
	var thrust_dir = self.global_transform.basis.y
	
	# Ensure thrust_offset is valid
	var thrust_offset = COT - COM
	if thrust_offset.length_squared() < 0.0001:  
		thrust_offset = Vector3(0, 0.01, 0)  # Small offset to prevent zero division
	
	# Compute thrust torque (add to accumulated torque directly)
	var thrust_torque = thrust_offset.cross(thrust_dir * thrust_force)
	accumulated_torque += thrust_torque
	
	# Reduce thrust with altitude (simplified model)
	var altitude_factor = exp(-current_altitude / 15000.0)  # Thrust decreases with altitude
	
	# Vary thrust during burn (simplified bell curve)
	var normalized_burn_time = (msl_life - motor_delay) / (burn_time - motor_delay)
	var thrust_profile = 1.0
	if normalized_burn_time <= 0.2:  # Ramp up
		thrust_profile = normalized_burn_time / 0.2
	elif normalized_burn_time >= 0.8:  # Ramp down
		thrust_profile = 1.0 - (normalized_burn_time - 0.8) / 0.2
	
	var _thrust_force = thrust_dir * thrust_force * altitude_factor * thrust_profile
	
	#print("Thrust Force Applied:", _thrust_force)
	
	accumulated_force += _thrust_force
	
	return _thrust_force  # Return thrust for debugging


# --------------------
# GUIDANCE
# --------------------
func calculate_guidance_force(target_pos: Vector3, _delta: float) -> Vector3:
	var to_target = target_pos - self.global_transform.origin
	var distance = to_target.length()

	if distance > max_range:
		return Vector3.ZERO  

	var local_target = self.global_transform.basis.inverse() * to_target.normalized()

	var yaw_error = rad_to_deg(atan2(local_target.x, local_target.y))
	var pitch_error = rad_to_deg(atan2(local_target.z, local_target.y))

	if abs(yaw_error) > horizontal_fov * 0.5 or abs(pitch_error) > vertical_fov * 0.5:
		return Vector3.ZERO

	var guidance_strength = clamp(distance / max_range, 0.1, 1.0)

	var lateral_force = self.transform.basis.x * (-yaw_error * guidance_strength) + transform.basis.z * (-pitch_error * guidance_strength)
	return lateral_force.limit_length(100000.0)


# --------------------
# TARGET TRACKING
# --------------------
func get_relative_angles_to_target(target_global_position: Vector3) -> Vector2:
	var to_target = target_global_position - self.global_transform.origin
	var distance = to_target.length()

	if distance > max_range:
		return Vector2.INF

	var local_direction = self.global_transform.basis.inverse() * to_target.normalized()
	var yaw_deg = rad_to_deg(atan2(local_direction.x, local_direction.y))
	var pitch_deg = rad_to_deg(atan2(local_direction.z, local_direction.y))

	if abs(yaw_deg) <= horizontal_fov * 0.5 and abs(pitch_deg) <= vertical_fov * 0.5:
		return Vector2(yaw_deg, pitch_deg)
	else:
		return Vector2.INF


func update_flight_conditions(delta: float) -> void:
	# Calculate acceleration for next step
	current_acceleration = (linear_velocity - previous_velocity) / delta
	previous_velocity = linear_velocity
	
	# Estimate current altitude based on y position (simplified)
	current_altitude = max(0, self.global_position.y)
	
	# Update air density based on altitude
	var air_density = calculate_air_density(current_altitude)
	
	# Calculate mach number (assuming speed of sound = 343 m/s at sea level)
	var speed_of_sound = 343.0 - (current_altitude * 0.004)  # Simplified decrease with altitude
	current_mach_number = linear_velocity.length() / speed_of_sound
	
	# Calculate Reynolds number (simplified)
	var kinematic_viscosity = 1.48e-5  # m²/s for air at 20°C
	current_reynolds_number = linear_velocity.length() * missile_length / kinematic_viscosity
	
	# Calculate dynamic pressure
	current_dynamic_pressure = 0.5 * air_density * linear_velocity.length_squared()


func calculate_air_density(altitude: float) -> float:
	# Simplified exponential atmosphere model
	return air_density_sea_level * exp(-altitude / 8500.0)  # 8500m is approximate scale height


func calculate_aerodynamic_forces_and_torques() -> Dictionary:
	var velocity = linear_velocity
	var velocity_length = velocity.length()

	if velocity_length < min_effective_speed:
		return {force = Vector3.ZERO, torque = Vector3.ZERO}

	var missile_forward = self.global_transform.basis.y

	# Calculate angle of attack (AoA) and sideslip
	var velocity_dir = velocity.normalized()
	var dot_product = missile_forward.dot(velocity_dir)
	var angle_of_attack_rad = acos(clamp(dot_product, -1.0, 1.0))
	var angle_of_attack_deg = rad_to_deg(angle_of_attack_rad)

	# Calculate sideslip angle
	#var missile_right = self.global_transform.basis.x
	#var side_component = velocity_dir.dot(missile_right)
	#var sideslip_angle_rad = asin(clamp(side_component, -1.0, 1.0))
	#var sideslip_angle_deg = rad_to_deg(sideslip_angle_rad)

	# Calculate lift coefficient with stall behavior
	var lift_coef = 0.0
	if angle_of_attack_deg < stall_angle:
		lift_coef = lift_curve_slope * sin(angle_of_attack_rad)
	else:
		# Post-stall behavior (lift drops off)
		var stall_factor = 1.0 - min(1.0, (angle_of_attack_deg - stall_angle) / 10.0)
		lift_coef = max_lift_coef * stall_factor

	# ---- MACH-DEPENDENT DRAG MODEL ----
	var wave_drag_coef = 0.0
	if current_mach_number > 0.8:
		# Transonic wave drag rise (significant increase between Mach 0.8 - 1.2)
		wave_drag_coef = 0.1 * pow(current_mach_number - 0.8, 2)
	if current_mach_number > 1.2:
		# Supersonic shockwave drag increase
		wave_drag_coef += 0.15 * (current_mach_number - 1.2)

	# Induced drag (due to lift)
	var induced_drag_coef = induced_drag_factor * pow(lift_coef, 2)

	# Form drag (increases with angle of attack)
	var form_drag_coef = zero_lift_drag_coef * (1.0 + form_factor * pow(angle_of_attack_rad, 2))

	# Additional pressure drag effect (high at supersonic speeds)
	var pressure_drag_coef = 0.0
	if current_mach_number > 1.0:
		pressure_drag_coef = 0.02 * (current_mach_number - 1.0)

	# Total drag coefficient
	var total_drag_coef = form_drag_coef + induced_drag_coef + wave_drag_coef + pressure_drag_coef

	# Scale coefficients based on flight regime (Reynolds number effect)
	var reynolds_factor = clamp(log(current_reynolds_number) / 15.0, 0.8, 1.2)
	lift_coef *= reynolds_factor
	total_drag_coef *= reynolds_factor

	# Normal force direction (perpendicular to missile axis)
	var normal_direction = velocity - missile_forward * velocity.dot(missile_forward)
	if normal_direction.length_squared() > 0.001:
		normal_direction = normal_direction.normalized()
	else:
		normal_direction = Vector3.ZERO

	# Compute aerodynamic forces
	var lift_force = normal_direction * lift_coef * current_dynamic_pressure * reference_area
	var drag_force = -velocity_dir * total_drag_coef * current_dynamic_pressure * reference_area

	# Compute aerodynamic torque (CP offset from COM)
	var cp_offset = CP - COM
	var aero_torque = cp_offset.cross(lift_force)

	# Apply damping torques to stabilize rotation
	var damping_torque = Vector3(
		-current_angular_velocity.x * pitch_damping,
		-current_angular_velocity.y * yaw_damping,
		-current_angular_velocity.z * roll_damping
	) * current_dynamic_pressure * reference_area * missile_length

	return {
		force = lift_force + drag_force,
		torque = aero_torque + damping_torque
	}


func calculate_roll_stabilization() -> Vector3:
	var roll_rate = current_angular_velocity.z
	
	# Calculate roll stabilization torque (fins tend to keep missile from rolling)
	var roll_stabilization_torque = Vector3(0, 0, -roll_rate * roll_damping)
	
	return roll_stabilization_torque


func calculate_guidance_torque(delta: float) -> Vector3:
	var angles = get_relative_angles_to_target(target_node.global_position)
	angles = Vector2(angles.y, -angles.x)
	
	var ax = pidX.update(delta, angles.x, 0, P, I, D)
	var ay = pidY.update(delta, angles.y, 0, P, I, D)
	
	# Calculate current roll angle
	var roll = (self.transform.basis.get_euler().z)/(PI/2.0) * 10.0
	
	# Scale control forces based on dynamic pressure for more realistic handling
	var control_effectiveness = clamp(current_dynamic_pressure / 500.0, 0.1, 2.0)
	
	return Vector3(ax, ay, -roll) * control_effectiveness * TLA


func _physics_process(delta: float) -> void:
	msl_life += delta
	if msl_life >= msl_lifetime:
		LAUCNHER_CHILD_SHARE_SET("world", "missiles", Array().pop_back())
		queue_free()
		return
	
	current_angular_velocity = self.angular_velocity
	update_flight_conditions(delta)
	
	# Reset accumulated forces
	accumulated_force = Vector3.ZERO
	accumulated_torque = Vector3.ZERO
	
	# Apply thrust while the motor is burning
	if msl_life < burn_time and msl_life > motor_delay:
		accumulated_force += calculate_thrust()
	
	# Calculate aerodynamic forces
	var aero_forces_torques = calculate_aerodynamic_forces_and_torques()
	accumulated_force += aero_forces_torques.force
	accumulated_torque += aero_forces_torques.torque
	
	# Apply guidance forces if tracking a target
	target_node = get_tree().current_scene.get_node_or_null("World/Active_Target")
	if target_node and has_ir_seeker:
		var guidance_torque = calculate_guidance_torque(delta)
		accumulated_torque += guidance_torque
	
	# Apply stabilizing roll damping
	accumulated_torque += calculate_roll_stabilization()
	
	# Multi-step integration for improved accuracy
	var substeps = 4
	var _sub_step_size = delta / substeps
	
	for i in range(substeps):
		self.apply_central_force(Vector3(0, -9.80665 * mass / substeps, 0))  # Gravity
		
		# Scale torque using proper inertia
		var inverse_inertia = Vector3(
			1.0 / max(0.01, self.inertia.x),
			1.0 / max(0.01, self.inertia.y),
			1.0 / max(0.01, self.inertia.z)
		)
		var scaled_torque = Vector3(
			accumulated_torque.x * inverse_inertia.x,
			accumulated_torque.y * inverse_inertia.y,
			accumulated_torque.z * inverse_inertia.z
		)
		
		var clamped_force = accumulated_force.limit_length(100000.0)
		var clamped_torque = scaled_torque.limit_length(100000.0)
		
		# Apply accumulated force
		self.apply_central_force(clamped_force / substeps)
		self.apply_torque(clamped_torque / substeps)
	
	#print("Updated Velocity:", self.linear_velocity)


#var prev_rot = Vector3.ZERO
#var prev_pos = Vector3.ZERO
#func _process(_delta: float) -> void:
	#var rot = self.global_rotation
	#var pos = self.self.global_position
	#print("msl tick delta rot: ",prev_rot - rot)
	#print("msl tick delta pos: ",prev_pos - pos)
	#prev_rot = rot
	#prev_pos = pos


func LAUCNHER_CHILD_SHARE_SET(scene, key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data

func LAUCNHER_CHILD_SHARE_GET(scene, key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key]
		return data
