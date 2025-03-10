extends RigidBody3D  # Vector up = missile forward

var papa: Node3D
var launcher = Node # FOR DATA SHARE

@export_subgroup("PHYSICS")
@export var thrust_force: float = 5000.0
@export var air_density_sea_level: float = 1.225  # kg/m^3 at sea level
@export var min_effective_speed: float = 15.0

# Aerodynamic coefficients
@export_subgroup("AERODYNAMICS")
@export var max_lift_coef: float = 10.0  # Maximum lift coefficient
@export var stall_angle: float = 15.0  # Degrees
@export var form_factor: float = 1.1  # Shape factor for drag

# Flight dynamics
@export_subgroup("FLIGHT DYNAMICS")
@export var static_margin: float = 0.125  # Distance between CG and CP as fraction of length
@export var roll_damping: float = 2.0  # Damping coefficient for roll
@export var missile_length: float = 5.0  # Length in meters
@export var missile_diameter: float = 0.2  # Diameter in meters

@export_subgroup("MAIN")
@export var prox_det_radius: float = 15.0
@export var horizontal_fov: float = 30.0
@export var vertical_fov: float = 30.0
@export var max_range: float = 2500.0
@export var msl_lifetime: float = 15.0
@export var motor_delay: float = 0.1
@export var P = 1.0
@export var I = 0.0
@export var D = 0.01

var COM: Vector3 = Vector3.ZERO  # Center of mass
var CP: Vector3 = Vector3.ZERO   # Center of pressure
var COT: Vector3 = Vector3.ZERO  # Center of thrust

var blocks := []
var fuel: int = 0
var has_ir_seeker: bool = false
var TLA: float = 0.0
var burn_time = 0.0

var msl_life: float = 0.0
var TARGETING: bool = false
var target_node: Node3D = null

var pidX
var pidY

# Cached values for performance
var current_altitude := 0.0

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
	#self.center_of_mass = COM
	
	# how much burn time each fuel block adds
	burn_time = fuel * 3.0
	
	pidX = PID.new()
	pidY = PID.new()


func _physics_process(delta: float) -> void:
	msl_life += delta
	if msl_life >= msl_lifetime:
		var list = LAUCNHER_CHILD_SHARE_GET("world", "missiles")
		list.pop_back()
		LAUCNHER_CHILD_SHARE_SET("world", "missiles", list)
		queue_free()
		return
	
	# Variables for custom integrator
	var accumulated_force := Vector3.ZERO
	var accumulated_torque := Vector3.ZERO
	
	# Apply thrust while the motor is burning
	if burn_time > motor_delay and msl_lifetime > motor_delay:
		if msl_life < burn_time:
			accumulated_force += calculate_thrust()
			pass
	
	# Calculate aerodynamic forces
	var aero_forces_torques = aoa_aos()
	var aoas = (rad_to_deg(aero_forces_torques.x) + rad_to_deg(aero_forces_torques.y))
	print(aoas)
	
	# Apply guidance forces if tracking a target
	target_node = get_tree().current_scene.get_node_or_null("World/Active_Target")
	if target_node and has_ir_seeker:
		var guidance_torque = calculate_guidance_torque(delta)
		accumulated_torque += guidance_torque
	
	# Apply stabilizing roll damping
	accumulated_torque += calculate_roll_stabilization()
	
	# Apply stabilizing point-2-forward™ correction technology
	accumulated_torque += align_up_to_velocity()
	
	# Multi-step integration for improved accuracy
	var substeps = 3
	var _sub_step_size = delta / substeps
	
	for i in range(substeps):
		accumulated_force += Vector3(0, -9.80665 * mass / substeps, 0)  # Gravity
		
		# Scale torque using proper inertia
		var inverse_inertia = Vector3(
			1.0 / max(0.05, self.inertia.x),
			1.0 / max(0.05, self.inertia.y),
			1.0 / max(0.05, self.inertia.z)
		)
		var scaled_torque = Vector3(
			accumulated_torque.x * inverse_inertia.x,
			accumulated_torque.y * inverse_inertia.y,
			accumulated_torque.z * inverse_inertia.z
		)
		
		var clamped_force = accumulated_force.limit_length(100000.0)
		var clamped_torque = scaled_torque.limit_length(1000.0)
		
		# Apply accumulated force
		self.apply_central_force(clamped_force / substeps)
		
		if aoas > stall_angle:
			self.apply_torque((clamped_torque / substeps))
		else:
			self.apply_torque(clamped_torque / substeps)


