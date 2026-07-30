extends Node3D

@export var expand_time := 1.5
@export var max_radius := 1.0
@export var damage := 25
@export var delay_before_damage := 0.2

var current_radius := 0.0
var elapsed := 0.0
var triggered := false

@onready var mesh := $MeshInstance3D
@onready var area := $Area3D

func _process(delta):
	if triggered:
		return

	elapsed += delta
	current_radius = clamp(elapsed / expand_time, 0.0, 1.0)

	# Update shader radius
	var mat : ShaderMaterial = mesh.get_active_material()
	mat.set_shader_parameter("radius", current_radius * max_radius)

	# Update collision shape radius
	var shape : CylinderShape3D = area.get_node("CollisionShape3D").shape
	shape.radius = current_radius * max_radius * 2.0

	# When fully expanded → deal damage
	if elapsed >= expand_time + delay_before_damage:
		triggered = true
		apply_damage()
		queue_free()


func apply_damage():
	for body in area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage)
