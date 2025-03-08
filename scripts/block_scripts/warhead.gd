extends Node3D
@export_subgroup("META_DATA")
@export var DATA = {
	"NAME": "Warhead",
	"MASS": 10,
	"UDLRTB": [-1,-1,0,0,0,0],
	"TYPE": 3
}


@export_subgroup("MAIN")
@export var max_prox_range: float = 30.0
var TRIGGERED: bool = false

func _ready():
	pass

func _process(_delta: float) -> void:
	pass
	
func _physics_process(_delta: float):
	pass
