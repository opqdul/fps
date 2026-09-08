extends CanvasLayer

## Scoreboard: hold TAB to see connected players and their ping.

@onready var list_box: VBoxContainer = $Center/Panel/VBox/List

var _refresh_t := 0.0

func _unhandled_input(event: InputEvent) -> void:
	if Net.role == Net.Role.SOLO:
		return
	if event.is_action_pressed("scoreboard"):
		visible = true
		_refresh()
		_refresh_t = 0.0
	elif event.is_action_released("scoreboard"):
		visible = false

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_t += delta
	if _refresh_t >= 0.5:
		_refresh_t = 0.0
		_refresh()

func _refresh() -> void:
	for child in list_box.get_children():
		child.queue_free()
	var my_id := multiplayer.get_unique_id()
	# Players we know about, plus ourselves (in case we haven't spawned yet).
	var ids: Array = []
	var seen := {}
	for id in Net.players:
		ids.append(id)
		seen[id] = true
	if not seen.has(my_id):
		ids.append(my_id)
	for id in ids:
		var row := Label.new()
		var name_str: String = Net.players.get(id, "Player %d" % id)
		var ping_ms: int = Net.pings.get(id, 0) if id != my_id else 0
		var marker := " (you)" if id == my_id else ""
		row.text = "%s%s  —  %d ms" % [name_str, marker, ping_ms]
		row.add_theme_font_size_override("font_size", 20)
		list_box.add_child(row)
