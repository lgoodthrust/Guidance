extends Node3D

@export var intersection_distance: float = 3000.0  # Distance in front of leader node

var launcher: Node  # FOR DATA SHARE
var leader_node: Node3D  # The node to follow
var loader_saver: Loader_Saver

var list_o_msls: Array = []

func _ready():
	launcher = get_tree().root.get_node("Launcher")  # FOR DATA SHARE
	leader_node = get_player()
	
	loader_saver = Loader_Saver.new(
		self,
		{},
		1.0,
		LAUCNHER_CHILD_SHARE_GET("file_dirs", "assemblies_path")
	)

func _process(_delta: float) -> void:
	# Check shared "world/active_builder" flag instead of local variable
	var is_builder_mode = LAUCNHER_CHILD_SHARE_GET("world", "active_builder")
	# Only spawn when not in builder mode and main menu is inactive
	if Input.is_action_just_pressed("key_mouse_left") and not is_builder_mode:
		if LAUCNHER_CHILD_SHARE_GET("main_menu", "active") == false:
			spawn_missile()

func _physics_process(_delta: float) -> void:
	look_dir(self, Vector3.UP)

func look_dir(node, look_vec):
	if not leader_node:
		return
	
	var leader_forward = -leader_node.global_transform.basis.z
	var target_position = leader_node.global_transform.origin + leader_forward * intersection_distance
	node.look_at(target_position, look_vec)

func get_player() -> Node3D:
	var node = LAUCNHER_CHILD_SHARE_GET("scenes", "player")
	if node == InstancePlaceholder:
		return null
	else:
		var cam: Camera3D = node.get_node("Player_Camera")
		return cam

func spawn_missile():
	var dest = LAUCNHER_CHILD_SHARE_GET("main_menu", "FILE_NAME")
	var missile_instance: Node3D = loader_saver.load_assembly(dest)
	var missile_script = load("res://scripts/active_missile_main.gd")
	
	var world_root = get_tree().current_scene.get_node(".")
	
	# Assume the first child is the rigid body
	var msl_rigid = missile_instance.get_children()[0]
	msl_rigid.set_script(missile_script)
	missile_instance.name = "Active_Missile"
	
	world_root.add_child(missile_instance)
	missile_instance.owner = world_root
	
	missile_instance.global_position = global_position
	look_dir(missile_instance, Vector3.UP)
	missile_instance.rotate_object_local(Vector3.LEFT, PI / 2)
	
	# Track active missiles in shared data
	list_o_msls.push_front(missile_instance)
	LAUCNHER_CHILD_SHARE_SET("world", "missiles", list_o_msls)

func LAUCNHER_CHILD_SHARE_SET(scene, key, data):  # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data

func LAUCNHER_CHILD_SHARE_GET(scene, key):  # FOR DATA SHARE
	if launcher:
		return launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key]
	return null
