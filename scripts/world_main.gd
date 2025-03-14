extends Node3D

const CHUNK_SIZE = 32
const CHUNK_AMOUNT = 8

var noise: FastNoiseLite
var chunks = {}  # Stores active chunks
var ground_material = preload("res://textures/terrain.png")

var player_position: Vector3
var range_in = CHUNK_AMOUNT / 2.0
var range_out = range_in + 1.0
var launcher = Node # FOR DATA SHARE

func _ready():
	launcher = self.get_parent() # FOR DATA SHARE
	_initialize_noise()
	LAUCNHER_CHILD_SHARE_SET("world", "TARGET", get_node("Active_Target"))
	LAUCNHER_CHILD_SHARE_SET("world", "SPAWNER", get_node("Missile_Spawner"))


func _initialize_noise():
	noise = FastNoiseLite.new()
	noise.seed = randi_range(1, 1000000)
	noise.set_noise_type(FastNoiseLite.TYPE_PERLIN)
	noise.set_frequency(0.001)
	noise.set_fractal_gain(0.125)

func add_chunk(x: int, z: int):
	var key = Vector2i(x, z)
	if chunks.has(key):
		return  # Already exists, skip

	var chunk = Chunk.new(noise, x * CHUNK_SIZE, z * CHUNK_SIZE, CHUNK_SIZE)
	chunk.transform.origin = Vector3(x * CHUNK_SIZE, 0, z * CHUNK_SIZE)

	add_child(chunk)
	chunks[key] = chunk


func remove_chunk(x: int, z: int):
	var key = Vector2i(x, z)
	if chunks.has(key):
		var chunk = chunks[key]
		chunks.erase(key)
		chunk.queue_free()

func _physics_process(_delta):
	player_position = LAUCNHER_CHILD_SHARE_GET("player", "POS") # get player position
	if player_position == null:
		return
	var p_x = player_position.x / CHUNK_SIZE
	var p_z = player_position.z / CHUNK_SIZE
	
	# Remove far chunks
	for key in chunks.keys():
		var chunk_x = key.x
		var chunk_z = key.y
		if chunk_x < (p_x - range_out) or chunk_x > (p_x + range_out) or \
		   chunk_z < (p_z - range_out) or chunk_z > (p_z + range_out):
			remove_chunk(chunk_x, chunk_z)
	
	# Load nearby chunks
	for x in range(p_x - range_in, p_x + range_in):
		for z in range(p_z - range_in, p_z + range_in):
			add_chunk(x, z)


func LAUCNHER_CHILD_SHARE_SET(scene, key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data

func LAUCNHER_CHILD_SHARE_GET(scene, key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key]
		return data
