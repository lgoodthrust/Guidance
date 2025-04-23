extends RigidBody3D

# Main missile parameters
@export var thrust_force: float = 300.0
@export var lifetime: float = 25.0
@export var launch_charge_force: float = 20.0
@export var motor_delay: float = 0.3
@export var fuel_duration: float = 1.0
@export var proximity_detonation_radius: float = 10.0
@export var max_range: float = 3500.0
@export var seeker_fov: float = 40.0
@export var unlocked_detonation_delay: float = 3.0

# Seeker type enum
enum Seeker { NONE, IR, LASER, RADAR }
var seeker_type: Seeker = Seeker.NONE

# Guidance PID gains
@export var YAW_KP: float = 1
@export var YAW_KI: float = 0.0
@export var YAW_KD: float = 0.1
@export var PITCH_KP: float = 1.0
@export var PITCH_KI: float = 0.0
@export var PITCH_KD: float = 0.1

@export var GAIN_0: float = 0.0
@export var GAIN_1: float = 1.0
@export var GAIN_2: float = 0.0

# Flags (set these as desired in the Inspector)
var centers = {
	"mass": Vector3.ZERO,
	"pressure": Vector3.ZERO,
	"thrust": Vector3.ZERO
}

var properties = {
	"fuel": 0,
	"mass": 0.0,
	"total_lift": 0.0,
	"has_ir_seeker": false,
	"has_controller": false,
	"has_warhead": false,
	"has_front_cannard": false,
	"has_back_cannard": false,
	"has_fin": false,
	"has_motor": false
}

# Internal state
var blocks = []
var life: float = 0.0
var unlocked_life: float = 0.0
var smoking: bool = false
var dist = 100.0
var target: Node3D
var target_position
var player
var tracking: bool = true
var speed: float = 0.0

# PID controllers for yaw and pitch
@onready var pidx0 = PID.new()
@onready var pidy0 = PID.new()

@onready var adv_move = ADV_MOVE.new()

@onready var particles = gpu_particle_effects.new()

@onready var summerx = SUM.new()
@onready var summery = SUM.new()
@onready var summers = SUM.new()

var grav: Vector3 = Vector3.ZERO
var launch_force: Vector3 = Vector3.ZERO
func _ready() -> void:
	target_position = Vector3()
	player = get_tree().current_scene.get_node_or_null("Player/Player_Camera")
	
	# add missile blocks to list
	load_missile_blocks()
	
	# calculate data
	calculate_centers()
	
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.25, 0.25, 0.25)
	var box = CollisionShape3D.new()
	box.shape = shape
	add_child(box)
	box.position = centers["mass"]
	box.owner = self
	
	# Basic physics settings
	freeze = false
	gravity_scale = 0.0
	linear_damp = 0.001
	angular_damp = 0.001
	mass = max(1.0, properties["mass"])
	inertia = Vector3(1, 10, 1) * mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centers["mass"]
	grav = (Vector3.DOWN * 9.80665 * mass)
	
	target = get_tree().current_scene.get_node_or_null("World/Active_Target")

func load_missile_blocks() -> void:
	for child in get_children():
		if child.get_class() == "Node3D" and child.DATA.has("NAME"):
			blocks.append(child)

func calculate_centers() -> void:
	var lift_blocks = 0
	var thrust_blocks = 0
	
	for block:Node3D in blocks:
		var block_pos = block.to_global(Vector3.ZERO)
		if block.DATA.has("TYPE"):
			if block.DATA["TYPE"] == 1:
				properties["has_ir_seeker"] = true
				match block.DATA["NAME"]:
					"IR_Seeker":
						seeker_type = Seeker.IR
					"Laser_Seeker":
						seeker_type = Seeker.LASER
					"Radar_Seeker":
						seeker_type = Seeker.RADAR
			
			if block.DATA["TYPE"] == 2:
				properties["has_controller"] = true
			
			if block.DATA["TYPE"] == 3:
				properties["has_warhead"] = true
	
			if block.DATA["TYPE"] == 4:
				properties["has_fin"] = true
				centers["pressure"] += block_pos
				lift_blocks += 1
				properties["total_lift"] += block.DATA["LIFT"]
			
			if block.DATA["TYPE"] == 5:
				properties["has_front_cannard"] = true
				centers["pressure"] += block_pos
				lift_blocks += 1
				properties["total_lift"] += block.DATA["LIFT"]
			
			if block.DATA["TYPE"] == 6:
				properties["has_back_cannard"] = true
				centers["pressure"] += block_pos
				lift_blocks += 1
				properties["total_lift"] += block.DATA["LIFT"]
			
			if block.DATA["TYPE"] == 7:
				properties["fuel"] += fuel_duration
			
			if block.DATA["TYPE"] == 8:
				properties["has_motor"] = true
				centers["thrust"] += block_pos
				thrust_blocks += 1
		
		if block.DATA.has("MASS"):
			centers["mass"] += block_pos * block.DATA["MASS"]
			properties["mass"] += block.DATA["MASS"]
	
	# Average out centers if needed
	if properties["mass"] > 0:
		centers["mass"] /= properties["mass"]
	if lift_blocks > 0:
		centers["pressure"] /= lift_blocks
	if thrust_blocks > 0:
		centers["thrust"] /= thrust_blocks

