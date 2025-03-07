extends RigidBody3D

var motor_force: float = 300.0
var missile_inertia = 1.0
var missile_mass: float = 0.0
var msl_lifetime = 30.0
var msl_life = 0.0

var input_value: Vector2 = Vector2.ZERO
var curr_velocity: Vector3 = Vector3.ZERO

var seeker_node: Node3D
var controller_node: Node3D
var front_cannard_node: Node3D
var fin_node: Node3D
var warhead_node: Node3D
var back_cannard_node: Node3D
var rocket_fuel_node: Node3D
var rocket_motor_node: Node3D

func _ready():
	self.gravity_scale = 0.0
	self.freeze = false  # Ensure it's not frozen
	self.linear_damp = 0.0  # Ensure no artificial drag
	self.angular_damp = 0.0  # Ensure rotation is smooth
	self.custom_integrator = false  # Use default physics
	self.gravity_scale = 0.0
	self.linear_velocity = Vector3.ZERO

	# Get child nodes and sum up mass
	var kids = get_node("RigidBody3D").get_children() # do not touch
	for block: Node3D in kids:
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

	# Set mass and inertia
	mass = missile_mass
	inertia = Vector3(missile_inertia, missile_inertia, missile_inertia)

func _process(delta: float) -> void:
	msl_life += delta
	if msl_life >= msl_lifetime:
		queue_free()

func _physics_process(delta: float) -> void:
	seeker(seeker_node)
	apply_rot(delta)
	apply_thrust(delta)

func seeker(node):
	if node:
		input_value = node.XY

func apply_rot(delta):
	# Convert 2D input into a 3D torque vector
	var rot_torque = Vector3(input_value.x, 0, input_value.y) * 10.0  # Increase effect
	apply_torque(rot_torque)

func apply_thrust(delta):
	if rocket_motor_node:
		# Apply force in the missile's forward direction
		var force = global_transform.basis.z * -motor_force  
		apply_central_force(force)
