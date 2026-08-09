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

const GRAVITY = 20.0

var current_health: int
var state: State = State.NORMAL

var climb_target: Node3D = null
var climb_angle: float = 0.0    # radians around the target's vertical (Y) axis
var climb_height: float = 0.0   # local Y offset from the target's origin
var climb_radius: float = 0.0   # horizontal distance from the target's axis, fixed at grab time
var climb_cooldown_timer: float = 0.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var climb_detector: Area3D = $ClimbDetector

func _ready():
	current_health = max_health
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

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

func _on_climb_detector_body_entered(body: Node3D):
	if state != State.NORMAL:
		return
	if climb_cooldown_timer > 0.0:
		return
	if is_on_floor():
		return
	if body.is_in_group("climbable"):
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

	if Input.is_action_just_pressed("jump"):
		_end_climb()
		return

	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
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
	#look_at(target_pos + Vector3(0, global_position.y - target_pos.y, 0), Vector3.UP)

func _end_climb():
	state = State.NORMAL
	climb_cooldown_timer = climb_regrab_cooldown
	var away = Vector3(cos(climb_angle), 0, sin(climb_angle))
	velocity = away * (climb_detach_impulse * 0.5) + Vector3.UP * climb_detach_impulse
	climb_target = null

func take_damage(amount: int):
	current_health -= amount
	print("Player took damage: ", amount, " -> health ", current_health)
	if current_health <= 0:
		die()

func die():
	print("Player died")
