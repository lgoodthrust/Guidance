extends Node3D

var motor_force: float = 1000.0
var missile_mass: float = 0.0
var missile_inertia: float = 1.0  # Base inertia value
var msl_lifetime = 30.0
var msl_life = 0.0

var input_value: Vector2 = Vector2.ZERO
var curr_velocity: float = 0.0
var torque_multiplier: float = 1.0  # Dynamic torque scaling

var rigid_node: RigidBody3D

var seeker_node: Node3D
var controller_node: Node3D
var front_cannard_node: Node3D
var fin_node: Node3D
var warhead_node: Node3D
var back_cannard_node: Node3D
var rocket_fuel_node: Node3D
var rocket_motor_node: Node3D

func _ready():
	print("ready")
	rigid_node = get_node("MissileRoot/RigidBody3D")
	print("applying rigid params")
	
	rigid_node.gravity_scale = 0.0
	rigid_node.freeze = false
	rigid_node.linear_damp = 0.0
	rigid_node.angular_damp = 0.0
	rigid_node.custom_integrator = false
	rigid_node.linear_velocity = Vector3.ZERO

	# Get child nodes and sum up mass
	var kids = get_node("MissileRoot/RigidBody3D").get_children() # do not touch
	for block in kids:
		match block.name:
			"IR_Seeker":
				seeker_node = block
			"Controller":
				controller_node = block
			"Front_Cannard":
				front_cannard_node = block
			"Back_Cannard":
				back_cannard_node = block
			"Warhead":
				warhead_node = block
			"Rocket_Fuel":
				rocket_fuel_node = block
			"Fin":
				fin_node = block
			"Rocket_Motor":
				rocket_motor_node = block
		
		if "DATA" in block:
			missile_mass += block.DATA.get("MASS", 0)

	# Set mass and initial inertia
	rigid_node.mass = missile_mass
	missile_inertia = missile_mass * 0.1  # Base inertia (adjustable)
	rigid_node.inertia = Vector3(missile_inertia, missile_inertia, missile_inertia)
	rigid_node.angular_damp = 0.125
	rigid_node.linear_damp = 0.01

func _process(delta: float) -> void:
	msl_life += delta
	if msl_life >= msl_lifetime:
		queue_free()

func _physics_process(delta: float) -> void:
	# Compute velocity magnitude
	curr_velocity = rigid_node.linear_velocity.length()
	
	# Adjust missile inertia dynamically based on velocity
	torque_multiplier = clamp(curr_velocity / 343.0, 0.75, 1.75)  # Scale between 1.0x and 5.0x
	
	# Apply dynamic inertia to the rigid body
	rigid_node.inertia = Vector3(
		missile_mass * 0.1 * torque_multiplier, 
		missile_mass * 1.0 * torque_multiplier, 
		missile_mass * 0.1 * torque_multiplier
		)
	
	seeker(seeker_node)
	apply_rot(delta)
	apply_thrust(delta)
	
	var clamped = Vector3(10.0,10.0,10.0)
	rigid_node.angular_velocity = clamp(rigid_node.angular_velocity, -clamped, clamped)

func seeker(node):
	if node:
		if node.XY == Vector2.INF:
			input_value = Vector2(0,0)
		else:
			input_value = node.XY

func apply_rot(delta):
	if not front_cannard_node:
		return
	
	var torque_x = transform.basis.x * input_value.y  # **Pitch correction (X-axis)**
	var torque_z = transform.basis.z * input_value.x  # **Yaw correction (Z-axis)**
	
	var missile_quat = rigid_node.global_transform.basis.get_rotation_quaternion()
	var roll_angle = missile_quat.get_euler().y  # Extract roll **around forward Y-axis**

	# Compute a corrective torque to minimize roll
	var roll_torque = -roll_angle * transform.basis.y  # **Apply counter-torque along Y (forward)**
	
	var roll_stabilization_strength = 50.0  # Adjust as needed
	roll_torque *= roll_stabilization_strength

	var rot_torque = (torque_x + torque_z) + roll_torque

	rigid_node.apply_torque(rot_torque * torque_multiplier)
	print(rigid_node.angular_velocity)

func apply_thrust(delta):
	if rocket_motor_node:
		var force = (transform.basis.y).normalized() * motor_force
		rigid_node.apply_force(force, rocket_motor_node.position)
