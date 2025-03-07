extends RigidBody3D

var motor_force: float = 50.0
var c_g: Vector3
var c_l: Vector3
var missile_inertia = 1.0
var missile_mass: float = 0.0
var msl_lifetime = 30.0
var msl_life = 0.0

var velocity

# Yaw and pitch targets
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
	var kids = get_node("RigidBody3D").get_children()
	print(kids)
	for block: Node3D in kids:
		if block.name == "IR_Seeker":
			print("IR_Seeker")
			seeker_node = block
			missile_mass += block.DATA["MASS"]
		if block.name == "Controller":
			print("Controller")
			controller_node = block
			missile_mass += block.DATA["MASS"]
		if block.name == "Front_Cannard":
			print("Front_Cannard")
			front_cannard_node = block
			missile_mass += block.DATA["MASS"]
		if block.name == "Back_Cannard":
			print("Back_Cannard")
			back_cannard_node = block
			missile_mass += block.DATA["MASS"]
		if block.name == "Warhead":
			print("Warhead")
			warhead_node = block
			missile_mass += block.DATA["MASS"]
		if block.name == "Rocket_Fuel":
			print("Rocket_Fuel")
			rocket_fuel_node = block
			missile_mass += block.DATA["MASS"]
		if block.name == "Fin":
			print("Fin")
			fin_node = block
			missile_mass += block.DATA["MASS"]
		if block.name == "Rocket_Motor":
			print("Rocket_Motor")
			rocket_motor_node = block
			missile_mass += block.DATA["MASS"]
	
	mass = missile_mass
	inertia = Vector3(missile_inertia, missile_inertia, missile_inertia)

func _process(delta: float) -> void:
	msl_life += delta
	if msl_life >= msl_lifetime:
		self.queue_free()


func _physics_process(delta: float) -> void:
	velocity = self.linear_velocity.y
	seeker(seeker_node)
	
	apply_rot(delta)
	apply_thrust(delta)

func seeker(node):
	input_value = node.XY

func apply_rot(delta):
	var rot_torque = (Vector3(input_value.x, 0, input_value.y) * velocity * delta)
	self.apply_torque(rot_torque)

func apply_thrust(delta):
	var force = Vector3.UP * 5000.0
	self.apply_force(force * delta, rocket_motor_node.position)
