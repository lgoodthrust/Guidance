extends Control

@onready var ftps: Label = $FTPS
@onready var tps: Label = $TPS
@onready var fps: Label = $FPS

# Declare necessary variables
var camera: Camera3D
var targets: Array = []
var msls
var buildering: bool = false

var w_size = DisplayServer.window_get_size()
var w_center = w_size / 2.0
var launcher: Node

# Called when the node enters the scene tree for the first time
func _ready() -> void:
	launcher = get_tree().root.get_node("./Launcher")
	camera = get_parent()  # Assuming the parent is the camera node
	if not camera:
		print("Warning: Parent is not a Camera3D!")

func _physics_process(_delta: float) -> void:
	if ftps:
		ftps.text = "FTPS: " + str(1/_delta)
	
	targets = get_targets()

func _process(_delta: float) -> void:
	if tps and fps:
		tps.text = "TPS: " + str(floor(1/_delta))
		fps.text = "FPS: " + str(Engine.get_frames_per_second())
	
	w_size = DisplayServer.window_get_size()
	w_center = w_size / 2.0
	
	queue_redraw()

func _get_rigidbody_or_null(n: Node) -> RigidBody3D:
	if n is RigidBody3D:
		return n
	for c in n.get_children():
		if c is RigidBody3D:
			return c
	return null

func get_missiles() -> Array:
	var bodies: Array = []
	
	if launcher.LAUCNHER_CHILD_SHARED_DATA.has("world") \
		and launcher.LAUCNHER_CHILD_SHARED_DATA["world"].has("missiles"):
		var missiles: Array = launcher.LAUCNHER_CHILD_SHARED_DATA["world"]["missiles"]
		
		for m in missiles:
			var body := _get_rigidbody_or_null(m)
			if body and is_instance_valid(body):
				bodies.append(body)
	
	return bodies

func get_targets() -> Array:
	return launcher.LAUCNHER_CHILD_SHARED_DATA["scenes"]["targets"]

# Function to draw the target on screen
func _draw() -> void:
	draw_circle(w_center, 3.0, Color.WHITE)
	
	if not buildering:
		if len(targets) > 0:
			for target in targets:
				if is_instance_valid(target) and camera:
					# Convert world position to screen position
					var screen_pos = camera.unproject_position(target.global_transform.origin)
					
					# Ensure the position is within screen bounds
					screen_pos.x = clamp(screen_pos.x, 0, w_size.x)
					screen_pos.y = clamp(screen_pos.y, 0, w_size.y)
					
					# Drawing parameters
					var t_radius = 45.0
					var t_filled = false
					var t_thickness = 2.0
					var t_color = Color(
							lerp(1, 0, (target.HEALTH/100.0)),
						 	lerp(0, 1, (target.HEALTH/100.0)),
						 	0,
							1
						)
					var t_aa = true
					
					# Draw the target indicator
					var t_r_size = Vector2(t_radius, t_radius)
					var t_r_shape = Rect2(screen_pos - (t_r_size / 2.0), t_r_size)
					if not camera.is_position_behind(target.global_transform.origin):
						draw_rect(t_r_shape, t_color, t_filled, t_thickness, t_aa)
			
			msls = get_missiles()
			if msls.is_empty():
				return
			
			for msl in msls:
				
				# Convert world position to screen position
				var msls_pos = camera.unproject_position(msl.global_transform.origin)
				
				# Ensure the position is within screen bounds
				msls_pos.x = clamp(msls_pos.x, 0, w_size.x)
				msls_pos.y = clamp(msls_pos.y, 0, w_size.y)
				
				# Drawing parameters
				var m_radius = 30.0
				var m_filled = false
				var m_thickness = 2.0
				var m_color = Color8(255, 0, 0, 255)
				var m_aa = true
				
				# Draw the target indicator
				var m_r_size = Vector2(m_radius, m_radius)
				var m_r_shape = Rect2(msls_pos - (m_r_size / 2.0), m_r_size)
				if not camera.is_position_behind(msl.global_transform.origin):
					draw_rect(m_r_shape, m_color, m_filled, m_thickness, m_aa)
