extends Node3D
class_name Chunk

static var active_threads: int = 0
const MAX_THREADS : int = 128
const LOD_DIVISIONS : int = 4
const TEX_TILE_SIZE : float = 1.0

var meshInstance : MeshInstance3D
var noise : FastNoiseLite
var chunkX : int
var chunkZ : int
var chunkSize : int
var thread : Thread = null
var ground_material: Material
var A : float

func _init(noiseParam: FastNoiseLite, x: int, z: int, size: int, height: float=10.0) -> void:
	noise = noiseParam
	chunkX = x
	chunkZ = z
	chunkSize = size
	A = height

func _ready() -> void:
	_try_launch_thread()
	
func _try_launch_thread() -> void:
	if active_threads >= MAX_THREADS:
		await get_tree().create_timer(0.125).timeout
		if is_inside_tree():
			_try_launch_thread()
		return
	
	thread = Thread.new()
	var err: int = thread.start(_threaded_generate_chunk)
	if err != OK:
		push_error("Failed to start terrain generation thread: %s" % err)
	else:
		active_threads += 1

func _threaded_generate_chunk() -> void:
	var mesh: ArrayMesh = _build_mesh_one_pass()
	call_deferred("_apply_mesh", mesh)
	call_deferred("_cleanup_thread")

func _cleanup_thread() -> void:
	if thread:
		thread.wait_to_finish()
		thread = null
		active_threads = max(0, active_threads - 1)

func _build_mesh_one_pass() -> ArrayMesh:
	@warning_ignore("integer_division")
	var div : int = chunkSize / LOD_DIVISIONS
	var step: float = float(chunkSize) / float(div)
	var half: float = chunkSize * 0.5
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for z: int in range(div + 1):
		var vz : float = z * step - half
		var uv_v : float = (float(z) / float(div)) * TEX_TILE_SIZE
		for x: int in range(div + 1):
			var vx : float = x * step - half
			var vy : float = noise.get_noise_2d(vx + chunkX, vz + chunkZ) * A
			var uv_u : float = (float(x) / float(div)) * TEX_TILE_SIZE
			
			st.set_uv(Vector2(uv_u, uv_v))
			st.add_vertex(Vector3(vx, vy, vz))
	
	for z: int in range(div):
		for x: int in range(div):
			var i: int = z * (div + 1) + x
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + div + 1)
			
			st.add_index(i + 1)
			st.add_index(i + div + 2)
			st.add_index(i + div + 1)
	
	st.generate_normals()
	st.generate_tangents()
	return st.commit()

func _apply_mesh(mesh: ArrayMesh) -> void:
	meshInstance = MeshInstance3D.new()
	meshInstance.mesh = mesh
	meshInstance.create_trimesh_collision()
	meshInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	if ground_material:
		meshInstance.set_surface_override_material(0, ground_material)
	
	add_child(meshInstance)

func _exit_tree() -> void:
	if thread and thread.is_alive():
		thread.wait_to_finish()
		thread = null
