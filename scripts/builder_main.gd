extends Node3D

@export_subgroup("BUILDER CONFIG")
@export var grid_size: Vector3i = Vector3i(1, 10, 1)  # Grid dimensions
@export var cell_size: float = 1.0  # Grid cell size
@export var placement_distance: int = 3  # Distance from camera to place block
@export_subgroup("MISC")
@export var ghost_block_scene: PackedScene  # Ghost block preview
@export var gc_block_scene: PackedScene  # CG block preview
@export var cl_block_scene: PackedScene  # CL block preview
@export var ct_block_scene: PackedScene  # CT block preview

var grid: Dictionary = {}  # Stores placed blocks
var selected_position: Vector3i = Vector3i.ZERO  # Current selected grid cell
var ghost_block: Node3D  # Ghost block instance
var cg_block: Node3D  # CG block instance
var cl_block: Node3D  # CL block instance
var ct_block: Node3D  # CL block instance
var launcher = Node  # FOR DATA SHARE
var grid_mesh: MeshInstance3D  # The grid renderer
var selected_block: PackedScene = null
var loader_saver

var aval_blocks = [
	load("res://game_data/blocks/back_cannard.tscn"),
	load("res://game_data/blocks/controller.tscn"),
	load("res://game_data/blocks/fin.tscn"),
	load("res://game_data/blocks/front_cannard.tscn"),
	load("res://game_data/blocks/ir_seeker.tscn"),
	load("res://game_data/blocks/laser_seeker.tscn"),
	load("res://game_data/blocks/radar_seeker.tscn"),
	load("res://game_data/blocks/rocket_fuel.tscn"),
	load("res://game_data/blocks/rocket_motor.tscn"),
	load("res://game_data/blocks/warhead.tscn"),
	]

@onready var camera = $Builder_Camera
@onready var block_selector = $Builder_Camera/GUI/GUI_Scroll_Container/GUI_Scroll_Selector/GUI_Scroll_Selector_Seporater

func _ready():
	launcher = self.get_parent() # FOR DATA SHARE
	
	center_camera()
	
	loader_saver = Loader_Saver.new(
		self,  # Pass builder node
		grid,  # Reference to the grid
		cell_size  # Pass cell size
	)
	
	if gc_block_scene:
		cg_block = gc_block_scene.instantiate()
		cg_block.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(cg_block)
	else:
		push_error("cg block scene not assigned!")
	
	if cl_block_scene:
		cl_block = cl_block_scene.instantiate()
		cl_block.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(cl_block)
	else:
		push_error("cl block scene not assigned!")
	
	if ct_block_scene:
		ct_block = ct_block_scene.instantiate()
		ct_block.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(ct_block)
	else:
		push_error("ct block scene not assigned!")
	
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
	create_block_button()

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
	
	# Align selection with the grid origin (0,0,0)
	selected_position = Vector3i(
		int(floor(target_position.x / cell_size + 0.5)), 
		int(floor(target_position.y / cell_size + 0.5)), 
		int(floor(target_position.z / cell_size + 0.5))
		)
	
	# Clamp within grid bounds
	selected_position.x = clamp(selected_position.x, 0, grid_size.x - 1)
	selected_position.y = clamp(selected_position.y, 0, grid_size.y - 1)
	selected_position.z = clamp(selected_position.z, 0, grid_size.z - 1)


func center_camera():
	@warning_ignore("integer_division")
	var grid_center = Vector3(
		grid_size.x / 2,
		grid_size.y / 2,
		grid_size.z / 2
	)
	camera.global_position = grid_center


func is_valid_placement(pos: Vector3i, block):
	var block_connections = block.DATA["UDLRTB"]
	
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
	var block_name = block.DATA["NAME"]
	var block_mass = block.DATA["MASS"]
	var block_connections = block.DATA["UDLRTB"]
	
	print("Placing Block:", block_name)
	print("Mass:", block_mass, "kg")
	print("Connections:", block_connections)
	
	add_child(block)
	grid[selected_position] = block
	update_center_of_gravity()
	update_center_of_lift()
	update_center_of_thrust()

func remove_block():
	if grid.has(selected_position):
		grid[selected_position].queue_free()
		grid.erase(selected_position)
	update_center_of_gravity()
	update_center_of_lift()
	update_center_of_thrust()

