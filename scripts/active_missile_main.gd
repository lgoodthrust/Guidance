extends RigidBody3D

@export var thrust_force: float = 300.0
@export var lifetime: float = 25.0
@export var launch_charge_force: float = 30.0
@export var motor_delay: float = 0.3
@export var fuel_duration: float = 0.5
@export var proximity_detonation_radius: float = 30.0
@export var max_range: float = 5000.0
@export var seeker_fov: float = 30.0
@export var unlocked_detonation_delay: float = 3.0

enum Seeker { NONE, IR, LASER, RADAR }
var seeker_type: Seeker = Seeker.NONE

var COM: Vector3 = Vector3.ZERO
var COP: Vector3 = Vector3.ZERO
var COT: Vector3 = Vector3.ZERO

var has_motor: bool = false
var has_controller: bool = false
var has_seeker: bool = false
var has_warhead: bool = false
var has_back_cannard: bool = false
var has_front_cannard: bool = false
var has_fin: bool = false
var mass_value: float = 0.0
var fuel_time: float = 0.0
var total_lift: float = 0.0

var launched: bool = false
var p_error: Vector3 = Vector3.ZERO
var p_trans: Transform3D = Transform3D()
var p_speed: float = 0.001
var p_dynq: float = 0.001
var p_delta: float = 0.0001
var p_forward: Vector3 = Vector3.ZERO
var prev_lin_vel: Vector3 = Vector3.ZERO
var prev_ang_vel: Vector3 = Vector3.ZERO
var p_lin_vel: Vector3 = Vector3.ZERO
var p_ang_vel: Vector3 = Vector3.ZERO
var p_lin_acc: Vector3 = Vector3.ZERO
var p_ang_acc: Vector3 = Vector3.ZERO

var blocks: Array[Node3D] = []
var launcher: Node
var life: float = 0.0
var unlocked_life: float = 0.0
var smoking: bool = false
var dist: float = 100.0
var target: Node3D
var targets: Array = []
var player: Node3D
var tracking: bool = true

var sound_launch: AudioStreamPlayer3D
var sound_fly: AudioStreamPlayer3D
var sound_wind: AudioStreamPlayer3D
var wind_playing: bool = false
var sound_scale: float = 1.0
var YES_A_HIT: bool = false

@onready var pidx0: PID = PID.new()
@onready var pidy0: PID = PID.new()
@onready var adv_move: ADV_MOVE = ADV_MOVE.new()
@onready var particles: gpu_particle_effects = gpu_particle_effects.new()
@onready var rng: RandomNumberGenerator = RandomNumberGenerator.new()
@onready var flame: SpotLight3D = SpotLight3D.new()

# === Aerodynamic parameters ===
const AIR_DENSITY: float = 1.225
const DRAG_CO_A: float = 0.05
const chord_length: float = 0.5
const diameter: float = 0.5
const REFERENCE_AREA = PI * (diameter * 0.5) ** 2
const LIFT_SLOPE = 4.0
const CD0 = 0.04
const DRAG_FACTOR = 0.075
const MOMENT_COEFF = 0.08
const MEAN_CHORD = chord_length

func _ready() -> void:
	launcher = get_tree().root.get_node("Launcher")
	player = get_tree().current_scene.get_node_or_null("Player/Player_Camera")
	
	sound_launch = _spawn_sound("res://game_data/sound/cursed_missile_01.mp3", true)
	sound_fly = _spawn_sound("res://game_data/sound/cursed_missile_02.mp3")
	sound_wind = _spawn_sound("res://game_data/sound/cursed_missile_03.mp3")
	
	_calculate_centers()
	
	flame.spot_range = 50.0
	flame.spot_angle = 25.0
	flame.light_color = Color(1, 0.745, 0.528)
	flame.light_energy = 12.0
	flame.light_specular = 12.0
	flame.shadow_enabled = true
	add_child(flame)
	flame.hide()
	flame.rotation = Vector3.BACK * global_transform.basis
	flame.position = Vector3(0,-1,0) #COT
	
	var shape: BoxShape3D = BoxShape3D.new()
	var box: CollisionShape3D = CollisionShape3D.new()
	shape.size = Vector3(0.5, len(blocks) * 2, 0.5)
	box.shape = shape
	add_child(box)
	box.owner = self
	box.position = COM - Vector3(0,5,0)
	
	freeze = false
	gravity_scale = 0.0
	linear_damp = 0.001
	angular_damp = 0.001
	mass = max(0.001, mass_value) # Good: avoid zero mass
	inertia = Vector3(blocks.size(), blocks.size() / 10.0, blocks.size()) * mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = COM
	
	rng.randomize()

