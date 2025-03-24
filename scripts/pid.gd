class_name PID

extends RefCounted

## PID Controller for general use
## Call `update(delta, target, current, p, i, d)` to get the control output

@export var integral_limit: float = INF # Limits the integral term to prevent windup

var _prev_error: float = 0.0
var _integral: float = 0.0

func reset():
	_prev_error = 0.0
	_integral = 0.0

func update(delta: float, target: float, current: float, p: float, i: float, d: float) -> float:
	var error = target - current
	
	# Proportional term
	var p_term = p * error
	
	# Integral term with windup guard
	_integral += error * delta
	_integral = clamp(_integral, -integral_limit, integral_limit)
	var i_term = i * _integral
	
	# Derivative term
	var derivative = (error - _prev_error) / delta if delta > 0 else 0.0
	var d_term = d * derivative
	
	_prev_error = error
	
	return p_term + i_term + d_term
