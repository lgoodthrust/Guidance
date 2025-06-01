extends Window

@export var KEY_ESCAPE := "key_esc"  # Consider using Input.is_action_just_released("ui_cancel") to rely on built-in actions

@export_subgroup("PARAMETERS")
@export var Target_Speed: float = 25.0
@export var Target_Altitude: float = 50.0
@export var Target_Distance: float = 100.0
@export var Build_Filename: String = "TEST"

@onready var Input_Target_Speed: LineEdit = $Control/V_Container_Tester/Line_Target_Speed
@onready var Input_Target_Altitude: LineEdit = $Control/V_Container_Tester/Line_Target_Altitude
@onready var Input_Target_Distance: LineEdit = $Control/V_Container_Tester/Line_Target_Distance
@onready var Input_Target_Apply: Button = $Control/V_Container_Tester/HSeparator4/VBoxContainer/HBoxContainer/Button_Target_Apply
@onready var Input_Targets_ID: SpinBox = $Control/V_Container_Tester/HSeparator4/VBoxContainer/HBoxContainer/ID_Spinbox
@onready var Input_Targets_Add: Button = $Control/V_Container_Tester/HSeparator4/VBoxContainer/Button_Add_Target
@onready var Input_Targets_Remove: Button = $Control/V_Container_Tester/HSeparator4/VBoxContainer/Button_Remove_Target
@onready var Tester_Container: Control = $Control/V_Container_Tester  # Group for showing/hiding tester UI

@onready var Input_Build_Filename: LineEdit = $Control/V_Container_Builder/Line_Build_Filename
@onready var Input_Switch_to_Builder: Button = $Control/Misc/Button_Builder
@onready var Input_Switch_to_Tester: Button = $Control/Misc/Button_Tester
@onready var Input_How_To_Button: Button = $Control/V_Container_Game/How_To_Button
@onready var Input_Volume_Slider: HSlider = $Control/V_Container_Game/Slider_Game_Volume

var active = false
enum Mode {build, test}
var cur_mode = Mode.test
var launcher  # FOR DATA SHARE
var active_targets: Array = []

func _ready() -> void:
	launcher = self.get_parent()  # Assumes parent has LAUCNHER_CHILD_SHARED_DATA
	active_targets = LAUCNHER_CHILD_SHARE_GET("scenes", "targets")
	hide()
	Input_Build_Filename.text = Build_Filename
	update_build_file(Input_Build_Filename.text)
	switch_to_tester()
	
	LAUCNHER_CHILD_SHARE_SET("main_menu", "active", false)
	
	Input_Volume_Slider.value = 80.0
	update_volume(Input_Volume_Slider.value)

var pressing: bool = false
var pressing_add: bool = false
var pressing_apply: bool = false
var pressing_remove: bool = false
var pressing_help: bool = false
func _process(_delta) -> void:
	if Input.is_action_just_released(KEY_ESCAPE):
		toggler()
	
	# Only handle tester inputs when in test mode
	if cur_mode == Mode.test:
		get_targets()  # This could be expensive if called every frame; consider caching or signals
		
		if Input_Targets_Add.button_pressed:
			if not pressing_add:
				launcher.load_targets()
				pressing_add = true
			pressing = true
		
		elif Input_Target_Apply.button_pressed:
			if not pressing_apply:
				# No bounds check: ensure ID is within range to avoid errors
				update_target(int(Input_Targets_ID.value))
				pressing_apply = true
			pressing = true
		
		elif Input_Targets_Remove.button_pressed:
			if not pressing_remove:
				if active_targets.size() > 0:
					active_targets.pop_back()
				pressing_remove = true
			pressing = true
		elif Input_How_To_Button.button_pressed:
			if not pressing_help:
				OS.shell_open("https://shattereddisk.github.io/rickroll/rickroll.mp4")
				pressing_help = true
			pressing = true
		
		else:
			# Resetting press flags; might be simplified by using signals rather than polling
			pressing = false
			pressing_add = false
			pressing_help = false
			pressing_apply = false
			pressing_remove = false

	# Volume slider and build filename updates run regardless of mode
	if Input_Volume_Slider.drag_ended:
		update_volume(Input_Volume_Slider.value)
	
	update_build_file(Input_Build_Filename.text)
	
	if active_targets.size() > 0:
		Input_Targets_ID.max_value = active_targets.size()

