extends RigidBody3D  # Vector up = missile forward

@export_subgroup("Main")
@export var thrust_force: float = 300.0
@export var min_effective_speed: float = 50.0
@export var lifetime: float = 10.0
@export var max_range = 3500.0
@export var seeker_fov = 15.0
@export var unlocked_detonation_delay = 1.5
@export var motor_delay = 0.35
@export var fuel_block_duration = 1.0
@export var launch_charge_force = 3000.0
@export var proximity_detonation_radius = 10.0

var launcher
var blocks = []
var life := 0.0
var target_distance = 0.0
var unlocked_life = 0.0


var cur_accel: Vector3 = Vector3.ZERO
var vel =  Vector3.ZERO
var vel_sq =  Vector3.ZERO
var vel_dir =  Vector3.ZERO
var cur_dir =  Vector3.ZERO


var centers = {
	"mass": Vector3.ZERO,
	"pressure": Vector3.ZERO,
	"thrust": Vector3.ZERO
}

var properties = {
	"fuel": 0,
	"mass": 0.0,
	"total_lift": 0.0,
	"has_seeker": false,
	"seeker_type": 0, # 0 = non, 1 = ir, 2 = saclos, 3 = radar
	"has_front_cannard": false,
	"has_back_cannard": false,
	"has_warhead": false,
	"has_fin": false,
	"has_motor": false
}

@onready var effects = gpu_particle_effects.new()
@onready var adv_move = ADV_MOVE.new()
@onready var pidx = PID.new()
@onready var pidy = PID.new()

func _ready() -> void:
	launcher = get_parent().get_parent()
	load_missile_blocks()
	calculate_centers()
	
	# Minimal physics setup
	freeze = false
	gravity_scale = 0.0
	linear_damp = 0
	angular_damp = 0
	mass = max(1.0, properties["mass"])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centers["mass"]
	
	launch()

var smoking = false
func smoke():
	if not smoking:
		smoking = true
		#self.add_child(effects.smoke_01())

func launch():
	var asp = AudioStreamPlayer3D.new()
	asp.stream = load("res://game_data/sound/missile_01.mp3")
	asp.volume_db = 0.0
	asp.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	asp.max_distance = 3000.0
	asp.doppler_tracking = true
	add_child(asp)
	asp.play()

func remove():
	var missile_list = launcher.LAUCNHER_CHILD_SHARED_DATA["world"]["missiles"]
	if typeof(missile_list) == 28:
		missile_list.pop_back()
		launcher.LAUCNHER_CHILD_SHARED_DATA["world"]["missiles"] = missile_list
	queue_free()

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
				properties["has_seeker"] = true
				if block.DATA["NAME"] == "IR_Seeker":
					properties["seeker_type"] = 1
				if block.DATA["NAME"] == "Laser_Seeker":
					properties["seeker_type"] = 2
				if block.DATA["NAME"] == "Radar_Seeker":
					properties["seeker_type"] = 3
			
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
				properties["fuel"] += fuel_block_duration
			
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

