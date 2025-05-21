extends RigidBody3D

@export var thrust_force: float = 300.0
@export var lifetime: float = 25.0
@export var launch_charge_force: float = 30.0
@export var motor_delay: float = 0.3
@export var fuel_duration: float = 1.5
@export var proximity_detonation_radius: float = 20.0
@export var max_range: float = 8000.0
@export var seeker_fov: float = 40.0
@export var unlocked_detonation_delay: float = 3.0

enum Seeker { NONE, IR, LASER, RADAR }
var seeker_type: Seeker = Seeker.NONE

@export var YAW_KP: float = 1.25
@export var YAW_KI: float = 15.0
@export var YAW_KD: float = 0.3
@export var PITCH_KP: float = 1.25
@export var PITCH_KI: float = 15.0
@export var PITCH_KD: float = 0.3

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

var launched: bool = false # corrected typo
var p_trans: Transform3D = Transform3D()
var p_speed: float = 0.001
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
var target: Node3D
var target_position: Vector3 = Vector3.ZERO
var player
var laucnhed = false
var tracking: bool = true
var sound_launch: AudioStreamPlayer3D
var sound_fly: AudioStreamPlayer3D
var sound_wind: AudioStreamPlayer3D

@onready var pidx0 = PID.new()
@onready var pidy0 = PID.new()
@onready var pidx1 = PID.new()
@onready var pidy1 = PID.new()

@onready var adv_move = ADV_MOVE.new()

@onready var particles = gpu_particle_effects.new()

func _ready() -> void:
	for child in get_children():
		if child.get_class() == "Node3D" and child.DATA.has("NAME"):
			blocks.append(child)

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
	
	calculate_centers()
	
	var shape = BoxShape3D.new()
	var box = CollisionShape3D.new()
	shape.size = Vector3(0.5, len(blocks), 0.5)
	box.shape = shape
	add_child(box)
	box.position = centers["mass"]
	box.owner = self
	
	freeze = false
	gravity_scale = 0.0
	linear_damp = 0.001
	angular_damp = 0.001
	mass = max(1e-3, properties["mass"])
	inertia = Vector3(len(blocks), len(blocks) / 10.0, len(blocks)) * mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centers["mass"]
	
	target = launcher.LAUCNHER_CHILD_SHARED_DATA["scenes"]["target"]
	player = get_tree().current_scene.get_node_or_null("Player/Player_Camera")

func calculate_centers() -> void:
	for child in get_children():
		if child.get_class() == "Node3D" and child.DATA.has("NAME"):
			blocks.append(child)
	
	var lift_blocks = 0
	var thrust_blocks = 0
	
	for block:Node3D in blocks:
		var block_pos = block.to_global(Vector3(0,0,0))
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

var A = 1.0
var B = 1.0
var air_density = 1.225 # ISA/USSA standard STP

