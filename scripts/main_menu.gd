extends Control

## Entry point: splash logo, main menu, server browser.

@onready var splash_box: CenterContainer = $SplashBox
@onready var servers_box: CenterContainer = $ServersBox
@onready var center_box: CenterContainer = $Center
@onready var menu_container: VBoxContainer = $Center/VBox
@onready var server_list: ItemList = $ServersBox/Panel/VBox/ServerList
@onready var join_edit: LineEdit = $ServersBox/Panel/VBox/JoinEdit
@onready var status_label: Label = $ServersBox/Panel/VBox/StatusLabel

var _waiting_for_discovery := false

func _ready() -> void:
	# Dedicated server mode (--server): skip the menu and boot the game scene.
	if Net.role == Net.Role.HOST:
		get_tree().change_scene_to_file.call_deferred("res://scenes/Main.tscn")
		return
	# Coming back from a match: tear down any leftover connection.
	Net.reset()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		# Headless test client: auto-join via --join=ip:port.
		if Net._auto_join != "":
			var parts := Net._auto_join.split(":")
			Net._auto_join = "" # consume it: rejoining the menu must not loop back
			if parts.size() == 2:
				Net.join_server(parts[0], int(parts[1]))
				_start_game()
				return
	# Splash: logo fades in, holds, then reveals the menu.
	splash_box.modulate.a = 0.0
	center_box.visible = false
	servers_box.visible = false
	var tw := create_tween()
	tw.tween_property(splash_box, "modulate:a", 1.0, 0.35)
	tw.tween_interval(0.8)
	tw.tween_property(splash_box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(_reveal_menu)
	# Scan the LAN right away so the list is warm when multiplayer is opened.
	_refresh_servers()

func _reveal_menu() -> void:
	splash_box.visible = false
	menu_container.modulate.a = 0.0
	center_box.visible = true
	create_tween().tween_property(menu_container, "modulate:a", 1.0, 0.5)

func _process(_delta: float) -> void:
	if _waiting_for_discovery and not Net._discovering:
		_waiting_for_discovery = false
		print("[Menu] Discovery: %d server(s) found" % Net.discovered.size())
		for s in Net.discovered:
			server_list.add_item("%s   (%s:%d)" % [s.name, s.ip, s.port])
		status_label.text = "No servers found on LAN — or type an IP above." if Net.discovered.is_empty() else "%d server(s) found." % Net.discovered.size()

func _on_play_pressed() -> void:
	# Quick fade out, then start the game.
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(_start_game)

func _on_servers_pressed() -> void:
	center_box.visible = false
	servers_box.visible = true
	_refresh_servers()

func _back_to_menu() -> void:
	servers_box.visible = false
	center_box.visible = true

func _on_back_pressed() -> void:
	_back_to_menu()

func _refresh_servers() -> void:
	server_list.clear()
	status_label.text = "Scanning the LAN for servers..."
	_waiting_for_discovery = true
	Net.start_discovery()

func _on_server_item_activated(index: int) -> void:
	var s: Dictionary = Net.discovered[index]
	_join(s.ip, s.port)

func _on_connect_pressed() -> void:
	var parts := join_edit.text.split(":")
	if parts.size() == 2:
		_join(parts[0], int(parts[1]))
	else:
		status_label.text = "Write it as ip:port, e.g. 1.2.3.4:9999"

func _join(ip: String, port: int) -> void:
	var err := Net.join_server(ip, port)
	if err != OK:
		status_label.text = "Failed to join (%s) — is the server running?" % ip
		return
	_start_game()

func _start_game() -> void:
	# Deferred: scene changes can't run while the tree is still initializing.
	get_tree().change_scene_to_file.call_deferred("res://scenes/Main.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
