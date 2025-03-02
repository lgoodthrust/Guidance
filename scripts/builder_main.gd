extends Node3D

@export var grid_size: Vector3i = Vector3i(10, 10, 10)  # Grid dimensions
@export var cell_size: float = 1.0  # Grid cell size
@export var block_folder_path: String = "res://game_data/blocks/"  # Folder for blocks
@export var ghost_block_scene: PackedScene  # Ghost block preview
@export var placement_distance: int = 3  # Distance from camera to place block

var grid: Dictionary = {}  # Stores placed blocks
var selected_position: Vector3i = Vector3i.ZERO  # Current selected grid cell
var ghost_block: Node3D  # Ghost block instance
var launcher = Node  # FOR DATA SHARE
var grid_mesh: MeshInstance3D  # The grid renderer
var selected_block: PackedScene = null  # Currently selected block

@onready var camera = $Builder_Camera #get_tree().current_scene.find_child("Player_Camera", true, false)
@onready var block_selector = $Builder_Camera/GUI/GUI_Scroll_Container/GUI_Scroll_Selector/GUI_Scroll_Selector_Seporater

func _ready():
	launcher = get_node(".").get_parent() # FOR DATA SHARE
	
	#Ensure ghost block scene is assigned
	if ghost_block_scene:
		ghost_block = ghost_block_scene.instantiate()
		ghost_block.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(ghost_block)
	else:
		push_error("Ghost block scene not assigned!")

	# Create the grid mesh instance
	grid_mesh = MeshInstance3D.new()
	grid_mesh.mesh = ImmediateMesh.new()
	add_child(grid_mesh)
	
	# Draw the grid
	_draw_grid()

	# Load UI block selector
	load_blocks_into_ui()

func _process(_delta):
	
	update_selected_position()
	ghost_block.position = selected_position * cell_size  # Move ghost block
	
	if Input.is_action_just_pressed("key_e"):
		place_block()
	elif Input.is_action_just_pressed("key_q"):
		remove_block()


func update_selected_position():
	var forward = -camera.global_transform.basis.z.normalized()
	
	var target_position = camera.global_position + forward * (placement_distance * cell_size)
	selected_position = (target_position / cell_size).round()

	selected_position.x = clamp(selected_position.x, 0, grid_size.x - 1)
	selected_position.y = clamp(selected_position.y, 0, grid_size.y - 1)
	selected_position.z = clamp(selected_position.z, 0, grid_size.z - 1)


func is_valid_placement(pos: Vector3i, block):
	var block_connections = block["UDLRTB"]
	
	var neighbors = {
		"UP": pos + Vector3i(0, 1, 0),
		"DOWN": pos + Vector3i(0, -1, 0),
		"LEFT": pos + Vector3i(-1, 0, 0),
		"RIGHT": pos + Vector3i(1, 0, 0),
		"FRONT": pos + Vector3i(0, 0, -1),
		"BACK": pos + Vector3i(0, 0, 1)
	}

	for i in range(6):
		if block_connections[i] == -1:
			continue  # Allow any connection
		if block_connections[i] == 0 and grid.has(neighbors.values()[i]):
			return false  # No connection allowed, but a block is present

	return true

func place_block():
	if selected_block == null:
		return

	if grid.has(selected_position):
		return  # Block already exists

	var block = selected_block.instantiate()

	#Ensure block is valid before placement
	if not is_valid_placement(selected_position, block):
		print("Invalid placement!")
		block.queue_free()
		return

	block.position = selected_position * cell_size

	#Read Metadata for Behavior
	var block_name = block["NAME"]
	var block_mass = block["MASS"]
	var block_connections = block["UDLRTB"]

	print("Placing Block:", block_name)
	print("Mass:", block_mass, "kg")
	print("Connections:", block_connections)

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

	# Draw grid lines along the X-Z plane at every Y level (horizontal layers)
	for y in range(grid_size.y + 1):
		var y_pos = y * cell_size - half_y
		for x in range(grid_size.x + 1):
			var x_pos = x * cell_size - half_x
			im.surface_set_color(Color(0.1, 0.8, 0.1, 0.5))
			im.surface_add_vertex(Vector3(x_pos, y_pos, -half_z))
			im.surface_add_vertex(Vector3(x_pos, y_pos, half_z))
		
		for z in range(grid_size.z + 1):
			var z_pos = z * cell_size - half_z
			im.surface_set_color(Color(0.1, 0.8, 0.1, 0.5))
			im.surface_add_vertex(Vector3(-half_x, y_pos, z_pos))
			im.surface_add_vertex(Vector3(half_x, y_pos, z_pos))

	# Draw vertical lines along the Y-axis (Z-X layers)
	for x in range(grid_size.x + 1):
		var x_pos = x * cell_size - half_x
		for z in range(grid_size.z + 1):
			var z_pos = z * cell_size - half_z
			im.surface_set_color(Color(0.1, 0.8, 0.1, 0.5))
			im.surface_add_vertex(Vector3(x_pos, -half_y, z_pos))
			im.surface_add_vertex(Vector3(x_pos, half_y, z_pos))

	# Draw vertical lines along the Y-axis (X-Z layers)
	for z in range(grid_size.z + 1):
		var z_pos = z * cell_size - half_z
		for x in range(grid_size.x + 1):
			var x_pos = x * cell_size - half_x
			im.surface_set_color(Color(0.1, 0.8, 0.1, 0.5))
			im.surface_add_vertex(Vector3(x_pos, -half_y, z_pos))
			im.surface_add_vertex(Vector3(x_pos, half_y, z_pos))

	im.surface_end()


func load_blocks_into_ui():
	for child in block_selector.get_children():
		child.queue_free()

	var dir = DirAccess.open(block_folder_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tscn"):
				var block_path = block_folder_path + file_name
				create_block_button(block_path)
			file_name = dir.get_next()
	else:
		push_error("Failed to open block folder!")

func create_block_button(block_path: String):
	var block_scene = load(block_path)
	if block_scene:
		var block_instance = block_scene.instantiate()
		var block_name = block_instance.get_meta("NAME", "Unknown Block")  # Read metadata
		var block_type = block_instance.get_meta("TYPE", 0)  # Read type metadata

		var button = Button.new()
		button.text = block_name + " (" + str(block_type) + ")"  # Show name & type
		button.pressed.connect(func(): select_block(block_path))
		
		block_selector.add_child(button)

		block_instance.queue_free()  # We only needed metadata, remove instance

func select_block(block_path: String):
	selected_block = load(block_path)
	print("Selected Block:", block_path)

#LAUCNHER_CHILD_SHARE_SET("builder", [])

func LAUCNHER_CHILD_SHARE_SET(key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[key] = [data]
		launcher.LAUCNHER_CHILD_SHARED_DATA_CALL()

func LAUCNHER_CHILD_SHARE_GET(key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[key]
		return data
