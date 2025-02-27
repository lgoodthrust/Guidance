extends GridMap

@export var tile_size: int = 50  # Size of each grid tile (meters)
@export var max_height: int = 50  # Maximum terrain height (meters)
@export var render_distance: int = 2000  # Render up to 5km
@export var terrain_resolution: int = 10  # Number of tiles in X and Z
@export var terrain_texture: Texture2D  # Assign a terrain texture in the Inspector

var noise = FastNoiseLite.new()
var mesh_lib: MeshLibrary
var static_node: StaticBody3D  # Holds all collision shapes
var concave_shape: ConcavePolygonShape3D  # Optimized terrain collision

func _ready():
	static_node = StaticBody3D.new()
	static_node.name = "Static"
	add_child(static_node)  # Attach StaticBody3D to this node

	create_mesh_library()  # Create and assign a MeshLibrary
	setup_noise()
	generate_terrain()
	generate_collision()  # Generates a single optimized collision shape
	show()  # Ensure visibility

func create_mesh_library():
	mesh_lib = MeshLibrary.new()
	
	# Create a textured plane mesh
	var tile_mesh = PlaneMesh.new()
	tile_mesh.size = Vector2(tile_size, tile_size)

	# Create a material with a texture
	var material = StandardMaterial3D.new()
	material.albedo_texture = terrain_texture
	material.uv1_scale = Vector3(30,30,30)  # Adjust to match grid scaling
	material.roughness = 1.0  # Reduce shine
	material.texture_repeat = StandardMaterial3D.TEXTURE_FILTER_LINEAR

	tile_mesh.surface_set_material(0, material)

	# Add tile to the MeshLibrary
	mesh_lib.create_item(0)  # Tile ID 0
	mesh_lib.set_item_mesh(0, tile_mesh)

	self.mesh_library = mesh_lib  # Assign to GridMap

func setup_noise():
	noise.seed = randi()
	noise.frequency = 0.01  # Lower frequency for larger terrain variation

func generate_terrain():
	for x in range(-terrain_resolution, terrain_resolution):
		for z in range(-terrain_resolution, terrain_resolution):
			var world_x = x * tile_size
			var world_z = z * tile_size
			
			# Only generate terrain within render distance
			if Vector2(world_x, world_z).length() > render_distance:
				continue  # Skip tiles outside the render distance

			var height = int((noise.get_noise_2d(x, z) + 1) * 0.5 * max_height)  # Normalize noise
			height = clamp(height, tile_size, max_height)  # Ensure a minimum height

			for y in range(height / tile_size):
				set_cell_item(Vector3i(x, y, z), 0)  # Place tile from MeshLibrary

func generate_collision():
	# Collect all vertex data for collision
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	for cell in get_used_cells():
		var world_pos = map_to_local(cell)

		# Create quad faces for each tile
		var v0 = world_pos + Vector3(-tile_size * 0.5, 0, -tile_size * 0.5)
		var v1 = world_pos + Vector3(tile_size * 0.5, 0, -tile_size * 0.5)
		var v2 = world_pos + Vector3(tile_size * 0.5, 0, tile_size * 0.5)
		var v3 = world_pos + Vector3(-tile_size * 0.5, 0, tile_size * 0.5)

		surface_tool.add_vertex(v0)
		surface_tool.add_vertex(v1)
		surface_tool.add_vertex(v2)
		surface_tool.add_vertex(v2)
		surface_tool.add_vertex(v3)
		surface_tool.add_vertex(v0)

	# Generate the final collision mesh
	var mesh = surface_tool.commit()
	concave_shape = ConcavePolygonShape3D.new()
	concave_shape.set_faces(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])

	# Create a single `CollisionShape3D` for the terrain
	var col_shape = CollisionShape3D.new()
	col_shape.shape = concave_shape
	static_node.add_child(col_shape)
