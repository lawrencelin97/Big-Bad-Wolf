extends CharacterBody3D

enum State { NORMAL, CLIMBING }

@export var speed: float = 6.0
@export var jump_velocity: float = 8.0
@export var mouse_sensitivity: float = 0.003
@export var max_health: int = 100

@export_group("Climbing")
@export var climb_speed: float = 3.0           # linear speed moving up/down the target
@export var climb_max_height: float = 4.0      # how high above/below the target's origin you can climb
@export var climb_detach_impulse: float = 6.0  # push-off speed when jumping away from a climb
@export var climb_regrab_cooldown: float = 0.3 # prevents instantly re-grabbing right after detaching

@export_group("Weapon")
@export var attack_damage: int = 20
@export var attack_cooldown: float = 0.5
@export var attack_active_delay: float = 0.15  # time into the swing before the hit registers
@export var climb_attack_damage: int = 15
@export var climb_attack_cooldown: float = 0.6

@export_group("Stamina")
@export var max_stamina: float = 100.0
@export var stamina_drain_climb_idle: float = 5.0     # per second, attached but not moving
@export var stamina_drain_climb_active: float = 12.0  # per second, actively moving while climbing
@export var stamina_cost_attack: float = 15.0         # flat cost per swing (ground or climb)
@export var stamina_regen_rate: float = 20.0          # per second, only while not climbing/sprinting

@export_group("Sprint")
@export var sprint_speed_multiplier: float = 1.5
@export var sprint_stamina_drain: float = 15.0  # per second while sprinting

@export_group("Dodge")
@export var dodge_speed: float = 30.0
@export var dodge_duration: float = 0.2   # how long the dash overrides normal movement
@export var dodge_cooldown: float = 0.1
@export var dodge_stamina_cost: float = 25.0  # flat cost per dodge

const GRAVITY = 20.0

var current_health: int
var state: State = State.NORMAL

var climb_target: Node3D = null
var climb_angle: float = 0.0    # radians around the target's vertical (Y) axis
var climb_height: float = 0.0   # local Y offset from the target's origin
var climb_radius: float = 0.0   # horizontal distance from the target's axis, fixed at grab time
var climb_cooldown_timer: float = 0.0

var attack_cooldown_timer: float = 0.0
var climb_attack_cooldown_timer: float = 0.0
var is_attacking: bool = false
var current_stamina: float
var dodge_cooldown_timer: float = 0.0
var is_dodging: bool = false
var is_stamina_depleted: bool = false

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var climb_detector: Area3D = $ClimbDetector
@onready var attack_hitbox: Area3D = $AttackHitbox
@onready var weapon_pivot: Node3D = $WeaponPivot

func _ready():
	current_health = max_health
	current_stamina = max_stamina
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	climb_detector.body_entered.connect(_on_climb_detector_body_entered)

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.2, 1.2)

func _physics_process(delta):
	if climb_cooldown_timer > 0.0:
		climb_cooldown_timer -= delta
	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
	if climb_attack_cooldown_timer > 0.0:
		climb_attack_cooldown_timer -= delta
	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta

	match state:
		State.NORMAL:
			_physics_normal(delta)
		State.CLIMBING:
			_physics_climbing(delta)

func _physics_normal(delta):
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var is_sprinting = Input.is_action_pressed("sprint") and is_on_floor() and direction != Vector3.ZERO and current_stamina > 0.0 and not is_dodging and not is_stamina_depleted

	if is_sprinting:
		current_stamina = max(0.0, current_stamina - sprint_stamina_drain * delta)
	else:
		current_stamina = min(max_stamina, current_stamina + stamina_regen_rate * delta)

	if not is_dodging:
		var current_speed = speed * sprint_speed_multiplier if is_sprinting else speed
		if direction:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed)
			velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	if Input.is_action_just_pressed("attack") and attack_cooldown_timer <= 0.0 and not is_attacking and not is_stamina_depleted:
		_perform_swing_attack()

	if Input.is_action_just_pressed("dodge") and not is_stamina_depleted:
		_try_dodge(direction)
		
	if current_stamina==0:
		is_stamina_depleted=true
	if is_stamina_depleted and current_stamina>50:
		is_stamina_depleted=false

