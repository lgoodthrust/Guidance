class_name FEEDBACK
extends RefCounted

var integral: float = 0.0
var history: Array = []

var sum: float = 0.0
var sums: Array = []

var derivative: float = 0.0

func reset():
	integral = 0.0
	derivative = 0.0
	history.clear()

func update_sum(value: float, stack_size: int = 10) -> float:
	sums.append(value)
	if len(sums) > stack_size:
		sums.pop_front()
	var _count = 0.0
	for i in sums:
		_count += i
	sum = _count / len(sums)
	return sum

func update_i(value: float, stack_size: int = 10, min_max: float = 10.0) -> float:
	history.append(value)
	integral += value
	if history.size() > stack_size:
		integral -= history.pop_front()
	integral = clamp(integral, -min_max, min_max)
	return integral

func update_d(delta: float, error: float) -> float:
	var _derivative = (error - derivative) / delta
	derivative = error
	return _derivative
