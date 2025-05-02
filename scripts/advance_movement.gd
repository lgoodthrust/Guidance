class_name ADV_MOVE

extends RefCounted

# returns vector3 torque that can be applied to an "apply_torque()" function
# returns the "torque stuff" that will rotate an object toward a position
func torque_to_pos(delta:float, current_object:Node3D, current_forward_axis:Vector3, target_global_position:Vector3) -> Vector3:
	var co_go = current_object.global_transform.origin
	var co_fgb = current_object.global_transform.basis * current_forward_axis
	
	# Get direction vector to target
	var to_target = (target_global_position - co_go).normalized()
	
	# Compute the rotation axis using the cross product
	var rotation_axis = co_fgb.cross(to_target).normalized()
	
	# Compute the angle between the forward direction and the target direction
	var angle = co_fgb.angle_to(to_target)
	
	# Compute torque (proportional to angle & frame time)
	var torque = rotation_axis * angle * delta
	
	# Handle edge cases (no rotation needed or invalid axis)
	if rotation_axis.is_zero_approx():
		return Vector3.ZERO  # No rotation needed
	
	var output = torque
	
	return output

# returns vector3 force that can be applied to an "apply_force()" function
# returns the "force stuff" that will apply a force that to move an object to its forward vector3
func force_to_forward(delta:float, current_object:Node3D, current_forward_axis:Vector3, target_global_position:Vector3) -> Vector3:
	var co_go = current_object.global_transform.origin
	var co_fgb = current_object.global_transform.basis * current_forward_axis
	
	# Get direction vector to target
	var to_target = (target_global_position - co_go).normalized()
	
	# Project target movement direction onto the forward axis
	var force_direction = co_fgb.project(to_target).normalized()
	
	# Compute force (proportional to force strength and delta time)
	var force = force_direction * delta
	
	# Handle edge cases (no force needed or invalid axis)
	if force.is_zero_approx():
		return Vector3.ZERO  # No force needed
	
	var output = force
	
	return output

# rot pos offset
func get_offset_position(origin: Vector3, basis: Basis, local_offset: Vector3) -> Vector3:
	var transform = Transform3D(basis, origin)
	return transform * local_offset

# Returns a torque vector to rotate an object so its forward axis points toward a target position
func torque_to_position(
	object: RigidBody3D,
	target: Vector3,
	forward:Vector3=-Vector3.FORWARD,
	P:float=12.0,
	D:float=2.0
	) -> Vector3:
	# Desired world-space direction (unit)
	var to_target: Vector3 = (target - object.global_transform.origin).normalized()
	
	# Current world-space direction of the chosen local vector (unit)
	var v_current: Vector3 = (object.global_transform.basis * forward).normalized()
	
	# Angle error
	var dot_val: float = clamp(v_current.dot(to_target), -1.0, 1.0)
	var angle_err: float = acos(dot_val)            # radians  (0‥π)
	if angle_err < 1e-5:
		return Vector3.ZERO                         # already aligned
	
	# Rotation axis (handle the 180° anti-parallel case)
	var axis: Vector3 = v_current.cross(to_target)
	if axis.length_squared() < 1e-8:                # vectors are opposite
		axis = v_current.cross(Vector3.RIGHT)
		if axis.length_squared() < 1e-8:
			axis = v_current.cross(Vector3.UP)
	axis = axis.normalized()
	
	# Proportional term (τ = k_p · θ · axis)
	var torque_p: Vector3 = axis * angle_err * P
	
	# Derivative term (damp current spin around *any* axis)
	var torque_d: Vector3 = -object.angular_velocity * D
	
	return torque_p + torque_d

# returns vector3 torque that can be applied to an "apply_torque()" function
# returns the "torque stuff" that will rotate an object toward a vector3
func forward_to_force(delta:float, current_object:RigidBody3D, current_forward_axis:Vector3) -> Vector3:
	var co_fgb = current_object.global_transform.basis * current_forward_axis
	var co_velvec = current_object.linear_velocity.normalized()

	# Compute the rotation axis using the cross product
	var rotation_axis = co_fgb.cross(co_velvec).normalized()

	# Compute the angle between the forward direction and velocity direction
	var angle = co_fgb.angle_to(co_velvec)

	# Compute torque (proportional to angle & frame time)
	var torque = rotation_axis * angle * delta

	# Handle edge cases (no rotation needed or invalid axis)
	if rotation_axis.is_zero_approx():
		return Vector3.ZERO  # No rotation needed
	
	var output = torque
	
	return output

func roll_pd(object: RigidBody3D, target_roll: float, kp: float = 10.0, kd: float = 2.0) -> Vector3:
	var angle = object.global_transform.basis
	var f = object.basis.z.normalized()
	var r = f.cross(Vector3.UP)
	if r.length_squared() < 1e-4:
		r = f.cross(Vector3.RIGHT)
	r = r.normalized()
	var u = r.cross(f)
	
	var cur = atan2(object.basis.y.dot(r),object.basis.y.dot(u))
	var err := wrapf(target_roll - cur, -PI, PI)
	
	var torque = f * (err * kp - object.angular_velocity.dot(f) * kd)
	return torque

# returns vector3 roll, pitch, and yaw of an object
# returns roll pitch and yaw angles of an object
func forward_rpy(current_object:Node3D, current_forward_axis:Vector3) -> Vector3:
	var co_fgb = current_object.global_transform.basis * current_forward_axis

	# Extract roll, pitch, and yaw from the basis
	var yaw = atan2(co_fgb[0].z, co_fgb[2].z)  # Yaw (rotation around Y-axis)
	var pitch = asin(-co_fgb[1].z)  # Pitch (rotation around X-axis)
	var roll = atan2(co_fgb[1].x, co_fgb[1].y)  # Roll (rotation around Z-axis)
	
	var r = rad_to_deg(roll)
	var p = rad_to_deg(pitch)
	var y = rad_to_deg(yaw)
	
	var output = Vector3(r, p, y)
	
	return output

# return the x,y angle of a of an object reletive to the forward direction of another object
func get_target_angles_in_degrees(current_object: Node3D, current_forward_axis: Vector3, current_right_axis: Vector3, current_up_axis: Vector3, target: Node3D) -> Vector2:
	var co_go = current_object.global_transform.origin
	var co_fgb = current_object.global_transform.basis * current_forward_axis
	var co_rgb = current_object.global_transform.basis * current_right_axis
	var co_ugb = current_object.global_transform.basis * current_up_axis
	
	# Vectors from the current object to the target
	var to_target = (target.global_transform.origin - co_go).normalized()
	
	# Horizontal angle (yaw-like): using right and forward axis
	var horizontal_angle_radians = atan2(to_target.dot(co_rgb), to_target.dot(co_fgb))
	var horizontal_angle_degrees = rad_to_deg(horizontal_angle_radians)
	
	# Vertical angle (pitch-like): using up and forward axis
	var vertical_angle_radians = atan2(to_target.dot(co_ugb), to_target.dot(co_fgb))
	var vertical_angle_degrees = rad_to_deg(vertical_angle_radians)
	
	return Vector2(horizontal_angle_degrees, vertical_angle_degrees)
