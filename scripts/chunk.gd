extends Node3D
class_name Chunk

const MAX_THREADS: int = 128
const LOD_DIVISIONS: int = 4
const TEX_TILE_SIZE: float = 1.0

static var thread_semaphore: Semaphore = Semaphore.new()
static var _semaphore_init: bool = false

var noise_template: FastNoiseLite
var chunkX: int
var chunkZ: int
var chunkSize: int
var height_amp: float
var ground_material: Material

var meshInstance: MeshInstance3D
var collisionShape: CollisionShape3D
var thread: Thread

func _init(noiseParam: FastNoiseLite, x: int, z: int, size: int, height: float = 10.0) -> void:
	noise_template = noiseParam
	chunkX = x
	chunkZ = z
	chunkSize = size
	height_amp = height

func _ready() -> void:
	if not _semaphore_init:
		for _i in range(MAX_THREADS):
			thread_semaphore.post()
		_semaphore_init = true
	
	meshInstance = MeshInstance3D.new()
	meshInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(meshInstance)
	
	collisionShape = CollisionShape3D.new()
	add_child(collisionShape)
	
	_spawn_build_thread()

func _exit_tree() -> void:
	if thread and thread.is_alive():
		thread.wait_to_finish()
		thread = null
		thread_semaphore.post()

func _spawn_build_thread() -> void:
	if not thread_semaphore.try_wait():
		call_deferred("_spawn_build_thread")
		return
	thread = Thread.new()
	var err: int = thread.start(Callable(self, "_threaded_generate_chunk"))
	if err != OK:
		push_error("Failed to start terrain thread: %s" % err)
		thread_semaphore.post()

func _cleanup_thread() -> void:
	if thread:
		thread.wait_to_finish()
		thread = null
	thread_semaphore.post()

func _threaded_generate_chunk() -> void:
	var local_noise: FastNoiseLite = noise_template.duplicate()
	var mesh: ArrayMesh = _build_mesh_fast(local_noise)
	call_deferred("_apply_mesh", mesh)
	call_deferred("_cleanup_thread")

func _build_mesh_fast(n: FastNoiseLite) -> ArrayMesh:
	@warning_ignore("integer_division")
	var div: int = max(chunkSize / LOD_DIVISIONS, 1)
	var size: int = div + 1
	var inv_div: float = 1.0 / float(div)
	var step: float = float(chunkSize) * inv_div
	var half: float = float(chunkSize) * 0.5
	
	var vert_cnt: int = size * size
	var tri_cnt: int = div * div * 6
	
	var vertices: PackedVector3Array = PackedVector3Array()
	vertices.resize(vert_cnt)
	var uvs: PackedVector2Array = PackedVector2Array()
	uvs.resize(vert_cnt)
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize(tri_cnt)
	
	var idx: int = 0
	for z_idx in range(size):
		var vz: float = z_idx * step - half
		var uv_v: float = z_idx * inv_div * TEX_TILE_SIZE
		for x_idx in range(size):
			var vx: float = x_idx * step - half
			var uv_u: float = x_idx * inv_div * TEX_TILE_SIZE
			var vy: float = n.get_noise_2d(vx + chunkX, vz + chunkZ) * height_amp
			vertices[idx] = Vector3(vx, vy, vz)
			uvs[idx] = Vector2(uv_u, uv_v)
			idx += 1
	
	idx = 0
	for z_idx in range(div):
		var base: int = z_idx * size
		for x_idx in range(div):
			var i0: int = base + x_idx
			var i1: int = i0 + 1
			var i2: int = i0 + size
			var i3: int = i2 + 1
			indices[idx + 0] = i0
			indices[idx + 1] = i1
			indices[idx + 2] = i2
			indices[idx + 3] = i1
			indices[idx + 4] = i3
			indices[idx + 5] = i2
			idx += 6
	
	var normals: PackedVector3Array = _calculate_normals(vertices, indices)
	
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# Generate tangents if a normal-map is present
	if ground_material is StandardMaterial3D and (ground_material as StandardMaterial3D).normal_texture:
		mesh.generate_tangents()
	elif ground_material is ORMMaterial3D and (ground_material as ORMMaterial3D).normal_texture:
		mesh.generate_tangents()
	
	return mesh

func _calculate_normals(verts: PackedVector3Array, inds: PackedInt32Array) -> PackedVector3Array:
	var norms: PackedVector3Array = PackedVector3Array()
	norms.resize(verts.size())
	for i in range(0, inds.size(), 3):
		var i0: int = inds[i]
		var i1: int = inds[i + 1]
		var i2: int = inds[i + 2]
		var n: Vector3 = (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
		if n.length_squared() > 0.0:
			n = n.normalized()
		norms[i0] += n
		norms[i1] += n
		norms[i2] += n
	for v in range(norms.size()):
		norms[v] = norms[v].normalized()
	return norms

func _apply_mesh(mesh: ArrayMesh) -> void:
	meshInstance.mesh = mesh
	if ground_material:
		meshInstance.set_surface_override_material(0, ground_material)
	
	meshInstance.create_trimesh_collision()
	collisionShape.shape = mesh.create_trimesh_shape()
