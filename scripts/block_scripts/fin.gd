extends Node3D
@export_subgroup("META_DATA")
@export var DATA = {
	"NAME": "Fin",
	"MASS": 5,
	"LIFT": 0.0437,
	"UDLRTB": [-1,-1,0,0,0,0],
	"TYPE": 4
}


var fin_area = DATA["LIFT"]
@export var drag_coefficient: float = 1.2  # Drag coefficient (dimensionless)
var damping_factor: float = 0.01  # Reduces excessive oscillations
var air_density: float = 1.225  # Air density (kg/m³)

var rocket: RigidBody3D  # Reference to the rocket's rigid body

func _ready():
	rocket = get_parent() as RigidBody3D
	if not rocket:
		push_error("StabilizationFin must be a child of a RigidBody3D!")
	
func _physics_process(delta):
	if not rocket:
		return
	
	apply_stabilization(delta)

func apply_stabilization(delta):
	var velocity = rocket.linear_velocity
	if velocity.length() < 0.1:
		return  # No stabilization needed if rocket is nearly stationary

	var forward_dir = -rocket.global_transform.basis.z.normalized()
	var velocity_dir = velocity.normalized()
	
	# Find the angle between velocity and rocket's forward direction
	var angle_to_velocity = forward_dir.angle_to(velocity_dir)
	
	# If the angle is too small, no significant stabilization needed
	if angle_to_velocity < 0.01:
		return

	# Compute aerodynamic force
	var dynamic_pressure = 0.5 * air_density * velocity.length_squared()
	var corrective_force_magnitude = dynamic_pressure * fin_area * drag_coefficient * sin(angle_to_velocity)

	# Compute torque direction
	var torque_axis = forward_dir.cross(velocity_dir).normalized()
	
	# Apply torque to align the rocket with its velocity
	rocket.apply_torque_impulse(torque_axis * corrective_force_magnitude * damping_factor * delta)
