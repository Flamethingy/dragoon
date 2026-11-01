class_name NetTable
extends Node
## TASK-5 spike: the DM hosts the table over ENet, players join by IP and port.
## The DM instance owns all state: players only *request* moves, the host validates
## them, writes a `token.moved` event to the campaign's EventLog and broadcasts the
## result; everyone (host included) then moves the token. New players get a full sync.
## Command line: `-- --host[=port]` or `-- --join=ip:port` to start right away.
## Session notes (TASK-14) go the same way: players send a note, the DM stamps it with the
## real date, session number and in-world moment, saves it and shares it with everyone.

signal status_changed(text: String)
signal notes_changed

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8

## Where the campaign's event log lives (one per campaign).
@export var log_path := "user://campaigns/example/events.jsonl"
@export var auto_ui := true
@export var calendar_path := "res://calendars/default.json"
## Shown on notes; empty = "DM" or "Player <id>" (names come with the lobby, TASK-8).
@export var player_name := ""

var grid: TokenGrid
var event_log: EventLog  ## host only
var status := "Offline"
## Notes of the current session: the DM's writes the file, the players' only shows them.
var notes: SessionNotes

var _address: LineEdit
var _host_button: Button
var _join_button: Button
var _status_label: Label
var _notes_title: Label
var _notes_text: RichTextLabel
var _note_edit: TextEdit
var _next_session: Button


func _ready() -> void:
	grid = TokenGrid.new()
	grid.name = "Grid"
	add_child(grid)
	grid.move_requested.connect(_on_move_requested)
	notes = SessionNotes.new()
	notes.calendar = WorldCalendar.load_file(calendar_path)
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
	_open_notes()
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
		sync_notes.rpc_id(id, notes.session, notes.entries)


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


# --- Session notes -----------------------------------------------------------------

## Writes a note: the DM directly, players through the DM.
func add_note(text: String) -> void:
	if text.strip_edges() == "":
		return
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_set_status("Host or join a table first")
	elif is_dm():
		_handle_note(1, text, player_name)
	else:
		request_note.rpc_id(1, text, player_name)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_note(text: String, author: String) -> void:
	if is_dm():
		_handle_note(multiplayer.get_remote_sender_id(), text, author)


func _handle_note(sender: int, text: String, author: String) -> void:
	var by := author if author != "" else ("DM" if sender == 1 else "Player %d" % sender)
	var entry := notes.add(text.left(10000), by, event_log.day, event_log.time)
	note_added.rpc(entry)


## DM -> everyone: a new note (the DM's own list already has it).
@rpc("authority", "call_local", "reliable")
func note_added(entry: Dictionary) -> void:
	if not is_dm():
		notes.entries.append(entry)
	_show_notes()


## DM -> players: all notes of the current session (on join and when a session starts).
@rpc("authority", "call_remote", "reliable")
func sync_notes(session: int, entries: Array) -> void:
	notes.session = session
	notes.entries.clear()
	for e: Dictionary in entries:
		notes.entries.append(e)
	_show_notes()


## DM: the next session starts (an event in the log; notes go to a new file).
func start_next_session() -> void:
	if not is_dm():
		return
	event_log.start_session(event_log.session + 1)
	_open_notes()
	sync_notes.rpc(notes.session, notes.entries)
	_set_status("Session %d started" % event_log.session)


func _open_notes() -> void:
	notes = SessionNotes.open(log_path.get_base_dir(), event_log.session, notes.calendar)
	_show_notes()


func _show_notes() -> void:
	notes_changed.emit()
	if _notes_text == null:
		return
	_notes_title.text = "Notes · %s" % ("between sessions" if notes.session <= 0 else "Session %d" % notes.session)
	var parts := PackedStringArray()
	for e in notes.entries:
		parts.append("[color=#%s][font_size=12]%s[/font_size][/color]
%s" % [
			Markdown.MUTED.to_html(false), Markdown.escape(notes.heading(e)), Markdown.to_bbcode(str(e.text))])
	_notes_text.text = "

".join(parts) if not parts.is_empty() else 		"[color=#%s]No notes yet.[/color]" % Markdown.MUTED.to_html(false)
	_notes_text.scroll_to_line(_notes_text.get_line_count())


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
	_build_notes_ui(layer)


func _build_notes_ui(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.theme = UISkin.theme()
	panel.theme_type_variation = UISkin.V_PAGE
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -400
	panel.offset_right = -12
	panel.offset_top = 40
	panel.offset_bottom = -12
	layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_notes_title = Label.new()
	_notes_title.theme_type_variation = UISkin.V_HEADING
	_notes_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_notes_title)
	_next_session = Button.new()
	_next_session.text = "Next session"
	_next_session.tooltip_text = "DM: start the next session (new notes file)"
	_next_session.visible = false
	_next_session.pressed.connect(start_next_session)
	head.add_child(_next_session)
	_notes_text = RichTextLabel.new()
	_notes_text.bbcode_enabled = true
	_notes_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes_text.scroll_following = true
	_notes_text.selection_enabled = true
	col.add_child(_notes_text)
	_note_edit = TextEdit.new()
	_note_edit.placeholder_text = "Write a note (markdown)... Ctrl+Enter adds it"
	_note_edit.custom_minimum_size = Vector2(0, 90)
	_note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note_edit.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and event.ctrl_pressed:
			_submit_note()
			_note_edit.accept_event())
	col.add_child(_note_edit)
	var add := Button.new()
	add.text = "Add note"
	add.size_flags_horizontal = Control.SIZE_SHRINK_END
	add.pressed.connect(_submit_note)
	col.add_child(add)
	_show_notes()


func _submit_note() -> void:
	add_note(_note_edit.text)
	_note_edit.text = ""


func _lock_buttons() -> void:
	_host_button.disabled = true
	_join_button.disabled = true
	_address.editable = false
	_next_session.visible = is_dm()
