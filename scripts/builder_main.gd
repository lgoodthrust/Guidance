extends Node3D

@export var grid_size: Vector3i = Vector3i(10, 10, 10)  # Grid dimensions
@export var cell_size: float = 1.0  # Grid cell size
@export var block_scene: PackedScene  # Assign a block scene in the editor
@export var ghost_block_scene: PackedScene  # Assign a ghost block scene in the editor

var grid: Dictionary = {}  # Stores placed blocks
var selected_position: Vector3i = Vector3i.ZERO  # Current selected grid cell
var ghost_block: Node3D  # The ghost block instance
var launcher = Node # FOR DATA SHARE
var grid_mesh: MeshInstance3D  # The grid renderer

@onready var camera = get_tree().current_scene.find_child("Player_Camera", true, false)

func _ready():
	launcher = get_node(".").get_parent() # FOR DATA SHARE
	
	# Instantiate the ghost block
	ghost_block = ghost_block_scene.instantiate()
	ghost_block.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ghost_block)

	# Create the grid mesh instance
	grid_mesh = MeshInstance3D.new()
	grid_mesh.mesh = ImmediateMesh.new()
	add_child(grid_mesh)
	
	# Draw the grid
	_draw_grid()

func _process(_delta):
	update_selected_position()
	ghost_block.position = selected_position * cell_size  # Move ghost block
	
	if Input.is_action_just_pressed("place_block"):
		place_block()
	elif Input.is_action_just_pressed("remove_block"):
		remove_block()

func update_selected_position():
	var space_state = get_world_3d().direct_space_state
	var from = camera.project_ray_origin(get_viewport().get_mouse_position())
	var to = from + camera.project_ray_normal(get_viewport().get_mouse_position()) * 100.0
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)

	if result:
		var hit_position = result.position
		selected_position = (hit_position / cell_size).round()  # Snap to grid

func place_block():
	if grid.has(selected_position):
		return  # Block already exists

	var block = block_scene.instantiate()
	block.position = selected_position * cell_size
	add_child(block)
	grid[selected_position] = block

func remove_block():
	if grid.has(selected_position):
		grid[selected_position].queue_free()
		grid.erase(selected_position)

func _draw_grid():
	var im = grid_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	var half_x = grid_size.x * cell_size * 0.5
	var half_y = grid_size.y * cell_size * 0.5
	var half_z = grid_size.z * cell_size * 0.5
	
	# Draw grid lines along X-Z plane
	for x in range(grid_size.x + 1):
		var x_pos = x * cell_size - half_x
		im.surface_set_color(Color(0.1, 0.8, 0.1, 0.5))  # Green grid lines
		im.surface_add_vertex(Vector3(x_pos, 0, -half_z))
		im.surface_add_vertex(Vector3(x_pos, 0, half_z))
	
	for z in range(grid_size.z + 1):
		var z_pos = z * cell_size - half_z
		im.surface_set_color(Color(0.1, 0.8, 0.1, 0.5))
		im.surface_add_vertex(Vector3(-half_x, 0, z_pos))
		im.surface_add_vertex(Vector3(half_x, 0, z_pos))

	# Draw grid lines along X-Y plane
	for x in range(grid_size.x + 1):
		var x_pos = x * cell_size - half_x
		im.surface_set_color(Color(0.1, 0.8, 0.1, 0.5))
		im.surface_add_vertex(Vector3(x_pos, -half_y, 0))
		im.surface_add_vertex(Vector3(x_pos, half_y, 0))

	for y in range(grid_size.y + 1):
		var y_pos = y * cell_size - half_y
		im.surface_set_color(Color(0.1, 0.8, 0.1, 0.5))
		im.surface_add_vertex(Vector3(-half_x, y_pos, 0))
		im.surface_add_vertex(Vector3(half_x, y_pos, 0))

	im.surface_end()

# FOR DATA SHARE
func LAUCNHER_CHILD_SHARE_SET(key, data):
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[key] = [data]
		launcher.LAUCNHER_CHILD_SHARED_DATA_CALL()

func LAUCNHER_CHILD_SHARE_GET(key):
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[key]
		return data
