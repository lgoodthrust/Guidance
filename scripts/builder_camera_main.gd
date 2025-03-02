extends Camera3D

## PLAYER MOVEMENT SCRIPT ##
###########################

@export_subgroup("Settings")
@export var SPEED := 50.0
@export var ACCEL := 150.0



@export_subgroup("Clamp Head Rotation")
@export var CLAMP_HEAD_ROTATION := true
@export var CLAMP_HEAD_ROTATION_MIN := -90.0
@export var CLAMP_HEAD_ROTATION_MAX := 90.0

@export_subgroup("Mouse")
@export var CAPTURE_ON_START := true
@export var MOUSE_ACCEL := false
@export var KEY_BIND_MOUSE_SENS := 0.005
@export var KEY_BIND_MOUSE_ACCEL := 50

@export_subgroup("Movement")
@export var KEY_BIND_UP := "key_w"
@export var KEY_BIND_LEFT := "key_a"
@export var KEY_BIND_RIGHT := "key_d"
@export var KEY_BIND_DOWN := "key_s"
@export var KEY_BIND_SPRINT := "key_r_shift"
@export var KEY_BIND_CROUTCH := "key_r_ctrl"

@export_category("Advanced")
@export var UPDATE_PLAYER_ON_PHYS_STEP := true

var speed = SPEED
var accel = ACCEL
var velocity

var rotation_target_player : float
var rotation_target : float
var start_pos : Vector3
var camming: bool = false

func _ready():
	if CAPTURE_ON_START:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	start_pos = self.position

func _physics_process(delta):
	
	if UPDATE_PLAYER_ON_PHYS_STEP:
		move_player(delta)
		rotate_player(delta)

func _process(delta):
	if !UPDATE_PLAYER_ON_PHYS_STEP:
		move_player(delta)
		rotate_player(delta)

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				camming = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				camming = false
				Input.mouse_mode = Input.MOUSE_MODE_CONFINED

	if camming and event is InputEventMouseMotion:
		set_rotation_target(event.relative)


func set_rotation_target(mouse_motion : Vector2):
	rotation_target_player += -mouse_motion.x * KEY_BIND_MOUSE_SENS
	rotation_target += -mouse_motion.y * KEY_BIND_MOUSE_SENS
	
	if CLAMP_HEAD_ROTATION:
		rotation_target = clamp(rotation_target, deg_to_rad(CLAMP_HEAD_ROTATION_MIN), deg_to_rad(CLAMP_HEAD_ROTATION_MAX))
	
func rotate_player(delta):
	if MOUSE_ACCEL:
		# Use slerp for smooth rotation
		var target_quat_y = Quaternion(Vector3.UP, rotation_target_player)
		
		self.quaternion = self.quaternion.slerp(target_quat_y, KEY_BIND_MOUSE_ACCEL * delta)
		self.rotation.x = lerp(self.rotation.x, rotation_target, KEY_BIND_MOUSE_ACCEL * delta)
	else:
		# Directly set rotation without interpolation
		self.rotation.y = rotation_target_player
		self.rotation.x = rotation_target


func move_player(delta):
	var input_dir = Input.get_vector(KEY_BIND_LEFT, KEY_BIND_RIGHT, KEY_BIND_UP, KEY_BIND_DOWN)

	# Noclip flying mode
	speed = SPEED * (2.0 if Input.is_action_pressed(KEY_BIND_SPRINT) else (0.5 if Input.is_action_pressed(KEY_BIND_CROUTCH) else 1.0))
	accel = ACCEL
	# Get current camera rotation as a quaternion
	var camera_quat = self.global_transform.basis.get_rotation_quaternion()
	# Get movement directions based on camera quaternion
	var forward = camera_quat * Vector3.BACK
	var right = camera_quat * Vector3.RIGHT
	# Compute movement direction in 3D space
	var movement_dir = (forward * input_dir.y) + (right * input_dir.x)
	if movement_dir.length() > 0.0:
		movement_dir = movement_dir.normalized()
	# Apply movement using lerp for smooth acceleration
	velocity = movement_dir * speed * delta
	# Directly move the player in noclip (bypassing physics)
	global_transform.origin += velocity * delta
