extends RigidBody3D

@export var thrust_force: float = 300.0
@export var lifetime: float = 25.0
@export var launch_charge_force: float = 20.0
@export var motor_delay: float = 0.3
@export var fuel_duration: float = 1.5
@export var proximity_detonation_radius: float = 20.0
@export var max_range: float = 4000.0
@export var seeker_fov: float = 40.0
@export var unlocked_detonation_delay: float = 3.0

enum Seeker { NONE, IR, LASER, RADAR }
var seeker_type: Seeker = Seeker.NONE

@export var YAW_KP: float = 1.25
@export var YAW_KI: float = 15.0
@export var YAW_KD: float = 0.25
@export var PITCH_KP: float = 1.25
@export var PITCH_KI: float = 15.0
@export var PITCH_KD: float = 0.25

var centers = {
	"mass": Vector3.ZERO,
	"pressure": Vector3.ZERO,
	"thrust": Vector3.ZERO,
}

var properties = {
	"fuel": 0,
	"mass": 0.0,
	"total_lift": 0.0,
	"has_seeker": false,
	"has_controller": false,
	"has_warhead": false,
	"has_front_cannard": false,
	"has_back_cannard": false,
	"has_fin": false,
	"has_motor": false
}

var A = 1.0
var B = 1.0
var C = 0.001
var air_density = 1.225 #1.225 # ISA/USSA standard STP

var laucnhed: bool = false
var p_transform: Transform3D = Transform3D()
var p_speed: float = 0.0
var p_delta: float = 0.0001
var p_forward: Vector3 = Vector3.ZERO
var prev_lin_vel: Vector3 = Vector3.ZERO
var prev_ang_vel: Vector3 = Vector3.ZERO
var p_lin_vel: Vector3 = Vector3.ZERO
var p_ang_vel: Vector3 = Vector3.ZERO
var p_lin_acc: Vector3 = Vector3.ZERO
var p_ang_acc: Vector3 = Vector3.ZERO

var blocks = []
var launcher
var life: float = 0.0
var unlocked_life: float = 0.0
var smoking: bool = false
var dist = 100.0
var num_blocks: int = 0
var target: Node3D
var target_position
var player
var tracking: bool = true
var sound_launch: AudioStreamPlayer3D
var sound_fly: AudioStreamPlayer3D
var sound_wind: AudioStreamPlayer3D

@onready var pidx0 = PID.new()
@onready var pidy0 = PID.new()

@onready var adv_move = ADV_MOVE.new()

@onready var particles = gpu_particle_effects.new()

var launch_force: Vector3 = Vector3.ZERO
func _ready() -> void:
	launcher = get_tree().root.get_node("Launcher")
	target_position = Vector3()
	
	var sound1 = AudioStreamPlayer3D.new()
	sound1.stream = load("res://game_data/sound/cursed_missile_01.mp3")
	add_child(sound1)
	sound1.owner = self
	sound_launch = sound1
	sound_launch.play()
	
	var sound2 = AudioStreamPlayer3D.new()
	sound2.stream = load("res://game_data/sound/cursed_missile_02.mp3")
	add_child(sound2)
	sound2.owner = self
	sound_fly = sound2
	
	var sound3 = AudioStreamPlayer3D.new()
	sound3.stream = load("res://game_data/sound/cursed_missile_03.mp3")
	add_child(sound3)
	sound3.owner = self
	sound_wind = sound3
	
	player = get_tree().current_scene.get_node_or_null("Player/Player_Camera")
	
	load_missile_blocks()
	calculate_centers()
	
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.5, 8, 0.5)
	var box = CollisionShape3D.new()
	box.shape = shape
	add_child(box)
	box.position = centers["mass"]
	box.owner = self
	
	custom_integrator = true
	freeze = false
	gravity_scale = 1.0
	linear_damp = 0.001
	angular_damp = 0.001
	mass = max(1e-3, properties["mass"])
	inertia = Vector3(num_blocks, num_blocks / 10.0, num_blocks) * mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centers["mass"]
	
	target = launcher.LAUCNHER_CHILD_SHARED_DATA["scenes"]["target"]

