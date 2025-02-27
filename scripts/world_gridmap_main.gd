extends GridMap

@export var tile_size: int = 100  # Size of each grid tile (meters)
@export var max_height: int = 800  # Maximum terrain height (meters)
@export var render_distance: int = 3000  # Render up to 5km
@export var terrain_resolution: int = 50  # Number of tiles in X and Z
@export var terrain_texture: Texture2D  # Assign a terrain texture in the Inspector

var noise = FastNoiseLite.new()
var mesh_lib: MeshLibrary

func _ready():
	create_mesh_library()  # Create and assign a MeshLibrary
	setup_noise()
	generate_terrain()
	show()  # Ensure visibility

func create_mesh_library():
	mesh_lib = MeshLibrary.new()
	
	# Create a textured plane mesh
	var tile_mesh = PlaneMesh.new()
	tile_mesh.size = Vector2(tile_size, tile_size)
	tile_mesh.subdivide_width = 1
	tile_mesh.subdivide_depth = 1

	# Create a material with a texture
	var material = StandardMaterial3D.new()
	material.albedo_texture = terrain_texture
	material.uv1_scale = Vector3(1.0, 1.0, 1.0)  # Adjust to match grid scaling
	material.roughness = 1.0  # Reduce shine

	tile_mesh.surface_set_material(0, material)

	# Create collision shape
	var collision_shape = BoxShape3D.new()
	collision_shape.extents = Vector3(tile_size * 0.5, tile_size * 0.5, tile_size * 0.5)

	# Add tile to the MeshLibrary
	mesh_lib.create_item(0)  # Tile ID 0
	mesh_lib.set_item_mesh(0, tile_mesh)
	mesh_lib.set_item_shapes(0, [{ "shape": collision_shape, "transform": Transform3D.IDENTITY }])

	self.mesh_library = mesh_lib  # Assign to GridMap

func setup_noise():
	noise.seed = randi()
	noise.frequency = 0.002  # Lower frequency for larger terrain variation

func generate_terrain():
	for x in range(-terrain_resolution, terrain_resolution):
		for z in range(-terrain_resolution, terrain_resolution):
			var world_x = x * tile_size
			var world_z = z * tile_size
			
			# Only generate terrain within 5km radius
			if Vector2(world_x, world_z).length() > render_distance:
				continue  # Skip tiles outside the render distance

			var height = int((noise.get_noise_2d(x, z) + 1) * 0.5 * max_height)  # Normalize noise
			height = clamp(height, tile_size, max_height)  # Ensure a minimum height

			for y in range(height / tile_size):
				set_cell_item(Vector3i(x, y, z), 0)  # Place tile from MeshLibrary
