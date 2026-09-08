extends Node

## Network autoload: starts/joins games and runs LAN server discovery.
##
## Dedicated server on the same executable:
##   godot --headless --path . -- --server [--name="My Server"]
## Auto-join from the command line (for testing):
##   godot --headless --path . -- --join=127.0.0.1:9999

enum Role { SOLO, HOST, CLIENT }

const GAME_PORT := 9999
const DISCOVERY_PORT := 9998
const DISCOVERY_TIME := 1.2
const HOST_RF: String = "FPS_SERVER"
const DISCOVER_RF: String = "FPS_DISCOVER"
const NAME_PREFIXES: Array[String] = [
	"Shadow", "Raven", "Ghost", "Viper", "Blaze", "Frost", "Nova", "Wolf", "Reaper", "Storm",
]

var role: int = Role.SOLO
var player_name := ""
var server_name := "Akbar's Server"
## Known players: peer_id -> display name (kept up to date by game.gd).
var players: Dictionary = {}
## Measured round-trip time per peer in ms (server keeps this up to date).
var pings: Dictionary = {}
## Servers found by LAN discovery: [{ name, ip, port }]
var discovered: Array[Dictionary] = []

var _discovering := false
var _discover_deadline := 0.0
var _udp: PacketPeerUDP
var _broadcast_acc := 0.0
var _auto_join := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--server":
			start_host(GAME_PORT)
		elif a.begins_with("--name="):
			server_name = a.trim_prefix("--name=")
		elif a.begins_with("--join="):
			_auto_join = a.trim_prefix("--join=")
		elif a.begins_with("--player="):
			player_name = a.trim_prefix("--player=")
	if player_name == "":
		# Random callsign so joins get distinct names by default.
		player_name = "%s%d" % [NAME_PREFIXES.pick_random(), randi_range(10, 99)]

func start_host(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_error("[Net] Could not start server on port %d (error %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	_begin_discovery_listener()
	print("[Net] Server listening on port %d" % port)
	return OK

## The server we last joined (used by the auto-reconnect loop).
var last_address := ""
var last_port := GAME_PORT

func join_server(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("[Net] Could not join %s:%d (error %d)" % [address, port, err])
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	last_address = address
	last_port = port
	print("[Net] Connecting to %s:%d" % [address, port])
	return OK

## Leave any server and return to solo state (called when back at the menu).
func reset() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	role = Role.SOLO
	discovered.clear()
	pings.clear()
	players.clear()

## The player node this machine controls, or null.
func get_local_player() -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			return p
	return null

# ---------- LAN discovery ----------

func _begin_discovery_listener() -> void:
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(DISCOVERY_PORT)
	if err != OK:
		_udp = null
		print("[Net] Could not bind discovery port %d" % DISCOVERY_PORT)
		return
	_udp.set_broadcast_enabled(true)

func start_discovery() -> void:
	discovered.clear()
	_discovering = true
	_discover_deadline = Time.get_ticks_msec() / 1000.0 + DISCOVERY_TIME
	if _udp:
		_udp.close()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	# Broadcast for the LAN, and localhost for a server on this same machine.
	_send_discovery("255.255.255.255")
	_send_discovery("127.0.0.1")

func _send_discovery(addr: String) -> void:
	_udp.set_dest_address(addr, DISCOVERY_PORT)
	_udp.put_packet(DISCOVER_RF.to_utf8_buffer())

func _broadcast_payload() -> String:
	return "%s|%s|%d" % [HOST_RF, server_name, GAME_PORT]

func _process(delta: float) -> void:
	if _udp == null:
		return
	if role == Role.HOST:
		# Periodic broadcast so clients can also find us with no request.
		_broadcast_acc += delta
		if _broadcast_acc >= 2.0:
			_broadcast_acc = 0.0
			_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
			_udp.put_packet(_broadcast_payload().to_utf8_buffer())
	_poll_udp()
	if _discovering and Time.get_ticks_msec() / 1000.0 >= _discover_deadline:
		_discovering = false

func _poll_udp() -> void:
	while _udp.get_available_packet_count() > 0:
		var sender_ip := _udp.get_packet_ip()
		var sender_port := _udp.get_packet_port()
		var data := _udp.get_packet().get_string_from_utf8()
		if data == DISCOVER_RF and role == Role.HOST:
			_udp.set_dest_address(sender_ip, sender_port)
			_udp.put_packet(_broadcast_payload().to_utf8_buffer())
		elif data.begins_with(HOST_RF + "|") and role != Role.HOST:
			# We're in the menu (solo) or already a client: collect the reply.
			var parts := data.split("|")
			if parts.size() >= 3:
				var peer_port := int(parts[2])
				var already := false
				for s in discovered:
					if s.ip == sender_ip and s.port == peer_port:
						already = true
						break
				if not already:
					discovered.append({
						"name": parts[1],
						"ip": sender_ip,
						"port": peer_port,
					})
