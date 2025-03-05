extends Window

@export_subgroup("KEY BINDS")
@export var KEY_ESCAPE := "key_esc"

@export_subgroup("PARAMETERS")
@export var Target_Speed: float = 25.0
@export var Target_Altitude: float = 50.0
@export var Target_Distance: float = 100.0
@export var Build_Filename: String = "TEST"


@onready var Input_Target_Speed = $Control/V_Container_Tester/Label_Target_Speed
@onready var Input_Target_Altitude = $Control/V_Container_Tester/Label_Target_Altitude
@onready var Input_Target_Distance = $Control/V_Container_Tester/Label_Target_Distance

@onready var Input_Build_Filename = $Control/V_Container_Builder/Line_Build_Filename

@onready var Input_Switch_to_Builder = $Control/Misc/Button_Builder
@onready var Input_Switch_to_Tester = $Control/Misc/Button_Tester


var active = false
var launcher = Node # FOR DATA SHARE
var build_file_path: String = "res://game_data/assemblies/"


func _init() -> void:
	pass


func _ready() -> void:
	launcher = get_node(".").get_parent() # FOR DATA SHARE
	hide()
	Input_Build_Filename.text = Build_Filename
	update_build_file(Input_Build_Filename.text)
	
	switch_to_tester()


func _process(_delta) -> void:
	if Input.is_action_just_released(KEY_ESCAPE):
		toggler()


func toggler(): # release mouse when menu active
	active = !active
	
	if active:
		show()
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	else:
		hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func update_build_file(filename: String):
	var full_filename = str(build_file_path + filename)
	LAUCNHER_CHILD_SHARE_SET("main_menu", [full_filename])


func switch_to_tester():
	for scene: Node in LAUCNHER_CHILD_SHARE_GET("scenes"):
		if scene.name == "Builder":
			var cam:Camera3D = scene.get_node("Builder_Camera")
			cam.current = false
			scene.hide()
			scene.process_mode = Node.PROCESS_MODE_DISABLED
	
		if scene.name == "World":
			scene.show()
			scene.process_mode = Node.PROCESS_MODE_INHERIT
	
	for scene: Node in LAUCNHER_CHILD_SHARE_GET("scenes"):
		if scene.name == "Player":
			var cam:Camera3D = scene.get_node("Player_Camera")
			cam.current = true
			scene.show()
			scene.process_mode = Node.PROCESS_MODE_INHERIT
			

func switch_to_builder():
	for scene: Node in LAUCNHER_CHILD_SHARE_GET("scenes"):
		if scene.name == "Player":
			var cam:Camera3D = scene.get_node("Player_Camera")
			cam.current = false
			scene.hide()
			scene.process_mode = Node.PROCESS_MODE_DISABLED
	
		if scene.name == "World":
			scene.hide()
			scene.process_mode = Node.PROCESS_MODE_DISABLED
	
	for scene: Node in LAUCNHER_CHILD_SHARE_GET("scenes"):
		if scene.name == "Builder":
			var cam:Camera3D = scene.get_node("Builder_Camera")
			cam.current = true
			scene.show()
			scene.process_mode = Node.PROCESS_MODE_INHERIT


func LAUCNHER_CHILD_SHARE_SET(key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[key] = [data]
		launcher.LAUCNHER_CHILD_SHARED_DATA_CALL()


func LAUCNHER_CHILD_SHARE_GET(key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[key]
		return data