func _rand_range() -> float:
	return rng.randf_range(-0.1, 0.1)

func _spawn_sound(path: String, autoplay: bool = false) -> AudioStreamPlayer3D:
	var s: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	s.stream = load(path)
	add_child(s)
	s.owner = self
	if autoplay:
		s.play()
	return s

func _process(_delta: float) -> void:
	targets = launcher.LAUCNHER_CHILD_SHARED_DATA["scenes"]["targets"]
	
	sound_scale = Engine.time_scale - 0.25 * Engine.time_scale
	sound_launch.pitch_scale = sound_scale
	sound_fly.pitch_scale = sound_scale
	sound_wind.pitch_scale = sound_scale

func _physics_process(delta: float) -> void:
	p_delta = delta
	p_trans = global_transform
	p_forward = p_trans.basis.y.normalized()
	p_lin_vel = linear_velocity
	p_ang_vel = angular_velocity
	p_speed = p_lin_vel.length()
	p_dynq = 0.5 * AIR_DENSITY * (p_speed**2)
	p_error = Vector3(_rand_range(), _rand_range(), _rand_range())
	
	p_lin_acc = (p_lin_vel - prev_lin_vel) / p_delta
	p_ang_acc = (p_ang_vel - prev_ang_vel) / p_delta
	prev_lin_vel = p_lin_vel
	prev_ang_vel = p_ang_vel
	
	if p_speed > 30.0 and not wind_playing:
		sound_wind.play()
		wind_playing = true
	
	life += p_delta
	if life >= lifetime:
		_explode_and_remove()
		return
	
	if not launched:
		apply_central_impulse(p_forward * launch_charge_force * mass)
		launched = true
	
	if has_motor and life > motor_delay and life < fuel_time:
		apply_force(p_forward * thrust_force * mass, COT)
		flame.show()
		
		if not sound_fly.playing:
			sound_fly.play()
			sound_fly.pitch_scale = sound_scale
		if not smoking:
			smoking = true
			var smoke: Node3D = particles.smoke_01()
			add_child(smoke)
			smoke.position = COT
		else:
			flame.hide()
	
	_apply_aero_forces()
	
	if is_instance_valid(target):
		dist = global_transform.origin.distance_to(target.global_transform.origin)
		if dist <= proximity_detonation_radius and has_warhead:
			_explode_and_remove()
			if not YES_A_HIT:
				target.HEALTH -= 25.0
				YES_A_HIT = true
			return
	
	if has_controller and has_seeker:
		var ids: int = find_visible_target_id(targets, p_trans.origin, p_forward)
		if ids != -1:
			target = targets[ids]
		
		match seeker_type:
			Seeker.IR:
				if is_instance_valid(target):
					_ir_guidance()
			Seeker.LASER:
				_laser_guidance()
			Seeker.RADAR:
				if is_instance_valid(target):
					_radar_guidance()
		
		if seeker_type != Seeker.LASER:
			if tracking == false or ids == -1:
					unlocked_life += p_delta
	
	if unlocked_life >= unlocked_detonation_delay or global_transform.origin.y < -10.0:
		_explode_and_remove()

func find_visible_target_id(
		targs: Array,
		missile_pos: Vector3,
		missile_forward: Vector3
	) -> int:
	
	var best_id = -1
	var closest_dist_sq = INF
	var cos_fov = cos(deg_to_rad(seeker_fov * 0.5))
	
	for i in range(targs.size()):
		var targ = targs[i]
		if not targ or not targ is Node3D:
			continue
		
		var to_target = targ.global_position - missile_pos
		var dist_sq = to_target.length_squared()
		if dist_sq > max_range * max_range:
			continue
		
		var dir_to_target = to_target.normalized()
		var dot = missile_forward.normalized().dot(dir_to_target)
		if dot < cos_fov:
			continue
		
		if dist_sq < closest_dist_sq:
			closest_dist_sq = dist_sq
			best_id = i
	
	return best_id

