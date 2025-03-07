extends Node3D

@export var intersection_distance: float = 1000.0  # Distance in front of leader node



var launcher: Node # FOR DATA SHARE
var leader_node: Node3D  # The node to follow
var loader_saver


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
	var node: Node
	for scene: Node in LAUCNHER_CHILD_SHARE_GET("scenes"):
		if scene.name == "Player":
			var cam:Camera3D = scene.get_node("Player_Camera")
			node = cam
	return node


func spawn_missile():
	var path = LAUCNHER_CHILD_SHARE_GET("main_menu")[0][0]["FILE_PATH"] # get save file path
	var missile_instance: Node3D = loader_saver.load_assembly(path)
	var missile_script = load("res://scripts/active_missile_main.gd")
	var seeker_script = load("res://scripts/block_scripts/ir_seeker.gd")
	var seeker = missile_instance.get_node("RigidBody3D/IR_Seeker")
	var papa = get_tree().current_scene.get_node(".")
	
	# Assign scripts
	missile_instance.set_script(missile_script)
	seeker.set_script(seeker_script)

	# Add to scene
	papa.add_child(missile_instance)
	missile_instance.owner = papa
	
	missile_instance.name = "Active_Missile"
	missile_instance.global_position = global_position
	look_dir(missile_instance, Vector3.UP)
	missile_instance.rotate_object_local(Vector3.LEFT, PI/2)



func LAUCNHER_CHILD_SHARE_GET(key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[key]
		return data
