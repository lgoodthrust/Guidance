extends RigidBody3D  # Vector up = missile forward

@export_subgroup("Main")
@export var thrust_force: float = 500.0
@export var min_effective_speed: float = 50.0
@export var lifetime: float = 15.0
@export var max_range = 3500.0
@export var seeker_fov = 15
@export var motor_delay = 0.25
@export var fuel_block_duration = 0.75
@export var launch_charge_force = 3000.0
@export var proximity_detonation_radius = 15.0

var launcher
var blocks = []
var life := 0.0
var target_distance

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
	"has_front_cannard": false,
	"has_back_cannard": false,
	"has_warhead": false,
	"has_fin": false,
	"has_motor": false
}

@onready var pidx = PID.new()
@onready var pidy = PID.new()

func _ready() -> void:
	launcher = get_parent().get_parent()
	load_missile_blocks()
	calculate_centers()
	
	# Minimal physics setup
	freeze = false
	gravity_scale = 0.0
	linear_damp = 0.001
	angular_damp = 0.001
	mass = max(1.0, properties["mass"])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centers["mass"]

var smoking = false
func smoke():
	if not smoking:
		smoking = true
		var color = Color8(128, 128, 128, 200)
		var gpup = GPUParticles3D.new()
		gpup.amount = 3000
		gpup.one_shot = false
		gpup.fixed_fps = 45.0
		gpup.explosiveness = 0.125
		gpup.lifetime = 3.0
		var ppm = ParticleProcessMaterial.new()
		ppm.gravity = Vector3.UP * 0.25
		ppm.inherit_velocity_ratio = 0.25
		gpup.process_material = ppm
		gpup.draw_passes = 1
		var bm = BoxMesh.new()
		bm.size = Vector3(0.1, 0.1, 0.1)
		var bmm = StandardMaterial3D.new()
		bmm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		bmm.albedo_color = color
		bmm.emission_enabled = true
		bmm.emission = color
		bmm.emission_energy_multiplier = 1.0
		bm.material = bmm
		gpup.draw_pass_1 = bm
		self.add_child(gpup)

func kaboom():
	var c = Curve.new()
	c.bake_resolution = 32
	c.add_point(Vector2(0,1), 0, -1)
	c.add_point(Vector2(1,0), -1, 0)
	
	var ct = CurveTexture.new()
	ct.width = 32
	ct.curve = c
	
	var ppm = ParticleProcessMaterial.new()
	ppm.inherit_velocity_ratio = 0.01
	ppm.initial_velocity_min = 200.0
	ppm.initial_velocity_max = 500.0
	ppm.spread = 180.0
	ppm.gravity = Vector3.ZERO
	ppm.scale_min = 0.5
	ppm.scale_max = 1.0
	ppm.scale_curve = ct
	
	var sm = StandardMaterial3D.new()
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	sm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	sm.disable_ambient_light = true
	sm.emission_enabled = true
	sm.emission = Color8(255,255,255,255)
	
	var bm = BoxMesh.new()
	bm.size = Vector3(0.5,0.5,0.5)
	bm.material = sm
	
	var gpup = GPUParticles3D.new()
	gpup.amount = 100
	gpup.one_shot = true
	gpup.lifetime = 0.125
	gpup.explosiveness = 1.0
	gpup.fixed_fps = 15
	gpup.process_material = ppm
	gpup.draw_pass_1 = bm
	get_parent().add_child(gpup)
	gpup.global_position = self.global_position
	remove()

func remove():
	var missile_list = launcher.LAUCNHER_CHILD_SHARED_DATA["world"]["missiles"]
	if missile_list:
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
	if life < 0.01:
		# Small impulse at spawn
		apply_impulse(global_transform.basis.y.normalized() * launch_charge_force)
	
	life += delta
	
	if life >= lifetime:
		remove()
	
	var forward_dir = global_transform.basis.y.normalized()
	
	# Apply thrust if there's still "fuel" time
	if properties["fuel"] > life and life > motor_delay and properties["has_motor"]:
		apply_force(forward_dir * thrust_force * properties["mass"], centers["thrust"])
		smoke()
	
	# Apply weight force
	apply_central_force(Vector3.DOWN * 9.80665 * properties["mass"])
	
	# If moving faster than a certain speed
	if linear_velocity.length() > min_effective_speed:
		# Apply aerodynamic alignment (forward flight toward missile's forward direction)
		var vel_dir = linear_velocity.normalized()
		var afd = (forward_dir - vel_dir).normalized()
		var afm = forward_dir.angle_to(vel_dir) * linear_velocity.length_squared()
		apply_central_force(afd * afm * 0.8)
		
		# apply aerodynamic alignment (missile toward foward flight)
		var axis = forward_dir.cross(vel_dir)
		var angle = forward_dir.angle_to(vel_dir)
		if axis.length() > 0.001 and angle > 0.001:
			var torque = axis.normalized() * angle
			apply_torque(torque * linear_velocity.length_squared() * 1.2)
		
		aim_and_torque_at_target(delta)

