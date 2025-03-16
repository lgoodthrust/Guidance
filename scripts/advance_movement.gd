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
