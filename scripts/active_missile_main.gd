extends RigidBody3D  # Vector up = missile forward

var papa: Node3D
var launcher = Node # FOR DATA SHARE

@export_subgroup("PHYSICS")
@export var thrust_force: float = 30000.0
@export var air_density: float = 1.225
@export var drag_coefficient: float = 0.05
@export var fin_stability_factor: float = 0.5
@export var cannard_stability_factor: float = 0.25
@export var min_effective_speed: float = 15.0

@export_subgroup("MAIN")
@export var prox_det_radius: float = 15.0
@export var horizontal_fov: float = 30.0
@export var vertical_fov: float = 30.0
@export var max_range: float = 2500.0
@export var msl_lifetime: float = 15.0
@export var motor_delay: float = 0.15
@export var P = 25.0
@export var I = 0.0
@export var D = 15.0

var COM: Vector3 = Vector3.ZERO
var COL: Vector3 = Vector3.ZERO
var COT: Vector3 = Vector3.ZERO

var blocks := []
var fuel: int = 0
var has_ir_seeker: bool = true
var TLA: float = 0.0
var burn_time = 0.0


var msl_life: float = 0.0
var XY: Vector2 = Vector2.ZERO
var TARGETING: bool = false
var target_node: Node3D = null

var pidX
var pidY

func _ready():
	papa = get_parent()
	launcher = papa.get_parent() # FOR DATA SHARE
	self.global_position = papa.global_position
	self.freeze = false
	self.gravity_scale = 1.0
	self.linear_damp = 0.0
	self.angular_damp = 0.0
	self.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	
	for block in get_children():
		if block is Node3D and block.DATA.has("NAME"):
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
				COL += block_pos
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
	COL /= max(1, lift_blocks)
	COT /= max(1, thrust_blocks)
	
	self.mass = max(1.0, total_mass)
	self.inertia = Vector3(self.mass, self.mass, self.mass)
	self.center_of_mass = Vector3(0, 0.0, 0)
	
	burn_time = fuel * 1.5
	
	pidX = PID.new()
	pidY = PID.new()


func _physics_process(delta: float) -> void:
	msl_life += delta
	if msl_life >= msl_lifetime:
		LAUCNHER_CHILD_SHARE_SET("world", "missiles", Array().pop_front())
		queue_free()
		return
	
	var total_force = Vector3.ZERO
	var total_torque = align_up_to_velocity()
	var correction_force = align_velocity_to_up() * TLA

	# Apply thrust while the motor is burning
	if msl_life < burn_time and msl_life > motor_delay:
		total_force += calculate_thrust()
	
	# Apply aerodynamic drag
	total_force += calculate_drag()

	# Apply guidance forces if tracking a target
	target_node = get_tree().current_scene.get_node_or_null("World/Active_Target")
	if target_node and has_ir_seeker:
		var angles = get_relative_angles_to_target(target_node.global_position)
		angles = Vector2(angles.y, -angles.x)
		var ax = pidX.update(delta, angles.x, 0, P, I, D)
		var ay = pidY.update(delta, angles.y, 0, P, I, D)
		var roll = (transform.basis.get_euler().z)/(PI/2.0) * 10.0
		var tracking_force = Vector3(ax, ay, -roll) * linear_velocity.length() * TLA
		total_torque += tracking_force * cannard_stability_factor
	
	# Apply forces
	apply_force(total_force + correction_force)  # Apply both thrust and correction force
	apply_torque(total_torque)  # Apply torque for rotational stabilization

# --------------------
# THRUST, LIFT, DRAG
# --------------------

func calculate_thrust() -> Vector3:
	var forces = (papa.transform.basis.y * thrust_force)
	return forces


func calculate_drag() -> Vector3:
	var velocity = linear_velocity
	if velocity.length() < 0.1:
		return Vector3.ZERO
	
	var frontal_area = PI
	var drag_magnitude = 0.5 * air_density * velocity.length_squared() * drag_coefficient * frontal_area
	return -velocity.normalized() * drag_magnitude

# --------------------
# TARGET TRACKING
# --------------------

func get_relative_angles_to_target(target_global_position: Vector3) -> Vector2:
	var to_target = target_global_position - global_position
	var distance = to_target.length()
	
	if distance < prox_det_radius:
		LAUCNHER_CHILD_SHARE_SET("world", "missiles", Array().pop_front())
		queue_free()
	
	if distance > max_range:
		return Vector2.ZERO
	
	var local_direction = global_transform.basis.inverse() * to_target.normalized()
	var yaw_deg = rad_to_deg(atan2(local_direction.x, local_direction.y))
	var pitch_deg = rad_to_deg(atan2(local_direction.z, local_direction.y))
	
	if abs(yaw_deg) <= horizontal_fov * 0.5 and abs(pitch_deg) <= vertical_fov * 0.5:
		return Vector2(yaw_deg/horizontal_fov, pitch_deg/vertical_fov)
	else:
		return Vector2.ZERO


func align_up_to_velocity() -> Vector3:
	var velocity = linear_velocity
	if velocity.length() < min_effective_speed:
		return Vector3.ZERO
	
	var desired_up = velocity.normalized()  # The desired up vector (velocity direction)
	var current_up = global_transform.basis.y  # Current up direction
	
	var rotation_axis = current_up.cross(desired_up)  # Axis of rotation
	var angle = acos(clamp(current_up.dot(desired_up), -1, 1))  # Angle difference
	
	if angle > 0.01:  
		var angular_correction = rotation_axis.normalized() * angle * fin_stability_factor * mass * TLA
		return angular_correction
	else:
		return Vector3.ZERO


func align_velocity_to_up() -> Vector3:
	var velocity = linear_velocity
	if velocity.length() < min_effective_speed:
		return Vector3.ZERO
	
	var missile_up = global_transform.basis.y  # Missile's up direction
	var velocity_dir = velocity.normalized()
	
	# Compute the lateral correction force
	var correction_axis = velocity_dir.cross(missile_up).normalized()  # Perpendicular axis
	var correction_force = correction_axis.cross(velocity) * fin_stability_factor * mass
	
	return correction_force


func LAUCNHER_CHILD_SHARE_SET(scene, key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data

func LAUCNHER_CHILD_SHARE_GET(scene, key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key]
		return data
