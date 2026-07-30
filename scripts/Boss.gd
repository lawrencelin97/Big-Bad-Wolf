extends CharacterBody3D

@export var max_health: int = 500
@export var move_speed: float = 2.0        # slow — size implies weight
@export var attack_radius: float = 6.0     # trigger range AND the AOE's radius
@export var attack_damage: int = 30
@export var telegraph_time: float = 1.0    # big enemies need a readable tell before the hit lands
@export var attack_cooldown: float = 1.2

const GRAVITY = 20.0
const CircleAOEScene := preload("res://scenes/attacks/CircleAOE.tscn")

var current_health: int
var player: Node3D
var attacking := false

func _ready():
	current_health = max_health
	player = get_tree().get_first_node_in_group("player")

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

func _start_attack():
	attacking = true

	var atk: CircleAOE = CircleAOEScene.instantiate()
	get_tree().current_scene.add_child(atk)
	atk.radius = attack_radius
	atk.damage = attack_damage
	atk.telegraph_time = telegraph_time

	await atk.execute(global_position)

	await get_tree().create_timer(attack_cooldown).timeout
	attacking = false

func take_damage(amount: int):
	current_health -= amount
	print("Boss took damage: ", amount, " -> health ", current_health)
	if current_health <= 0:
		die()

func die():
	print("Boss defeated")
	queue_free()
