extends RigidBody3D  # Vector up = missile forward

@export_subgroup("Main")
@export var thrust_force: float = 100.0
@export var min_effective_speed: float = 75.0
@export var lifetime: float = 15.0
@export var max_range = 3500.0
@export var seeker_fov = 30.0
@export var unlocked_detonation_delay = 1.5
@export var motor_delay = 0.35
@export var fuel_block_duration = 2.5
@export var launch_charge_force = 10.0
@export var proximity_detonation_radius = 10.0

var launcher
var blocks = []
var life := 0.0
var target_distance = 0.0
var unlocked_life = 0.0
var smoking = false


var cur_accel: Vector3 = Vector3.ZERO
var vel =  Vector3.ZERO
var vel_forward =  Vector3.ZERO
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

@onready var pidx = PID.new()
@onready var pidy = PID.new()

@export var YAW_KP: float = 0.03
@export var YAW_KD: float = 0.5
@export var PITCH_KP: float = 0.03
@export var PITCH_KD: float = 0.5

func _ready() -> void:
	freeze = false
	gravity_scale = 0.0       # We'll apply gravity manually
	linear_damp = 0.0
	angular_damp = 3.0        # Helps reduce oscillations
	mass = 1.0                # We'll set this once we parse blocks

	load_missile_blocks()
	calculate_centers()

	mass = max(1.0, properties["mass"])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centers["mass"]

	# Small initial impulse along local Y
	apply_central_impulse(basis.y * launch_charge_force * mass)

func _physics_process(delta: float) -> void:
	life += delta

	# Remove after lifetime
	if life >= lifetime:
		remove()
		return

	# Thrust if there's still fuel
	if properties["has_motor"] and life > motor_delay and life < properties["fuel"]:
		apply_central_force(basis.y * thrust_force * mass)
		if not smoking:
			smoking = true
			# If you have a smoke particle, attach it here

	# Gravity
	apply_central_force(basis.y * 9.81 * mass)

	# If there's a seeker, do a very simple guidance
	if properties["has_seeker"]:
		var target = get_tree().current_scene.get_node_or_null("World/Active_Target")
		if target:
			var dist = global_transform.origin.distance_to(target.global_transform.origin)

			# Proximity detonation
			if dist <= proximity_detonation_radius and properties["has_warhead"]:
				explode_and_remove()
				return

			# If target is in range, attempt a simple PD-based steering
			if dist < max_range:
				var angles = _get_target_angles(target)
				if angles != Vector2.ZERO:
					var out = _pid_steering(angles, delta)
					_apply_pitch_yaw_torque(out)

func remove() -> void:
	queue_free()

func explode_and_remove():
	# You could instance explosion VFX here if desired
	remove()

# ----------------------------------
#   Parse child blocks to find mass, motor, etc.
# ----------------------------------
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

# ----------------------------------
#   VERY Simple PID Steering
# ----------------------------------
func _get_target_angles(target: Node3D) -> Vector2:
	# missile forward (local y)
	var forward = basis.y
	var to_target = (target.global_transform.origin - global_transform.origin).normalized()

	# Yaw: angle around missile "up" axis
	var right_dir = -global_transform.basis.x
	var yaw_angle = atan2(to_target.dot(right_dir), to_target.dot(forward))

	# Pitch: angle around missile "right" axis
	var up_dir = global_transform.basis.z
	var pitch_angle = atan2(to_target.dot(up_dir), to_target.dot(forward))

	var limit = deg_to_rad(seeker_fov)
	if abs(yaw_angle) > limit or abs(pitch_angle) > limit:
		return Vector2.ZERO

	return Vector2(yaw_angle, pitch_angle)

func _pid_steering(angles: Vector2, delta: float) -> Vector2:
	# angles.x => yaw, angles.y => pitch
	var yaw_cmd   = pidx.update(delta, 0.0, angles.x, YAW_KP, 0.0, YAW_KD)
	var pitch_cmd = pidy.update(delta, 0.0, angles.y, PITCH_KP, 0.0, PITCH_KD)

	var limit = deg_to_rad(seeker_fov)
	yaw_cmd   = clamp(yaw_cmd,   -limit, limit)
	pitch_cmd = clamp(pitch_cmd, -limit, limit)

	return Vector2(yaw_cmd, pitch_cmd)

func _apply_pitch_yaw_torque(cmd: Vector2) -> void:
	var yaw_rad   = cmd.x
	var pitch_rad = cmd.y

	var right = global_transform.basis.x
	var up = global_transform.basis.z

	var pitch_torque = right * pitch_rad
	var yaw_torque   = up    * yaw_rad

	var speed_sq = max(linear_velocity.length_squared(), 1.0)
	speed_sq = clamp(speed_sq, 0.0, 10000.0)

	apply_torque((pitch_torque + yaw_torque) * speed_sq)
