extends CanvasLayer

## Where settings are stored (user:// points to Godot's per-user data folder).
const SETTINGS_PATH := "user://settings.cfg"
## Resolutions offered in the settings menu (used in windowed mode).
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

@onready var dim: ColorRect = $Dim
@onready var menu_box: VBoxContainer = $MenuBox
@onready var settings_box: VBoxContainer = $SettingsBox
@onready var mouse_slider: HSlider = $SettingsBox/MouseSlider
@onready var invert_check: CheckBox = $SettingsBox/InvertYCheck
@onready var fov_slider: HSlider = $SettingsBox/FovSlider
@onready var view_kick_check: CheckBox = $SettingsBox/ViewKickCheck
@onready var volume_slider: HSlider = $SettingsBox/VolumeSlider
@onready var quality_slider: HSlider = $SettingsBox/QualitySlider
@onready var resolution_option: OptionButton = $SettingsBox/ResolutionOption
@onready var fullscreen_check: CheckBox = $SettingsBox/FullscreenCheck
@onready var vsync_check: CheckBox = $SettingsBox/VsyncCheck

var _player: CharacterBody3D

func _ready() -> void:
	# Grab OUR player (in multiplayer there are remote copies in the group).
	_player = Net.get_local_player()
	for res in RESOLUTIONS:
		resolution_option.add_item("%d x %d" % [res.x, res.y])
	_load_settings()
	_apply_settings()

func _process(_delta: float) -> void:
	# In multiplayer our player spawns a moment after the scene loads;
	# keep looking until it exists so settings reach the right node.
	if _player == null:
		_player = Net.get_local_player()

func _unhandled_input(event: InputEvent) -> void:
	# ESC toggles the pause menu. In multiplayer the server decides, so the
	# whole match freezes together instead of only this machine.
	if event.is_action_pressed("ui_cancel"):
		if Net.role == Net.Role.SOLO:
			if get_tree().paused:
				_resume()
			else:
				_pause()
		else:
			get_tree().current_scene.pause_request.rpc_id(1)

func _pause() -> void:
	# paused = true freezes every node, except the ones with process_mode ALWAYS (this menu).
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_pause_ui(true)

func _resume() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_pause_ui(false)

## Called by game.gd when the server broadcasts a pause change.
func pause_from_network(paused: bool) -> void:
	if paused:
		_set_pause_ui(true)
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_set_pause_ui(false)
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _set_pause_ui(show: bool) -> void:
	dim.visible = show
	menu_box.visible = show
	settings_box.visible = false

func _on_resume_pressed() -> void:
	if Net.role == Net.Role.SOLO:
		_resume()
	else:
		get_tree().current_scene.pause_request.rpc_id(1)

func _on_settings_pressed() -> void:
	menu_box.visible = false
	settings_box.visible = true

func _on_back_pressed() -> void:
	_save_settings()
	settings_box.visible = false
	menu_box.visible = true

func _on_exit_pressed() -> void:
	_save_settings()
	get_tree().quit()

func _on_menu_pressed() -> void:
	_save_settings()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_mouse_slider_value_changed(_value: float) -> void:
	_apply_controls_settings()

func _on_invert_toggled(_pressed: bool) -> void:
	_apply_controls_settings()

func _on_fov_value_changed(_value: float) -> void:
	_apply_controls_settings()

func _on_view_kick_toggled(_pressed: bool) -> void:
	_apply_controls_settings()

func _on_volume_slider_value_changed(_value: float) -> void:
	_apply_controls_settings()

func _on_quality_slider_value_changed(_value: float) -> void:
	# 3D render scale: lower = faster, less pretty.
	get_viewport().scaling_3d_scale = quality_slider.value

func _on_resolution_selected(_index: int) -> void:
	_apply_window_settings()

func _on_fullscreen_toggled(_pressed: bool) -> void:
	_apply_window_settings()

func _on_vsync_toggled(_pressed: bool) -> void:
	_apply_window_settings()

func _apply_controls_settings() -> void:
	if _player:
		_player.mouse_sensitivity = mouse_slider.value
		_player.invert_y = invert_check.button_pressed
		_player.base_fov = fov_slider.value
		_player.sprint_fov = fov_slider.value + 7.0
		_player.view_kick = view_kick_check.button_pressed
	# Bus 0 is the Master audio bus. linear_to_db converts 0..1 into decibels.
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume_slider.value, 0.0001)))

func _apply_window_settings() -> void:
	var win := get_window()
	if fullscreen_check.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		win.size = RESOLUTIONS[resolution_option.selected]
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_check.button_pressed else DisplayServer.VSYNC_DISABLED
	)

func _apply_settings() -> void:
	_apply_controls_settings()
	_apply_window_settings()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return # No file yet: keep the defaults.
	mouse_slider.value = cfg.get_value("settings", "mouse_sensitivity", mouse_slider.value)
	invert_check.button_pressed = cfg.get_value("settings", "invert_y", false)
	fov_slider.value = cfg.get_value("settings", "fov", fov_slider.value)
	view_kick_check.button_pressed = cfg.get_value("settings", "view_kick", true)
	volume_slider.value = cfg.get_value("settings", "volume", volume_slider.value)
	quality_slider.value = cfg.get_value("settings", "quality", quality_slider.value)
	resolution_option.selected = cfg.get_value("settings", "resolution", resolution_option.selected)
	fullscreen_check.button_pressed = cfg.get_value("settings", "fullscreen", false)
	vsync_check.button_pressed = cfg.get_value("settings", "vsync", true)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "mouse_sensitivity", mouse_slider.value)
	cfg.set_value("settings", "invert_y", invert_check.button_pressed)
	cfg.set_value("settings", "fov", fov_slider.value)
	cfg.set_value("settings", "view_kick", view_kick_check.button_pressed)
	cfg.set_value("settings", "volume", volume_slider.value)
	cfg.set_value("settings", "quality", quality_slider.value)
	cfg.set_value("settings", "resolution", resolution_option.selected)
	cfg.set_value("settings", "fullscreen", fullscreen_check.button_pressed)
	cfg.set_value("settings", "vsync", vsync_check.button_pressed)
	cfg.save(SETTINGS_PATH)
