extends Node

class_name Loader_Saver

var load_dir: String
var save_dir: String
var load_scene_dir: String
var save_scene_dir: String
var builder_instance: Node  # This is the builder that owns the grid
var assembly_scene_instance: Node3D
var grid: Dictionary
var cell_size: float


func _init(load_json_dir: String, save_json_dir: String, load_assembly_dir: String, save_assembly_dir: String, builder: Node, grid_ref: Dictionary, cell_size_ref: float):
	
	load_dir = load_json_dir
	
	save_dir = save_json_dir
	
	load_scene_dir = load_assembly_dir
	
	save_scene_dir = save_assembly_dir
	
	builder_instance = builder
	grid = grid_ref
	cell_size = cell_size_ref


func save_vehicle():
	var save_data = []

	# Loop through placed blocks in the grid
	for pos in grid.keys():
		var block = grid[pos]
		var block_data = {
			"path": block.scene_file_path,  # Store scene path
			"position": {  # Store as a dictionary
				"x": pos.x,
				"y": pos.y,
				"z": pos.z
			},
			"rotation": {  # Store as a dictionary
				"x": block.rotation_degrees.x,
				"y": block.rotation_degrees.y,
				"z": block.rotation_degrees.z
			},
			"DATA": block.DATA  # Save part data
		}
		save_data.append(block_data)

	# Convert to JSON and save
	var file = FileAccess.open(save_dir, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))  # Pretty print JSON
		file.close()
		print("Vehicle saved successfully!")
	else:
		print("Failed to save vehicle!")


func load_vehicle():
	# Clear current vehicle
	for pos in grid.keys():
		grid[pos].queue_free()
	grid.clear()

	var file = FileAccess.open(load_dir, FileAccess.READ)
	if not file:
		print("Failed to load vehicle!")
		return
	
	# Parse JSON data
	var save_data = JSON.parse_string(file.get_as_text())
	file.close()

	# Rebuild vehicle
	for block_data in save_data:
		var block_scene = load(block_data["path"])
		if block_scene:
			var block = block_scene.instantiate()

			# Extract position dictionary
			var pos_dict = block_data["position"]
			block.position = Vector3(pos_dict.x, pos_dict.y, pos_dict.z) * cell_size

			# Extract rotation dictionary
			var rot_dict = block_data["rotation"]
			block.rotation_degrees = Vector3(rot_dict.x, rot_dict.y, rot_dict.z)
			
			# Restore DATA dictionary
			block.DATA = block_data["DATA"]

			# Add to scene and grid
			builder_instance.add_child(block)
			grid[Vector3i(pos_dict.x, pos_dict.y, pos_dict.z)] = block

	print("Vehicle loaded successfully!")


func save_assembly():
	var file = FileAccess.open(load_dir, FileAccess.READ)
	if not file:
		push_error("Failed to open vehicle file at: %s" % load_dir)
		return Node3D.new()  # Return an empty node on failure

	# Parse JSON data
	var save_data = JSON.parse_string(file.get_as_text())
	file.close()

	# Create a new Node3D that will hold the entire vehicle
	var vehicle_root = Node3D.new()

	# Iterate over each block in the JSON data
	for block_data in save_data:
		var block_scene = load(block_data["path"])
		if block_scene:
			var block_instance = block_scene.instantiate()

			# Extract position dictionary
			var pos_dict = block_data["position"]
			block_instance.position = Vector3(pos_dict.x, pos_dict.y, pos_dict.z) * cell_size

			# Extract rotation dictionary
			var rot_dict = block_data["rotation"]
			block_instance.rotation_degrees = Vector3(rot_dict.x, rot_dict.y, rot_dict.z)

			# Restore DATA dictionary (if your block script expects this)
			block_instance.DATA = block_data["DATA"]

			# Add this block as a child of our vehicle root
			vehicle_root.add_child(block_instance)

	# Convert to packed scene
	var packed_scene = PackedScene.new()
	packed_scene.pack(vehicle_root)

	# Save as a .tscn file (scene, path)
	ResourceSaver.save(packed_scene, save_scene_dir)
	
	print("Assembled vehicle saved successfully!")


func load_assembly() -> Node3D:
	var file = ResourceLoader.load(load_scene_dir)
	if not file:
		push_error("Failed to open vehicle file at: %s" % load_dir)
		return
	
	var instance = file.instantiate() as Node3D
	assembly_scene_instance = instance
	file.close()
	
	return assembly_scene_instance
