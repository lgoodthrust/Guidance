extends Node3D

@export var horizontal_fov: float = 30.0
@export var vertical_fov: float = 30.0
@export var max_range: float = 8000.0

func _ready():
	# Optional: any initialization you need
	pass

# Call this function to check if a given target (by its position) is
# within range and within the FOV of this seeker. If so, returns
# a Vector2(yaw_degrees, pitch_degrees), otherwise returns null.
func get_relative_angles_to_target(target_global_position: Vector3) -> Vector2:
	var to_target: Vector3 = target_global_position - global_transform.origin
	var distance: float = to_target.length()

	# 1) Check if within max detection range
	if distance > max_range:
		return Vector2(0,0)

	# 2) Convert direction into local space
	#    (Assuming 'forward' is -Z in your missile orientation).
	var local_direction: Vector3 = global_transform.basis * to_target.normalized()

	# 3) Calculate yaw and pitch in degrees.
	var yaw_deg   = rad_to_deg(atan2(local_direction.x, local_direction.z))
	var pitch_deg = rad_to_deg(asin(-local_direction.y))  # Negative sign if forward is -Z

	# 4) Check if within the horizontal/vertical half-FOV
	if abs(yaw_deg) <= horizontal_fov * 0.5 and abs(pitch_deg) <= vertical_fov * 0.5:
		return Vector2(yaw_deg, pitch_deg)
	else:
		return Vector2(0,0)

# Example usage: checks some "enemies" array each frame to see who is in range/FOV
func _physics_process(_delta: float):
	var enemies := get_tree().get_nodes_in_group("enemies")  # or however you track targets
	for enemy in enemies:
		if enemy is Node3D:
			var angles = get_relative_angles_to_target(enemy.global_transform.origin)
			if angles != null:
				print("Detected enemy within FOV! Yaw =", angles.x, " Pitch =", angles.y)
			# else: out of range/FOV
