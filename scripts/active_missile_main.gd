## missile_main.gd -------------------------------------------------
## Complete missile script with fixed guidance, finished SUM usage,
## and a few minor clean‑ups for stability.

extends RigidBody3D

# ─────────────────── Missile parameters ──────────────────────────
@export var thrust_force:                    float = 25.0
@export var lifetime:                        float = 25.0
@export var launch_charge_force:             float = 0.0
@export var motor_delay:                     float = 0.15
@export var fuel_duration:                   float = 1.5
@export var proximity_detonation_radius:     float = 10.0

# ─────────────────── Seeker parameters ───────────────────────────
@export var max_range:                       float = 3500.0
@export var seeker_fov:                      float = 40.0
@export var unlocked_detonation_delay:       float = 1.5

# ─────────────────── Guidance PID gains ──────────────────────────
@export var YAW_KP:                          float = 1.0
@export var YAW_KI:                          float = 1.5
@export var YAW_KD:                          float = 0.75
@export var PITCH_KP:                        float = 1.0
@export var PITCH_KI:                        float = 1.5
@export var PITCH_KD:                        float = 0.75

@export var GAIN_0:                          float = 0.0
@export var GAIN_1:                          float = 1.0
@export var GAIN_2:                          float = 0.0

# ─────────────────── Centres / properties ────────────────────────
var centers := {
	"mass":     Vector3.ZERO,
	"pressure": Vector3.ZERO,
	"thrust":   Vector3.ZERO
}

var properties := {
	"seeker_type":        "",
	"fuel":               0,
	"mass":               0.0,
	"total_lift":         0.0,
	"has_ir_seeker":      false,
	"has_controller":     false,
	"has_warhead":        false,
	"has_front_cannard":  false,
	"has_back_cannard":   false,
	"has_fin":            false,
	"has_motor":          false
}

# ─────────────────── Internal state ──────────────────────────────
var blocks: Array         = []
var life:   float         = 0.0
var unlocked_life: float  = 0.0
var smoking: bool         = false
var dist:    float        = 100.0

var target: Node3D
var target_position: Vector3
var player: Node3D

# ─────────────────── Helper objects ──────────────────────────────
@onready var pidx0    := PID.new()
@onready var pidy0    := PID.new()
@onready var adv_move := ADV_MOVE.new()
@onready var particles:= gpu_particle_effects.new()

@onready var summerx := SUM.new()
@onready var summery := SUM.new()
@onready var summers  := SUM.new()

# ─────────────────── Ready ───────────────────────────────────────
func _ready() -> void:
	target_position = Vector3()
	player          = get_tree().current_scene.get_node_or_null("Player/Player_Camera")
	
	load_missile_blocks()
	calculate_centers()
	
	freeze                = false
	gravity_scale         = 0.0
	linear_damp           = 0.0035
	angular_damp          = 0.125
	mass                  = max(1.0, properties["mass"])
	inertia               = Vector3.ONE * mass
	center_of_mass_mode   = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass        = centers["mass"]
	
	target = get_tree().current_scene.get_node_or_null("World/Active_Target")
	
	# Initial impulse in local –Y (missile forward)
	apply_central_impulse(-global_basis.y * launch_charge_force * mass)

# ─────────────────── Helper: load blocks ─────────────────────────
func load_missile_blocks() -> void:
	for child in get_children():
		if child is Node3D and child.DATA.has("NAME"):
			blocks.append(child)

# ─────────────────── Helper: centres of mass / lift / thrust ────
func calculate_centers() -> void:
	var lift_blocks = 0
	var thrust_blocks = 0
	
	for block:Node3D in blocks:
		var block_pos = block.to_global(Vector3.ZERO)
		if block.DATA.has("TYPE"):
			if block.DATA["TYPE"] == 1:
				properties["has_ir_seeker"] = true
				properties["seeker_type"] = block.DATA["NAME"]
			
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

# ─────────────────── Physics process ─────────────────────────────
var prev_vel: Vector3 = Vector3.ZERO

func _physics_process(delta: float) -> void:
	life += delta
	if life >= lifetime:
		_remove_missile()
		return
	
	#apply_central_force(global_basis.y * thrust_force * mass)
	
	# Thrust
	if properties["has_motor"] and life > motor_delay and life < properties["fuel"]:
		apply_force(global_basis.y * thrust_force * mass, centers["thrust"])
		if not smoking:
			smoking = true
			add_child(particles.smoke_01())
	
	# Basic aero alignment force
	var afd  := (global_basis.y - linear_velocity.normalized()).normalized()
	var afm  := global_basis.y.angle_to(linear_velocity.normalized())
	apply_central_force(afd * afm * 10.0)
	
	# Counteract deceleration from alignment
	var cur_accel = (linear_velocity - prev_vel) / max(delta, 1e-4)
	apply_central_force(-cur_accel * global_basis.y * 1.25)
	
	# Torque missile nose into velocity
	var axis  := global_basis.y.cross(linear_velocity.normalized())
	var angle := global_basis.y.angle_to(linear_velocity.normalized())
	if axis.length() > 0.005 and angle > 0.005:
		apply_torque(axis.normalized() * angle * (linear_velocity.length() / 10.0) * 10.0)
	
	if target:
		dist = global_transform.origin.distance_to(target.global_transform.origin)
	
	if properties["has_ir_seeker"]:
		if dist <= proximity_detonation_radius and properties["has_warhead"]:
			_explode_and_remove()
			return
		
		if dist < max_range:
			var ang := _get_target_angles(target)
			if ang != Vector2.ZERO:
				var cmd := guidance_control_law(ang, delta, properties["seeker_type"])
				_apply_pitch_yaw_torque(cmd)
	
	prev_vel = linear_velocity

