extends Control

@export var terrain_scene: PackedScene  # Assign the terrain scene in the Inspector
@export var player_scene: PackedScene  # Assign the terrain scene in the Inspector
@export var main_menu_scene: PackedScene  # Assign the terrain scene in the Inspector

var terrain_instance: Node3D
var player_instance: CharacterBody3D
var main_menu_instance: Control


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
		terrain_instance.global_position = Vector3(0, 0, 0)  # Position it correctly
		print("Terrain loaded successfully!")
	else:
		print("Error: Terrain scene not assigned!")

func load_player():
	if player_scene:
		player_instance = player_scene.instantiate()
		add_child(player_instance)
		player_instance.global_position = Vector3(0, 100, 0)  # Position it correctly
		print("Player loaded successfully!")
	else:
		print("Error: Terrain scene not assigned!")


func load_main_menu():
	if player_scene:
		main_menu_instance = main_menu_scene.instantiate()
		add_child(main_menu_instance)
		print("Player loaded successfully!")
	else:
		print("Error: Terrain scene not assigned!")


func _on_window_close_requested() -> void:
	load_terrain()
	load_player()
	load_main_menu()
