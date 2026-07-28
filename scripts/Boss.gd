extends CharacterBody3D

@export var max_health: int = 500
@export var move_speed: float = 2.0        # slow — size implies weight
@export var attack_radius: float = 6.0     # both the trigger range AND the AOE damage/telegraph radius
@export var attack_damage: int = 30
@export var telegraph_time: float = 1.0    # big enemies need a readable tell before the hit lands
@export var attack_cooldown: float = 1.2
@export var telegraph_y_offset: float = -3.95  # local Y so the circle sits at the boss's feet (adjust to your model)

const GRAVITY = 20.0

var current_health: int
var player: Node3D
var attacking := false

var telegraph: Node3D
var fill_material: StandardMaterial3D
var ring_material: StandardMaterial3D
var pulse_tween: Tween

@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready():
	current_health = max_health
	player = get_tree().get_first_node_in_group("player")
	_create_telegraph_visual()

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if not player or attacking:
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	var to_player = player.global_position - global_position
	to_player.y = 0
	var dist = to_player.length()

	if dist > attack_radius:
		var dir = to_player.normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
	else:
		velocity.x = 0
		velocity.z = 0
		_start_attack()

	move_and_slide()

## Builds a flat red disc + brighter ring, both unshaded and depth-test-disabled
## so they read clearly as a ground telegraph even over hilly terrain.
func _create_telegraph_visual():
	telegraph = Node3D.new()
	telegraph.name = "TelegraphCircle"
	add_child(telegraph)
	telegraph.position = Vector3(0, telegraph_y_offset, 0)
	telegraph.scale = Vector3(attack_radius, 1.0, attack_radius)
	telegraph.visible = false

	# Fill disc
	var fill_mesh = CylinderMesh.new()
	fill_mesh.top_radius = 1.0
	fill_mesh.bottom_radius = 1.0
	fill_mesh.height = 0.02
	fill_mesh.radial_segments = 48
	var fill_instance = MeshInstance3D.new()
	fill_instance.mesh = fill_mesh

	fill_material = StandardMaterial3D.new()
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_material.albedo_color = Color(1, 0, 0, 0.18)
	fill_material.no_depth_test = true       # draw on top of terrain instead of clipping into hills
	fill_material.render_priority = 1
	fill_instance.material_override = fill_material
	telegraph.add_child(fill_instance)

	# Brighter edge ring so the boundary of the AOE is unambiguous
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.92
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 8
	var ring_instance = MeshInstance3D.new()
	ring_instance.mesh = ring_mesh

	ring_material = StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color = Color(1, 0, 0, 0.9)
	ring_material.no_depth_test = true
	ring_material.render_priority = 2
	ring_instance.material_override = ring_material
	telegraph.add_child(ring_instance)

func _start_attack():
	attacking = true
	_show_telegraph()
	await get_tree().create_timer(telegraph_time).timeout
	_hide_telegraph()
	_deal_attack_damage()
	await get_tree().create_timer(attack_cooldown).timeout
	attacking = false

func _show_telegraph():
	telegraph.visible = true
	fill_material.albedo_color.a = 0.12
	ring_material.albedo_color.a = 0.5

	if pulse_tween:
		pulse_tween.kill()
	pulse_tween = create_tween()
	pulse_tween.set_loops()
	# Pulses faster as the attack gets closer to landing — classic MMO "fill up" tension.
	var pulse_speed = max(telegraph_time / 4.0, 0.15)
	pulse_tween.tween_property(fill_material, "albedo_color:a", 0.45, pulse_speed)
	pulse_tween.parallel().tween_property(ring_material, "albedo_color:a", 1.0, pulse_speed)
	pulse_tween.tween_property(fill_material, "albedo_color:a", 0.12, pulse_speed)
	pulse_tween.parallel().tween_property(ring_material, "albedo_color:a", 0.5, pulse_speed)

func _hide_telegraph():
	if pulse_tween:
		pulse_tween.kill()
	telegraph.visible = false

func _deal_attack_damage():
	if not player or not player.has_method("take_damage"):
		return
	var to_player = player.global_position - global_position
	to_player.y = 0
	if to_player.length() <= attack_radius:
		player.take_damage(attack_damage)

func take_damage(amount: int):
	current_health -= amount
	print("Boss took damage: ", amount, " -> health ", current_health)
	if current_health <= 0:
		die()

func die():
	print("Boss defeated")
	queue_free()
