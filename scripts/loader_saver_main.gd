extends Node

class_name Loader_Saver

var save_dir: String
var load_dir: String
var object_instance: Node  # This is the builder that owns the grid
var grid: Dictionary
var cell_size: float

func _init(file_load_path: String, file_save_path: String, builder: Node, grid_ref: Dictionary, cell_size_ref: float):
	save_dir = file_load_path
	load_dir = file_save_path
	object_instance = builder
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
			object_instance.add_child(block)
			grid[Vector3i(pos_dict.x, pos_dict.y, pos_dict.z)] = block

	print("Vehicle loaded successfully!")
