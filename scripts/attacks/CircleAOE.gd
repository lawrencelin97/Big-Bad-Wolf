class_name CircleAOE
extends AOEAttack

## Simple circular ground AOE, centered on this node.

func _get_boundary_points(segments: int = 48) -> PackedVector3Array:
	var points = PackedVector3Array()
	for i in range(segments + 1):
		var angle = i * TAU / segments
		var wx = global_position.x + cos(angle) * radius
		var wz = global_position.z + sin(angle) * radius
		var h = _terrain_height_at(wx, wz) + ground_clearance
		points.append(Vector3(wx - global_position.x, h - global_position.y, wz - global_position.z))
	return points

func _is_inside(local_offset: Vector3) -> bool:
	return local_offset.length() <= radius
