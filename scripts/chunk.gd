extends Node3D
class_name Chunk

static var active_threads: int = 0
static var thread_mutex: Mutex = Mutex.new()
const MAX_THREADS: int = 128
const LOD_DIVISIONS: int = 4
const TEX_TILE_SIZE: float = 1.0

var meshInstance: MeshInstance3D
var collisionShape: CollisionShape3D
var noise: FastNoiseLite
var chunkX: int
var chunkZ: int
var chunkSize: int
var thread: Thread = null
var ground_material: Material
var A: float

func _init(noiseParam: FastNoiseLite, x: int, z: int, size: int, height: float = 10.0) -> void:
	noise = noiseParam
	chunkX = x
	chunkZ = z
	chunkSize = size
	A = height

func _ready() -> void:
	if meshInstance == null:
		meshInstance = MeshInstance3D.new()
		meshInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(meshInstance)
	if collisionShape == null:
		collisionShape = CollisionShape3D.new()
		add_child(collisionShape)
	_try_launch_thread()

func _try_launch_thread() -> void:
	thread_mutex.lock()
	while active_threads >= MAX_THREADS:
		thread_mutex.unlock()
		await get_tree().create_timer(0.125).timeout
		if not is_inside_tree():
			return
		thread_mutex.lock()
	thread_mutex.unlock()
	thread = Thread.new()
	var err: int = thread.start(Callable(self, "_threaded_generate_chunk"))
	if err != OK:
		push_error("Failed to start terrain generation thread: %s" % err)
	else:
		thread_mutex.lock()
		active_threads += 1
		thread_mutex.unlock()

func _threaded_generate_chunk() -> void:
	var meshObj: ArrayMesh = _build_mesh_fast()
	call_deferred("_apply_mesh", meshObj)
	call_deferred("_cleanup_thread")

func _cleanup_thread() -> void:
	if thread:
		thread.wait_to_finish()
		thread = null
		thread_mutex.lock()
		active_threads = max(0, active_threads - 1)
		thread_mutex.unlock()

func _build_mesh_fast() -> ArrayMesh:
	@warning_ignore("integer_division")
	var div: int = chunkSize / LOD_DIVISIONS
	div = max(div, 1)
	var size: int = div + 1
	var inv_div: float = 1.0 / float(div)
	var step: float = float(chunkSize) * inv_div
	var half: float = float(chunkSize) * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for z_idx in range(size):
		var vz: float = z_idx * step - half
		var uv_v: float = z_idx * inv_div * TEX_TILE_SIZE
		for x_idx in range(size):
			var vx: float = x_idx * step - half
			var nv: float = noise.get_noise_2d(vx + chunkX, vz + chunkZ)
			var vy: float = nv * A
			var uv_u: float = x_idx * inv_div * TEX_TILE_SIZE
			st.set_uv(Vector2(uv_u, uv_v))
			st.add_vertex(Vector3(vx, vy, vz))

	for z_idx in range(div):
		for x_idx in range(div):
			var i: int = z_idx * (size) + x_idx
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + size)
			st.add_index(i + 1)
			st.add_index(i + size + 1)
			st.add_index(i + size)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()

func _apply_mesh(mesh: ArrayMesh) -> void:
	meshInstance.mesh = mesh
	meshInstance.create_trimesh_collision()
	if ground_material:
		meshInstance.set_surface_override_material(0, ground_material)
	collisionShape.shape = mesh.create_trimesh_shape()

func _exit_tree() -> void:
	if thread and thread.is_alive():
		thread_mutex.lock()
		active_threads = max(0, active_threads - 1)
		thread_mutex.unlock()
		thread.wait_to_finish()
		thread = null
