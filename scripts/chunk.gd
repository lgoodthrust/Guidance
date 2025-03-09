extends Node3D
class_name Chunk

var meshInstance: MeshInstance3D
var noise: FastNoiseLite
var chunkX: int
var chunkZ: int
var chunkSize: int
var thread: Thread = null  # Initialize as null to prevent issues
var ground_material: Material

func _init(noiseParam: FastNoiseLite, chunkXParam: int, chunkZParam: int, chunkSizeParam: int):
	noise = noiseParam
	chunkX = chunkXParam
	chunkZ = chunkZParam
	chunkSize = chunkSizeParam

func _ready():
	thread = Thread.new()
	var err = thread.start(_threaded_generate_chunk)
	if err != OK:
		push_error("Failed to start terrain generation thread")

func _threaded_generate_chunk():
	# Generate terrain in a separate thread
	var mesh = _generate_mesh()
	
	# Transfer to main thread
	call_deferred("_apply_mesh", mesh)

	# Ensure thread cleanup
	call_deferred("_cleanup_thread")

func _cleanup_thread():
	if thread:
		thread.wait_to_finish()
		thread = null  # Ensure thread is properly cleared

func _generate_mesh() -> ArrayMesh:
	var planeMesh = PlaneMesh.new()
	planeMesh.size = Vector2(chunkSize, chunkSize)
	@warning_ignore("integer_division")
	planeMesh.subdivide_depth = chunkSize / 2
	@warning_ignore("integer_division")
	planeMesh.subdivide_width = chunkSize / 2

	var surfaceTool = SurfaceTool.new()
	surfaceTool.create_from(planeMesh, 0)

	var dataTool = MeshDataTool.new()
	dataTool.create_from_surface(surfaceTool.commit(), 0)

	# Generate heightmap in separate thread
	for i in range(dataTool.get_vertex_count()):
		var vertex = dataTool.get_vertex(i)
		vertex.y = noise.get_noise_3d(vertex.x + chunkX, vertex.y, vertex.z + chunkZ) * 50
		dataTool.set_vertex(i, vertex)

	dataTool.commit_to_surface(surfaceTool.commit())
	surfaceTool.generate_normals()
	return surfaceTool.commit()

func _apply_mesh(mesh: ArrayMesh):
	meshInstance = MeshInstance3D.new()
	meshInstance.mesh = mesh
	meshInstance.create_trimesh_collision()
	meshInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Assign material safely AFTER meshInstance is created
	if ground_material:
		meshInstance.set_surface_override_material(0, ground_material)

	add_child(meshInstance)

func _exit_tree():
	# Ensure thread cleanup before deletion
	if thread and thread.is_alive():
		thread.wait_to_finish()
		thread = null
