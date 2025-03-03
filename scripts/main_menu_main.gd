extends Window

@export_subgroup("KEY BINDS")
@export var KEY_ESCAPE := "key_esc"
var active = false
var launcher = Node # FOR DATA SHARE


func _init() -> void:
	pass

func _ready() -> void:
	launcher = get_node(".").get_parent() # FOR DATA SHARE
	hide()

func _process(_delta) -> void:
	if Input.is_action_just_released(KEY_ESCAPE):
		active = !active
	vis_ctrl(active)

func vis_ctrl(state):
	if state == true:
		show()
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	else:
		hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func LAUCNHER_CHILD_SHARE_SET(key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[key] = [data]
		launcher.LAUCNHER_CHILD_SHARED_DATA_CALL()

func LAUCNHER_CHILD_SHARE_GET(key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[key]
		return data