func aim_and_torque_at_target(delta):
	var target = get_tree().current_scene.get_node_or_null("World/Active_Target")
	if not target:
		return
	
	target_distance = global_transform.origin.distance_to(target.global_transform.origin)
	
	if target_distance <= proximity_detonation_radius and properties["has_warhead"]:
		kaboom()
	
	# If in range and we have IR seeker, we attempt to steer
	if target_distance < max_range and properties["has_seeker"] and properties["has_motor"]:
		var input_angles = _get_target_angles_in_degrees(target)
		var guidance_output = guidance_control_law(input_angles, delta)
		
		_apply_pitch_yaw_torque(guidance_output)

# ----------------------------------------------------------
#  CUSTOM GUIDANCE LAW
# ----------------------------------------------------------
var prev_angles = Vector2.ZERO  # store angles from previous frame
var p_tick := 1
var p_tick_cur := 0
@export_subgroup("Guidance")
@export var YAW_KP = 1.0
@export var YAW_KI = 0.0
@export var YAW_KD = 0.1
@export var PITCH_KP = 1.0
@export var PITCH_KI = 0.0
@export var PITCH_KD = 0.1
@export var N_FACTOR = 3.0
func guidance_control_law(relative_angles: Vector2, delta: float) -> Vector2:
	p_tick_cur += 1
	# `relative_angles.x` => horizontal angle (degrees) from forward
	# `relative_angles.y` => vertical angle (degrees) from forward
	
	# Convert to local variables, flipping sign if needed for your coordinate system
	var xval = -relative_angles.x
	var yval =  relative_angles.y

	# Calculate LOS angle rates (deg/s)
	var d_xval = (xval - prev_angles.x)
	var d_yval = (yval - prev_angles.y)
	
	# Missile speed along forward axis (approx "closing speed" if target is in front).
	var vel = linear_velocity.length()
	
	# Compute LOS rate-based acceleration
	var los_rate_x = d_xval  # Approximate LOS rate in horizontal direction
	var los_rate_y = d_yval  # Approximate LOS rate in vertical direction
	
	# Proportional Navigation (PN) parameters
	var _acc_x = N_FACTOR * vel * los_rate_x  # PN acceleration command (horizontal)
	var _acc_y = N_FACTOR * vel * los_rate_y  # PN acceleration command (vertical)

	var leadx = xval
	var leady = yval
	
	# PID update for smooth correction with clamping
	var cmd_x = pidx.update(delta, leadx, 0, YAW_KP, YAW_KI, YAW_KD)
	var cmd_y = pidy.update(delta, leady, 0, PITCH_KP, PITCH_KI, PITCH_KD)
	
	if p_tick_cur >= p_tick:
		print()
		print("cmd yaw: ", cmd_x)
		print("cmd pitch: ", cmd_y)
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
func _get_target_angles_in_degrees(target: Node3D) -> Vector2:
	var forward_dir = global_transform.basis.y
	var to_target = (target.global_transform.origin - global_transform.origin).normalized()
	
	# Horizontal angle (yaw-like):
	var right_dir = global_transform.basis.x
	var horizontal_angle_radians = atan2(
		to_target.dot(right_dir),
		to_target.dot(forward_dir)
	)
	var horizontal_angle_degrees = rad_to_deg(horizontal_angle_radians)
	
	# Vertical angle (pitch-like):
	var up_dir = global_transform.basis.z
	var vertical_angle_radians = atan2(
		to_target.dot(up_dir),
		to_target.dot(forward_dir)
	)
	var vertical_angle_degrees = rad_to_deg(vertical_angle_radians)
	
	# if the missile can see the target, it can see the target
	if abs(vertical_angle_degrees) > seeker_fov or abs(horizontal_angle_degrees) > seeker_fov:
		return Vector2.ZERO
	
	return Vector2(horizontal_angle_degrees, vertical_angle_degrees)

# ----------------------------------------------------------
#   HELPER: Apply the pitch/yaw torque in degrees
# ----------------------------------------------------------
func _apply_pitch_yaw_torque(guidance_output: Vector2) -> void:
	var pitch_rad = deg_to_rad(guidance_output.x)/PI
	var yaw_rad   = deg_to_rad(guidance_output.y)/PI
	
	var local_x = global_transform.basis.x.normalized()
	var local_z = global_transform.basis.z.normalized()
	
	var pitch_torque = local_x * pitch_rad
	var yaw_torque   = local_z * yaw_rad
	
	apply_torque((pitch_torque + yaw_torque) * linear_velocity.length_squared())
