extends Node3D
class_name Chunk

static var active_threads := 0
const MAX_THREADS := 64

var meshInstance: MeshInstance3D
var noise: FastNoiseLite
var chunkX: int
var chunkZ: int
var chunkSize: int
var thread: Thread = null  # Initialized as null to prevent issues
var ground_material: Material

func _init(noiseParam: FastNoiseLite, chunkXParam: int, chunkZParam: int, chunkSizeParam: int):
	noise = noiseParam
	chunkX = chunkXParam
	chunkZ = chunkZParam
	chunkSize = chunkSizeParam

func _ready():
	# Only proceed if under thread limit
	if active_threads >= MAX_THREADS:
		# Defer chunk creation slightly
		await get_tree().create_timer(0.25).timeout
		_ready()  # retry
		return
	
	thread = Thread.new()
	var err = thread.start(_threaded_generate_chunk)
	if err != OK:
		push_error("Failed to start terrain generation thread")
	else:
		active_threads += 1

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
		thread = null
		active_threads = max(0, active_threads - 1)

func _generate_mesh() -> ArrayMesh:
	var planeMesh = PlaneMesh.new()
	planeMesh.size = Vector2(chunkSize, chunkSize)
	@warning_ignore("integer_division")
	planeMesh.subdivide_depth = chunkSize / 2
	@warning_ignore("integer_division")
	planeMesh.subdivide_width = chunkSize / 2

	var st = SurfaceTool.new()
	st.create_from(planeMesh, 0)
	# Commit the initial mesh only once
	var mesh = st.commit()

	var mdt = MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)
	var vertex_count = mdt.get_vertex_count()
	for i in range(vertex_count):
		var vertex = mdt.get_vertex(i)
		vertex.y = noise.get_noise_3d(vertex.x + chunkX, vertex.y, vertex.z + chunkZ) * 50
		mdt.set_vertex(i, vertex)
	mdt.commit_to_surface(mesh)
	
	# Reuse SurfaceTool to generate normals efficiently
	st.clear()
	st.create_from(mesh, 0)
	st.generate_normals()
	var final_mesh = st.commit()
	return final_mesh

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
