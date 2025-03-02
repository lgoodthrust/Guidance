extends Window

var Main : Control
var Graphics : Control
var Controls : Control
var Sound : Control

var Param_Node_List = []


func _init() -> void:
	pass

func _ready() -> void:
	Main = $Tab_Container/Main/Grid
	Graphics = $Tab_Container/Graphics/Grid
	Controls = $Tab_Container/Controls/Grid
	Sound = $Tab_Container/Sound/Grid
	
	for SETTING in Main.get_children():
		pass
	for SETTING in Graphics.get_children():
		pass
	for SETTING in Controls.get_children():
		pass
	for SETTING in Sound.get_children():
		pass

func _process(_delta) -> void:
	pass

func update_launch_settings():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


func _on_close_requested() -> void:
	update_launch_settings()
	self.queue_free()
