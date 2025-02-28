extends Control

@export var terrain_scene: PackedScene
@export var player_scene: PackedScene
@export var main_menu_scene: PackedScene
@export var builder_scene: PackedScene

var terrain_instance: Node3D
var player_instance: CharacterBody3D
var main_menu_instance: Window
var builder_instance: Node3D
var LAUCNHER_CHILD_SHARED_DATA = {"player":[], "world":[], "main_menu":[], "builder":[]} # Variable to store data from Scene A


func _init() -> void:
	pass


func _ready() -> void:
	pass


func _process(_delta) -> void:
	pass


func load_terrain():
	if terrain_scene:
		terrain_instance = terrain_scene.instantiate()
		add_child(terrain_instance)
		terrain_instance.global_position = Vector3(0, 0, 0)
		print("World loaded successfully!")
	else:
		print("Error: World scene not assigned!")

func load_Builder():
	if builder_scene:
		builder_instance = builder_scene.instantiate()
		add_child(builder_instance)
		builder_instance.global_position = Vector3(0, 1, 0)
		print("Builder loaded successfully!")
	else:
		print("Error: World scene not assigned!")

func load_player():
	if player_scene:
		player_instance = player_scene.instantiate()
		add_child(player_instance)
		player_instance.global_position = Vector3(10, 2, 0)
		print("Player loaded successfully!")
	else:
		print("Error: Player scene not assigned!")


func load_main_menu():
	if player_scene:
		main_menu_instance = main_menu_scene.instantiate()
		add_child(main_menu_instance)
		print("Main Menu loaded successfully!")
	else:
		print("Error: Main Menu scene not assigned!")

func _on_window_close_requested() -> void:
	load_player()
	load_terrain()
	load_main_menu()


func LAUCNHER_CHILD_SHARED_DATA_CALL():
	#LAUCNHER_CHILD_SHARED_DATA
	pass
