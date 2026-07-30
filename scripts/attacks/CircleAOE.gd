class_name CircleAOE
extends AOEAttack

## Simple circular ground AOE, centered on this node.

func _get_boundary_points(segment_count: int = 48) -> PackedVector3Array:
	var points = PackedVector3Array()
	for i in range(segment_count + 1):
		var angle = i * TAU / segment_count
		var wx = global_position.x + cos(angle) * radius
		var wz = global_position.z + sin(angle) * radius
		var h = _terrain_height_at(wx, wz) + ground_clearance
		points.append(Vector3(wx - global_position.x, h - global_position.y, wz - global_position.z))
	return points

func _create_shape() -> Shape3D:
	var shape = CylinderShape3D.new()
	shape.radius = radius
	shape.height = collision_height
	return shape
