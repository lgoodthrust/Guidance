class_name ADV_MOVE

extends RefCounted

func torque_from_offset_force(transform: Transform3D, offset: Vector3, force: Vector3) -> Vector3:
	var world_point = transform.origin + transform.basis * offset
	var r = world_point - transform.origin
	
	var torque = r.cross(force)
	return torque

func torque_to_pos(delta: float, current_object: Node3D, current_forward_axis: Vector3, target_global_position: Vector3) -> Vector3:
	# Cached transform access to reduce repeated property lookups
	var gt = current_object.global_transform
	var origin = gt.origin
	var forward_dir = (gt.basis * current_forward_axis).normalized()
	var to_target = target_global_position - origin
	if to_target.length_squared() < 1e-6:
		return Vector3.ZERO  # early exit: too close to consider
	to_target = to_target.normalized()
	var angle = forward_dir.angle_to(to_target)
	if angle < 1e-3:
		return Vector3.ZERO  # tiny angle ignore threshold (consider constant)
	var axis = forward_dir.cross(to_target)
	if axis.length_squared() < 1e-6:
		return Vector3.ZERO
	axis = axis.normalized()
	return axis * angle * delta

# TODO: extract global_transform caching as helper to avoid duplicate code
func force_to_forward(delta: float, transform: Transform3D, current_forward_axis: Vector3, target_global_position: Vector3) -> Vector3:
	var to_target = target_global_position - transform.origin
	if to_target.length_squared() < 1e-6:
		return Vector3.ZERO
	to_target = to_target.normalized()
	var forward_dir = (transform.basis * current_forward_axis).normalized()  # ensure normalized before projection
	var proj = forward_dir.dot(to_target)
	if abs(proj) < 1e-6:
		return Vector3.ZERO
	return forward_dir * proj * delta

# Static rotation utilities (direct vs composed)
static func rotate_transform_about_point(transform: Transform3D, pivot: Vector3, rot_basis: Basis) -> Transform3D:
	var offset = transform.origin - pivot
	var new_origin = rot_basis * offset + pivot
	var new_basis = rot_basis * transform.basis
	return Transform3D(new_basis, new_origin)

static func rotate_transform_about_point_composed(transform: Transform3D, pivot: Vector3, rot_basis: Basis) -> Transform3D:
	# composed method allocates multiple Transforms; may impact performance in tight loops
	var to_origin = Transform3D(Basis(), -pivot)
	var rot_tf = Transform3D(rot_basis, Vector3.ZERO)
	var back = Transform3D(Basis(), pivot)
	return back * rot_tf * to_origin * transform
