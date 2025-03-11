extends RigidBody3D  # Vector up = missile forward

@export var thrust_force: float = 10000.0
@export var min_speed: float = 50.0
@export var lifetime: float = 10.0
@export var max_range = 3000.0

var launcher
var blocks = []
var life := 0.0

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
	launcher = get_parent().get_parent()
	load_missile_blocks()
	calculate_centers()
	
	# Minimal physics setup
	freeze = false
	gravity_scale = 0.0
	linear_damp = 0.0
	angular_damp = 2.0
	mass = max(1.0, properties["mass"])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centers["mass"]
	
	apply_impulse(global_transform.basis.y.normalized() * 100.0)

func load_missile_blocks() -> void:
	for child in get_children():
		if child.get_class() == "Node3D" and child.DATA.has("NAME"):
			blocks.append(child)

func calculate_centers() -> void:
	var total_mass = 0.0
	var lift_blocks = 0
	var thrust_blocks = 0
	
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
	
	properties["mass"] = total_mass
	
	# Average out centers if needed
	if total_mass > 0:
		centers["mass"] /= total_mass
	if lift_blocks > 0:
		centers["pressure"] /= lift_blocks
	if thrust_blocks > 0:
		centers["thrust"] /= thrust_blocks

func _physics_process(delta: float) -> void:
	life += delta
	
	if life >= lifetime:
		var missile_list = launcher.LAUCNHER_CHILD_SHARED_DATA["world"]["missiles"]
		if missile_list:
			missile_list.pop_back()
			launcher.LAUCNHER_CHILD_SHARED_DATA["world"]["missiles"] = missile_list
		queue_free()
	
	var forward_dir = global_transform.basis.y.normalized()
	
	if properties["fuel"] > life:
		apply_force(forward_dir * thrust_force, centers["thrust"])
	apply_central_force(Vector3.DOWN * 9.81 * properties["mass"])
	
	if linear_velocity.length() > min_speed:
		var inv_vel_dir = linear_velocity.normalized()
		var inv_axis = inv_vel_dir.cross(forward_dir)
		var inv_angle = inv_vel_dir.angle_to(forward_dir)
		if inv_axis.length() > 0.001 and inv_angle > 0.001:
			inv_axis = inv_axis.normalized()
			var inv_torque = inv_axis * inv_angle
			apply_torque(inv_torque * linear_velocity.length_squared())
		
		var vel_dir = linear_velocity.normalized()
		var axis = forward_dir.cross(vel_dir)
		var angle = forward_dir.angle_to(vel_dir)
		if axis.length() > 0.001 and angle > 0.001:
			axis = axis.normalized()
			var torque = axis * angle
			apply_torque(torque * linear_velocity.length_squared())
			aim_and_torque_at_target()

func aim_and_torque_at_target():
	var target = get_tree().current_scene.get_node_or_null("World/Active_Target")
	if not target:
		return
	
	var target_distance = global_transform.origin.distance_to(target.global_transform.origin)
	
	if target_distance < max_range and properties.has_ir_seeker:
		var forward_dir = global_transform.basis.y
		var to_target = (target.global_transform.origin - global_transform.origin).normalized()
		var rotation_axis = forward_dir.cross(to_target)
		var angle = forward_dir.angle_to(to_target)
		var point_2_target_torque = rotation_axis * angle
		apply_torque(point_2_target_torque * linear_velocity.length_squared())
