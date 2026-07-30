class_name AOEAttack
extends Node3D

## Base class for ground-telegraphed AOE attacks (circle, cone, line, etc).
## Subclasses override:
##   _get_boundary_points() — terrain-conforming edge points, for the visuals
##   _create_shape()        — a Shape3D used as the actual damage volume
## The telegraph animation (static ring + sweeping fill) and damage
## resolution (via Area3D overlap) are shared by every shape.

@export var radius: float = 6.0
@export var damage: int = 30
@export var telegraph_time: float = 1.0     # time for the fill to sweep from empty to full
@export var color: Color = Color(1, 0, 0)
@export var target_group: String = "player"
@export var ground_clearance: float = 0.03
@export var ring_thickness: float = 0.5
@export var ring_alpha: float = 0.7
@export var fill_alpha: float = 0.35
@export var segments: int = 48
@export var collision_height: float = 12.0  # vertical extent of the damage volume

signal telegraph_started
signal attack_resolved(targets_hit: Array)

var terrain: Node
var fill_tween: Tween
var cached_boundary: PackedVector3Array

@onready var fill_mesh_instance: MeshInstance3D = $FillMesh
@onready var ring_mesh_instance: MeshInstance3D = $RingMesh
@onready var fill_material: StandardMaterial3D = fill_mesh_instance.material_override.duplicate()
@onready var ring_material: StandardMaterial3D = ring_mesh_instance.material_override.duplicate()
@onready var damage_area: Area3D = $DamageArea
@onready var collision_shape: CollisionShape3D = $DamageArea/CollisionShape3D

func _ready():
	# Duplicate materials so multiple attack instances don't share state.
	fill_mesh_instance.material_override = fill_material
	ring_mesh_instance.material_override = ring_material
	fill_material.albedo_color = Color(color.r, color.g, color.b, fill_alpha)
	ring_material.albedo_color = Color(color.r, color.g, color.b, ring_alpha)

	terrain = get_tree().get_first_node_in_group("terrain")
	top_level = true   # ignore parent rotation/scale — stays flat and world-aligned
	visible = false

	collision_shape.shape = _create_shape()
	damage_area.monitoring = true
	damage_area.monitorable = false

## Override in a derived class: terrain-conforming boundary points (local
## offsets from this node's origin) outlining the shape's edge.
func _get_boundary_points(segment_count: int = 48) -> PackedVector3Array:
	push_error("AOEAttack subclasses must override _get_boundary_points()")
	return PackedVector3Array()

## Override in a derived class: the physics volume used to detect who's
## standing in the danger zone (e.g. CylinderShape3D for a circle,
## BoxShape3D for a line, a custom ConvexPolygonShape3D for a cone).
func _create_shape() -> Shape3D:
	push_error("AOEAttack subclasses must override _create_shape()")
	return null

## Runs the full telegraph -> sweep-completes -> damage -> cleanup sequence
## at the given world position. Call as: await attack.execute(boss.global_position)
func execute(at_position: Vector3):
	global_position = at_position
	await _show_telegraph()
	visible = false
	var hit = _resolve_damage()
	attack_resolved.emit(hit)
	queue_free()

func _terrain_height_at(world_x: float, world_z: float) -> float:
	if terrain and terrain.has_method("get_height_at"):
		return terrain.get_height_at(world_x, world_z)
	return global_position.y

func _resolve_damage() -> Array:
	var hit := []
	for body in damage_area.get_overlapping_bodies():
		if body.is_in_group(target_group) and body.has_method("take_damage"):
			body.take_damage(damage)
			hit.append(body)
	return hit

## Shows the static ring immediately, then sweeps the fill wedge from empty
## to full over telegraph_time. Awaiting this coroutine blocks until the
## sweep finishes — i.e. until the fill is fully closed.
func _show_telegraph():
	visible = true
	cached_boundary = _get_boundary_points(segments)
	_rebuild_static_ring()
	_rebuild_fill_wedge(0.0)
	telegraph_started.emit()

	if fill_tween:
		fill_tween.kill()
	fill_tween = create_tween()
	fill_tween.tween_method(_rebuild_fill_wedge, 0.0, 1.0, telegraph_time)
	await fill_tween.finished

func _rebuild_static_ring():
	var center_h = _terrain_height_at(global_position.x, global_position.z) + ground_clearance
	var center_local = Vector3(0, center_h - global_position.y, 0)

	var st_ring = SurfaceTool.new()
	st_ring.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(cached_boundary.size() - 1):
		var a_len = max(cached_boundary[i].length(), 0.01)
		var b_len = max(cached_boundary[i + 1].length(), 0.01)
		var inner_a = cached_boundary[i].lerp(center_local, ring_thickness / a_len)
		var inner_b = cached_boundary[i + 1].lerp(center_local, ring_thickness / b_len)
		st_ring.add_vertex(inner_a)
		st_ring.add_vertex(cached_boundary[i])
		st_ring.add_vertex(cached_boundary[i + 1])
		st_ring.add_vertex(inner_a)
		st_ring.add_vertex(cached_boundary[i + 1])
		st_ring.add_vertex(inner_b)
	st_ring.generate_normals()
	ring_mesh_instance.mesh = st_ring.commit()

## Rebuilds the fill as a growing "pie wedge" from angle 0 up to progress*TAU.
## Static ring + this sweeping fill reads as a fill-up timer: when the wedge
## closes into a full circle, the sweep tween finishes and the attack lands.
func _rebuild_fill_wedge(progress: float):
	var count = cached_boundary.size() - 1
	var exact = progress * count
	var full_segments = int(floor(exact))
	var partial_t = exact - full_segments

	var center_h = _terrain_height_at(global_position.x, global_position.z) + ground_clearance
	var center_local = Vector3(0, center_h - global_position.y, 0)

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(full_segments):
		st.add_vertex(center_local)
		st.add_vertex(cached_boundary[i])
		st.add_vertex(cached_boundary[i + 1])
	if full_segments < count and partial_t > 0.0:
		var interp = cached_boundary[full_segments].lerp(cached_boundary[full_segments + 1], partial_t)
		st.add_vertex(center_local)
		st.add_vertex(cached_boundary[full_segments])
		st.add_vertex(interp)
	st.generate_normals()
	fill_mesh_instance.mesh = st.commit()
