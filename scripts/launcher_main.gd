extends Control

@export var world_scene: PackedScene
@export var player_scene: PackedScene
@export var main_menu_scene: PackedScene
@export var builder_scene: PackedScene
@export var target_scene: PackedScene

var world_instance: Node
var player_instance: Node
var main_menu_instance: Node
var builder_instance: Node
var target_instance: Node

var LIFE_SUPPORT = preload("res://coconut.png")

var defualt_assembly_json = preload("res://game_data/assemblies/TEST.json")
var defualt_assembly_tscn = preload("res://game_data/assemblies/TEST.tscn")

var LAUCNHER_CHILD_SHARED_DATA = {
	"scenes":{
		"player":InstancePlaceholder,
		"world":InstancePlaceholder,
		"main_menu":InstancePlaceholder,
		"builder":InstancePlaceholder,
		"target":InstancePlaceholder
		},
	"player":{},
	"world":{},
	"main_menu":{
		"active":false
		},
	"builder":{},
	"target":{},
	"file_dirs":{
		"exe_path":"",
		"game_res_path":"",
		"assemblies_path":""
		}
	}

func _ready() -> void:
	
	if not LIFE_SUPPORT.get_size() == Vector2(256, 256):
		return
	setup_dirs()
	load_player()
	load_world()
	load_Builder()
	load_target()
	load_main_menu()

func _process(_delta) -> void:
	if Input.is_action_just_pressed("key_alt_f4"):
		get_tree().quit()

func setup_dirs() -> void:
	var exe_path: String = OS.get_executable_path()
	var exe_dir: String = exe_path.get_base_dir()
	var dir_instance: DirAccess = DirAccess.open(exe_dir)
	var subfolder: String = exe_dir.path_join("game_data/assemblies")
	if not dir_instance.dir_exists(subfolder):
		var err = dir_instance.make_dir_recursive(subfolder)
		if err != OK:
			push_error("Could not create folder: %s (error %d)" % [subfolder, err])
		else:
			print("Created folder at: ", subfolder)
	else:
		print("Folder already exists: ", subfolder)
	
	ResourceSaver.save(defualt_assembly_json, subfolder.path_join("TEST.json"))
	ResourceSaver.save(defualt_assembly_tscn, subfolder.path_join("TEST.tscn"))
	
	LAUCNHER_CHILD_SHARED_DATA["file_dirs"]["assemblies_path"] = subfolder

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

func load_target():
	if target_scene:
		target_instance = target_scene.instantiate()
		add_child(target_instance)
		target_instance.set_owner(self)
		LAUCNHER_CHILD_SHARED_DATA["scenes"]["target"] = target_instance
		target_instance.global_position = Vector3(0, 300, -3000)
		print("Target loaded successfully!")
	else:
		print("Error: Target scene not assigned!")
