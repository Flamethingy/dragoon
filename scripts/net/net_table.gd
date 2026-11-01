class_name NetTable
extends Node
## TASK-5 spike: the DM hosts the table over ENet, players join by IP and port.
## The DM instance owns all state: players only *request* moves, the host validates
## them, writes a `token.moved` event to the campaign's EventLog and broadcasts the
## result; everyone (host included) then moves the token. New players get a full sync.
## Command line: `-- --host[=port]` or `-- --join=ip:port` to start right away.

signal status_changed(text: String)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8

## Where the campaign's event log lives (one per campaign).
@export var log_path := "user://campaigns/example/events.jsonl"
@export var auto_ui := true

var grid: TokenGrid
var event_log: EventLog  ## host only
var status := "Offline"

var _address: LineEdit
var _host_button: Button
var _join_button: Button
var _status_label: Label


func _ready() -> void:
	grid = TokenGrid.new()
	grid.name = "Grid"
	add_child(grid)
	grid.move_requested.connect(_on_move_requested)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(func(id: int) -> void: _set_status("Player %d left" % id))
	multiplayer.connected_to_server.connect(func() -> void: _set_status("Joined as player %d" % multiplayer.get_unique_id()))
	multiplayer.connection_failed.connect(func() -> void: _set_status("Could not connect"))
	multiplayer.server_disconnected.connect(func() -> void: _set_status("The DM closed the table"))
	if auto_ui:
		_build_ui()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--host"):
			host(int(arg.get_slice("=", 1)) if "=" in arg else DEFAULT_PORT)
		elif arg.begins_with("--join="):
			join(arg.get_slice("=", 1))


# --- Hosting and joining -----------------------------------------------------------

## The DM: opens the event log (so the table continues where it stopped) and listens.
func host(port := DEFAULT_PORT) -> Error:
	event_log = EventLog.open(log_path)
	var placed := Replay.tokens_on(grid.map_id, event_log.effective())
	for id: String in placed:
		grid.set_token_cell(id, placed[id], false)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		_set_status("Can't host on port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	_set_status("Hosting on port %d (%d events in the log)" % [port, event_log.events.size()])
	return OK


## A player: "ip:port" or just "ip".
func join(address: String) -> Error:
	var ip := address.get_slice(":", 0).strip_edges()
	var port := int(address.get_slice(":", 1)) if ":" in address else DEFAULT_PORT
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip if ip != "" else "127.0.0.1", port)
	if err != OK:
		_set_status("Can't join %s: %s" % [address, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	_set_status("Joining %s:%d..." % [ip, port])
	return OK


func is_dm() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server() \
		and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func _on_peer_connected(id: int) -> void:
	if is_dm():
		_set_status("Player %d joined" % id)
		var cells := {}
		for t: String in grid.tokens:
			cells[t] = grid.token_cell(t)
		sync_tokens.rpc_id(id, cells)


# --- Moves -------------------------------------------------------------------------

## Dropped a token here: the DM decides directly, players ask the DM.
func _on_move_requested(entity: String, cell: Vector2i) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_set_status("Host or join a table first")
	elif is_dm():
		_handle_move(1, entity, cell)
	else:
		request_move.rpc_id(1, entity, cell)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_move(entity: String, cell: Vector2i) -> void:
	if not is_dm():
		return  # only the DM decides
	_handle_move(multiplayer.get_remote_sender_id(), entity, cell)


## The DM validates, logs and broadcasts (or tells the player no).
func _handle_move(sender: int, entity: String, cell: Vector2i) -> void:
	if not grid.tokens.has(entity):
		_deny(sender, entity, "unknown token")
		return
	if not grid.can_place(entity, cell):
		_deny(sender, entity, "that square is blocked")
		return
	var from := grid.token_cell(entity)
	var by := "dm" if sender == 1 else "player:%d" % sender
	var e := event_log.move_token(entity, grid.map_id, from, cell, by)
	token_moved.rpc(entity, cell, int(e.get("id", 0)))


## DM -> everyone (the DM too): the move happened.
@rpc("authority", "call_local", "reliable")
func token_moved(entity: String, cell: Vector2i, event_id: int) -> void:
	grid.set_token_cell(entity, cell)
	_set_status("%s moved to %s (event %d)" % [_name_of(entity), cell, event_id])


## DM -> one player: the move was refused.
@rpc("authority", "call_local", "reliable")
func move_denied(entity: String, reason: String) -> void:
	_set_status("Can't move %s: %s" % [_name_of(entity), reason])


func _deny(sender: int, entity: String, reason: String) -> void:
	if sender == 1:
		move_denied(entity, reason)
	else:
		move_denied.rpc_id(sender, entity, reason)


## DM -> a new player: where every token is.
@rpc("authority", "call_remote", "reliable")
func sync_tokens(cells: Dictionary) -> void:
	for id: String in cells:
		grid.set_token_cell(id, cells[id], false)


func _name_of(entity: String) -> String:
	return str(grid.entities.get(entity, {}).get("frontmatter", {}).get("name", entity))


# --- UI ----------------------------------------------------------------------------

func _set_status(text: String) -> void:
	status = text
	if _status_label:
		_status_label.text = text
	status_changed.emit(text)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bar := PanelContainer.new()
	bar.theme = UISkin.theme()
	bar.theme_type_variation = UISkin.V_PAGE
	bar.position = Vector2(12, 40)
	layer.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	_address = LineEdit.new()
	_address.text = "127.0.0.1:%d" % DEFAULT_PORT
	_address.custom_minimum_size = Vector2(190, 0)
	_address.tooltip_text = "IP and port to join (Host uses the port)"
	row.add_child(_address)
	_host_button = Button.new()
	_host_button.text = "Host as DM"
	_host_button.pressed.connect(func() -> void:
		var port := int(_address.text.get_slice(":", 1)) if ":" in _address.text else DEFAULT_PORT
		if host(port) == OK:
			_lock_buttons())
	row.add_child(_host_button)
	_join_button = Button.new()
	_join_button.text = "Join"
	_join_button.pressed.connect(func() -> void:
		if join(_address.text) == OK:
			_lock_buttons())
	row.add_child(_join_button)
	_status_label = Label.new()
	_status_label.text = status
	_status_label.custom_minimum_size = Vector2(280, 0)
	row.add_child(_status_label)


func _lock_buttons() -> void:
	_host_button.disabled = true
	_join_button.disabled = true
	_address.editable = false