func load_missile_blocks() -> void:
	for child in get_children():
		if child.get_class() == "Node3D" and child.DATA.has("NAME"):
			blocks.append(child)
			num_blocks += 1

func calculate_centers() -> void:
	var lift_blocks = 0
	var thrust_blocks = 0
	
	for block:Node3D in blocks:
		var block_pos = block.to_global(Vector3(0, 0, 0))
		if block.DATA.has("TYPE"):
			if block.DATA["TYPE"] == 1:
				properties["has_seeker"] = true
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
				properties["fuel"] += 0.25
				thrust_blocks += 1
		
		if block.DATA.has("MASS"):
			centers["mass"] += block_pos * block.DATA["MASS"]
			properties["mass"] += block.DATA["MASS"]
	
	if properties["mass"] > 0:
		centers["mass"] /= properties["mass"]
		
	if lift_blocks > 0:
		centers["pressure"] /= lift_blocks
		
	if thrust_blocks > 0:
		centers["thrust"] /= thrust_blocks
	
	properties["fuel"] += motor_delay

var sound_scale: float = 1.0
func _process(_delta):
	sound_scale = Engine.time_scale - 0.25 * Engine.time_scale
	sound_launch.pitch_scale = sound_scale
	sound_wind.pitch_scale = sound_scale

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	p_delta = state.step
	p_transform = global_transform
	p_forward = p_transform.basis.y
	p_speed = max(1e-3, linear_velocity.length())
	p_lin_vel = state.linear_velocity
	p_ang_vel = state.angular_velocity
	p_lin_acc = (p_lin_vel - prev_lin_vel) / p_delta
	p_ang_acc = (p_ang_vel - prev_ang_vel) / p_delta
	prev_lin_vel = p_lin_vel
	prev_ang_vel = p_ang_vel
	
	if abs(p_speed) < 0.1 and life > motor_delay:
		return
	elif p_speed > 45.0:
		if not sound_wind.playing:
			sound_wind.play()
	
	life += p_delta
	if life >= lifetime:
		_explode_and_remove()
		return
	
	if laucnhed == false:
		state.apply_central_impulse(p_forward * launch_charge_force * properties["mass"])
		laucnhed = true
	
	state.add_constant_central_force(Vector3.DOWN * 9.8067 * properties["mass"])
	
	if properties["has_motor"] and life > motor_delay and life < properties["fuel"]:
		state.add_constant_force(p_forward * thrust_force * properties["mass"], centers["thrust"])
		if not sound_fly.playing:
			sound_fly.play()
			sound_fly.pitch_scale = sound_scale
		
		if not smoking:
			smoking = true
			var smoke = particles.smoke_01()
			add_child(smoke)
			smoke.position = centers["thrust"]
	
	var vel_dir = p_lin_vel.normalized()
	var aoaos_axis = p_forward.cross(vel_dir)
	var force_scale = 0.5 * air_density * p_speed**2
	if aoaos_axis.length() > 0.005:
		aoaos_axis = aoaos_axis.normalized()
		var lift_dir = aoaos_axis.cross(vel_dir).normalized()
		
		var lift = lift_dir * force_scale * properties["total_lift"] * A
		state.apply_force(lift, centers["pressure"])
	
	var cur_accel = (p_lin_vel - prev_lin_vel) / p_delta
	prev_lin_vel = p_lin_vel
	var anti_drag = -cur_accel * C
	state.apply_force(anti_drag, centers["mass"])
	
	var angle = p_forward.angle_to(vel_dir)
	if aoaos_axis.length() > 0.005 and angle > 0.005:
		var torque_cmd = aoaos_axis.normalized() * angle
		var aero_mom = torque_cmd * force_scale * 0.88 * B
		var damp_mom = -p_ang_vel * (inertia.length() * 2.0)
		#state.apply_torque(aero_mom + damp_mom)
	
	if target:
		dist = global_transform.origin.distance_to(target.global_transform.origin)
		
		if dist <= proximity_detonation_radius and properties["has_warhead"]:
			_explode_and_remove()
			return
	
	if properties["has_seeker"]:
			if dist < max_range:
				var angles = _get_target_angles(target)
				if angles != Vector2.ZERO:
					var xval = 0
					var yval = 0
					
					if seeker_type == Seeker.IR: # ir
						xval = -angles.x
						yval =  angles.y
					
					elif seeker_type == Seeker.LASER: # SACLOS/laser (beam-riding)
						if player:
							var beam_origin = player.global_transform.origin
							var beam_dir = -player.global_transform.basis.z.normalized()
							var missile_pos = p_transform.origin
							var rel = missile_pos - beam_origin
							var rd = max(beam_dir.dot(rel), 0.0)
							var bp = beam_origin + beam_dir * rd
							var obp = bp + beam_dir * min(p_speed, 343)
							var st = adv_move.torque_to_pos(p_delta, self, Vector3.UP, obp)
							var lim = properties["mass"] / 10.0
							var sst = clamp(st * 10.0, -Vector3.ONE*lim, Vector3.ONE*lim)
							var p_torque = p_transform.basis.x * sst.y
							var y_torque = p_transform.basis.z * sst.x
							var comb_torque = (p_torque + y_torque) * properties["mass"] * p_speed**2
							#state.apply_torque(comb_torque)
						
						xval = 0
						yval = 0
						
					elif seeker_type == Seeker.RADAR: # radar
						xval = -angles.x
						yval =  angles.y
						var rel = Vector2(xval, yval)
						
						var calcs = _radar_steering_01(rel)
						
						xval = calcs.x
						yval = calcs.y
					
					else: # non
						xval = 0
						yval = 0
					
					var xx = -pidx0.update(p_delta, 0, xval, YAW_KP, YAW_KI, YAW_KD)
					var yy = -pidy0.update(p_delta, 0, yval, PITCH_KP, PITCH_KI, PITCH_KD)
					
					var output = Vector2(xx, yy)
					
					var pitch_torque = p_transform.basis.x * output.y
					var yaw_torque = p_transform.basis.z * output.x
					var forces = (pitch_torque + yaw_torque) * properties["mass"] * p_speed**2
					#state.apply_torque(forces)
	
	if tracking == false and not seeker_type == Seeker.LASER:
		unlocked_life += p_delta
	
	if unlocked_life >= unlocked_detonation_delay:
		_explode_and_remove()
	
	state.integrate_forces()

