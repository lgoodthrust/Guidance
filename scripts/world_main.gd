extends Node3D

const chunk_size = 32
const chunk_amount = 8

var noise: FastNoiseLite
var chunks = {}
var unready_chunks = {}
var ground = preload("res://textures/terrain.png")
var range_in = chunk_amount / float(2)
var range_out = range_in + 1
var player_position: Vector3


func _ready():
	
	var sed = randi_range(1, 1000000)
	noise = FastNoiseLite.new()
	noise.seed = sed
	noise.set_noise_type(FastNoiseLite.TYPE_PERLIN)
	noise.set_frequency(0.001) # hillness... hill factor... idk
	noise.set_fractal_gain(0.125) # hill roughness
	

func add_chunk(x, z):
	var key = str(x) + "," + str(z)
	if chunks.has(key) or unready_chunks.has(key):
		return
	
	_load_chunk(x, z)
	unready_chunks[key] = 1

func _load_chunk(x, z):
	var chunk = Chunk.new(noise, x * chunk_size, z * chunk_size, chunk_size)
	chunk.transform.origin = Vector3(x * chunk_size, 0, z * chunk_size)
	add_child(chunk)
	chunk.meshInstance.set_surface_override_material(0, ground)
	chunks[str(x) + "," + str(z)] = chunk

func _physics_process(_delta):
	var player_translation = player_position
	var p_x = player_translation.x / chunk_size
	var p_z = player_translation.z / chunk_size
	
	for chunk_hash in chunks:
		var chunk = chunks[chunk_hash]
		var chunk_x = chunk.transform.origin.x / chunk_size
		var chunk_z = chunk.transform.origin.z / chunk_size
		
		if chunk_x < (p_x - range_out) or chunk_x > (p_x + range_out)\
		or chunk_z < (p_z - range_out) or chunk_z > (p_z + range_out):
			chunks.erase(chunk_hash)
			unready_chunks.erase(chunk_hash)
			remove_child(chunk)
			
	
	for x in range(p_x - range_in, p_x + range_in):
		for z in range(p_z - range_in, p_z + range_in):
			add_chunk(x, z)

func receive_data(data):
	player_position = data
	
