extends Node3D

const CHUNK_SIZE = 32
const CHUNK_AMOUNT = 16
const CHUNK_HEIGHT = 5.0

var noise: FastNoiseLite
var chunks: Dictionary = {}  # Vector2i → Chunk
var ground_tex = preload("res://textures/grass.png")
var ground_material: StandardMaterial3D

var launcher: Node  # FOR DATA SHARE
@warning_ignore("integer_division")
var range_in: int = CHUNK_AMOUNT / 2
var range_out: int = range_in + 1

var obj: MeshInstance3D = MeshInstance3D.new()
var bm: BoxMesh = BoxMesh.new()

func _ready() -> void:
	launcher = get_parent()
	_initialize_noise()
	
	LAUCNHER_CHILD_SHARE_SET("world", "SPAWNER",  get_node("Missile_Spawner"))
	
	ground_material = StandardMaterial3D.new()
	ground_material.albedo_texture = ground_tex
	ground_material.roughness = 1.0
	ground_material.uv1_scale = Vector3(1, 1, 1)

func _physics_process(_delta: float) -> void:
	var player_pos : Vector3 = LAUCNHER_CHILD_SHARE_GET("player", "POS")
	if player_pos == null:
		return
	
	var anchors : PackedVector2Array = PackedVector2Array()
	anchors.push_back(Vector2(player_pos.x, player_pos.z))
	
	# ---------- build set of required chunks ----------
	var required : Dictionary = {}  # Set<Vector2i>
	for pos in anchors:
		var cx : int = int(floor(pos.x / CHUNK_SIZE))
		var cz : int = int(floor(pos.y / CHUNK_SIZE))
		for x in range(cx - range_in, cx + range_in + 1):
			for z in range(cz - range_in, cz + range_in + 1):
				required[Vector2i(x, z)] = true
	# ---------- unload / load ----------
	for key in chunks.keys():
		if not required.has(key):
			remove_chunk(key.x, key.y)
	for key in required.keys():
		if not chunks.has(key):
			add_chunk(key.x, key.y)

func _initialize_noise():
	noise = FastNoiseLite.new()
	noise.seed = randi_range(1, 1_000)
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.005
	noise.fractal_gain = 0.75

func add_chunk(x: int, z: int) -> void:
	var key := Vector2i(x, z)
	if chunks.has(key):
		return
	var chunk := Chunk.new(noise, x * CHUNK_SIZE, z * CHUNK_SIZE, CHUNK_SIZE, CHUNK_HEIGHT)
	chunk.transform.origin = Vector3(x * CHUNK_SIZE, 0, z * CHUNK_SIZE)
	chunk.ground_material = ground_material
	add_child(chunk)
	chunks[key] = chunk

func remove_chunk(x: int, z: int) -> void:
	var key := Vector2i(x, z)
	if chunks.has(key):
		chunks[key].queue_free()
		chunks.erase(key)

func LAUCNHER_CHILD_SHARE_SET(scene, key, data):
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key] = data

func LAUCNHER_CHILD_SHARE_GET(scene, key):
	if launcher:
		return launcher.LAUCNHER_CHILD_SHARED_DATA[scene][key]