# --------------------
# math-moo-tacs
# --------------------
func calculate_thrust() -> Vector3:
	var thrust_dir = self.global_transform.basis.y.normalized()
	
	# Ensure thrust_offset is valid
	var thrust_offset = COT - COM
	if thrust_offset.length_squared() < 0.01:  
		thrust_offset = Vector3(0, 0.01, 0)  # Small offset to prevent zero division
	
	# Reduce thrust with altitude (simplified model)
	var altitude_factor = exp(-current_altitude / 15000.0)  # Thrust decreases with altitude
	
	# Vary thrust during burn (simplified bell curve)
	var normalized_burn_time = (msl_life - motor_delay) / (burn_time - motor_delay)
	var thrust_profile = 1.0
	if normalized_burn_time <= 0.2:  # Ramp up
		thrust_profile = normalized_burn_time / 0.2
	elif normalized_burn_time >= 0.8:  # Ramp down
		thrust_profile = 1.0 - (normalized_burn_time - 0.8) / 0.2
	
	var thrust = thrust_dir * thrust_force * altitude_factor * thrust_profile
	
	return thrust


func aoa_aos() -> Vector2:
	var velocity = linear_velocity
	var velocity_length = velocity.length()

	if velocity_length < min_effective_speed:
		return Vector2.ZERO

	var missile_forward = self.global_transform.basis.y

	# Calculate angle of attack
	var velocity_dir = velocity.normalized()
	var dot_product = missile_forward.dot(velocity_dir)
	var angle_of_attack_rad = acos(clamp(dot_product, -1.0, 1.0))

	# Calculate angle of slip
	var missile_right = self.global_transform.basis.x
	var side_component = velocity_dir.dot(missile_right)
	var angle_of_slip_rad = asin(clamp(side_component, -1.0, 1.0))
	
	return Vector2(angle_of_attack_rad, angle_of_slip_rad)


func calculate_roll_stabilization() -> Vector3:
	var roll_rate = self.angular_velocity.z
	
	# Calculate roll stabilization torque (fins tend to keep missile from rolling)
	var roll_stabilization_torque = Vector3(0, 0, -roll_rate * roll_damping)
	
	return roll_stabilization_torque


func align_up_to_velocity() -> Vector3:
	var velocity = linear_velocity
	if velocity.length() < min_effective_speed:
		return Vector3.ZERO
	
	var desired_up = velocity.normalized()  # The desired up vector (velocity direction)
	var current_up = self.global_transform.basis.y.normalized()  # Current up direction
	
	var rotation_axis = current_up.cross(desired_up)  # Axis of rotation
	var angle = acos(clamp(current_up.dot(desired_up), -1, 1))  # Angle difference
	
	if angle > 0.01:  
		var angular_correction = rotation_axis.normalized() * angle * 0.5 * mass * TLA
		return angular_correction
	else:
		return Vector3.ZERO


func calculate_guidance_torque(_delta: float) -> Vector3:
	if not target_node:
		return Vector3.ZERO
	
	var current_speed = linear_velocity.length()
	if current_speed < 0.5:
		return Vector3.ZERO
	
	# Compute the desired direction from the missile to the target.
	var desired_dir = (target_node.global_transform.origin - self.global_transform.origin).normalized()
	
	# Our missile’s forward direction is its local up (Y axis)
	var forward: Vector3 = self.global_transform.basis.y.normalized()
	
	# Compute the angle between the current forward and the desired direction.
	var dot_val: float = clamp(forward.dot(desired_dir), -1.0, 1.0)
	var error_angle: float = acos(dot_val)  # This is in radians
	
	# Determine the axis around which to rotate to align with the desired direction.
	# This cross product gives an axis perpendicular to both vectors.
	var error_axis: Vector3 = forward.cross(desired_dir)
	if error_axis.length() < 0.001:
		return Vector3.ZERO  # They are nearly aligned.
	
	error_axis = error_axis.normalized()
	
	# Optionally, you can incorporate a gain factor.
	# Here, TLA or another constant can serve as the proportional gain.
	var gain: float = TLA  # Adjust this as needed.
	var guidance_torque: Vector3 = error_axis * (error_angle * gain)
	
	# Optionally, if you wish to further modulate the torque by speed (corrections builds with velocity):
	var speed_scale: float = clamp(current_speed / min_effective_speed, 0.0, max_lift_coef)
	guidance_torque *= speed_scale
	
	return guidance_torque


func LAUCNHER_CHILD_SHARE_SET(scene, key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data

func LAUCNHER_CHILD_SHARE_GET(scene, key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key]
		return data
