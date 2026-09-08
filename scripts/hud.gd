extends CanvasLayer

const WIND_SND := preload("res://audio/wind.wav")

@onready var ammo_label: Label = $AmmoLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel
@onready var blood_overlay: ColorRect = $BloodOverlay
@onready var conn_label: Label = $ConnLabel

var _blood_tween: Tween
## The player this HUD reports for. In multiplayer it spawns a moment AFTER
## the scene loads, so we keep looking until we find it.
var _hud_player: Node

func _ready() -> void:
	_find_player()
	# Ambient wind: loop it so the world is never silent.
	var amb := AudioStreamPlayer.new()
	var stream: AudioStreamWAV = WIND_SND
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	amb.stream = stream
	amb.volume_db = -20.0
	add_child(amb)
	amb.play()

func _process(_delta: float) -> void:
	if _hud_player == null:
		_find_player()

func _find_player() -> void:
	var player := Net.get_local_player()
	if player == null:
		return
	_hud_player = player
	player.ammo_changed.connect(_on_ammo_changed)
	player.health_changed.connect(_on_health_changed)
	player.player_damaged.connect(_on_player_damaged)
	# Show the starting state (the player's _ready may fire before we connect).
	_on_ammo_changed.callv(player.hud_info())

func _on_ammo_changed(weapon_name: String, current: int, max_ammo: int, reloading: bool) -> void:
	if reloading:
		ammo_label.text = "RELOADING..."
	elif max_ammo <= 0:
		ammo_label.text = weapon_name
	else:
		ammo_label.text = "%s  %d / %d" % [weapon_name, current, max_ammo]

func _on_health_changed(current: int, max_hp: int) -> void:
	health_bar.max_value = max_hp
	health_bar.value = current
	health_label.text = str(current)

## Connection status banner (game.gd drives it).
func show_conn_lost(msg: String) -> void:
	conn_label.text = msg
	conn_label.visible = true

func hide_conn_lost() -> void:
	conn_label.visible = false

## Red vignette flash when we take damage.
func _on_player_damaged(_amount: int) -> void:
	if _blood_tween:
		_blood_tween.kill()
	blood_overlay.color.a = 0.45
	_blood_tween = create_tween()
	_blood_tween.tween_property(blood_overlay, "color:a", 0.0, 0.8)