var prev_rel_ang: Vector2 = Vector2.ZERO
var prev_ang_rate = Vector2.ZERO
var wind_playing = false
var radar_first: bool = true
func _physics_process(delta: float) -> void:
	p_delta = delta
	p_trans = global_transform
	p_forward = p_trans.basis.y
	p_lin_vel = linear_velocity
	p_ang_vel = angular_velocity
	p_speed = max(0.001, p_lin_vel.length())
	p_lin_acc = (p_lin_vel - prev_lin_vel) / p_delta
	p_ang_acc = (p_ang_vel - prev_ang_vel) / p_delta
	prev_lin_vel = p_lin_vel
	prev_ang_vel = p_ang_vel
	
	if p_speed > 45.0 and not wind_playing:
		sound_wind.play()
		wind_playing = true
	
	life += p_delta
	if life >= lifetime:
		explode_and_remove()
		return
	
	if not launched:
		apply_central_impulse(p_forward * launch_charge_force * properties["mass"])
		launched = true
	
	if properties["has_motor"] and life > motor_delay and life < properties["fuel"]:
		apply_force(p_forward * thrust_force * properties["mass"], centers["thrust"])
	
		if not sound_fly.playing:
			sound_fly.play()
			sound_fly.pitch_scale = sound_scale
	
		if not smoking:
			smoking = true
			var smoke = particles.smoke_01()
			add_child(smoke)
			smoke.position = centers["thrust"]
	
	apply_central_force(Vector3.DOWN * 9.80665 * properties["mass"])
	
	var damp_mom: Vector3 = Vector3(
		-p_ang_vel.x * inertia.x,
		-p_ang_vel.y * inertia.y,
		-p_ang_vel.z * inertia.z)
	
	var vel_dir: Vector3 = p_lin_vel.normalized()
	var aoas_axis: Vector3 = p_forward.cross(vel_dir)
	var dynq = 0.5 * air_density * (p_speed**2.0)
	var aoaos_scale = p_forward.dot(vel_dir)
	
	if abs(p_speed) > 1e-3:
		var ang: float = acos(clamp(aoaos_scale, -1.0, 1.0))
		var aoas_hat: Vector3 = aoas_axis / aoas_axis.length()
		
		# push back against aoa/aos
		var lift_dir: Vector3 = vel_dir.cross(aoas_hat).normalized()
		var lift: Vector3 = lift_dir * dynq * properties["total_lift"] * A * ang
		apply_force(lift, centers["pressure"])
		
		# rotate toward velocity direction
		var aero_torque: Vector3 = -aoas_axis * ang * dynq * properties["total_lift"] * B
		apply_torque((aero_torque) + damp_mom)
	
	if target:
		dist = global_transform.origin.distance_to(target.global_transform.origin)
		if dist <= proximity_detonation_radius and properties["has_warhead"]:
			explode_and_remove()
			return
	
	if properties["has_seeker"] and target and dist < max_range:
		var angles: Vector2 = get_target_angles(target)
		
		if angles != Vector2.ZERO:
			var xerr: float = angles.x
			var yerr: float = angles.y
			match seeker_type:
				Seeker.IR:
					var yaw_tq = -pidx0.update(p_delta, 0.0, xerr, 1.25, 15.0, 0.3)
					var pitch_tq = -pidy0.update(p_delta, 0.0, yerr, 1.25, 15.0, 0.3)
					
					var comb_forces = (p_trans.basis.z * yaw_tq + p_trans.basis.x * pitch_tq)
					apply_torque(comb_forces * dynq)
					
				Seeker.LASER:
					if player:
						var beam_origin = player.global_transform.origin
						var beam_dir = -player.global_transform.basis.z.normalized()
						var rel = p_trans.origin - beam_origin
						var rd = max(beam_dir.dot(rel), 0.0)
						var bp = beam_origin + (beam_dir * rd) # axil
						var obp = bp + (beam_dir * min(dynq, 343)) # axil + forwarding
						var st = adv_move.torque_to_pos(p_delta, self, Vector3.UP, obp)
						apply_torque(st * dynq)
					
				Seeker.RADAR:
					if radar_first:
						radar_first = false
						prev_rel_ang = angles
						prev_ang_rate = Vector2.ZERO
					
					var ang_rate = (angles - prev_rel_ang) / p_delta
					prev_rel_ang = angles
					
					ang_rate *= 5.0
					
					# Compute desired correction (LOS rate - body rotation)
					var yaw_cmd = ang_rate.x - p_ang_vel.z
					var pitch_cmd = ang_rate.y - p_ang_vel.x
					
					# PID gains
					var kp = 100.0
					var ki = 0.0
					var kd = 0.0
					
					# Get torques from PID
					var yaw_tq = -pidx1.update(p_delta, 0.0, yaw_cmd, kp, ki, kd)
					var pitch_tq = -pidy1.update(p_delta, 0.0, pitch_cmd, kp, ki, kd)
					
					# Apply torque in missile's local basis
					var torque = p_trans.basis.z * yaw_tq + p_trans.basis.x * pitch_tq
					torque = torque.lerp(Vector3.ZERO, 0.125) 
					apply_torque(torque)
					
				Seeker.NONE:
					pass
	
	if not tracking and seeker_type != Seeker.LASER:
		unlocked_life += p_delta
	if unlocked_life >= unlocked_detonation_delay:
		explode_and_remove()
	if p_trans.origin.y < -10.0:
		explode_and_remove()

func explode_and_remove() -> void:
	var kaboom = particles.explotion_01()
	get_tree().current_scene.get_node(".").add_child(kaboom)
	kaboom.global_position = p_trans.origin
	for block in blocks:
		block.hide()
	await get_tree().create_timer(0.05).timeout
	queue_free()

func get_target_angles(target_node: Node3D) -> Vector2:
	var dir: Vector3 = (target_node.global_position - p_trans.origin).normalized()
	var right: Vector3 = p_trans.basis.x
	var up: Vector3 = p_trans.basis.z
	
	var yaw: float = atan2(dir.dot(right), dir.dot(p_forward))
	var pitch: float = atan2(dir.dot(up), dir.dot(p_forward))
	
	if abs(rad_to_deg(yaw)) > seeker_fov or abs(rad_to_deg(pitch)) > seeker_fov:
		tracking = false
		return Vector2.ZERO
	else:
		tracking = true
	return Vector2(-yaw, pitch)
