extends Node
class_name Loader_Saver

var builder_instance: Node
var grid: Dictionary
var cell_size: float
var folder: String = ""

func _init(builder: Node, grid_ref: Dictionary, cell_size_ref: float, path: String):
	builder_instance = builder
	grid = grid_ref
	cell_size = cell_size_ref
	folder = path

func save_vehicle(save_dir: String):
	var path = save_dir + ".json"
	path = folder.path_join(path)
	
	var save_data = []
	for pos in grid.keys():
		var block = grid[pos]
		var block_info = {
			"path": block.scene_file_path,
			"position": {
				"x": pos.x,
				"y": pos.y,
				"z": pos.z
			},
			"rotation": {
				"x": block.rotation_degrees.x,
				"y": block.rotation_degrees.y,
				"z": block.rotation_degrees.z
			},
			"DATA": block.DATA
		}
		save_data.append(block_info)
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		print("Vehicle JSON saved to: %s" % path)
	else:
		push_error("Failed to save vehicle JSON at: %s" % path)

func load_vehicle(load_dir: String):
	var path = load_dir + ".json"
	path = folder.path_join(path)
	
	# Clear out old blocks
	for pos in grid.keys():
		grid[pos].queue_free()
	grid.clear()
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open JSON at: %s" % path)
		return
	
	var parse_result = JSON.parse_string(file.get_as_text())
	file.close()
	
	# Expect an array of block-data dictionaries
	if typeof(parse_result) != TYPE_ARRAY:
		push_error("Expected an array of blocks in JSON: %s" % path)
		return
	
	var block_dict_array = parse_result
	for data_dict in block_dict_array:
		var block_scene = load(data_dict["path"])
		if block_scene:
			var block = block_scene.instantiate()
			
			var pos_dict = data_dict["position"]
			block.position = Vector3(pos_dict.x, pos_dict.y, pos_dict.z) * cell_size
			
			var rot_dict = data_dict["rotation"]
			block.rotation_degrees = Vector3(rot_dict.x, rot_dict.y, rot_dict.z)
			
			block.DATA = data_dict["DATA"]
			
			builder_instance.add_child(block)
			grid[Vector3i(pos_dict.x, pos_dict.y, pos_dict.z)] = block
	
	print("Vehicle loaded from JSON: %s" % path)

func save_assembly(save_dir: String):
	# Create a top-level Node3D as the new root.
	var missile_root = Node3D.new()
	missile_root.name = "MissileRoot"
	
	# Create a RigidBody3D child to hold all the blocks.
	var rigid_body = RigidBody3D.new()
	rigid_body.name = "RigidBody3D"
	
	# Attach the RigidBody3D to MissileRoot, and set its owner
	missile_root.add_child(rigid_body)
	rigid_body.owner = missile_root
	
	# Prepare to parse the JSON
	var path = save_dir + ".json"
	path = folder.path_join(path)
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open JSON at: %s" % path)
		return
	
	# Clear out old blocks in your builder (if you really need to do that here)
	for pos in grid.keys():
		grid[pos].queue_free()
	grid.clear()
	
	var parse_result = JSON.parse_string(file.get_as_text())
	file.close()
	
	if typeof(parse_result) != TYPE_ARRAY:
		push_error("Expected an array of blocks in JSON: %s" % path)
		return
	
	var block_dict_array = parse_result
	
	# Instantiate each block and:
	# - Add one copy to your in-editor builder (if you need it)
	# - Add one copy to the RigidBody3D for the final scene
	for data_dict in block_dict_array:
		var block_scene = load(data_dict["path"])
		if block_scene:
			# a) Create the block for the builder
			var block_builder_instance = block_scene.instantiate()
			
			var pos_dict = data_dict["position"]
			block_builder_instance.position = Vector3(pos_dict.x, pos_dict.y, pos_dict.z) * cell_size
			
			var rot_dict = data_dict["rotation"]
			block_builder_instance.rotation_degrees = Vector3(rot_dict.x, rot_dict.y, rot_dict.z)
			
			block_builder_instance.DATA = data_dict["DATA"]
			
			builder_instance.add_child(block_builder_instance)
			grid[Vector3i(pos_dict.x, pos_dict.y, pos_dict.z)] = block_builder_instance
			
			# b) Create a second copy for the actual RigidBody scene
			var block_rigid_instance = block_scene.instantiate()
			
			# Position/rotation
			block_rigid_instance.position = block_builder_instance.position
			block_rigid_instance.rotation_degrees = block_builder_instance.rotation_degrees
			block_rigid_instance.DATA = block_builder_instance.DATA
			
			# Add to the RigidBody, set its owner to missile_root so it's saved
			rigid_body.add_child(block_rigid_instance)
			block_rigid_instance.owner = missile_root
	
	# pack the top-level MissileRoot into a PackedScene
	var packed_scene = PackedScene.new()
	packed_scene.pack(missile_root)
	
	var tscn_dir = save_dir + ".tscn"
	tscn_dir = folder.path_join(tscn_dir)
	var err = ResourceSaver.save(packed_scene, tscn_dir)
	if err == OK:
		print("Assembled TSCN saved to: %s" % tscn_dir)
	else:
		push_error("Failed to save TSCN. Error: %d" % err)

func load_assembly(tscn_dir: String) -> Node3D:
	tscn_dir = tscn_dir + ".tscn"
	tscn_dir = folder.path_join(tscn_dir)
	
	var resource = ResourceLoader.load(tscn_dir)
	if not resource or not (resource is PackedScene):
		push_error("Failed to load TSCN at: %s" % tscn_dir)
		return Node3D.new()
	
	# Instantiate the assembly as a Node3D
	var assembly = resource.instantiate() as Node3D
	
	# Return the fully populated rigid body
	return assembly
