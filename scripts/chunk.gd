extends Node3D
class_name Chunk

var meshInstance
var noise
var chunkX
var chunkZ
var chunkSize

func _init(noiseParam, chunkXParam, chunkZParam, chunkSizeParam):
	noise = noiseParam
	chunkX = chunkXParam
	chunkZ = chunkZParam
	chunkSize = chunkSizeParam

func _ready():
	generateChunk()

func generateChunk():
	var planeMesh = PlaneMesh.new()
	planeMesh.size = Vector2(chunkSize, chunkSize)
	planeMesh.subdivide_depth = (chunkSize / 2)
	planeMesh.subdivide_width = (chunkSize / 2)

	var surfaceTool = SurfaceTool.new()
	var dataTool = MeshDataTool.new()
	surfaceTool.create_from(planeMesh, 0)
	var arrayPlane = surfaceTool.commit()
	dataTool.create_from_surface(arrayPlane, 0)

	for i in range(dataTool.get_vertex_count()):
		var vertex = dataTool.get_vertex(i)
		vertex.y = noise.get_noise_3d(vertex.x + chunkX, vertex.y, vertex.z + chunkZ) * 25
		dataTool.set_vertex(i, vertex)

	dataTool.commit_to_surface(arrayPlane)
	surfaceTool.begin(Mesh.PRIMITIVE_TRIANGLES)
	surfaceTool.create_from(arrayPlane, 1)
	surfaceTool.generate_normals()

	meshInstance = MeshInstance3D.new()
	meshInstance.mesh = surfaceTool.commit()
	meshInstance.create_trimesh_collision()
	meshInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(meshInstance)