func smooth_vector3(
	x_prev: Vector3,
	z: Vector3,
	tau: float,
	delta: float) -> Vector3:
	var alpha = delta / (tau + delta)
	return x_prev + (z - x_prev) * alpha

func _apply_aero_forces() -> void:
	var speed = p_lin_vel.length()
	if speed < 1e-3:
		return
	var vdir = p_lin_vel / speed
	var fwd = p_forward.normalized()
	var right = p_trans.basis.x.normalized()
	var up = p_trans.basis.z.normalized()
	
	# angle of attack
	var pdot = clamp(fwd.dot(vdir), -1.0, 1.0)
	var alpha = acos(pdot)
	if vdir.dot(up) > 0.0:
		alpha = -alpha
	
	# lift & drag coefficients
	var cl = LIFT_SLOPE * alpha
	var cd = CD0 + DRAG_FACTOR * (cl * cl)
	
	# dynamic pressure
	var q = p_dynq
	
	# forces
	var lift_dir = right.cross(vdir).normalized()
	if lift_dir.dot(up) < 0.0:
		lift_dir = -lift_dir
	var lift  = lift_dir * q * cl * REFERENCE_AREA
	var drag  = -vdir    * q * cd * REFERENCE_AREA
	apply_force(lift + drag, COP)
	
	# gravity
	apply_central_force(Vector3.DOWN * 9.80665 * mass)
	
	# pitching moment
	var axis = fwd.cross(vdir)
	if axis.length() >= 1e-3:
		axis = axis.normalized()
		var Cm = MOMENT_COEFF * alpha
		var M  = axis * q * Cm * REFERENCE_AREA * MEAN_CHORD
		apply_torque(M)

func _ir_guidance() -> void:
	var noisy_pos = target.global_position + (p_error * dist * 0.01)
	var dir: Vector3 = (noisy_pos - p_trans.origin).normalized()
	var right: Vector3 = -p_trans.basis.x.normalized()
	var up: Vector3 = p_trans.basis.z.normalized()
	var pdot = dir.dot(p_forward.normalized())
	
	var angs = Vector2(
		atan2(dir.dot(-right), pdot),
		atan2(dir.dot(up),  pdot)
	)
	
	if abs(rad_to_deg(angs.x)) > seeker_fov or abs(rad_to_deg(angs.y)) > seeker_fov:
		tracking = false
		return
	else:
		tracking = true
	
	var ptz = p_trans.basis.z.normalized()
	var ptx = p_trans.basis.x.normalized()
	var yaw_tq: float = -pidx0.update(p_delta, 0.0, -angs.x, 2.0, 15, 0.3)
	var pitch_tq: float = -pidy0.update(p_delta, 0.0, angs.y, 2.0, 15, 0.3)
	var torque: Vector3 = ptz * yaw_tq + ptx * pitch_tq
	apply_torque(torque * p_dynq)

func _laser_guidance() -> void:
	if not player:
		return
	
	if p_speed > 15.0:
		var beam_origin: Vector3 = player.global_transform.origin
		var beam_dir: Vector3 = -player.global_transform.basis.z.normalized()
		var rel_to_beam = p_trans.origin - beam_origin
		var forward_dist = beam_dir.dot(rel_to_beam)
		var beam_point = beam_origin + beam_dir * forward_dist
		var intercept_point = beam_point + beam_dir * clamp(p_speed * 0.5, 10.0, 686.0)
		var steer_torque = adv_move.torque_to_pos(p_trans, Vector3.UP, intercept_point)
		apply_torque(steer_torque * p_dynq)

