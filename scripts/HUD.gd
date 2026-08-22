extends CanvasLayer

## Polls the player and boss directly each frame rather than using signals —
## simplest option given nothing else in this project uses an event system
## yet. Fine at this scale (two characters); worth switching to signals
## (health_changed/stamina_changed) if more UI consumers show up later.

@onready var player_health_bar: ProgressBar = $PlayerBars/HealthBar
@onready var player_stamina_bar: ProgressBar = $PlayerBars/StaminaBar
@onready var boss_bar_container: Control = $BossBar
@onready var boss_health_bar: ProgressBar = $BossBar/HealthBar

var player: Node
var boss: Node

func _ready():
	player = get_tree().get_first_node_in_group("player")
	boss = get_tree().get_first_node_in_group("boss")

func _process(_delta):
	if is_instance_valid(player):
		player_health_bar.max_value = player.max_health
		player_health_bar.value = player.current_health
		player_stamina_bar.max_value = player.max_stamina
		player_stamina_bar.value = player.current_stamina
	else:
		player = get_tree().get_first_node_in_group("player")

	if is_instance_valid(boss):
		boss_bar_container.visible = true
		boss_health_bar.max_value = boss.max_health
		boss_health_bar.value = boss.current_health
	else:
		boss_bar_container.visible = false
		boss = get_tree().get_first_node_in_group("boss")
