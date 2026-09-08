extends Node3D

## Multiplayer coordinator (attached to the Main scene root).
##
## - HOST (dedicated server): spawns one Player per connected peer, relays
##   target hits. Runs fine headless.
## - CLIENT: spawns players as the server announces them; this machine's
##   player is the one it has authority over.
## - SOLO: leaves the built-in Player node alone, no networking.

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(0, 0.05, 2),
	Vector3(-8, 0.05, -4),
	Vector3(8, 0.05, -4),
	Vector3(0, 0.05, 12),
	Vector3(-10, 0.05, 8),
	Vector3(10, 0.05, 8),
]

var _spawn_count := 0
var _ping_t := 0.0

## Reconnect state: after a connection drop we retry the last server a few
## times; if that fails, the client goes back to the main menu.
const RECONNECT_ATTEMPT := 2.0
const RECONNECT_TIMEOUT := 12.0
## If no ping table arrives for this long, the server is considered dead.
const CONN_LOSS_AFTER := 4.0
var _reconnecting := false
var _reconnect_left := 0.0
var _reconnect_t := 0.0
var _conn_t := 0.0

func _ready() -> void:
	if Net.role == Net.Role.SOLO:
		return
	# Multiplayer spawns its own players; the built-in solo one gets removed.
	$Player.queue_free()
	if Net.role == Net.Role.HOST:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	else:
		if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_on_connected()
		else:
			multiplayer.connected_to_server.connect(_on_connected)
			multiplayer.connection_failed.connect(_on_connection_failed)
			multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta: float) -> void:
	if _reconnecting:
		_reconnect_step(delta)
		return
	# Ping keeper: clients time an echo to the server every second; the
	# server measures RTT and broadcasts the table to everyone.
	if Net.role == Net.Role.SOLO:
		return
	_ping_t += delta
	if _ping_t >= 1.0:
		_ping_t = 0.0
		if Net.role == Net.Role.CLIENT:
			client_ping.rpc_id(1, Time.get_ticks_msec())
	# Watchdog: the server echoes pings every second; silence means it's gone.
	if Net.role == Net.Role.CLIENT:
		_conn_t += delta
		if _conn_t >= CONN_LOSS_AFTER:
			_start_reconnect()

func _start_reconnect() -> void:
	if _reconnecting or Net.role != Net.Role.CLIENT:
		return
	print("[Game] Connection lost — reconnecting...")
	_reconnecting = true
	_reconnect_left = RECONNECT_TIMEOUT
	_reconnect_t = 0.0
	$HUD.show_conn_lost("CONNECTION LOST — RECONNECTING...")

func _reconnect_step(delta: float) -> void:
	_reconnect_left -= delta
	_reconnect_t -= delta
	# Try again every couple of seconds against the last server.
	if _reconnect_t <= 0.0:
		_reconnect_t = RECONNECT_ATTEMPT
		if Net.last_address != "":
			Net.reset()
			Net.join_server(Net.last_address, Net.last_port)
	# Give up after the timeout: clean up and drop back to the menu.
	if _reconnect_left <= 0.0:
		print("[Game] Giving up on reconnection — returning to menu.")
		_reconnecting = false
		Net.reset()
		get_tree().change_scene_to_file.call_deferred("res://scenes/MainMenu.tscn")

@rpc("any_peer", "call_remote", "unreliable")
func client_ping(t: int) -> void:
	if Net.role != Net.Role.HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	Net.pings[id] = Time.get_ticks_msec() - t
	ping_table.rpc(Net.pings)

@rpc("any_peer", "call_remote", "unreliable")
func ping_table(pings: Dictionary) -> void:
	if Net.role != Net.Role.HOST:
		Net.pings = pings
		_conn_t = 0.0 # server is alive

# ---------- joining ----------

