extends RigidBody3D  # Vector up = missile forward

@export_subgroup("PHYSICS")
@export var thrust_force: float = 3000.0
@export var lift_coefficient: float = 1.2
@export var air_density: float = 1.225
@export var drag_coefficient: float = 0.125
@export var stability_factor: float = 0.01
@export var max_lateral_force: float = 150.0  # Limits guidance force

@export_subgroup("MAIN")
@export var horizontal_fov: float = 30.0
@export var vertical_fov: float = 30.0
@export var max_range: float = 8000.0
@export var msl_lifetime: float = 30.0

var COM: Vector3 = Vector3.ZERO
var COL: Vector3 = Vector3.ZERO
var COT: Vector3 = Vector3.ZERO

var blocks := []
var fuel: int = 0
var has_ir_seeker := false
var TLA: float = 0.0

var msl_life: float = 0.0
var XY: Vector2 = Vector2.ZERO
var TARGETING: bool = false
var target_node: Node3D = null

func _ready():
	self.freeze = false
	self.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	self.gravity_scale = 0.0#9.08665  
	self.linear_damp = 1.0
	self.angular_damp = 1.0
	self.custom_integrator = false 

	for block in get_children():
		if block is Node3D and block.DATA.has("NAME"):
			blocks.append(block)
	
	var total_mass := 0.0
	var lift_blocks: int = 0
	var thrust_blocks: int = 0
	var center: Vector3 = Vector3.ZERO
	
	for block:Node3D in blocks:
		var block_pos = block.to_global(Vector3.ZERO)  
		if block.DATA.has("TYPE"):
			match block.DATA["TYPE"]:
				1: has_ir_seeker = true
				4, 5, 6:
					COL += block_pos
					lift_blocks += 1
					TLA += block.DATA["LIFT"]
				7: fuel += 1
				8:
					COT += block_pos
					thrust_blocks += 1
		
		if block.DATA.has("MASS"):
			COM += block_pos * block.DATA["MASS"]
			total_mass += block.DATA["MASS"]
			center = block.to_global(Vector3.ZERO)
	
	center /= len(blocks)
	COM /= total_mass
	COL /= max(1, lift_blocks)
	COT /= max(1, thrust_blocks)
	
	self.mass = max(1.0, total_mass)
	self.inertia = Vector3(self.mass / 5.0, self.mass, self.mass / 5.0)
	self.center_of_mass = COM


func _physics_process(delta: float) -> void:
	msl_life += delta
	if msl_life >= msl_lifetime:
		queue_free()  
		return

	var total_force = Vector3.ZERO
	var total_torque = calculate_stability()

	if msl_life < 2.0 + (fuel * 3.0):
		total_force += calculate_thrust()

	total_force += calculate_lift() + calculate_drag()

	target_node = get_tree().current_scene.get_node_or_null("World/Active_Target")
	if target_node and has_ir_seeker:
		var tracking_force = calculate_guidance_force(target_node.global_transform.origin, delta)
		total_force += tracking_force
	
	self.apply_force(total_force, COM)
	self.apply_torque_impulse(total_torque)

# --------------------
# THRUST, LIFT, DRAG
# --------------------
func calculate_thrust() -> Vector3:
	var thrust_direction = transform.basis.y.normalized()
	return thrust_direction * thrust_force

func calculate_lift() -> Vector3:
	var velocity = self.linear_velocity
	var forward_speed = velocity.dot(transform.basis.y)
	var lift_area = max(0.1, TLA)
	var lift_magnitude = 0.5 * air_density * forward_speed ** 2 * lift_coefficient * lift_area
	return transform.basis.y * lift_magnitude

func calculate_drag() -> Vector3:
	var velocity = self.linear_velocity
	if velocity.length() < 0.1:
		return Vector3.ZERO
	
	var frontal_area = PI * 0.02  # Assume missile is roughly cylindrical
	var drag_magnitude = 0.5 * air_density * velocity.length_squared() * drag_coefficient * frontal_area
	return -velocity.normalized() * drag_magnitude

# --------------------
# STABILITY & GUIDANCE
# --------------------
func calculate_stability() -> Vector3:
	var local_velocity = transform.basis.inverse() * self.linear_velocity
	var pitch_torque = -local_velocity.z * stability_factor
	var yaw_torque = local_velocity.x * stability_factor
	return transform.basis.x * pitch_torque + transform.basis.z * yaw_torque

func calculate_guidance_force(target_pos: Vector3, delta: float) -> Vector3:
	var to_target = target_pos - global_transform.origin
	var distance = to_target.length()

	if distance > max_range:
		return Vector3.ZERO  

	var local_target = global_transform.basis.inverse() * to_target.normalized()

	var yaw_error = rad_to_deg(atan2(local_target.x, local_target.y))
	var pitch_error = rad_to_deg(atan2(local_target.z, local_target.y))

	if abs(yaw_error) > horizontal_fov * 0.5 or abs(pitch_error) > vertical_fov * 0.5:
		return Vector3.ZERO  

	var guidance_strength = clamp(distance / max_range, 0.1, 1.0)  

	var lateral_force = transform.basis.x * (-yaw_error * guidance_strength) + transform.basis.z * (-pitch_error * guidance_strength)
	return lateral_force.clamp(Vector3(-max_lateral_force, -max_lateral_force, -max_lateral_force), Vector3(max_lateral_force, max_lateral_force, max_lateral_force))

# --------------------
# TARGET TRACKING
# --------------------
func get_relative_angles_to_target(target_global_position: Vector3) -> Vector2:
	var to_target = target_global_position - global_transform.origin
	var distance = to_target.length()

	if distance > max_range:
		return Vector2.INF

	var local_direction = global_transform.basis.inverse() * to_target.normalized()
	var yaw_deg = rad_to_deg(atan2(local_direction.x, local_direction.y))
	var pitch_deg = rad_to_deg(atan2(local_direction.z, local_direction.y))

	if abs(yaw_deg) <= horizontal_fov * 0.5 and abs(pitch_deg) <= vertical_fov * 0.5:
		return Vector2(yaw_deg, pitch_deg)
	else:
		return Vector2.INF