var prev_targ_pos_est: Vector3 = Vector3.ZERO
var prev_vel: Vector3 = Vector3.ZERO
var radar_first: bool = true
func _radar_guidance() -> void:
	var noisy_pos = target.global_position + (p_error * dist * 0.01)
	var to_target_dir = (noisy_pos - p_trans.origin).normalized()
	var pdot = to_target_dir.dot(p_forward.normalized())
	var yaw   = atan2(to_target_dir.dot(p_trans.basis.x), pdot)
	var pitch = atan2(to_target_dir.dot(p_trans.basis.z), pdot)
	
	if abs(rad_to_deg(yaw)) > seeker_fov or abs(rad_to_deg(pitch)) > seeker_fov:
		tracking = false
		return
	tracking = true
	
	var dir_body = Vector3(
		sin(yaw) * cos(pitch),
		cos(yaw) * cos(pitch),
		sin(pitch)
	)
	var raw_est = p_trans.origin + (p_trans.basis * dir_body) * dist
	
	# compute & smooth velocity
	var raw_vel = raw_est - prev_targ_pos_est
	prev_targ_pos_est = raw_est
	prev_vel = smooth_vector3(prev_vel, raw_vel, 0.8, p_delta)
	
	var intercept_pt = debug_intercept(
		p_trans.origin,
		p_speed,
		raw_est,
		prev_vel
	)
	
	if intercept_pt == Vector3.ZERO:
		intercept_pt = raw_est
	
	if radar_first:
		radar_first = false
		return
	
	var torque = adv_move.torque_to_pos(p_trans, Vector3.UP, intercept_pt)
	apply_torque(torque * p_dynq)

func debug_intercept(P0, s, T0, v_targ):
	# initial guess
	var t = P0.distance_to(T0) / max(s, 1e-6)
	for i in range(3):
		var aim = T0 + v_targ * t
		var flight = P0.distance_to(aim) / s
		t = (t + flight) * 0.5
	print(" final t = ", t, "  aim_offset = ", (T0 + v_targ*t) - T0)
	
	return T0 + v_targ * max(t, 0.0)

func _calculate_centers() -> void:
	for child in get_children():
		if child.get_class() == "Node3D" and child.DATA.has("NAME"):
			blocks.append(child)
	
	var lift_blocks = 0
	var thrust_blocks = 0
	
	for block:Node3D in blocks:
		var block_pos = block.to_global(Vector3(0,0,0))
		if block.DATA.has("TYPE"):
			if block.DATA["TYPE"] == 1:
				has_seeker = true
				match block.DATA["NAME"]:
					"IR_Seeker":
						seeker_type = Seeker.IR
					"Laser_Seeker":
						seeker_type = Seeker.LASER
					"Radar_Seeker":
						seeker_type = Seeker.RADAR
			
			if block.DATA["TYPE"] == 2:
				has_controller = true
			
			if block.DATA["TYPE"] == 3:
				has_warhead = true
			
			if block.DATA["TYPE"] == 4:
				has_fin = true
				COP += block_pos
				lift_blocks += 1
				total_lift += block.DATA["LIFT"]
			
			if block.DATA["TYPE"] == 5:
				has_front_cannard = true
				COP += block_pos
				lift_blocks += 1
				total_lift += block.DATA["LIFT"]
			
			if block.DATA["TYPE"] == 6:
				has_back_cannard = true
				COP += block_pos
				lift_blocks += 1
				total_lift += block.DATA["LIFT"]
			
			if block.DATA["TYPE"] == 7:
				fuel_time += fuel_duration
			
			if block.DATA["TYPE"] == 8:
				has_motor = true
				COT += block_pos
				thrust_blocks += 1
			
		if block.DATA.has("MASS"):
			COM += block_pos * block.DATA["MASS"]
			mass_value += block.DATA["MASS"]
	
	if mass_value > 0:
		COM /= mass_value
	if lift_blocks > 0:
		COP /= lift_blocks
	if thrust_blocks > 0:
		COT /= thrust_blocks
	
	fuel_time += motor_delay
	
	has_motor = has_motor
	has_warhead = has_warhead
	has_controller = has_controller

func _explode_and_remove() -> void:
	var kaboom = particles.explotion_01()
	get_tree().current_scene.get_node(".").add_child(kaboom)
	kaboom.global_position = p_trans.origin
	for block in blocks:
		block.hide()
	await get_tree().create_timer(0.05).timeout
	queue_free()
