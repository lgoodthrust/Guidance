extends Node3D
@export_subgroup("META_DATA")
@export var DATA = {
	"NAME": "IR_Seeker",
	"MASS": 10,
	"LIFT": 0.0,
	"UDLRTB": [0,-1,0,0,0,0],
	"TYPE": 1
}


@export_subgroup("MAIN")
@export var horizontal_fov: float = 30.0
@export var vertical_fov: float = 30.0
@export var max_range: float = 8000.0
var XY: Vector2 = Vector2(0,0)
var TARGETING: bool = false

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
		return Vector2.INF

	# 2) Convert direction into local space (UP is now the scanning direction)
	var local_direction: Vector3 = global_transform.affine_inverse().basis * to_target.normalized()

	# 3) Calculate yaw and pitch in degrees
	# Since UP (+Y) is our scanning direction:
	var yaw_deg = rad_to_deg(atan2(local_direction.x, local_direction.y))  # X-axis relative to UP
	var pitch_deg = rad_to_deg(atan2(local_direction.z, local_direction.y))  # Z-axis relative to UP

	# 4) Check if within the horizontal/vertical half-FOV
	if abs(yaw_deg) <= horizontal_fov * 0.5 and abs(pitch_deg) <= vertical_fov * 0.5:
		return Vector2(yaw_deg, pitch_deg)
	else:
		return Vector2.INF

# Example usage: checks some "enemies" array each frame to see who is in range/FOV
func _physics_process(_delta: float):
	var enemy = get_tree().current_scene.get_node("World").get_node("Active_Target")
	if enemy:
		var angles = get_relative_angles_to_target(enemy.global_transform.origin)
		if angles != Vector2.INF:
			print("Detected enemy within FOV! Yaw =", angles.x, " Pitch =", angles.y)
			XY = Vector2(angles.x, angles.y)
		else:
			print("No enemy detected")
