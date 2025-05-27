class_name visulizer
extends RefCounted

func pos_rot(obj: Node, TA: Vector3, TB: Vector3) -> Dictionary:
	var center_pos: Vector3 = lerp(TA, TB, 0.5)
	var point_dir: Vector3 = (TA - TB).normalized()
	var point_len: float = (TA - TB).length()
	
	var rot: Basis = obj.basis.looking_at(point_dir, Vector3.UP)
	
	var stuff = {
		"trans": Transform3D(rot, center_pos),
		"len":point_len
	}
	
	return stuff
