extends CharacterBody3D

## PLAYER MOVEMENT SCRIPT ##
###########################

@export_subgroup("Settings")
@export var SPEED := 25.0
@export var ACCEL := 50.0
@export var IN_AIR_SPEED := 3.0
@export var IN_AIR_ACCEL := 5.0
@export var IN_NOCLIP_SPEED := 25.0
@export var IN_NOCLIP_ACCEL := 50.0
@export var JUMP_VELOCITY := 4.5


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
@export var KEY_BIND_JUMP := "key_space"
@export var KEY_BIND_SPRINT := "key_r_shift"
@export var KEY_BIND_CROUTCH := "key_r_ctrl"
@export var KEY_BIND_NOCLIP := "key_z"

@export_category("Advanced")
@export var UPDATE_PLAYER_ON_PHYS_STEP := true

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var speed = SPEED
var accel = ACCEL
var noclip = false

var rotation_target_player : float
var rotation_target : float
var start_pos : Vector3
var launcher = Node

func _ready():
	launcher = get_node(".").get_parent()

	if CAPTURE_ON_START:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	start_pos = $Player_Camera.position

func _physics_process(delta):
	
	if UPDATE_PLAYER_ON_PHYS_STEP:
		move_player(delta)
		rotate_player(delta)

func _process(delta):

	if !UPDATE_PLAYER_ON_PHYS_STEP:
		move_player(delta)
		rotate_player(delta)

func _input(event):
		
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		set_rotation_target(event.relative)

func set_rotation_target(mouse_motion : Vector2):
	rotation_target_player += -mouse_motion.x * KEY_BIND_MOUSE_SENS
	rotation_target += -mouse_motion.y * KEY_BIND_MOUSE_SENS
	
	if CLAMP_HEAD_ROTATION:
		rotation_target = clamp(rotation_target, deg_to_rad(CLAMP_HEAD_ROTATION_MIN), deg_to_rad(CLAMP_HEAD_ROTATION_MAX))
	
func rotate_player(delta):
	if MOUSE_ACCEL:
		quaternion = quaternion.slerp(Quaternion(Vector3.UP, rotation_target_player), KEY_BIND_MOUSE_ACCEL * delta)
		$Player_Camera.quaternion = $Player_Camera.quaternion.slerp(Quaternion(Vector3.RIGHT, rotation_target), KEY_BIND_MOUSE_ACCEL * delta)
	else:
		quaternion = Quaternion(Vector3.UP, rotation_target_player)
		$Player_Camera.quaternion = Quaternion(Vector3.RIGHT, rotation_target)

func move_player(delta):
	var input_dir = Input.get_vector(KEY_BIND_LEFT, KEY_BIND_RIGHT, KEY_BIND_UP, KEY_BIND_DOWN)
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if Input.is_action_just_pressed(KEY_BIND_NOCLIP):
		noclip = !noclip
		toggle_noclip(noclip)

	if noclip:
		# Noclip flying mode
		if Input.is_action_pressed(KEY_BIND_SPRINT):
			speed = IN_NOCLIP_SPEED * 2
		elif Input.is_action_pressed(KEY_BIND_CROUTCH):
			speed = IN_NOCLIP_SPEED * 0.5
		else:
			speed = IN_NOCLIP_SPEED
		accel = IN_NOCLIP_ACCEL
		# Get current camera rotation as a quaternion
		var camera_quat = $Player_Camera.global_transform.basis.get_rotation_quaternion()
		# Get movement directions based on camera quaternion
		var forward = camera_quat * Vector3.BACK
		var right = camera_quat * Vector3.RIGHT
		# Compute movement direction in 3D space
		var movement_dir = (forward * input_dir.y) + (right * input_dir.x)
		if movement_dir.length() > 0.0:
			movement_dir = movement_dir.normalized()
		# Apply movement using lerp for smooth acceleration
		velocity = velocity.lerp(movement_dir * speed, accel * delta)
		# Directly move the player in noclip (bypassing physics)
		global_transform.origin += velocity * delta
	else:
		# Regular movement with physics
		if is_on_floor():
			if Input.is_action_just_pressed(KEY_BIND_JUMP):
				velocity.y = JUMP_VELOCITY
			speed = SPEED
			accel = ACCEL
		else:
			speed = IN_AIR_SPEED
			accel = IN_AIR_ACCEL
			velocity.y -= gravity * delta
		velocity.x = move_toward(velocity.x, direction.x * speed, accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, accel * delta)
		move_and_slide()
	some_event_happens(self.global_position)

func toggle_noclip(enabled):
	if enabled:
		set_collision_layer_value(1, false)
		set_collision_mask_value(1, false)
	else:
		set_collision_layer_value(1, true)
		set_collision_mask_value(1, true)

func some_event_happens(data):
	if launcher:
		launcher.shared_data = data
		launcher.send_data_to_b()  # Notify Launcher to update Scene B
