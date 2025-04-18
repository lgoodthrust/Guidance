class_name SUM

extends RefCounted

var integral: float = 0.0
var history: Array = []

func reset():
	integral = 0.0
	history.clear()

func update(value: float, stack_size: int = 10, min_max: float = 10.0) -> float:
	# Add new value to history
	history.append(value)
	integral += value
	
	# Trim old values to maintain stack size
	if history.size() > stack_size:
		integral -= history.pop_front()
	
	# Clamp the integral to within ±min_max
	integral = clamp(integral, -min_max, min_max)
	
	return integral
