extends Node3D

## ROTATION ##
###########################
@export_category("Mouse Capture")
@export var CAPTURE_ON_START: bool = true

@export_subgroup("Clamp Rotation")
@export var CLAMP_ROTATION: bool = true
@export var CLAMP_ROTATION_MIN: float = -90.0
@export var CLAMP_ROTATION_MAX: float = 90.0

@export_subgroup("Mouse")
@export var KEY_BIND_MOUSE_SENS: float = 0.005

@export_category("Advanced")
@export var UPDATE_ON_PHYS_STEP: bool = true

# Using yaw for horizontal rotation and pitch for vertical rotation
var yaw: float = 0.0
var pitch: float = 0.0

func _ready():
	if CAPTURE_ON_START:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	if UPDATE_ON_PHYS_STEP:
		move_player(delta)
		rotate_player(delta)

func _process(delta):
	if not UPDATE_ON_PHYS_STEP:
		move_player(delta)
		rotate_player(delta)

func _input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_update_rotation(event.relative)

func _update_rotation(mouse_motion: Vector2) -> void:
	# Update yaw and pitch based on mouse motion
	yaw -= mouse_motion.x * KEY_BIND_MOUSE_SENS
	pitch -= mouse_motion.y * KEY_BIND_MOUSE_SENS
	
	# Clamp pitch to avoid over-rotation (vertical look)
	if CLAMP_ROTATION:
		pitch = clamp(pitch, deg_to_rad(CLAMP_ROTATION_MIN), deg_to_rad(CLAMP_ROTATION_MAX))

func rotate_player(delta: float) -> void:
	# Apply combined yaw and pitch to the node.
	# If you want to rotate a specific child (like a camera), replace 'self.rotation' with, for example, '$Camera3D.rotation'
	rotation = Vector3(pitch, yaw, 0)

func move_player(delta: float) -> void:
	# Simple forward movement example (modify as needed)
	var forward_dir = -transform.basis.z
	position += forward_dir * delta * 5  # 5 is the movement speed