func _on_connected() -> void:
	print("[Game] Connected to server as %s" % Net.player_name)
	if _reconnecting:
		_reconnecting = false
		$HUD.hide_conn_lost()
	Net.players[multiplayer.get_unique_id()] = Net.player_name
	register_player.rpc_id(1, Net.player_name)

func _on_connection_failed() -> void:
	print("[Game] Could not reach the server.")

func _on_server_disconnected() -> void:
	print("[Game] Server disconnected.")
	_start_reconnect()

@rpc("any_peer", "call_remote", "reliable")
func register_player(player_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	print("[Game] Player %d registered (%s)" % [id, player_name])
	Net.players[id] = player_name
	_spawn_player.rpc(id, player_name)
	# rpc() skips ourselves, so the server spawns its own copy too.
	_spawn_local_player(id, player_name)
	# Tell the newcomer about players that already exist.
	for peer_id in multiplayer.get_peers():
		if peer_id != id:
			_spawn_player.rpc_id(id, peer_id, Net.players.get(peer_id, "Player"))

func _on_peer_connected(_peer_id: int) -> void:
	pass # registrations drive the spawns

func _on_peer_disconnected(peer_id: int) -> void:
	print("[Game] Player %d left" % peer_id)
	Net.players.erase(peer_id)
	_remove_player.rpc(peer_id)
	_remove_local_player(peer_id)

# ---------- spawning ----------

@rpc("any_peer", "call_remote", "reliable")
func _spawn_player(peer_id: int, pname: String) -> void:
	Net.players[peer_id] = pname
	_spawn_local_player(peer_id, pname)

func _spawn_local_player(peer_id: int, pname: String) -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	player.name = "Player_%d" % peer_id
	player.position = SPAWN_POINTS[_spawn_count % SPAWN_POINTS.size()]
	_spawn_count += 1
	# Only the owning peer may drive this player.
	player.set_multiplayer_authority(peer_id)
	$Players.add_child(player)
	# Name the player's tag (the scene keeps it invisible in solo).
	var tag: Label3D = player.get_node("NameTag")
	tag.text = pname

@rpc("any_peer", "call_remote", "reliable")
func _remove_player(peer_id: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	Net.players.erase(peer_id)
	_remove_local_player(peer_id)

func _remove_local_player(peer_id: int) -> void:
	var node := get_node_or_null("Players/Player_%d" % peer_id)
	if node:
		node.queue_free()

# ---------- gameplay events ----------

## Any peer that shot a target reports it; everyone plays the animation.
@rpc("any_peer", "call_remote", "unreliable")
func hit_target(target_id: int) -> void:
	var target := get_node_or_null("Target%d" % target_id)
	if target and target.has_method("get_hit"):
		target.get_hit()

## A shooter reports damage done to a player; every machine applies it.
@rpc("any_peer", "call_remote", "unreliable")
func damage_player(peer_id: int, amount: int) -> void:
	var player := get_node_or_null("Players/Player_%d" % peer_id)
	if player and player.has_method("take_damage"):
		player.take_damage(amount)

## A client asks the server to toggle the networked pause.
@rpc("any_peer", "call_remote", "reliable")
func pause_request() -> void:
	if Net.role != Net.Role.HOST:
		return
	var new_state := not get_tree().paused
	set_pause.rpc(new_state)
	get_tree().paused = new_state
	$PauseMenu.pause_from_network(new_state)

## Server broadcasts the pause state; every machine applies it.
@rpc("any_peer", "call_remote", "reliable")
func set_pause(paused: bool) -> void:
	get_tree().paused = paused
	$PauseMenu.pause_from_network(paused)

## Death/respawn state broadcast so all machines hide/show the same player.
@rpc("any_peer", "call_remote", "reliable")
func set_dead(peer_id: int, is_dead: bool) -> void:
	var player := get_node_or_null("Players/Player_%d" % peer_id)
	if player and player.has_method("apply_dead_state"):
		player.apply_dead_state(is_dead)
