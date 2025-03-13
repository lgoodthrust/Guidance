extends Node3D

@export var intersection_distance: float = 3000.0  # Distance in front of leader node


var launcher: Node # FOR DATA SHARE
var leader_node: Node3D  # The node to follow
var loader_saver

var list_o_msls:Array = []

func _ready():
	launcher = get_tree().root.get_node("Launcher") # FOR DATA SHARE
	leader_node = get_player()
	
	loader_saver = Loader_Saver.new(self, {}, 1.0)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("key_mouse_left"):
		spawn_missile()


func _physics_process(_delta: float) -> void:
	look_dir(self, Vector3.UP)


func look_dir(node, look_vec):
	if not leader_node:
		return
	
	# Get leader node's forward direction (-Z in Godot)
	var leader_forward = -leader_node.global_transform.basis.z
	
	# Compute the intersection point 1000m ahead in leader's forward direction
	var target_position = leader_node.global_transform.origin + leader_forward * intersection_distance
	
	# Rotate this node to face the target position
	node.look_at(target_position, look_vec)


func get_player() -> Node:
	var node = LAUCNHER_CHILD_SHARE_GET("scenes", "player")
	if node == InstancePlaceholder:
		return
	else:
		var cam:Camera3D = node.get_node("Player_Camera")
		node = cam
	return node


func spawn_missile():
	var path = LAUCNHER_CHILD_SHARE_GET("main_menu", "FILE_PATH") # get save file path
	var missile_instance: Node3D = loader_saver.load_assembly(path + ".tscn")
	var missile_script = load("res://scripts/active_missile_main.gd")
	
	var world_root = get_tree().current_scene.get_node(".")
	
	var msl_rigid = missile_instance.get_children()[0]
	msl_rigid.set_script(missile_script)
	missile_instance.name = "Active_Missile"
	
	# Add to scene
	world_root.add_child(missile_instance)
	missile_instance.owner = world_root
	
	missile_instance.global_position = global_position
	look_dir(missile_instance, Vector3.UP)
	missile_instance.rotate_object_local(Vector3.LEFT, PI/2)
	list_o_msls.push_front(missile_instance)
	LAUCNHER_CHILD_SHARE_SET("world", "missiles", list_o_msls)


func LAUCNHER_CHILD_SHARE_SET(scene, key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data

func LAUCNHER_CHILD_SHARE_GET(scene, key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key]
		return data