# ─────────────────── Remove / explode ────────────────────────────
func _remove_missile() -> void: queue_free()
func _explode_and_remove() -> void: queue_free()  # hook explosion VFX here

# ─────────────────── Angle helper ────────────────────────────────
var _prev_ang: Vector2 = Vector2.ZERO

func _get_target_angles(target_node: Node3D) -> Vector2:
	var forward    := global_basis.y
	var to_target  := (target_node.global_transform.origin - global_transform.origin).normalized()
	var right      := global_basis.x
	var up         := global_basis.z
	
	var yaw_angle   := atan2(to_target.dot(right),  to_target.dot(forward))
	var pitch_angle := atan2(to_target.dot(up),     to_target.dot(forward))
	var ang         := Vector2(yaw_angle, pitch_angle)
	
	var limit := deg_to_rad(seeker_fov)
	if abs(yaw_angle) > limit or abs(pitch_angle) > limit:
		return _prev_ang  # out of FOV – hold last valid lock
	_prev_ang = ang
	return ang

# ─────────────────── Guidance control law ───────────────────────
func guidance_control_law(relative_angles: Vector2, delta: float, kind: String) -> Vector2:
	var xval := 0.0
	var yval := 0.0
	
	match kind:
		"IR_Seeker":
			xval = -relative_angles.x
			yval =  relative_angles.y
		
		"Laser_Seeker":  # beam‑ride SACLOS
			if player:
				var aim_dir := -player.global_basis.z
				target_position = player.global_transform.origin + aim_dir * 10000.0
			var vec := adv_move.force_to_forward(delta, self, Vector3.DOWN, target_position)
			apply_force(vec * linear_velocity * properties["mass"])
		
		"Radar_Seeker":
			var steer := _radar_steering(delta, relative_angles)
			xval = steer.x
			yval = steer.y
	
	# ───── PID correction (now actually used!) ─────
	var yaw_cmd   := pidx0.update(delta, 0.0, xval, YAW_KP, YAW_KI, YAW_KD)
	var pitch_cmd := pidy0.update(delta, 0.0, yval, PITCH_KP, PITCH_KI, PITCH_KD)
	return Vector2(yaw_cmd, pitch_cmd)

# ─────────────────── Radar steering (CB/DR) ─────────────────────
var _prev_angles:      Vector2 = Vector2.ZERO
var _prev_rate_angles: Vector2 = Vector2.ZERO
var _first_sample:     bool    = true

func _radar_steering(delta: float, angles: Vector2) -> Vector2:
	if _first_sample:
		_prev_angles = angles
		_first_sample = false
	
	var rate_angles = -(angles - _prev_angles) / max(delta, 1e-4)
	var jerk_angles = -(rate_angles - _prev_rate_angles) / max(delta, 1e-4)
	
	_prev_angles      = angles
	_prev_rate_angles = rate_angles
	
	var yc0 :=  angles.x * GAIN_0
	var pc0 := -angles.y * GAIN_0
	var yc1 =  rate_angles.x * GAIN_1
	var pc1 = -rate_angles.y * GAIN_1
	var yc2 =  jerk_angles.x * GAIN_2
	var pc2 = -jerk_angles.y * GAIN_2
	
	var Ax = yc0 + yc1 + yc2
	var Ay = pc0 + pc1 + pc2
	
	var outs := summers.update(Vector2(Ax, Ay).length(), 3, 10.0)
	return Vector2(-Ax, Ay) * outs

# ─────────────────── Apply torque ────────────────────────────────
func _apply_pitch_yaw_torque(cmd: Vector2) -> void:
	var right    := global_basis.x
	var up       := global_basis.z
	var forward  := -global_basis.y
	
	var pitch_tq := right * cmd.y
	var yaw_tq   := up    * cmd.x
	var roll_tq  := -forward.cross(right)  # simple roll damping / anti‑roll
	
	var speed = max(linear_velocity.dot(global_basis.y), 1.0)
	apply_torque((pitch_tq + yaw_tq + roll_tq) * speed)