func _draw_grid():
	var im = grid_mesh.mesh as ImmediateMesh
	var gs = cell_size / 2
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	
	# Set grid color
	var grid_color = Color(0.1, 0.8, 0.1, 0.5)
	
	# Draw horizontal lines (X-Z plane) at each Y level
	for y in range(grid_size.y + 1):
		var y_pos = y * cell_size
		for x in range(grid_size.x + 1):
			var x_pos = x * cell_size
			im.surface_set_color(grid_color)
			im.surface_add_vertex(Vector3(x_pos - gs, y_pos - gs, -gs))
			im.surface_add_vertex(Vector3(x_pos - gs, y_pos - gs, grid_size.z * cell_size - gs))
		
		for z in range(grid_size.z + 1):
			var z_pos = z * cell_size
			im.surface_set_color(grid_color)
			im.surface_add_vertex(Vector3(-gs, y_pos - gs, z_pos - gs))
			im.surface_add_vertex(Vector3(grid_size.x * cell_size - gs, y_pos - gs, z_pos - gs))
	
	# Draw vertical lines (Y axis) at each X-Z position
	for x in range(grid_size.x + 1):
		var x_pos = x * cell_size
		for z in range(grid_size.z + 1):
			var z_pos = z * cell_size
			im.surface_set_color(grid_color)
			im.surface_add_vertex(Vector3(x_pos - gs, -gs, z_pos - gs))
			im.surface_add_vertex(Vector3(x_pos - gs, grid_size.y * cell_size - gs, z_pos - gs))
	
	im.surface_end()

func update_center_of_gravity():
	var total_mass = 0.0
	var weighted_position = Vector3.ZERO

	# grid is { position: block_node }
	for pos in grid:
		var block_node = grid[pos]
		if block_node.DATA.has("MASS"):
			var part_mass = block_node.DATA["MASS"]
			total_mass += part_mass
			var block_pos = block_node.global_transform.origin
			weighted_position += block_pos * part_mass
	
	if total_mass > 0.0:
		var cog = weighted_position / total_mass
		cg_block.global_position = cog
		cg_block.visible = true
	else:
		cg_block.visible = false

func update_center_of_lift():
	var total_lift = 0.0
	var lifting_position = Vector3.ZERO
	
	# grid is { position: block_node }
	for pos in grid:
		var block_node = grid[pos]
		if block_node.DATA.has("LIFT"):
			var part_lift = block_node.DATA["LIFT"]
			total_lift += part_lift
			var block_pos = block_node.global_transform.origin
			lifting_position += block_pos * part_lift
	
	if total_lift > 0.0:
		var col = lifting_position / total_lift
		cl_block.global_position = col
		cl_block.visible = true
	else:
		cl_block.visible = false

func update_center_of_thrust():
	var thrusting_position = Vector3.ZERO # >:)
	
	# grid is { position: block_node }
	for pos in grid:
		var block_node = grid[pos]
		if block_node.DATA.has("TYPE"):
			if  block_node.DATA["TYPE"] == 8:
				var block_pos = block_node.global_transform.origin
				thrusting_position += block_pos
	
	if thrusting_position == Vector3.INF:
		ct_block.visible = false
	else:
		var cot = thrusting_position
		ct_block.global_position = cot
		ct_block.visible = true

func select_block(block_path: PackedScene):
	selected_block = block_path
	print("Selected Block:", block_path)

func create_block_button():
	for block: PackedScene in aval_blocks:
		if block:
			var block_instance = block.instantiate()
			var block_name = block_instance.DATA["NAME"]
			
			var button = Button.new()
			button.text = block_name
			button.pressed.connect(func(): select_block(block))
			
			block_selector.add_child(button)
			
			block_instance.queue_free()

func _SAVER():
	var path = LAUCNHER_CHILD_SHARE_GET("main_menu", "FILE_PATH") # get save file path
	if grid:
		loader_saver.save_vehicle(path)
		loader_saver.save_assembly(path)
	else:
		print("Invalid Grid Data")

func _LOADER():
	var path = LAUCNHER_CHILD_SHARE_GET("main_menu", "FILE_PATH") # get save file path
	loader_saver.load_vehicle(path)
	update_center_of_gravity()
	update_center_of_lift()
	update_center_of_thrust()

func LAUCNHER_CHILD_SHARE_SET(scene, key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data

func LAUCNHER_CHILD_SHARE_GET(scene, key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key]
		return data
