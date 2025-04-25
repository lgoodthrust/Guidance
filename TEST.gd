extends RigidBody3D

# Missile parameters
var navigation_constant: float = 4.0  # baseline PN constant
var closing_velocity: float

# LQR optimal gain parameters (pre-computed or dynamically updated)
var K_lambda: float = 2.5
var K_lambda_dot: float = 1.2

# Guidance state variables
var prev_LOS_angle: float = 0.0
var LOS_angle: float = 0.0
var LOS_rate: float = 0.0

func _physics_process(delta):

	# Compute relative position and velocity
	var rel_position = target.global_position - global_position
	var rel_velocity = target.linear_velocity - linear_velocity

	# Calculate Line-of-Sight (LOS) angle
	LOS_angle = atan2(rel_position.y, rel_position.x)

	# Calculate LOS rate
	LOS_rate = (LOS_angle - prev_LOS_angle) / delta
	prev_LOS_angle = LOS_angle

	# Calculate closing velocity (projected along LOS)
	closing_velocity = -rel_velocity.dot(rel_position.normalized())

	# True Proportional Navigation (TPN) baseline command
	var a_TPN = navigation_constant * closing_velocity * LOS_rate

	# LQR Optimal guidance correction
	# State vector x = [LOS_angle, LOS_rate], control u = missile acceleration
	var a_LQR = -(K_lambda * LOS_angle + K_lambda_dot * LOS_rate)

	# Combined TPN + LQR guidance acceleration
	var guidance_acceleration = a_TPN + a_LQR

	# Apply lateral acceleration (guidance command)
	_apply_guidance(guidance_acceleration)

func _apply_guidance(acceleration):
	# Assume missile lateral axis is along local Y-axis
	var lateral_force = Vector3(0, acceleration * mass, 0)
	apply_force(transform.basis * lateral_force, Vector3.ZERO)
