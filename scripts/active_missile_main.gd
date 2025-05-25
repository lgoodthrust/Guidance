extends RigidBody3D

@export var thrust_force: float = 300.0
@export var lifetime: float = 25.0
@export var launch_charge_force: float = 30.0
@export var motor_delay: float = 0.3
@export var fuel_duration: float = 1.5
@export var proximity_detonation_radius: float = 20.0
@export var max_range: float = 8000.0
@export var seeker_fov: float = 45.0
@export var unlocked_detonation_delay: float = 3.0

enum Seeker { NONE, IR, LASER, RADAR }
var seeker_type: Seeker = Seeker.NONE

@export var YAW_KP: float = 1.5
@export var YAW_KI: float = 15.0
@export var YAW_KD: float = 0.3
@export var PITCH_KP: float = 1.5
@export var PITCH_KI: float = 15.0
@export var PITCH_KD: float = 0.3

var centers = {
	"mass": Vector3.ZERO,
	"pressure": Vector3.ZERO,
	"thrust": Vector3.ZERO,
}

var properties = {
	"fuel": 0.0,
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
var player: Node3D
var tracking: bool = true

var sound_launch: AudioStreamPlayer3D
var sound_fly: AudioStreamPlayer3D
var sound_wind: AudioStreamPlayer3D
var wind_playing: bool = false
var sound_scale: float = 1.0

@onready var pidx0: PID = PID.new()
@onready var pidy0: PID = PID.new()
@onready var adv_move: ADV_MOVE = ADV_MOVE.new()
@onready var particles: gpu_particle_effects = gpu_particle_effects.new()
@onready var fdbk0: FEEDBACK = FEEDBACK.new()
@onready var fdbk1x: FEEDBACK = FEEDBACK.new()
@onready var fdbk1y: FEEDBACK = FEEDBACK.new()
var rng := RandomNumberGenerator.new()

const AIR_DENSITY: float = 1.225
const AERO_A: float = 1.0
const AERO_B: float = 1.0

var radar_first: bool = true
var prev_rel_ang: Vector2 = Vector2.ZERO
var prev_range: float = 0.0

func _ready() -> void:
	for child in get_children():
		if child is Node3D and child.DATA.has("NAME"):
			blocks.append(child)
	
	launcher = get_tree().root.get_node("Launcher")
	target = launcher.LAUCNHER_CHILD_SHARED_DATA["scenes"]["target"]
	player = get_tree().current_scene.get_node_or_null("Player/Player_Camera")
	
	sound_launch = _spawn_sound("res://game_data/sound/cursed_missile_01.mp3", true)
	sound_fly = _spawn_sound("res://game_data/sound/cursed_missile_02.mp3")
	sound_wind = _spawn_sound("res://game_data/sound/cursed_missile_03.mp3")
	
	_calculate_centers()
	
	var shape: BoxShape3D = BoxShape3D.new()
	var box: CollisionShape3D = CollisionShape3D.new()
	shape.size = Vector3(0.5, blocks.size(), 0.5)
	box.shape = shape
	add_child(box)
	box.owner = self
	box.position = centers["mass"] - Vector3(0,5,0)
	
	freeze = false
	gravity_scale = 0.0
	linear_damp = 0.001
	angular_damp = 0.001
	mass = max(0.001, properties["mass"])
	inertia = Vector3(blocks.size(), blocks.size() / 10.0, blocks.size()) * mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centers["mass"]
	
	rng.randomize()

func _rand_range() -> float:
	return rng.randf_range(-1.0, 1.0)

func _spawn_sound(path: String, autoplay: bool = false) -> AudioStreamPlayer3D:
	var s: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	s.stream = load(path)
	add_child(s)
	s.owner = self
	if autoplay:
		s.play()
	return s

func _process(_delta: float) -> void:
	sound_scale = Engine.time_scale - 0.25 * Engine.time_scale
	sound_launch.pitch_scale = sound_scale
	sound_fly.pitch_scale = sound_scale
	sound_wind.pitch_scale = sound_scale

func _physics_process(delta: float) -> void:
	p_delta = delta
	p_trans = global_transform
	p_forward = p_trans.basis.y
	p_lin_vel = linear_velocity
	p_ang_vel = angular_velocity
	p_speed = p_lin_vel.length()
	p_dynq = 0.5 * AIR_DENSITY * (p_speed**2)
	p_error = Vector3(_rand_range(), _rand_range(), _rand_range()) * 0.1
	
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
	
	if properties["has_motor"] and life > motor_delay and life < properties["fuel"]:
		apply_force(p_forward * thrust_force * mass, centers["thrust"])
		if not sound_fly.playing:
			sound_fly.play()
			sound_fly.pitch_scale = sound_scale
		if not smoking:
			smoking = true
			var smoke: Node3D = particles.smoke_01()
			add_child(smoke)
			smoke.position = centers["thrust"]
	
	apply_central_force(Vector3.DOWN * 9.80665 * mass)
	
	_apply_aero_forces()
	
	if target:
		dist = global_transform.origin.distance_to(target.global_transform.origin)
		if dist <= proximity_detonation_radius and properties["has_warhead"]:
			_explode_and_remove()
			return
	
	if properties["has_seeker"] and target and dist < max_range:
		var angles: Vector2 = _get_target_angles(target)
		if angles != Vector2.ZERO:
			match seeker_type:
				Seeker.IR:
					_ir_guidance(angles)
				Seeker.LASER:
					_laser_guidance()
				Seeker.RADAR:
					_radar_guidance(angles)
	
	if not tracking and seeker_type != Seeker.LASER:
		unlocked_life += p_delta
	if unlocked_life >= unlocked_detonation_delay or global_transform.origin.y < -10.0:
		_explode_and_remove()

func get_roll_y_forward() -> float:
	var b = p_trans.basis
	var f = b.y.normalized()
	var r = f.cross(Vector3.UP).normalized()
	var u = r.cross(f).normalized()
	var q = b.orthonormalized().get_rotation_quaternion()
	var q0 = Basis(r, f, u).orthonormalized().get_rotation_quaternion()
	var delta = q0.inverse()*q.normalized()
	var angle = 2.0 * acos(clamp(delta.w, -1.0, 1.0))
	var axis = delta.get_axis()
	var unstable = angle if axis.dot(f) < 0.0 else -angle
	var stable = fmod(unstable + PI, 2.0 * PI) - PI
	return stable

func _apply_aero_forces() -> void:
	if p_speed < 0.001:
		return
	var vel_dir: Vector3 = p_lin_vel.normalized()
	var aoa_axis: Vector3 = p_forward.cross(vel_dir)
	if aoa_axis.length() < 0.00001:
		return
	var ang: float = p_forward.angle_to(vel_dir)
	var aoa_hat: Vector3 = aoa_axis.normalized()
	var lift_axis: Vector3 = vel_dir.cross(aoa_hat).normalized()
	var lift: Vector3 = lift_axis * p_dynq * properties["total_lift"] * AERO_A * ang
	var error: Vector3 = p_error * p_speed
	apply_force(lift + error, centers["pressure"])
	var aero_tq: Vector3 = -aoa_hat * ang * p_dynq * properties["total_lift"] * AERO_B
	
	var roll = get_roll_y_forward()
	var roll_summed = fdbk0.update_sum(roll, 16)
	var roll_smooth = fdbk0.update_d(p_delta, roll_summed) * 0.001
	var rollerons = (roll - roll_smooth) * p_dynq * p_trans.basis.y.normalized()
	
	apply_torque((aero_tq + rollerons))

func _ir_guidance(angles: Vector2) -> void:
	var ptz = p_trans.basis.z.normalized()
	var ptx = p_trans.basis.x.normalized()
	var yaw_tq: float = -pidx0.update(p_delta, 0.0, -angles.x, YAW_KP, YAW_KI, YAW_KD)
	var pitch_tq: float = -pidy0.update(p_delta, 0.0, angles.y, PITCH_KP, PITCH_KI, PITCH_KD)
	var torque: Vector3 = ptz * yaw_tq + ptx * pitch_tq
	apply_torque(torque * p_dynq)

func _laser_guidance() -> void:
	if not player:
		return
	if p_speed > 15.0:
		var beam_origin: Vector3 = player.global_transform.origin
		var beam_dir: Vector3 = -player.global_transform.basis.z.normalized()
		var rel: Vector3 = p_trans.origin - beam_origin
		var rd: float = max(beam_dir.dot(rel), 10.0)
		var bp: Vector3 = beam_origin + beam_dir * rd
		var obp: Vector3 = bp + beam_dir * min(p_speed, 343.0)
		var st: Vector3 = adv_move.torque_to_pos(p_delta, self, Vector3.UP, obp)
		apply_torque(st * p_dynq)

const PN_N:     float = 10.0
const PN_SCALE: float = 0.95
const PN_DAMP:  float = 0.01
func _radar_guidance(angles: Vector2) -> void:
	if radar_first or not tracking:
		radar_first = false
		prev_rel_ang = angles
		prev_range   = dist
		return

	# 1) LOS rate and closing speed
	var los_rate = (angles - prev_rel_ang) / p_delta
	prev_rel_ang = angles

	var closing_v = -(dist - prev_range) / p_delta
	prev_range = dist
	if closing_v < 0.1:
		return

	# 2) optional damping
	var sm_x = los_rate.x - (fdbk1x.update_d(p_delta, los_rate.x) * PN_DAMP)
	var sm_y = los_rate.y - (fdbk1y.update_d(p_delta, los_rate.y) * PN_DAMP)

	# 3) raw errors around local up (z) and local right (x)
	var raw_yaw   = sm_x - p_ang_vel.z    # yaw‐rate is now .z
	var raw_pitch = sm_y - p_ang_vel.x

	# 4) scale error
	var yaw_err   = raw_yaw   * PN_SCALE
	var pitch_err = raw_pitch * PN_SCALE

	# 5) compute torque magnitudes
	var yaw_tq   = PN_N * closing_v * yaw_err   * dist/10.0
	var pitch_tq = PN_N * closing_v * pitch_err * dist/10.0

	# 6) apply about local up (basis.z) and local right (basis.x):
	# yaw torque float inverted to corret for backwards something-or-other
	var torque = p_trans.basis.z * -yaw_tq + p_trans.basis.x * pitch_tq
	# p_dynq = 0.5 * air_density(1.225) * speed**2(speed squard)
	print("yaw_force:", -yaw_tq, " pitch_force:", pitch_tq)
	apply_torque(torque * p_dynq)

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

func _explode_and_remove() -> void:
	var kaboom = particles.explotion_01()
	get_tree().current_scene.get_node(".").add_child(kaboom)
	kaboom.global_position = p_trans.origin
	for block in blocks:
		block.hide()
	await get_tree().create_timer(0.05).timeout
	queue_free()

func _get_target_angles(target_node: Node3D) -> Vector2:
	var targ_pos: Vector3 = target_node.global_position + ((p_error/100.0) * dist)
	var dir: Vector3 = (targ_pos - p_trans.origin).normalized()
	var fwd: Vector3 = p_forward.normalized()
	var right: Vector3 = p_trans.basis.x.normalized()
	var up: Vector3 = p_trans.basis.z.normalized()
	
	var yaw: float = atan2(dir.dot(right), dir.dot(fwd))
	var pitch: float = atan2(dir.dot(up), dir.dot(fwd))
	
	if abs(rad_to_deg(yaw)) > seeker_fov or abs(rad_to_deg(pitch)) > seeker_fov:
		tracking = false
		return Vector2.ZERO
	else:
		tracking = true
	return Vector2(yaw, pitch)
