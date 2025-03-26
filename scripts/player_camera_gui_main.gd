extends Control

# Declare necessary variables
var camera: Camera3D
var target: Node
var buildering: bool = false

var FOV

var w_size = DisplayServer.window_get_size()
var v_size: Vector2 = DisplayServer.screen_get_size()
var ar: float = v_size.x / v_size.y  # Aspect ratio (width/height)
var w_center = w_size / 2.0

# Called when the node enters the scene tree for the first time
func _ready() -> void:
	print("center: ", w_center)
	camera = get_parent()  # Assuming the parent is the camera node
	if not camera:
		print("Warning: Parent is not a Camera3D!")
	FOV = camera.fov

# Process function to control redrawing
func _process(_delta: float) -> void:
	FOV = camera.fov
	if not target:
		target = get_tree().current_scene.get_tree().root.get_node_or_null("./Launcher/World/Active_Target")
		return
	
	queue_redraw()

# Function to draw the target on screen
func _draw() -> void:
	if target and camera and not buildering:
		# Convert world position to screen position
		var screen_pos = camera.unproject_position(target.global_transform.origin)
		
		# Ensure the position is within screen bounds
		screen_pos.x = clamp(screen_pos.x, 0, w_size.x)
		screen_pos.y = clamp(screen_pos.y, 0, w_size.y)

		# Drawing parameters
		var radius = 45.0
		var filled = false
		var thickness = 2.0
		var color = Color8(0, 255, 0, 255)
		var aa = true
		
		# Draw the target indicator
		var r_size = Vector2(radius, radius)
		var r_shape = Rect2(screen_pos - (r_size / 2.0), r_size)
		if not camera.is_position_behind(target.global_transform.origin):
			draw_rect(r_shape, color, filled, thickness, aa)
