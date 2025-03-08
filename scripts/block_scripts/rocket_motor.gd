extends Node3D
@export_subgroup("META_DATA")
@export var DATA = {
	"NAME": "Rocket_Motor",
	"MASS": 5,
	"UDLRTB": [-1,-1,0,0,0,0],
	"TYPE": 8
}

var rigid_node: RigidBody3D
var thrust_force: float = 3000.0
var fuel_blocks: int = 0

var msl_life: float = 0.0


func _ready():
	rigid_node = get_parent()
	fuel_blocks = rigid_node.fuel

func _physics_process(delta: float) -> void:
	msl_life += delta
	if msl_life < 2.0 + (fuel_blocks * 3.0):
		apply_thrust(delta)

func apply_thrust(_delta):
		var force = (transform.basis.y).normalized() * thrust_force
		rigid_node.apply_force(force, self.position)