func _explode_and_remove() -> void:
	var kaboom = particles.explotion_01()
	get_tree().current_scene.get_node(".").add_child(kaboom)
	kaboom.global_position = p_transform.origin
	for block in blocks:
		block.hide()
	await get_tree().create_timer(0.05).timeout
	queue_free()

func _get_target_angles(target_node: Node3D) -> Vector2:
	var dir: Vector3 = (target_node.global_position - p_transform.origin).normalized()
	var fwd: Vector3 = p_forward
	var right: Vector3 = p_transform.basis.x
	var up: Vector3 = p_transform.basis.z
	
	var yaw: float = atan2(dir.dot(right), dir.dot(fwd)) * deg_to_rad(seeker_fov)
	var pitch: float = atan2(dir.dot(up), dir.dot(fwd)) * deg_to_rad(seeker_fov)
	
	if abs(rad_to_deg(yaw)) > seeker_fov or abs(rad_to_deg(pitch)) > seeker_fov:
		tracking = false
		return Vector2.ZERO
	else:
		tracking = true
	return Vector2(yaw, pitch)

var prev_rel_ang: Vector2 = Vector2.ZERO
func _radar_steering_01(relative_angles: Vector2) -> Vector2:
	var rate_rel_angle = (relative_angles - prev_rel_ang) / p_delta
	prev_rel_ang = relative_angles
	
	var pitch_rate = p_ang_vel.dot(p_transform.basis.x) / p_delta
	var yaw_rate = p_ang_vel.dot(p_transform.basis.z) / p_delta
	var py_vel = Vector2(yaw_rate, pitch_rate)
	
	var output = rate_rel_angle - py_vel
	
	return output
