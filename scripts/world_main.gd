extends Node3D
class_name WorldGenerator

const CHUNK_SIZE: int = 32
const CHUNK_AMOUNT: int = 16
const CHUNK_HEIGHT: float = 5.0
@warning_ignore("integer_division")
const RANGE_IN: int = CHUNK_AMOUNT / 2
const RANGE_OUT: int = RANGE_IN + 1

var noise: FastNoiseLite
var chunks: Dictionary = {}
var ground_tex: Texture = preload("res://textures/grass.png")
var ground_material: StandardMaterial3D
var launcher: Node

func _ready() -> void:
	launcher = get_parent()
	_initialize_noise()
	ground_material = StandardMaterial3D.new()
	ground_material.backlight_enabled = true
	ground_material.backlight = Color.WHITE
	ground_material.albedo_texture = ground_tex
	ground_material.roughness = 1.0
	ground_material.uv1_scale = Vector3(1, 1, 1)

func _physics_process(_delta: float) -> void:
	var player_pos = LAUCNHER_CHILD_SHARE_GET("player", "POS")
	if player_pos == null:
		return
	var cx = int(floor(player_pos.x / CHUNK_SIZE))
	var cz = int(floor(player_pos.z / CHUNK_SIZE))
	var min_x = cx - RANGE_IN
	var max_x = cx + RANGE_IN
	var min_z = cz - RANGE_IN
	var max_z = cz + RANGE_IN

	var to_remove: Array = []
	for key in chunks.keys():
		if key.x < min_x or key.x > max_x or key.y < min_z or key.y > max_z:
			to_remove.append(key)
	for key in to_remove:
		chunks[key].queue_free()
		chunks.erase(key)

	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var key = Vector2i(x, z)
			if not chunks.has(key):
				var world_x = x * CHUNK_SIZE
				var world_z = z * CHUNK_SIZE
				var chunk = Chunk.new(noise, world_x, world_z, CHUNK_SIZE, CHUNK_HEIGHT)
				chunk.transform.origin = Vector3(world_x, 0.0, world_z)
				chunk.ground_material = ground_material
				add_child(chunk)
				chunks[key] = chunk

func _initialize_noise() -> void:
	noise = FastNoiseLite.new()
	noise.seed = randi_range(1, 1000)
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.005
	noise.fractal_gain = 0.75

func add_chunk(x: int, z: int) -> void:
	var key = Vector2i(x, z)
	if chunks.has(key):
		return
	var chunk = Chunk.new(noise, x * CHUNK_SIZE, z * CHUNK_SIZE, CHUNK_SIZE, CHUNK_HEIGHT)
	chunk.transform.origin = Vector3(x * CHUNK_SIZE, 0.0, z * CHUNK_SIZE)
	chunk.ground_material = ground_material
	add_child(chunk)
	chunks[key] = chunk

func remove_chunk(x: int, z: int) -> void:
	var key = Vector2i(x, z)
	if chunks.has(key):
		chunks[key].queue_free()
		chunks.erase(key)

func LAUCNHER_CHILD_SHARE_SET(scene: String, key: String, data) -> void:
	if launcher and launcher.LAUCNHER_CHILD_SHARED_DATA.has(scene):
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data

func LAUCNHER_CHILD_SHARE_GET(scene: String, key: String):
	if launcher and launcher.LAUCNHER_CHILD_SHARED_DATA.has(scene):
		return launcher.LAUCNHER_CHILD_SHARED_DATA[scene].get(key, null)
	return null
