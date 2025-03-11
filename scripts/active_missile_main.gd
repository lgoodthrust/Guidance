extends RigidBody3D  # Vector up = missile forward

@export var thrust_force: float = 50.0
@export var min_speed: float = 10.0

var blocks = []

# Required centers dictionary for your unchanged code
var centers = {
	"mass": Vector3.ZERO,
	"pressure": Vector3.ZERO,
	"thrust": Vector3.ZERO
}

# Required properties dictionary for your unchanged code
var properties = {
	"fuel": 0,
	"mass": 0.0,
	"has_ir_seeker": false,
	"total_lift": 0.0
}

func _ready() -> void:
	# Load missile blocks and compute centers/mass
	load_missile_blocks()
	calculate_centers()

	# Minimal physics setup
	freeze = false
	gravity_scale = 0.0
	linear_damp = 0.0
	angular_damp = 0.0
	mass = max(1.0, properties["mass"])

func load_missile_blocks() -> void:
	for child in get_children():
		if child.get_class() == "Node3D" and child.DATA.has("NAME"):
			blocks.append(child)

func calculate_centers() -> void:
	var total_mass = 0.0
	var lift_blocks = 0
	var thrust_blocks = 0
	
	# ───── DO NOT CHANGE THIS BLOCK ─────
	for block:Node3D in blocks:
		var block_pos = block.to_global(Vector3.ZERO)  
		if block.DATA.has("TYPE"):
			if block.DATA["TYPE"] == 1:
				properties["has_ir_seeker"] = true

			if block.DATA["TYPE"] == 4 or block.DATA["TYPE"] == 5 or block.DATA["TYPE"] == 6:
				centers["pressure"] += block_pos
				lift_blocks += 1
				properties["total_lift"] += block.DATA["LIFT"]

			if block.DATA["TYPE"] == 7:
				properties["fuel"] += 1

			if block.DATA["TYPE"] == 8:
				centers["thrust"] += block_pos
				thrust_blocks += 1
		
		if block.DATA.has("MASS"):
			centers["mass"] += block_pos * block.DATA["MASS"]
			total_mass += block.DATA["MASS"]
	# ─────────────────────────────────────
	
	properties["mass"] = total_mass
	
	# Average out centers if needed
	if total_mass > 0:
		centers["mass"] /= total_mass
	if lift_blocks > 0:
		centers["pressure"] /= lift_blocks
	if thrust_blocks > 0:
		centers["thrust"] /= thrust_blocks

func _physics_process(_delta: float) -> void:
	# Simple forward thrust
	var forward_dir = global_transform.basis.y
	apply_force(forward_dir * thrust_force, centers["thrust"])

	# Align the missile to its velocity
	var vel = linear_velocity
	var speed = vel.length()
	if speed > min_speed:
		var vel_dir = vel.normalized()
		var axis = forward_dir.cross(vel_dir)
		var angle = forward_dir.angle_to(vel_dir)
		
		if axis.length() > 0.001 and angle > 0.001:
			axis = axis.normalized()
			# Increase the multiplier if you need stronger torque
			var torque = axis * angle * 1000.0
			apply_torque(torque)
