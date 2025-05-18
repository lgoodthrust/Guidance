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
var air_density = 1.225 # ISA/USSA standard STP

var launched: bool = false # corrected typo
var p_trans: Transform3D = Transform3D()
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
var target_position: Vector3 = Vector3.ZERO
var player
var laucnhed = false
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
	gravity_scale = 1.0 # TODO: set to 0 if manual gravity retained
	linear_damp = 0.001
	angular_damp = 0.001
	mass = max(1e-3, properties["mass"])
	inertia = Vector3(num_blocks, num_blocks / 10.0, num_blocks) * mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centers["mass"]
	
	target = launcher.LAUCNHER_CHILD_SHARED_DATA["scenes"]["target"]
	player = get_tree().current_scene.get_node_or_null("Player/Player_Camera")

func calculate_centers() -> void:
	for child in get_children():
		if child.get_class() == "Node3D" and child.DATA.has("NAME"):
			blocks.append(child)
			num_blocks += 1
	
	var lift_blocks = 0
	var thrust_blocks = 0
	
	for block: Node3D in blocks:
		var block_pos = block.to_global(Vector3.ZERO)
		# TODO: store local offset instead to avoid world/local mix-up
	
		if block.DATA.has("TYPE"):
			match block.DATA["TYPE"]:
				1:
					properties["has_seeker"] = true
					match block.DATA["NAME"]:
						"IR_Seeker":   seeker_type = Seeker.IR
						"Laser_Seeker": seeker_type = Seeker.LASER
						"Radar_Seeker": seeker_type = Seeker.RADAR
				2: properties["has_controller"] = true
				3: properties["has_warhead"] = true
				4,5,6:
					properties["has_fin"] = true
					centers["pressure"] += block_pos
					lift_blocks += 1
					properties["total_lift"] += block.DATA["LIFT"]
				7:
					properties["fuel"] += fuel_duration
				8:
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
	p_delta = state.get_step()
	p_trans = state.get_transform()
	p_forward = p_trans.basis.y
	p_lin_vel = state.get_linear_velocity()
	p_speed = max(1e-3, p_lin_vel.length())
	p_ang_vel = state.get_angular_velocity()
	p_lin_acc = (p_lin_vel - prev_lin_vel) / p_delta
	p_ang_acc = (p_ang_vel - prev_ang_vel) / p_delta
	prev_lin_vel = p_lin_vel
	prev_ang_vel = p_ang_vel
	
	var total_force: Vector3 = Vector3.ZERO
	var total_torque: Vector3 = Vector3.ZERO
	
	var force_scale = 0.5 * air_density * p_speed * p_speed
	
	if p_speed > 45.0 and not sound_wind.playing:
		sound_wind.play()
	
	life += p_delta
	if life >= lifetime:
		explode_and_remove()
		return
	
	if laucnhed == false:
		state.apply_central_impulse(p_forward * launch_charge_force * properties["mass"])
		laucnhed = true
	
	if properties["has_motor"] and life > motor_delay and life < properties["fuel"]:
		var stuff = p_forward * thrust_force * properties["mass"]
		total_force += stuff
		total_torque += adv_move.torque_from_offset_force(p_trans, centers["thrust"], stuff)
		if not sound_fly.playing:
			sound_fly.play()
			sound_fly.pitch_scale = sound_scale
		
		if not smoking:
			smoking = true
			var smoke = particles.smoke_01()
			add_child(smoke)
			smoke.position = centers["thrust"]
	
	total_force += p_trans.basis * Vector3.DOWN * 9.8067 * properties["mass"]
	
	var vel_dir = p_lin_vel.normalized()
	var aoaos_axis = p_forward.cross(vel_dir)
	if abs(aoaos_axis.length()) > 0.005:
		var lift_dir = aoaos_axis.normalized().cross(vel_dir).normalized()
		var lift = lift_dir * force_scale * properties["total_lift"] * A
		var lift_force = lift * properties["mass"]
		total_force += lift_force
		total_torque += adv_move.torque_from_offset_force(p_trans, centers["pressure"], lift_force)
	
	var anti_drag = -p_lin_acc * C
	var anti_forces = anti_drag * properties["mass"]
	total_force += anti_forces
	total_torque += adv_move.torque_from_offset_force(p_trans, centers["mass"], anti_forces)
	
	var angle = p_forward.angle_to(vel_dir)
	if abs(aoaos_axis.length()) > 0.005 and abs(angle) > 0.005:
		var torque_cmd = aoaos_axis.normalized() * angle
		var aero_mom = torque_cmd * force_scale * 0.88 * B
		var damp_mom = -p_ang_vel * (inertia.length() * 2.0)
		total_torque += (aero_mom + damp_mom * properties["mass"])
	
	if target:
		dist = global_transform.origin.distance_to(target.global_transform.origin)
		
		if dist <= proximity_detonation_radius and properties["has_warhead"]:
			explode_and_remove()
			return
	
	if properties["has_seeker"]:
			if dist < max_range:
				var angles = get_target_angles(target)
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
							var missile_pos = p_trans.origin
							var rel = missile_pos - beam_origin
							var rd = max(beam_dir.dot(rel), 0.0)
							var bp = beam_origin + beam_dir * rd
							var obp = bp + beam_dir * min(p_speed, 343)
							var st = adv_move.torque_to_pos(p_delta, self, Vector3.UP, obp)
							var lim = properties["mass"] / 10.0
							var sst = clamp(st * 10.0, -Vector3.ONE*lim, Vector3.ONE*lim)
							var p_torque = p_trans.basis.x * sst.y
							var y_torque = p_trans.basis.z * sst.x
							var torque_beam = (p_torque + y_torque)
							var comb_torque = torque_beam * properties["mass"] * p_speed
							total_torque += (comb_torque)
						
						xval = 0
						yval = 0
						
					elif seeker_type == Seeker.RADAR: # radar
						xval = -angles.x
						yval =  angles.y
						var rel = Vector2(xval, yval)
						
						var calcs = radar_steering_01(rel)
						
						xval = calcs.x
						yval = calcs.y
					
					else: # non
						xval = 0
						yval = 0
					
					var xx = -pidx0.update(p_delta, 0, xval, YAW_KP, YAW_KI, YAW_KD)
					var yy = -pidy0.update(p_delta, 0, yval, PITCH_KP, PITCH_KI, PITCH_KD)
					
					var output = Vector2(xx, yy)
					
					var pitch_torque = p_trans.basis.x * output.y
					var yaw_torque = p_trans.basis.z * output.x
					var torque_pid = (pitch_torque + yaw_torque)
					var forces = torque_pid * properties["mass"] * p_speed
					total_torque += (forces)
	
	if tracking == false and not seeker_type == Seeker.LASER:
		unlocked_life += p_delta
	
	if unlocked_life >= unlocked_detonation_delay:
		explode_and_remove()
	
	state.apply_central_force(total_force)
	state.apply_torque(total_torque)


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
	var fwd: Vector3 = p_forward
	var right: Vector3 = p_trans.basis.x
	var up: Vector3 = p_trans.basis.z
	
	var yaw: float = atan2(dir.dot(right), dir.dot(fwd)) * deg_to_rad(seeker_fov)
	var pitch: float = atan2(dir.dot(up), dir.dot(fwd)) * deg_to_rad(seeker_fov)
	
	if abs(rad_to_deg(yaw)) > seeker_fov or abs(rad_to_deg(pitch)) > seeker_fov:
		tracking = false
		return Vector2.ZERO
	else:
		tracking = true
	return Vector2(yaw, pitch)

var prev_rel_ang: Vector2 = Vector2.ZERO
func radar_steering_01(relative_angles: Vector2) -> Vector2:
	var rate_rel_angle = (relative_angles - prev_rel_ang) / p_delta
	prev_rel_ang = relative_angles
	
	var pitch_rate = p_ang_vel.dot(p_trans.basis.x) / p_delta
	var yaw_rate = p_ang_vel.dot(p_trans.basis.z) / p_delta
	var py_vel = Vector2(yaw_rate, pitch_rate)
	
	var output = rate_rel_angle - py_vel
	
	return output
