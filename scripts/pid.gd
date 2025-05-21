class_name PID
extends RefCounted

@export var integral_limit: float = INF # Prevents windup

var _prev_error: float = 0.0
var _integral: float = 0.0
var _history: Array = []

func reset():
	_prev_error = 0.0
	_integral = 0.0
	_history.clear()

func update(delta: float, target: float, current: float, p: float, i: float, d: float, I_COUNT: int = 10) -> float:
	var error = (target - current) * p
	
	# Proportional term
	var p_term = p * error
	
	# Integral term (integrated error * delta)
	var integrated_error = error * delta
	_history.append(integrated_error)
	_integral += integrated_error
	
	if _history.size() > I_COUNT:
		_integral -= _history.pop_front()
	_integral = clamp(_integral, -integral_limit, integral_limit)
	var i_term = i * _integral
	
	# Derivative term
	var derivative = (error - _prev_error) / delta
	var d_term = d * derivative
	
	_prev_error = error
	
	return p_term + i_term + d_term
