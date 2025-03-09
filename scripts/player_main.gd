extends CharacterBody3D

## PLAYER MOVEMENT SCRIPT ##
###########################

@export_subgroup("Settings")
@export var SPEED := 5.0
@export var ACCEL := 150.0
@export var IN_AIR_SPEED := 3.0
@export var IN_AIR_ACCEL := 5.0
@export var IN_NOCLIP_SPEED := 25.0
@export var IN_NOCLIP_ACCEL := 50.0
@export var JUMP_VELOCITY := 4.5


@export_subgroup("Clamp Head Rotation")
@export var CLAMP_HEAD_ROTATION := true
@export var CLAMP_HEAD_ROTATION_MIN := -89.999
@export var CLAMP_HEAD_ROTATION_MAX := 89.999

@export_subgroup("Mouse")
@export var CAPTURE_ON_START := true
@export var MOUSE_ACCEL := false
@export var KEY_BIND_MOUSE_SENS := 0.005
@export var KEY_BIND_MOUSE_ACCEL := 50
@export var KEY_MOUSE_ZOOM := "key_b"

@export_subgroup("Movement")
@export var KEY_BIND_UP := "key_w"
@export var KEY_BIND_LEFT := "key_a"
@export var KEY_BIND_RIGHT := "key_d"
@export var KEY_BIND_DOWN := "key_s"
@export var KEY_BIND_JUMP := "key_space"
@export var KEY_BIND_SPRINT := "key_r_shift"
@export var KEY_BIND_CROUTCH := "key_r_ctrl"
@export var KEY_BIND_NOCLIP := "key_z"
@export var KEY_BIND_MSL := "key_1"

@export_category("Advanced")
@export var UPDATE_PLAYER_ON_PHYS_STEP := true

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var speed = SPEED
var accel = ACCEL
var noclip_tog = false
var zoom_tog = false
var msl_follow_tog = false

var rotation_target_player : float
var rotation_target : float
var start_pos : Vector3
var launcher = Node # FOR DATA SHARE
var Camera: Camera3D


func _ready():
	launcher = self.get_parent() # FOR DATA SHARE
	
	Camera = $Player_Camera
	
	if CAPTURE_ON_START:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	start_pos = Camera.position
	


func _physics_process(delta):
	if UPDATE_PLAYER_ON_PHYS_STEP:
		toggle_msl_follow(msl_follow_tog)
		move_player(delta)
		rotate_player(delta)


func _process(delta):
	if !UPDATE_PLAYER_ON_PHYS_STEP:
		toggle_msl_follow(msl_follow_tog)
		move_player(delta)
		rotate_player(delta)
	
	if Input.is_action_just_pressed("key_b"):
		zoom_tog =! zoom_tog
	if zoom_tog:
		Camera.fov = 15.0
	else:
		Camera.fov = 75.0


func _input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: # if mouse moving, rotate
		set_rotation_target(event.relative)


func set_rotation_target(mouse_motion : Vector2):
	rotation_target_player += -mouse_motion.x * KEY_BIND_MOUSE_SENS
	rotation_target += -mouse_motion.y * KEY_BIND_MOUSE_SENS
	
	if CLAMP_HEAD_ROTATION:
		rotation_target = clamp(rotation_target, deg_to_rad(CLAMP_HEAD_ROTATION_MIN), deg_to_rad(CLAMP_HEAD_ROTATION_MAX))
	
func rotate_player(delta):
	if MOUSE_ACCEL:
		quaternion = quaternion.slerp(Quaternion(Vector3.UP, rotation_target_player), KEY_BIND_MOUSE_ACCEL * delta)
		Camera.quaternion = Camera.quaternion.slerp(Quaternion(Vector3.RIGHT, rotation_target), KEY_BIND_MOUSE_ACCEL * delta)
	else:
		quaternion = Quaternion(Vector3.UP, rotation_target_player)
		Camera.quaternion = Quaternion(Vector3.RIGHT, rotation_target)


