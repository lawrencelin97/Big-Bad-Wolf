class_name AOEAttack
extends Node3D

## Base class for ground-telegraphed AOE attacks (circle, cone, line, etc).
## Subclasses only need to override _get_boundary_points() and _is_inside();
## the telegraph visuals, terrain-conforming mesh, and damage resolution are
## all handled here and shared by every shape.

@export var radius: float = 6.0
@export var damage: int = 30
@export var telegraph_time: float = 1.0
@export var color: Color = Color(1, 0, 0)
@export var target_group: String = "player"
@export var ground_clearance: float = 0.03
@export var ring_thickness: float = 0.5

signal telegraph_started
signal attack_resolved(targets_hit: Array)

var terrain: Node
var pulse_tween: Tween

@onready var fill_mesh_instance: MeshInstance3D = $FillMesh
@onready var ring_mesh_instance: MeshInstance3D = $RingMesh
@onready var fill_material: StandardMaterial3D = fill_mesh_instance.material_override.duplicate()
@onready var ring_material: StandardMaterial3D = ring_mesh_instance.material_override.duplicate()

func _ready():
	# Duplicate materials so multiple attack instances don't share (and fight
	# over) the same alpha-pulse animation.
	fill_mesh_instance.material_override = fill_material
	ring_mesh_instance.material_override = ring_material
	fill_material.albedo_color = Color(color.r, color.g, color.b, fill_material.albedo_color.a)
	ring_material.albedo_color = Color(color.r, color.g, color.b, ring_material.albedo_color.a)

	terrain = get_tree().get_first_node_in_group("terrain")
	top_level = true   # ignore parent rotation/scale — stays flat and world-aligned
	visible = false

## Override in a derived class: return terrain-conforming boundary points
## (local offsets from this node's origin) that outline the shape's edge.
func _get_boundary_points(segments: int = 48) -> PackedVector3Array:
	push_error("AOEAttack subclasses must override _get_boundary_points()")
	return PackedVector3Array()

## Override in a derived class: true if a local offset (relative to this
## attack's origin, y ignored) falls inside the danger zone.
func _is_inside(local_offset: Vector3) -> bool:
	push_error("AOEAttack subclasses must override _is_inside()")
	return false

## Runs the full telegraph -> wait -> damage -> cleanup sequence at the given
## world position. Call as: await attack.execute(boss.global_position)
func execute(at_position: Vector3):
	global_position = at_position
	_rebuild_mesh()
	_show_telegraph()
	telegraph_started.emit()
	await get_tree().create_timer(telegraph_time).timeout
	_hide_telegraph()
	var hit = _resolve_damage()
	attack_resolved.emit(hit)
	queue_free()

func _terrain_height_at(world_x: float, world_z: float) -> float:
	if terrain and terrain.has_method("get_height_at"):
		return terrain.get_height_at(world_x, world_z)
	return global_position.y

func _resolve_damage() -> Array:
	var hit := []
	for body in get_tree().get_nodes_in_group(target_group):
		if not body is Node3D:
			continue
		var offset = body.global_position - global_position
		offset.y = 0
		if _is_inside(offset) and body.has_method("take_damage"):
			body.take_damage(damage)
			hit.append(body)
	return hit

func _rebuild_mesh():
	var outer = _get_boundary_points()
	var center_h = _terrain_height_at(global_position.x, global_position.z) + ground_clearance
	var center_local = Vector3(0, center_h - global_position.y, 0)

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(outer.size() - 1):
		st.add_vertex(center_local)
		st.add_vertex(outer[i])
		st.add_vertex(outer[i + 1])
	st.generate_normals()
	fill_mesh_instance.mesh = st.commit()

	# Edge ring: each boundary point pulled slightly toward center for a band.
	var st_ring = SurfaceTool.new()
	st_ring.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(outer.size() - 1):
		var a_len = max(outer[i].length(), 0.01)
		var b_len = max(outer[i + 1].length(), 0.01)
		var inner_a = outer[i].lerp(center_local, ring_thickness / a_len)
		var inner_b = outer[i + 1].lerp(center_local, ring_thickness / b_len)
		st_ring.add_vertex(inner_a)
		st_ring.add_vertex(outer[i])
		st_ring.add_vertex(outer[i + 1])
		st_ring.add_vertex(inner_a)
		st_ring.add_vertex(outer[i + 1])
		st_ring.add_vertex(inner_b)
	st_ring.generate_normals()
	ring_mesh_instance.mesh = st_ring.commit()

func _show_telegraph():
	visible = true
	fill_material.albedo_color.a = 0.12
	ring_material.albedo_color.a = 0.5

	if pulse_tween:
		pulse_tween.kill()
	pulse_tween = create_tween()
	pulse_tween.set_loops()
	# Pulses faster as the attack gets closer to landing.
	var pulse_speed = max(telegraph_time / 4.0, 0.15)
	pulse_tween.tween_property(fill_material, "albedo_color:a", 0.45, pulse_speed)
	pulse_tween.parallel().tween_property(ring_material, "albedo_color:a", 1.0, pulse_speed)
	pulse_tween.tween_property(fill_material, "albedo_color:a", 0.12, pulse_speed)
	pulse_tween.parallel().tween_property(ring_material, "albedo_color:a", 0.5, pulse_speed)

func _hide_telegraph():
	if pulse_tween:
		pulse_tween.kill()
	visible = false