var prev_vel: Vector3 = Vector3.ZERO
var laucnhed: bool = false
func _physics_process(delta: float) -> void:
	
	var FORWARD = global_transform.basis.y
	speed = max(1, linear_velocity.dot(global_transform.basis.y))
	
	life += delta
	if life >= lifetime:
		_explode_and_remove()
		return
	
	if laucnhed == false:
		# Apply an initial impulse in our "forward" (local Y) direction.
		apply_central_impulse(global_transform.basis.y * launch_charge_force * mass)
		laucnhed = true
	
	# Thrust: Apply force along forward direction if within fuel duration.
	if properties["has_motor"] and life > motor_delay and life < properties["fuel"]:
		apply_force(global_transform.basis.y * thrust_force * mass, centers["thrust"])
		# Optionally trigger smoke effect here.
		if not smoking:
			smoking = true
			add_child(particles.smoke_01())
	
	# Gravity: Apply a downward force.
	apply_central_force(grav)
	
	var A = 0.0 # val > 0 = +aim -flight, val < 0 = -aim +flight
	
	# Apply aerodynamic alignment (forward flight toward missile's forward direction)
	var afd = (FORWARD - linear_velocity.normalized()).normalized()
	var afm = FORWARD.angle_to(linear_velocity.normalized())
	apply_force(afd * afm * speed * (1.0-A), centers["pressure"])
	
	# counteract unwanted de-acceleration forces from alignment forces
	var cur_accel = linear_velocity - prev_vel
	var anti_drag = -cur_accel * 1.5
	apply_force(anti_drag * FORWARD * clamp(A,0,1), centers["mass"])
	
	# apply aerodynamic alignment (missile toward foward flight)
	var axis = FORWARD.cross(linear_velocity.normalized())
	var angle = FORWARD.angle_to(linear_velocity.normalized())
	if axis.length() > 0.005 and angle > 0.005:
		var torque = axis.normalized() * angle
		apply_torque(torque * speed * (1.0+A))
	
	if target:
		dist = global_transform.origin.distance_to(target.global_transform.origin)
	
	# Guidance: If a seeker is active, steer toward the target.
	if properties["has_ir_seeker"]:
			# Proximity detonation: Explode if too close.
			if dist <= proximity_detonation_radius and properties["has_warhead"]:
				_explode_and_remove()
				return
			
			# If within range, steer toward the target.
			if dist < max_range:
				var angles = _get_target_angles(target)
				if angles != Vector2.ZERO:
					var pid_output = control_algorithm(angles, delta, seeker_type)
					_apply_pitch_yaw_torque(pid_output)
	
	if tracking == false:
		unlocked_life += delta
	
	if unlocked_life >= unlocked_detonation_delay:
		_explode_and_remove()
	
	prev_vel = linear_velocity

func _explode_and_remove() -> void:
	var kaboom = particles.explotion_01()
	get_tree().current_scene.get_node(".").add_child(kaboom)
	kaboom.global_position = global_position
	for block in blocks:
		block.hide()
	await get_tree().create_timer(0.25).timeout
	queue_free()