func move_player(delta):
	var input_dir = Input.get_vector(KEY_BIND_LEFT, KEY_BIND_RIGHT, KEY_BIND_UP, KEY_BIND_DOWN)
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if Input.is_action_just_pressed(KEY_BIND_NOCLIP):
		noclip_tog = !noclip_tog
		toggle_noclip(noclip_tog)
	
	if Input.is_action_pressed(KEY_BIND_CROUTCH):
		$Player_Shape.shape.height = 1.0
		Camera.position.y = 1.0
		$Player_Object/Player_Collider.shape.height = 1.0
	else:
		$Player_Shape.shape.height = 2.0
		Camera.position.y = 2.0
		$Player_Object/Player_Collider.shape.height = 2.0

	if noclip_tog:
		# noclip_tog flying mode
		speed = IN_NOCLIP_SPEED * (2.0 if Input.is_action_pressed(KEY_BIND_SPRINT) else (0.5 if Input.is_action_pressed(KEY_BIND_CROUTCH) else 1.0))
		accel = IN_NOCLIP_ACCEL
		# Get current camera rotation as a quaternion
		var camera_quat = Camera.global_transform.basis.get_rotation_quaternion()
		# Get movement directions based on camera quaternion
		var forward = camera_quat * Vector3.BACK
		var right = camera_quat * Vector3.RIGHT
		# Compute movement direction in 3D space
		var movement_dir = (forward * input_dir.y) + (right * input_dir.x)
		if movement_dir.length() > 0.0:
			movement_dir = movement_dir.normalized()
		# Apply movement using lerp for smooth acceleration
		velocity = velocity.lerp(movement_dir * speed, accel * delta)
		# Directly move the player in noclip_tog (bypassing physics)
		global_transform.origin += velocity * delta
	else:
		# Regular movement with physics
		if is_on_floor():
			speed = SPEED * (2.0 if Input.is_action_pressed(KEY_BIND_SPRINT) else (0.5 if Input.is_action_pressed(KEY_BIND_CROUTCH) else 1.0))
			accel = ACCEL
			if Input.is_action_just_pressed(KEY_BIND_JUMP):
				velocity.y = JUMP_VELOCITY
		else:
			speed = IN_AIR_SPEED * (2.0 if Input.is_action_pressed(KEY_BIND_SPRINT) else (0.5 if Input.is_action_pressed(KEY_BIND_CROUTCH) else 1.0))
			accel = IN_AIR_ACCEL
			velocity.y -= gravity * delta
		velocity.x = move_toward(velocity.x, direction.x * speed, accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, accel * delta)
	
		if Input.is_action_just_pressed(KEY_BIND_MSL):
			msl_follow_tog =! msl_follow_tog
			
	
		move_and_slide()
	LAUCNHER_CHILD_SHARE_SET("player", "POS", self.global_position)

var back_step = false
func toggle_msl_follow(enabled: bool):
	if launcher.LAUCNHER_CHILD_SHARED_DATA["world"].has("missiles"):
		var msl = launcher.LAUCNHER_CHILD_SHARED_DATA["world"].get("missiles", [])
		
		if msl is Array and not msl.is_empty():
			var first_missile = msl[0]
			
			if enabled:
				print("enabled")
				var rigid = first_missile.get_child(0)
				global_position = rigid.global_position + Vector3(0,3,10)
				
			else:
				if not back_step:
					print("disabled")
					global_position = Vector3(0, 3, 10)
					back_step = true
					noclip_tog = true
			
		else:
			print("no missiles")
			msl_follow_tog = false
			back_step = false
			noclip_tog = false
	else:
		print("no list")
		back_step = true





func toggle_noclip(enabled):
	if enabled:
		set_collision_layer_value(1, false)
		set_collision_mask_value(1, false)
	else:
		set_collision_layer_value(1, true)
		set_collision_mask_value(1, true)


func LAUCNHER_CHILD_SHARE_SET(scene, key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data


func LAUCNHER_CHILD_SHARE_GET(scene, key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key]
		return data
