extends Node3D

const CHUNK_SIZE = 32
const CHUNK_AMOUNT = 8

var noise: FastNoiseLite
var chunks: Dictionary = {}  # Vector2i → Chunk
var ground_tex = preload("res://textures/terrain.png")
var ground_material: StandardMaterial3D

var launcher: Node  # FOR DATA SHARE
@warning_ignore("integer_division")
var range_in: int = CHUNK_AMOUNT / 2
var range_out: int = range_in + 1

# -- optional cache for extra anchors read from the launcher
var extra_anchors : PackedVector2Array = PackedVector2Array()  # keeps uniques

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
	
	extra_anchors.clear()  #  start fresh every tick
	_collect_missile_anchors()  #  (fills extra_anchors)
	
	var anchors : PackedVector2Array = PackedVector2Array()
	anchors.push_back(Vector2(player_pos.x, player_pos.z))
	anchors.append_array(extra_anchors)
	
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

# Pull EVERY valid missile as an anchor and avoid duplicates.
func _collect_missile_anchors():
	if not launcher or not launcher.LAUCNHER_CHILD_SHARED_DATA.has("world"):
		return
	var missiles: Array = launcher.LAUCNHER_CHILD_SHARED_DATA["world"].get("missiles", [])
	
	for m:Node3D in missiles:
		if m.get_child_count() > 1:
			var body:RigidBody3D = m.get_child(0)
			if body and is_instance_valid(body):
				if body.linear_velocity.length() > 685.0:
					continue  # too fast, ignore for terrain anchoring
				
				var pos := Vector2(body.global_position.x, body.global_position.z)
				if not extra_anchors.has(pos):
					extra_anchors.append(pos)

func _initialize_noise():
	noise = FastNoiseLite.new()
	noise.seed = randi_range(1, 1_000_000)
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.001
	noise.fractal_gain = 0.125

func add_chunk(x: int, z: int) -> void:
	var key := Vector2i(x, z)
	if chunks.has(key):
		return
	var chunk := Chunk.new(noise, x * CHUNK_SIZE, z * CHUNK_SIZE, CHUNK_SIZE)
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