## Quick directional burst: dodges in the currently-held movement direction,
## or straight forward if no direction is held. Overrides normal movement
## input for dodge_duration, then hands control back.
func _try_dodge(direction: Vector3):
	if is_dodging or dodge_cooldown_timer > 0.0:
		return
	if current_stamina < dodge_stamina_cost:
		return

	current_stamina -= dodge_stamina_cost
	dodge_cooldown_timer = dodge_cooldown
	is_dodging = true

	var dodge_dir = direction if direction != Vector3.ZERO else -transform.basis.z
	velocity.x = dodge_dir.x * dodge_speed
	velocity.z = dodge_dir.z * dodge_speed

	await get_tree().create_timer(dodge_duration).timeout
	is_dodging = false

func _on_climb_detector_body_entered(body: Node3D):
	if state != State.NORMAL:
		return
	if climb_cooldown_timer > 0.0:
		return
	if is_on_floor():
		return
	if body.is_in_group("climbable") and not is_stamina_depleted:
		_start_climb(body)

func _start_climb(target: Node3D):
	state = State.CLIMBING
	climb_target = target
	velocity = Vector3.ZERO

	var offset = global_position - target.global_position
	offset.y = 0
	climb_radius = max(offset.length(), 0.5)
	climb_angle = atan2(offset.z, offset.x)
	climb_height = clamp(global_position.y - target.global_position.y, -climb_max_height, climb_max_height)

	_update_climb_position()

func _physics_climbing(delta):
	if not is_instance_valid(climb_target):
		state = State.NORMAL
		return

	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var is_moving = input_dir.length() > 0.05
	var drain = stamina_drain_climb_active if is_moving else stamina_drain_climb_idle
	current_stamina = max(0.0, current_stamina - drain * delta)

	if current_stamina <= 0.0:
		_end_climb()
		is_stamina_depleted=true
		return

	if Input.is_action_just_pressed("jump"):
		_end_climb()
		return

	if Input.is_action_just_pressed("attack") and climb_attack_cooldown_timer <= 0.0:
		_perform_climb_attack()

	# forward/back climbs up/down; left/right moves around the target
	climb_height += -input_dir.y * climb_speed * delta
	climb_height = clamp(climb_height, -climb_max_height, climb_max_height)
	climb_angle -= input_dir.x * (climb_speed / max(climb_radius, 0.1)) * delta

	_update_climb_position()

func _update_climb_position():
	var target_pos = climb_target.global_position
	var offset = Vector3(cos(climb_angle), 0, sin(climb_angle)) * climb_radius
	offset.y = climb_height
	global_position = target_pos + offset
	# Deliberately not rotating the player here — this node also carries the
	# camera, and rotating it every physics frame fights mouse-look (the
	# camera would feel "locked" to always face the target). If you want the
	# character model to visually face the wall later, rotate a separate
	# visual/mesh node instead of this CharacterBody3D.

func _end_climb():
	state = State.NORMAL
	climb_cooldown_timer = climb_regrab_cooldown
	var away = Vector3(cos(climb_angle), 0, sin(climb_angle))
	velocity = away * (climb_detach_impulse * 0.5) + Vector3.UP * climb_detach_impulse
	climb_target = null

## Ground/air swing: brief cosmetic animation, then a short window where the
## hitbox is actually live. Hits anything in the "boss" group in front of
## the player.
func _perform_swing_attack():
	if current_stamina < stamina_cost_attack:
		return
	current_stamina -= stamina_cost_attack
	attack_cooldown_timer = attack_cooldown
	is_attacking = true
	_play_swing_animation()
	await get_tree().create_timer(attack_active_delay).timeout
	_resolve_swing_hit()
	is_attacking = false

func _resolve_swing_hit():
	for body in attack_hitbox.get_overlapping_bodies():
		if body != self and body.is_in_group("boss") and body.has_method("take_damage"):
			body.take_damage(attack_damage)

## Climbing attack: no hitbox needed, since the player is already attached
## to a specific target — just damage it directly.
func _perform_climb_attack():
	if current_stamina < stamina_cost_attack:
		return
	current_stamina -= stamina_cost_attack
	climb_attack_cooldown_timer = climb_attack_cooldown
	_play_swing_animation()
	if is_instance_valid(climb_target) and climb_target.has_method("take_damage"):
		climb_target.take_damage(climb_attack_damage)

func _play_swing_animation():
	if weapon_pivot == null:
		return
	var tween = create_tween()
	tween.tween_property(weapon_pivot, "rotation:x", -1.2, 0.08)
	tween.tween_property(weapon_pivot, "rotation:x", 0.3, 0.12)
	tween.tween_property(weapon_pivot, "rotation:x", 0.0, 0.15)

func take_damage(amount: int):
	current_health -= amount
	print("Player took damage: ", amount, " -> health ", current_health)
	if current_health <= 0:
		die()

func die():
	print("Player died")