#------------------------------------------------------------------
# Helpers – using only the RigidBody's orientation.
#------------------------------------------------------------------
# Get the angles (yaw and pitch) between our forward direction and the target.
var prev_ang: Vector2 = Vector2.ZERO
func _get_target_angles(t: Node3D) -> Vector2:
	var dir: Vector3 = (t.global_position - global_position).normalized()
	var fwd: Vector3 = global_transform.basis.y
	var right: Vector3 = global_transform.basis.x
	var up: Vector3 = global_transform.basis.z

	# dir  = (target - missile).normalized()
	# fwd  = global_transform.basis.y
	# right / up are the local X / Z axes
	var yaw   : float = atan2(dir.dot(right), dir.dot(fwd))   # yaw  (+ = right)
	var pitch : float = atan2(dir.dot(up), dir.dot(fwd))   # pitch (+ = up)

	if abs(rad_to_deg(yaw)) > seeker_fov or abs(rad_to_deg(pitch)) > seeker_fov:
		tracking = false
		return Vector2.ZERO
	tracking = true
	return Vector2(yaw, pitch)

# ----------------------------------------------------------
#  CUSTOM GUIDANCE LAW
# ----------------------------------------------------------
func control_algorithm(relative_angles: Vector2, delta: float, type: int) -> Vector2:
	var xval = 0
	var yval = 0
	
	if type == Seeker.IR: # ir
		xval = -relative_angles.x
		yval =  relative_angles.y
	
	elif type == Seeker.LASER: # SACLOS/laser (beam-riding)
		if player:
			var player_aim_dir = -player.global_transform.basis.z  # Player's forward direction
			target_position = player.global_transform.origin + player_aim_dir * 10000.0
		
		var vec = adv_move.force_to_forward(delta, self, Vector3.DOWN, target_position)
		apply_force(vec * linear_velocity * properties["mass"])
		
		xval = 0
		yval = 0
		
	elif type == Seeker.RADAR: # radar
		var stuff = _radar_steering(delta, relative_angles)
		xval = stuff.x
		yval = stuff.y
	
	else: # non
		xval = 0
		yval = 0
	
	var xx = -pidx0.update(delta, 0, xval, YAW_KP, YAW_KI, YAW_KD)
	var yy = -pidy0.update(delta, 0, yval, PITCH_KP, PITCH_KI, PITCH_KD)
	
	return Vector2(xx, yy)

# New and improved CB/DR guidance now with LR accel
var prev_angles = Vector2.ZERO
var prev_rate_angles = Vector2.ZERO
var first: bool = true
var rate_angles = Vector2.ZERO
func _radar_steering(delta:float, angles: Vector2) -> Vector2:
	# If first tick, equalize values to prevent launching jerk
	if first:
		prev_angles = angles
		first = false
	
	# imported as it allows a resonable delta to accumulate
	# Divide by delta time to make rate calculations FPS independant
	rate_angles = -(angles - prev_angles) / delta
	
	# Second derivative: angular acceleration (LOS jerk)
	var jerk_angles = -(rate_angles - prev_rate_angles) / delta
	
	# Update state history
	prev_angles = angles
	prev_rate_angles = rate_angles
	
	var yc0 = angles.x * GAIN_0
	var pc0 = -angles.y * GAIN_0
	
	var yc1 = rate_angles.x * GAIN_1
	var pc1 = -rate_angles.y * GAIN_1
	
	var yc2 = jerk_angles.x * GAIN_2
	var pc2 = -jerk_angles.y * GAIN_2
	
	var Ax = -yc0+yc1-yc2
	var Ay = -pc0+pc1-pc2
	
	# Sum (integral) of all the values
	var outx = Ax#summerx.update(Ax, 3, 3.0)
	var outy = Ay#summery.update(Ay, 3, 3.0)
	var outs =  summerx.update(abs(Vector2(outx, outy).length()), 5, 5.0)
	
	var out = Vector2(outx, outy) * outs
	
	# Output is final command vector
	return out

# Apply torque based on input.
# We interpret cmd.x as yaw and cmd.y as pitch.
func _apply_pitch_yaw_torque(cmd: Vector2) -> void:
	var right = global_basis.x
	var up = global_basis.z
	var forward = -global_basis.y
	var pitch_torque = right * cmd.y
	var yaw_torque = up * cmd.x
	var anti_roll_torque = forward.cross(right).cross(up)
	
	# Combine torque vectors and apply it as force
	var forces = ((pitch_torque + yaw_torque + anti_roll_torque) * speed)
	apply_torque(forces)