func get_targets():
	# Directly reassigning every frame could be costly; consider updating only when needed
	active_targets = LAUCNHER_CHILD_SHARE_GET("scenes", "targets")

func update_volume(volume: float) -> void:
	var val = lerp(-60, 0, volume / 100.0)
	AudioServer.set_bus_volume_db(0, val)

func update_target(id: int):
	# Convert text to float without validation can crash if text is non-numeric
	var dist = float(Input_Target_Distance.text)
	var alt = float(Input_Target_Altitude.text)
	var speed = float(Input_Target_Speed.text)
	# Setting properties directly without checking if target exists may cause errors
	active_targets[id - 1].forward_velocity = speed
	active_targets[id - 1].curr_pos = Vector3(0, alt, -dist)
	active_targets[id - 1].global_position = Vector3(0, alt, -dist)

func toggler():
	active = !active
	if active:
		show()
		LAUCNHER_CHILD_SHARE_SET("main_menu", "active", true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var scene1 = LAUCNHER_CHILD_SHARE_GET("scenes", "world")
		if scene1 == InstancePlaceholder:
			return
		# Always setting process_mode to INHERIT; might want to check prior state
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
	LAUCNHER_CHILD_SHARE_SET("main_menu", "FILE_NAME", filename)

func switch_to_tester():
	cur_mode = Mode.test
	Tester_Container.show()  # Ensures tester UI is interactive
	var scene1 = LAUCNHER_CHILD_SHARE_GET("scenes", "builder")
	if scene1 == InstancePlaceholder:
		return
	var cam1: Camera3D = scene1.get_node("Builder_Camera")
	cam1.current = false
	var cam1_gui = cam1.get_node("GUI")
	cam1_gui.hide()
	scene1.hide()
	scene1.process_mode = Node.PROCESS_MODE_DISABLED
	
	var scene2 = LAUCNHER_CHILD_SHARE_GET("scenes", "world")
	if scene2 == InstancePlaceholder:
		return
	scene2.show()
	LAUCNHER_CHILD_SHARE_SET("world", "active_builder", false)
	# Always unconditionally inheriting process_mode; consider storing previous mode
	for target in active_targets:
		target.process_mode = Node.PROCESS_MODE_INHERIT
	scene2.process_mode = Node.PROCESS_MODE_INHERIT
	
	var scene3 = LAUCNHER_CHILD_SHARE_GET("scenes", "player")
	if scene3 == InstancePlaceholder:
		return
	var hud: Control = scene3.get_node("Player_Camera/Player_Camera_GUI")
	hud.buildering = false
	hud.queue_redraw()
	scene3.show()
	scene3.process_mode = Node.PROCESS_MODE_INHERIT

func switch_to_builder():
	cur_mode = Mode.build
	Tester_Container.hide()  # Prevent clicks on tester UI
	var scene1: Node3D = LAUCNHER_CHILD_SHARE_GET("scenes", "player")
	if scene1 == InstancePlaceholder:
		return
	var hud: Control = scene1.get_node("Player_Camera/Player_Camera_GUI")
	hud.buildering = true
	hud.queue_redraw()
	scene1.hide()
	scene1.process_mode = Node.PROCESS_MODE_DISABLED
	
	var scene2 = LAUCNHER_CHILD_SHARE_GET("scenes", "world")
	if scene2 == InstancePlaceholder:
		return
	scene2.hide()
	LAUCNHER_CHILD_SHARE_SET("world", "active_builder", true)
	for target in active_targets:
		target.process_mode = Node.PROCESS_MODE_DISABLED
	scene2.process_mode = Node.PROCESS_MODE_DISABLED
	
	var scene3 = LAUCNHER_CHILD_SHARE_GET("scenes", "builder")
	if scene3 == InstancePlaceholder:
		return
	var cam2: Camera3D = scene3.get_node("Builder_Camera")
	cam2.current = true
	var cam2_gui = cam2.get_node("GUI")
	cam2_gui.show()
	scene3.show()
	scene3.process_mode = Node.PROCESS_MODE_INHERIT

func LAUCNHER_CHILD_SHARE_SET(scene, key, data):  # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data

func LAUCNHER_CHILD_SHARE_GET(scene, key):  # FOR DATA SHARE
	if launcher:
		return launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key]
