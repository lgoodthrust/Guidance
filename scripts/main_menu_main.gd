extends Window

@export_subgroup("KEY BINDS")
@export var KEY_ESCAPE := "key_esc"

@export_subgroup("PARAMETERS")
@export var Target_Speed: float = 25.0
@export var Target_Altitude: float = 50.0
@export var Target_Distance: float = 100.0
@export var Build_Filename: String = "TEST"

@onready var Input_Target_Speed: LineEdit = $Control/V_Container_Tester/Line_Target_Speed
@onready var Input_Target_Altitude: LineEdit = $Control/V_Container_Tester/Line_Target_Altitude
@onready var Input_Target_Distance: LineEdit = $Control/V_Container_Tester/Line_Target_Distance
@onready var Input_Target_Button_Apply: Button = $Control/V_Container_Tester/Button_Target_Apply

@onready var Input_Build_Filename: LineEdit = $Control/V_Container_Builder/Line_Build_Filename

@onready var Input_Switch_to_Builder: Button = $Control/Misc/Button_Builder
@onready var Input_Switch_to_Tester: Button = $Control/Misc/Button_Tester

@onready var Input_Volume_Slider: HSlider = $Control/V_Container_Game/Slider_Game_Volume

var active = false
enum Mode {build, test}
var cur_mode = Mode.test
var launcher # FOR DATA SHARE
var active_target_node: Node3D

func _ready() -> void:
	launcher = self.get_parent() # FOR DATA SHARE
	active_target_node = LAUCNHER_CHILD_SHARE_GET("scenes", "target")
	hide()
	Input_Build_Filename.text = Build_Filename
	update_build_file(Input_Build_Filename.text)
	switch_to_tester()
	
	LAUCNHER_CHILD_SHARE_SET("main_menu", "active", false)
	
	Input_Volume_Slider.value = 80.0
	update_volume(Input_Volume_Slider.value)

var pressing: bool = false
func _process(_delta) -> void:
	if Input.is_action_just_released(KEY_ESCAPE):
		toggler()
	
	if Input_Target_Button_Apply.button_pressed and not pressing:
		update_target()
		pressing = true
	elif not Input_Target_Button_Apply.button_pressed and pressing :
		pressing = false
	
	if Input_Volume_Slider.drag_ended:
		update_volume(Input_Volume_Slider.value)

func update_volume(volume: float) -> void:
	var val = lerp(-60, 0, volume/100.0)
	AudioServer.set_bus_volume_db(0, val)

func update_target():
	var dist = float(Input_Target_Distance.text)
	var alt = float(Input_Target_Altitude.text)
	var speed = float(Input_Target_Speed.text)
	
	print(dist, alt)
	
	active_target_node.forward_velocity = speed
	active_target_node.curr_pos = Vector3(0, alt, -dist)
	active_target_node.global_position = Vector3(0, alt, -dist)

func toggler():
	active = !active
	
	if active:
		show()
		LAUCNHER_CHILD_SHARE_SET("main_menu", "active", true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var scene1 = LAUCNHER_CHILD_SHARE_GET("scenes", "world")
		if scene1 == InstancePlaceholder:
			return
		scene1.process_mode = Node.PROCESS_MODE_INHERIT
		
		var scene2 = LAUCNHER_CHILD_SHARE_GET("scenes", "player")
		if scene2 == InstancePlaceholder:
			return
		else:
			scene2.noclip_tog = true
	else:
		hide()
		LAUCNHER_CHILD_SHARE_SET("main_menu", "active", false)
		if cur_mode == Mode.build:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif cur_mode == Mode.test:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var scene2 = LAUCNHER_CHILD_SHARE_GET("scenes", "world")
		if scene2 == InstancePlaceholder:
			return
		scene2.process_mode = Node.PROCESS_MODE_INHERIT

func update_build_file(filename: String):
	var full_filename = filename
	LAUCNHER_CHILD_SHARE_SET("main_menu", "FILE_PATH", full_filename)

func switch_to_tester():
	cur_mode = Mode.test
	var scene1 = LAUCNHER_CHILD_SHARE_GET("scenes", "builder")
	if scene1 == InstancePlaceholder:
		return
	var cam1:Camera3D = scene1.get_node("Builder_Camera")
	cam1.current = false
	var cam1_gui = cam1.get_node("GUI")
	cam1_gui.hide()
	scene1.hide()
	scene1.process_mode = Node.PROCESS_MODE_DISABLED
	
	var scene2 = LAUCNHER_CHILD_SHARE_GET("scenes", "world")
	if scene2 == InstancePlaceholder:
		return
	scene2.show()
	LAUCNHER_CHILD_SHARE_GET("world", "SPAWNER").active_builder = false
	
	var scene4 = active_target_node
	if scene4 == InstancePlaceholder:
		return
	scene4.process_mode = Node.PROCESS_MODE_INHERIT
	scene2.process_mode = Node.PROCESS_MODE_INHERIT
	
	var scene3 = LAUCNHER_CHILD_SHARE_GET("scenes", "player")
	if scene3 == InstancePlaceholder:
		return
	var hud:Control = scene3.get_node("Player_Camera/Player_Camera_GUI")
	hud.buildering = false
	hud.queue_redraw()
	scene3.show()
	scene3.process_mode = Node.PROCESS_MODE_INHERIT

func switch_to_builder():
	cur_mode = Mode.build
	var scene1:Node3D = LAUCNHER_CHILD_SHARE_GET("scenes", "player")
	if scene1 == InstancePlaceholder:
		return
	var hud:Control = scene1.get_node("Player_Camera/Player_Camera_GUI")
	hud.buildering = true
	hud.queue_redraw()
	scene1.hide()
	scene1.process_mode = Node.PROCESS_MODE_DISABLED
	
	var scene2 = LAUCNHER_CHILD_SHARE_GET("scenes", "world")
	if scene2 == InstancePlaceholder:
		return
	scene2.hide()
	LAUCNHER_CHILD_SHARE_GET("world", "SPAWNER").active_builder = true
	
	var scene4 = active_target_node
	if scene4 == InstancePlaceholder:
		return
	scene4.process_mode = Node.PROCESS_MODE_DISABLED
	scene2.process_mode = Node.PROCESS_MODE_DISABLED
	
	var scene3 = LAUCNHER_CHILD_SHARE_GET("scenes", "builder")
	if scene3 == InstancePlaceholder:
		return
	var cam2:Camera3D = scene3.get_node("Builder_Camera")
	cam2.current = true
	var cam2_gui = cam2.get_node("GUI")
	cam2_gui.show()
	scene3.show()
	scene3.process_mode = Node.PROCESS_MODE_INHERIT

func LAUCNHER_CHILD_SHARE_SET(scene, key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data

func LAUCNHER_CHILD_SHARE_GET(scene, key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key]
		return data
