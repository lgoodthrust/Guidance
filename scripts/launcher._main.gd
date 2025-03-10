extends Control

@export var world_scene: PackedScene
@export var player_scene: PackedScene
@export var main_menu_scene: PackedScene
@export var builder_scene: PackedScene

var world_instance: Node
var player_instance: Node
var main_menu_instance: Node
var builder_instance: Node

var LAUCNHER_CHILD_SHARED_DATA = {
	"scenes":{
		"player":InstancePlaceholder,
		"world":InstancePlaceholder,
		"main_menu":InstancePlaceholder,
		"builder":InstancePlaceholder
		},
	"player":{},
	"world":{},
	"main_menu":{},
	"builder":{}
	}


func _ready() -> void:
	load_player()
	load_world()
	load_Builder()
	load_main_menu()


func _process(_delta) -> void:
	if Input.is_action_just_pressed("key_alt_f4"):
		get_tree().quit()


func load_world():
	if world_scene:
		world_instance = world_scene.instantiate()
		add_child(world_instance)
		LAUCNHER_CHILD_SHARED_DATA["scenes"]["world"] = world_instance
		world_instance.global_position = Vector3(0, 0, 0)
		print("World loaded successfully!")
	else:
		print("Error: World scene not assigned!")


func load_Builder():
	if builder_scene:
		builder_instance = builder_scene.instantiate()
		add_child(builder_instance)
		LAUCNHER_CHILD_SHARED_DATA["scenes"]["builder"] = builder_instance
		builder_instance.global_position = Vector3(0, 0, 0)
		print("Builder loaded successfully!")
	else:
		print("Error: Builder scene not assigned!")


func load_player():
	if player_scene:
		player_instance = player_scene.instantiate()
		add_child(player_instance)
		LAUCNHER_CHILD_SHARED_DATA["scenes"]["player"] = player_instance
		player_instance.global_position = Vector3(0, 3, 10)
		print("Player loaded successfully!")
	else:
		print("Error: Player scene not assigned!")


func load_main_menu():
	if main_menu_scene:
		main_menu_instance = main_menu_scene.instantiate()
		add_child(main_menu_instance)
		LAUCNHER_CHILD_SHARED_DATA["scenes"]["main_menu"] = main_menu_instance
		print("Main Menu loaded successfully!")
	else:
		print("Error: Main Menu scene not assigned!")