func _physics_process(delta: float) -> void:
	vel = linear_velocity.length()
	vel_sq = linear_velocity.length_squared()
	vel_dir = linear_velocity.normalized()
	cur_dir = global_transform.basis.y
	
	#print("speed: ", vel)
	#print("distance: ", target_distance)
	#print("impact time: ", target_distance / vel)
	
	if life < 0.01:
		# Small impulse at spawn
		apply_impulse(cur_dir * launch_charge_force)
	
	life += delta
	
	if life >= lifetime:
		remove()
	
	if unlocked_life >= unlocked_detonation_delay:
		var kaboom = effects.explotion_01()
		var node = get_tree().current_scene.get_node_or_null(".")
		node.add_child(kaboom)
		kaboom.global_transform = global_transform
		remove()
	
	# Apply thrust if there's still "fuel" time
	if properties["fuel"] > life and life > motor_delay and properties["has_motor"]:
		apply_force(cur_dir * thrust_force * properties["mass"], centers["thrust"])
		smoke()
	
	# Apply weight/gravity force
	apply_central_force(Vector3.DOWN * 9.80665 * properties["mass"])
	
	# If moving faster than a certain speed
	if linear_velocity.length() > min_effective_speed:
		
		var A = -0.0 # val > 0 = +aim -flight, val < 0 = -aim +flight
		
		# Apply aerodynamic alignment (forward flight toward missile's forward direction)
		var afd = (cur_dir - vel_dir).normalized()
		var afm = cur_dir.angle_to(vel_dir) * linear_velocity.length_squared()
		apply_central_force(afd * afm * (1.0-A))
		
		# counteract unwanted de-acceleration forces from alignment forces
		var anti_drag = -cur_accel * 0.85
		apply_central_force(anti_drag * cur_dir)
		
		# apply aerodynamic alignment (missile toward foward flight)
		var axis = cur_dir.cross(vel_dir)
		var angle = cur_dir.angle_to(vel_dir)
		if axis.length() > 0.001 and angle > 0.001:
			var torque = axis.normalized() * angle
			apply_torque(torque * linear_velocity.length_squared() * (1.0+A))
		
		# target exists
		var target = get_tree().current_scene.get_node_or_null("World/Active_Target")
		if not target:
			return
		else:
			target_distance = global_transform.origin.distance_to(target.global_transform.origin)
		
		# proximity detination
		if target_distance <= proximity_detonation_radius and properties["has_warhead"]:
			var kaboom = effects.explotion_01()
			var node = get_tree().current_scene.get_node_or_null(".")
			node.add_child(kaboom)
			kaboom.global_transform = global_transform
			remove()
		
		# if ir or radar seeker
		var input_angles = get_target_angles_in_degrees(target)
		if not input_angles == Vector2.ZERO:
			unlocked_life = 0
			if properties["seeker_type"] == 1 or properties["seeker_type"] == 3:
				# If in seeker range, we attempt to steer
				if target_distance < max_range and properties["has_seeker"]:
					
					var guidance_output = guidance_control_law(input_angles, delta, properties["seeker_type"])
					_apply_pitch_yaw_torque(guidance_output)
			
		# if laser seeker
		if properties["seeker_type"] == 2:
			if properties["has_seeker"]:
				guidance_control_law(input_angles, delta, properties["seeker_type"])
		
		if input_angles == Vector2.ZERO and not properties["seeker_type"] == 2:
			unlocked_life += delta
		
		cur_accel = linear_velocity - cur_accel

# ----------------------------------------------------------
#  CUSTOM GUIDANCE LAW
# ----------------------------------------------------------
var prev_angles = Vector2.ZERO  # store angles from previous frame
var p_tick := 8 # for debig print interval
var p_tick_cur := 0 # for debig print interval
@export_subgroup("Guidance")
@export var YAW_KP = 1.0
@export var YAW_KI = 0.0
@export var YAW_KD = 0.01
@export var PITCH_KP = 1.0
@export var PITCH_KI = 0.0
@export var PITCH_KD = 0.01
@export var N_FACTOR = 5.0
func guidance_control_law(relative_angles: Vector2, delta: float, type: int) -> Vector2:
	p_tick_cur += 1
	# `relative_angles.x` => horizontal angle (degrees) from forward
	# `relative_angles.y` => vertical angle (degrees) from forward
	
	var xval = 0
	var yval = 0
	var x_rate = (-relative_angles.x - prev_angles.x) * delta
	var y_rate = (relative_angles.y - prev_angles.y) * delta
	
	if type == 1: # ir
		xval = -relative_angles.x
		yval =  relative_angles.y
	
	elif type == 2: # SACLOS/laser (beam-riding)
		var target_position = Vector3()
		var player = get_tree().current_scene.get_node_or_null("Player/Player_Camera")
		if player:
			var player_aim_dir = -player.global_transform.basis.z  # Player's forward direction
			target_position = player.global_transform.origin + player_aim_dir * 10000.0
		
		var vec = adv_move.force_to_forward(delta, self, Vector3.DOWN, target_position)
		apply_force(vec * vel_sq * properties["mass"])
		
		xval = 0
		yval = 0
	
	elif type == 3:
		
	
	else: # non
		xval = 0
		yval = 0
	
	# PID update
	var cmd_x = pidx.update(delta, 0, xval, YAW_KP, YAW_KI, YAW_KD)
	var cmd_y = pidy.update(delta, 0, yval, PITCH_KP, PITCH_KI, PITCH_KD)
	
	if p_tick_cur >= p_tick:
		print()
		print("cmd yaw: ", cmd_x)
		print("cmd pitch: ", cmd_y)
		print("x rate: ", x_rate)
		print("y rate: ", y_rate)
		p_tick_cur = 0
	
	# Clamp commands and update prev_angles for next frame
	cmd_x = clamp(cmd_x, -seeker_fov, seeker_fov)
	cmd_y   = clamp(cmd_y,   -seeker_fov, seeker_fov)
	prev_angles = Vector2(xval, yval)
	return Vector2(cmd_y, cmd_x)

