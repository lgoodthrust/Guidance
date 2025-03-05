extends Node
class_name Loader_Saver

var builder_instance: Node
var grid: Dictionary
var cell_size: float
var assembly_scene_instance: Node3D


func _init(builder: Node, grid_ref: Dictionary, cell_size_ref: float):
	builder_instance = builder
	grid = grid_ref
	cell_size = cell_size_ref


func save_vehicle(save_dir: String):
	var path = save_dir + ".json"

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
	var temp_scene = Node3D.new()
	var path = save_dir + ".json"

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

	var packed_scene = PackedScene.new()
	packed_scene.pack(temp_scene)
	
	temp_scene.queue_free()

	var tscn_dir = save_dir + ".tscn"
	var err = ResourceSaver.save(packed_scene, tscn_dir)
	if err == OK:
		print("Assembled TSCN saved to: %s" % tscn_dir)
	else:
		push_error("Failed to save TSCN. Error: %d" % err)


func load_assembly(tscn_dir: String) -> Node3D:
	var resource = ResourceLoader.load(tscn_dir)
	if not resource or not (resource is PackedScene):
		push_error("Failed to load TSCN at: %s" % tscn_dir)
		return Node3D.new()

	var instance = resource.instantiate() as Node3D
	assembly_scene_instance = instance
	return instance
