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
@onready var rng: RandomNumberGenerator = RandomNumberGenerator.new()


const AIR_DENSITY: float = 1.225
const DRAG_CO_A: float = 0.1
const DRAG_CO_B: float = 0.1

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
		match seeker_type:
			Seeker.IR:
				_ir_guidance()
			Seeker.LASER:
				_laser_guidance()
			Seeker.RADAR:
				_radar_guidance()
	
	if not tracking and seeker_type != Seeker.LASER:
		unlocked_life += p_delta
	if unlocked_life >= unlocked_detonation_delay or global_transform.origin.y < -10.0:
		_explode_and_remove()

func get_roll_ang() -> float:
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
	unstable = sin(unstable)
	var stable = fmod(unstable + PI, 2.0 * PI) - PI
	return stable

func _apply_aero_forces() -> void:
	if p_lin_vel.length() < 0.1:
		return

	# Direction of motion and forward vector
	var vel_dir: Vector3 = p_lin_vel.normalized()
	var forward: Vector3 = p_forward.normalized()

	# Angle of attack (alpha) between forward and velocity
	var alpha: float = forward.angle_to(vel_dir)
	if alpha < 0.001:
		# Almost no angle of attack => negligible lift
		return

	# Axis perpendicular to both forward and velocity (roll axis)
	var aoas_axis: Vector3 = forward.cross(vel_dir)
	
	if aoas_axis.length() < 0.0001:
		return
	
	aoas_axis = aoas_axis.normalized()

	# Lift direction: perpendicular to both velocity and aoa_axis
	var lift_dir: Vector3 = vel_dir.cross(aoas_axis).normalized()

	# Dynamic pressure q = 0.5 * rho * v^2 is precomputed in p_dynq
	var lift_mag: float = p_dynq * alpha * properties["total_lift"]
	var lift: Vector3 = lift_dir * lift_mag

	# Apply lift at aerodynamic center
	apply_force(lift, centers["pressure"])

	# Simple drag: D = q * Cd * S
	var Cd0: float = DRAG_CO_A
	var Cd02: float = DRAG_CO_B
	var drag_mag: float = p_dynq * (Cd0 + Cd02) * (alpha**2) * properties["total_lift"]
	var drag: Vector3 = -vel_dir * drag_mag
	apply_force(drag, centers["pressure"])

	# Aerodynamic pitching moment (optional)
	var pitch_moment: float = p_dynq * alpha * properties["total_lift"]
	apply_torque(aoas_axis * pitch_moment)

	# Roll damping: oppose roll rate around longitudinal axis
	var roll_rate: float = p_ang_vel.dot(forward)
	var roll_damp_torque: Vector3 = -forward * (roll_rate * 0.25)
	apply_torque(roll_damp_torque)

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
	var yaw_tq: float = -pidx0.update(p_delta, 0.0, -angs.x, 1.5, 15, 0.3)
	var pitch_tq: float = -pidy0.update(p_delta, 0.0, angs.y, 1.5, 15, 0.3)
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

const KP =  1.0
const KD =  1.0
const PNAV = 3.0
const TORQUE_LIMIT = 300
func _radar_guidance() -> void:
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
	
	# 2) PN guidance on those noisy angles
	var los_rate = (angs - prev_rel_ang) / p_delta
	prev_rel_ang = angs
	var closing_v = -(dist - prev_range) / p_delta
	prev_range = dist
	if closing_v < 1e-3:
		return
	
	# 3) Pure PN lateral accel
	var a_lat = PNAV * closing_v * los_rate
	var yaw_ff = clamp(a_lat.x * dist, -TORQUE_LIMIT, TORQUE_LIMIT)
	var pitch_ff = clamp(a_lat.y * dist, -TORQUE_LIMIT, TORQUE_LIMIT)
	
	# 4) Light PD to absorb jitter
	var rate_err = los_rate - Vector2(p_ang_vel.z, p_ang_vel.x)
	var yaw_pd = (KP * angs.x) - (KD * rate_err.x)
	var pitch_pd = (KP * angs.y) - (KD * rate_err.y)
	
	var yaw_cmd = clamp(yaw_ff + yaw_pd, -TORQUE_LIMIT, TORQUE_LIMIT)
	var pitch_cmd = clamp(pitch_ff + pitch_pd, -TORQUE_LIMIT, TORQUE_LIMIT)
	
	var torque = p_trans.basis.z * -yaw_cmd + p_trans.basis.x * pitch_cmd
	apply_torque(torque * p_speed)

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
