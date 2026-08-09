class_name AOEAttack
extends Node3D

## Base class for ground-telegraphed AOE attacks. Each attack type is its
## own scene (inheriting this one) with FillMesh, RingMesh, and the damage
## CollisionShape3D all authored directly in the editor — nothing about the
## shape is built or sized in script. This class only handles the shared
## telegraph animation (static ring + fill growing from the center) and
## damage resolution.

@export var damage: int = 30
@export var telegraph_time: float = 1.0   # time for the fill to grow from center to its authored size
@export var target_group: String = "player"
@export var height_offset: float = -3.5   # local Y from the spawn position down to ~ground level;
											# tune per-boss so the disc clears hill bumps without floating

signal telegraph_started
signal attack_resolved(targets_hit: Array)

var fill_tween: Tween
var fill_target_scale: Vector3

@onready var fill_mesh_instance: MeshInstance3D = $FillMesh
@onready var ring_mesh_instance: MeshInstance3D = $RingMesh
@onready var damage_area: Area3D = $DamageArea

func _ready():
	top_level = true   # ignore parent rotation/scale — stays flat and world-aligned
	visible = false

	fill_target_scale = fill_mesh_instance.scale   # remember the authored size before collapsing it
	fill_mesh_instance.scale = Vector3(0.001, 1, 0.001)

	damage_area.monitoring = true
	damage_area.monitorable = false

## Runs the full telegraph -> fill-completes -> damage -> cleanup sequence
## at the given world position. Call as: await attack.execute(boss.global_position)
func execute(at_position: Vector3):
	global_position = at_position + Vector3(0, height_offset, 0)
	await _show_telegraph()
	visible = false
	var hit = _resolve_damage()
	attack_resolved.emit(hit)
	queue_free()

func _resolve_damage() -> Array:
	var hit := []
	for body in damage_area.get_overlapping_bodies():
		if body.is_in_group(target_group) and body.has_method("take_damage"):
			body.take_damage(damage)
			hit.append(body)
	return hit

## Shows the static ring immediately, then grows the fill from the center
## out to its authored size over telegraph_time. Awaiting this coroutine
## blocks until the growth finishes.
func _show_telegraph():
	visible = true
	fill_mesh_instance.scale = Vector3(0.001, 1, 0.001)
	telegraph_started.emit()

	if fill_tween:
		fill_tween.kill()
	fill_tween = create_tween()
	fill_tween.tween_property(fill_mesh_instance, "scale", fill_target_scale, telegraph_time)
	await fill_tween.finished