# ----------------------------------------------------------
#   HELPER: Compute horizontal & vertical angles (in degrees)
#   from missile forward direction to the target
# ----------------------------------------------------------
func get_target_angles_in_degrees(target: Node3D) -> Vector2:
	var to_target = (target.global_transform.origin - global_transform.origin).normalized()
	
	# Horizontal angle (yaw-like):
	var right_dir = global_transform.basis.x
	var horizontal_angle_radians = atan2(to_target.dot(right_dir), to_target.dot(cur_dir))
	var horizontal_angle_degrees = rad_to_deg(horizontal_angle_radians)
	
	# Vertical angle (pitch-like):
	var up_dir = global_transform.basis.z
	var vertical_angle_radians = atan2(to_target.dot(up_dir), to_target.dot(cur_dir))
	var vertical_angle_degrees = rad_to_deg(vertical_angle_radians)
	
	# if the missile can see the target, it can see the target
	if abs(vertical_angle_degrees) > seeker_fov or abs(horizontal_angle_degrees) > seeker_fov:
		return Vector2.ZERO
	
	return Vector2(horizontal_angle_degrees, vertical_angle_degrees)

# ----------------------------------------------------------
#   HELPER: Apply the pitch/yaw torque in degrees
# ----------------------------------------------------------
func _apply_pitch_yaw_torque(guidance_output: Vector2) -> void:
	var pitch_rad = deg_to_rad(guidance_output.x) / PI
	var yaw_rad = deg_to_rad(guidance_output.y) / PI
	
	var local_x = global_transform.basis.x  # Right direction
	var local_z = global_transform.basis.z  # "Fake" forward (since Y is real forward)
	var local_y = global_transform.basis.y  # anti roll formula
	
	var roll = -local_y.dot(Vector3.FORWARD) * local_x * 0.125  # anti roll formula
	
	var pitch_torque = local_x * pitch_rad  # Control up/down rotation
	var yaw_torque = local_z * yaw_rad  # Control left/right rotation
	var roll_torque = roll
	
	# Apply torque (scaled by velocity to make control more responsive at higher speeds)
	apply_torque((pitch_torque + yaw_torque + roll_torque) * linear_velocity.length_squared())

# the algorithm
var prev_msl_target_rel_rot := 0.0  # Store previous target-relative rotation
func guidance_pn_cbdr(
	delta: float,              # Delta time (seconds)
	msl_forward_vel: float,    # Missile's velocity in its forward direction
	msl_abs_rot: float,        # Missile's absolute rotation in world
	msl_target_rel_rot: float, # Angle from missile heading to target
	target_dis: float,         # Distance to target
	nav_gain: float = 3.0      # Navigation gain (N factor)
) -> float:
	# Wrap the target-relative rotation to [-PI, PI]
	var wrapped_target_rel_rot = wrapf(msl_target_rel_rot, -PI, PI)
	
	# Calculate Line-of-Sight (LOS) rate using finite difference
	var los_rate = (wrapped_target_rel_rot - prev_msl_target_rel_rot) / delta
	prev_msl_target_rel_rot = wrapped_target_rel_rot  # Store for next frame
	
	# Apply Proportional Navigation Law: a_n = N * Vc * LOS_rate
	var lateral_accel = nav_gain * msl_forward_vel * los_rate
	
	# Convert acceleration to a rotational torque
	var torque = lateral_accel
	
	# (optional) scale torque with distance
	torque /= max(target_dis, 1.0)
	
	# Limit torque to prevent unrealistic movements
	torque = clamp(torque, -10.0, 10.0)
	
	return torque  # Rotational torque for missile control
