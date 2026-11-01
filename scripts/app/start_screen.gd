class_name StartScreen
extends PanelContainer
## The app's start screen (TASK-33, TASK-38).
## Left, the worlds: a card per world (picture, name, description) with its timelines;
## clicking a timeline hosts it. New world, New timeline (per world) and Edit world are there.
## Middle, the saved servers with a live status dot (ServerStatus heartbeat every 10 s);
## clicking an online server joins it. The compendium stays one click away.

signal host_requested(timeline_dir: String, port: int)
signal join_requested(address: String, player_name: String)
signal compendium_requested(timeline_dir: String)
signal edit_world_requested(world_dir: String)

const POLL_SECONDS := 10.0
const DOT := {"checking": Color("#b8a888"), "online": Color("#3f8f4f"), "offline": Color("#9a3b3b"), "mismatch": Color("#c88a2a")}

var worlds_root := ""
var port_edit: LineEdit
var name_edit: LineEdit
var status: Label
var worlds_box: VBoxContainer
var servers_box: VBoxContainer
var servers: Array = []  ## [{name, address, port}] (ServerStatus.servers_file)
var probes: Array = []  ## ServerStatus.Probe per server (null before the first check)
var poll_timer: Timer

var _world := ""  ## the last used world folder
var _timeline := ""  ## the last used timeline folder


func _ready() -> void:
	theme_type_variation = UISkin.V_COVER
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	var plate := PanelContainer.new()
	plate.theme_type_variation = UISkin.V_PLATE
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(plate)
	var title := Label.new()
	title.text = "Dragoon"
	title.theme_type_variation = UISkin.V_PLATE_LABEL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	# Worlds
	var worlds := _panel(row, "Worlds  ·  host a timeline as DM", 1.4)
	var wbar := HBoxContainer.new()
	wbar.add_theme_constant_override("separation", 6)
	worlds.add_child(wbar)
	_button(wbar, "New world...", "A new world, with its start timeline (the Prologue)", _new_world_dialog).name = "NewWorld"
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wbar.add_child(spacer)
	wbar.add_child(_muted("Port"))
	port_edit = LineEdit.new()
	port_edit.name = "Port"
	port_edit.text = str(NetTable.DEFAULT_PORT)
	port_edit.custom_minimum_size = Vector2(80, 0)
	port_edit.tooltip_text = "Hosting uses this port (UDP for the game, TCP for the heartbeat)"
	wbar.add_child(port_edit)
	worlds_box = VBoxContainer.new()
	worlds_box.name = "WorldCards"
	worlds_box.add_theme_constant_override("separation", 10)
	worlds.add_child(_scroll(worlds_box))

	# Servers
	var srv := _panel(row, "Servers  ·  join as a player", 1.0)
	var nrow := HBoxContainer.new()
	srv.add_child(nrow)
	nrow.add_child(_muted("Your name"))
	name_edit = LineEdit.new()
	name_edit.name = "PlayerName"
	name_edit.placeholder_text = "as the DM knows you"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(name_edit)
	var sbar := HBoxContainer.new()
	sbar.add_theme_constant_override("separation", 6)
	srv.add_child(sbar)
	_button(sbar, "Add server...", "Save a table's address", func() -> void: server_dialog(-1)).name = "AddServer"
	_button(sbar, "Check now", "Ask every server for its status", probe_all).name = "CheckServers"
	servers_box = VBoxContainer.new()
	servers_box.name = "ServerRows"
	servers_box.add_theme_constant_override("separation", 6)
	srv.add_child(_scroll(servers_box))

	# Compendium
	var book := _panel(row, "Compendium", 0.55)
	var hint := _muted("The books and source packages, without a session.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	book.add_child(hint)
	_button(book, "Open the compendium", "Browse and edit the books", func() -> void:
		compendium_requested.emit("")).name = "OpenCompendium"

	status = Label.new()
	status.add_theme_color_override("font_color", UISkin.TAN)  # on the dark cover
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status)

	poll_timer = Timer.new()
	poll_timer.wait_time = POLL_SECONDS
	poll_timer.timeout.connect(probe_all)
	add_child(poll_timer)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			poll_timer.start()
			probe_all()
		else:
			poll_timer.stop())
	load_servers()


# --- Worlds -------------------------------------------------------------------------------

## Fills the world cards; `world_dir` / `timeline` mark the last used ones.
func refresh(world_dir := "", timeline := "") -> void:
	if timeline != "" and world_dir == "":
		world_dir = timeline.get_base_dir().get_base_dir()
	_world = world_dir
	_timeline = timeline
	if worlds_box == null:
		return
	for c in worlds_box.get_children():
		worlds_box.remove_child(c)
		c.queue_free()
	var all := Worlds.list(worlds_root)
	if all.is_empty():
		worlds_box.add_child(_muted("No worlds yet: make one with New world."))
	for w in all:
		worlds_box.add_child(_world_card(w))


func _world_card(w: Dictionary) -> Control:
	var dir := str(w._dir)
	var card := PanelContainer.new()
	card.name = "World_" + str(w.get("id", ""))
	card.theme_type_variation = UISkin.V_PAGE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(110, 110)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.texture = world_picture(w)
	row.add_child(pic)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var head := Label.new()
	head.text = str(w.get("name", w.get("id", "")))
	head.theme_type_variation = UISkin.V_HEADING
	col.add_child(head)
	var desc := str(w.get("description", "")).strip_edges()
	if desc != "":
		var d := _muted(desc)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.max_lines_visible = 3
		col.add_child(d)
	for t in Timeline.list(dir):
		var b := Button.new()
		var tdir := str(t._dir)
		b.name = "Timeline_" + str(t.get("id", ""))
		b.text = timeline_line(t)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "Host this timeline as DM"
		b.icon = UISkin.tex("arrow_right")
		if tdir.simplify_path() == _timeline.simplify_path():
			b.add_theme_color_override("font_color", UISkin.WINE)
			b.text += "  (last played here)"
		b.pressed.connect(func() -> void: host_timeline(tdir))
		col.add_child(b)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	col.add_child(bar)
	_button(bar, "New timeline...", "Fork one of this world's timelines at a point of its history", func() -> void:
		_new_timeline_dialog(dir)).name = "NewTimeline"
	_button(bar, "Edit world", "The world's NPCs, places, maps, factions and lore", func() -> void:
		edit_world_requested.emit(dir)).name = "EditWorld"
	return card


## "Name · fork of x · 3 sessions · played 2026-11-01".
static func timeline_line(t: Dictionary) -> String:
	var parts := PackedStringArray([str(t.get("name", t.get("id", "")))])
	if str(t.get("parent", "")) != "":
		parts.append("fork of %s" % t.parent)
	var sessions := maxi(int(t.get("next_session", 1)) - 1, 0)
	parts.append("%d session%s" % [sessions, "" if sessions == 1 else "s"])
	var log_file := str(t._dir).path_join("events.jsonl")
	if FileAccess.file_exists(log_file) and FileAccess.get_file_as_string(log_file).strip_edges() != "":
		parts.append("played " + Time.get_date_string_from_unix_time(FileAccess.get_modified_time(log_file)))
	else:
		parts.append("not played yet")
	return "  ·  ".join(parts)


## The world's picture: its own `image`, else its first world map, else none.
static func world_picture(w: Dictionary) -> Texture2D:
	var dir := str(w._dir)
	var rel := str(w.get("image", ""))
	if rel == "":
		var maps: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("maps.json"))) if FileAccess.file_exists(dir.path_join("maps.json")) else null
		if maps is Array:
			for m: Variant in maps:
				if m is Dictionary and str(m.get("image", "")) != "" and (rel == "" or str(m.get("kind", "")) == "world"):
					rel = str(m.image)
	var path := dir.path_join(rel)
	if rel == "" or not FileAccess.file_exists(path):
		return UISkin.tex("icon_chest")
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img != null else null


func host_timeline(timeline_dir: String) -> void:
	_timeline = timeline_dir
	host_requested.emit(timeline_dir, int(port_edit.text) if port_edit.text.is_valid_int() else NetTable.DEFAULT_PORT)


## The last used world and timeline.
func world_dir() -> String:
	return _world


func timeline_dir() -> String:
	return _timeline


func _new_world_dialog() -> void:
	var d := ConfirmationDialog.new()
	d.name = "NewWorldDialog"
	d.title = "New world"
	d.ok_button_text = "Create"
	var col := VBoxContainer.new()
	d.add_child(col)
	col.add_child(_muted("Name"))
	var n := LineEdit.new()
	n.name = "WorldName"
	n.custom_minimum_size = Vector2(320, 0)
	col.add_child(n)
	col.add_child(_muted("Calendar"))
	var cal := OptionButton.new()
	cal.name = "Calendar"
	for c in calendars():
		cal.add_item(c)
	col.add_child(cal)
	d.confirmed.connect(func() -> void:
		create_world(n.text, cal.get_item_text(cal.selected) if cal.selected >= 0 else "default")
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


## Makes a world (and its Prologue). Returns the folder ("" if no name).
func create_world(world_name: String, calendar := "default") -> String:
	if world_name.strip_edges() == "":
		status.text = "Give the world a name."
		return ""
	var dir := Worlds.create(world_name.strip_edges(), calendar, worlds_root)
	refresh(dir, Worlds.start_timeline(dir))
	status.text = "Created %s with its start timeline, the Prologue." % world_name.strip_edges()
	return dir


## Calendar ids from res://calendars.
static func calendars() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at("res://calendars"):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	if out.is_empty():
		out.append("default")
	return out


func _new_timeline_dialog(world: String) -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.name = "NewTimelineDialog"
	d.title = "New timeline"
	d.ok_button_text = "Create"
	var form := NewTimelineForm.new()
	form.name = "Form"
	form.world_dir = world
	form.parent_dir = _timeline if _timeline.begins_with(world) else ""
	d.add_child(form)
	d.confirmed.connect(func() -> void:
		var made := form.create()
		if made != "":
			refresh(world, made)
			status.text = "Created the timeline %s." % form.name_edit.text
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(560, 0))
	return d


# --- Servers ----------------------------------------------------------------------------------

func load_servers() -> void:
	servers = ServerStatus.load_servers()
	probes = []
	probes.resize(servers.size())
	_fill_servers()


func add_server(server_name: String, address: String, port: int) -> void:
	servers.append({"name": server_name.strip_edges() if server_name.strip_edges() != "" else address, "address": address.strip_edges(), "port": port})
	probes.append(null)
	_save_servers()


func edit_server(i: int, server_name: String, address: String, port: int) -> void:
	if i < 0 or i >= servers.size():
		return
	servers[i] = {"name": server_name.strip_edges() if server_name.strip_edges() != "" else address, "address": address.strip_edges(), "port": port}
	probes[i] = null
	_save_servers()


func remove_server(i: int) -> void:
	if i < 0 or i >= servers.size():
		return
	servers.remove_at(i)
	probes.remove_at(i)
	_save_servers()


func _save_servers() -> void:
	ServerStatus.save_servers(servers)
	_fill_servers()
	probe_all()


## Asks every saved server for its status (the answers come in over the next frames).
func probe_all() -> void:
	for i in servers.size():
		var s: Dictionary = servers[i]
		probes[i] = ServerStatus.Probe.new(str(s.address), int(s.get("port", NetTable.DEFAULT_PORT)))
	_fill_servers()


## checking, online, offline, mismatch (or "" before the first check).
func server_state(i: int) -> String:
	var p: ServerStatus.Probe = probes[i] if i < probes.size() else null
	return p.state if p != null else ""


func _process(_delta: float) -> void:
	var changed := false
	for p: Variant in probes:
		if p != null and (p as ServerStatus.Probe).state == "checking" and (p as ServerStatus.Probe).poll():
			changed = true
	if changed:
		_fill_servers()


func _fill_servers() -> void:
	if servers_box == null:
		return
	for c in servers_box.get_children():
		servers_box.remove_child(c)
		c.queue_free()
	if servers.is_empty():
		var none := _muted("No servers yet: add the address your DM gave you.")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		servers_box.add_child(none)
	for i in servers.size():
		servers_box.add_child(_server_row(i))


func _server_row(i: int) -> Control:
	var s: Dictionary = servers[i]
	var st := server_state(i)
	var p: ServerStatus.Probe = probes[i] if i < probes.size() else null
	var row := HBoxContainer.new()
	row.name = "Server_%d" % i
	row.add_theme_constant_override("separation", 6)
	var dot := Label.new()
	dot.name = "Dot"
	dot.text = "●"
	dot.add_theme_color_override("font_color", DOT.get(st, DOT.checking))
	dot.tooltip_text = {"online": "Online", "offline": "Offline", "mismatch": "Online, but another Dragoon version", "checking": "Checking..."}.get(st, "Not checked yet")
	row.add_child(dot)
	var join := Button.new()
	join.name = "Join"
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.alignment = HORIZONTAL_ALIGNMENT_LEFT
	join.clip_text = true
	var line := "%s   %s:%d" % [s.get("name", ""), s.get("address", ""), int(s.get("port", NetTable.DEFAULT_PORT))]
	if st == "online" and p != null:
		var players: Array = p.info.get("players", [])
		line += "\n%s · %s · DM %s · %d player%s online" % [p.info.get("world", ""), p.info.get("timeline", ""), p.info.get("dm", ""),
			players.size(), "" if players.size() == 1 else "s"]
		join.tooltip_text = "Join this table" + ("" if players.is_empty() else " (%s)" % ", ".join(players))
	elif st == "mismatch":
		line += "\nanother Dragoon version: update to join"
	elif st == "offline":
		line += "\noffline"
	join.text = line
	join.disabled = st != "online"
	join.pressed.connect(join_server.bind(i))
	row.add_child(join)
	_button(row, "Edit", "Change name or address", func() -> void: server_dialog(i)).name = "Edit"
	_button(row, "×", "Remove this server", func() -> void: remove_server(i)).name = "Remove"
	return row


## Joins a saved server (asks for the player name once if there is none).
func join_server(i: int) -> void:
	if i < 0 or i >= servers.size():
		return
	var s: Dictionary = servers[i]
	var address := "%s:%d" % [s.address, int(s.get("port", NetTable.DEFAULT_PORT))]
	if name_edit.text.strip_edges() != "":
		join_requested.emit(address, name_edit.text.strip_edges())
		return
	var d := ConfirmationDialog.new()
	d.name = "AskName"
	d.title = "Your player name"
	d.ok_button_text = "Join"
	var n := LineEdit.new()
	n.name = "Name"
	n.custom_minimum_size = Vector2(280, 0)
	n.placeholder_text = "as the DM knows you"
	d.add_child(n)
	d.confirmed.connect(func() -> void:
		name_edit.text = n.text.strip_edges()
		if name_edit.text != "":
			join_requested.emit(address, name_edit.text)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


## Add (i = -1) or edit a saved server.
func server_dialog(i: int) -> ConfirmationDialog:
	var s: Dictionary = servers[i] if i >= 0 and i < servers.size() else {"name": "", "address": "", "port": NetTable.DEFAULT_PORT}
	var d := ConfirmationDialog.new()
	d.name = "ServerDialog"
	d.title = "Add server" if i < 0 else "Edit server"
	d.ok_button_text = "Save"
	var col := VBoxContainer.new()
	d.add_child(col)
	col.add_child(_muted("Name"))
	var n := LineEdit.new()
	n.name = "ServerName"
	n.text = str(s.name)
	n.placeholder_text = "Thursday group"
	n.custom_minimum_size = Vector2(320, 0)
	col.add_child(n)
	col.add_child(_muted("Address (ip or host, optionally :port)"))
	var a := LineEdit.new()
	a.name = "ServerAddress"
	a.text = str(s.address)
	col.add_child(a)
	col.add_child(_muted("Port"))
	var p := LineEdit.new()
	p.name = "ServerPort"
	p.text = str(int(s.get("port", NetTable.DEFAULT_PORT)))
	col.add_child(p)
	d.confirmed.connect(func() -> void:
		var parts := ServerStatus.split_address(a.text, int(p.text) if p.text.is_valid_int() else NetTable.DEFAULT_PORT)
		if str(parts[0]) != "":
			if i < 0:
				add_server(n.text, parts[0], parts[1])
			else:
				edit_server(i, n.text, parts[0], parts[1])
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()
	return d


# --- Helpers --------------------------------------------------------------------------------

func _panel(parent: Control, heading: String, ratio: float) -> VBoxContainer:
	var page := PanelContainer.new()
	page.theme_type_variation = UISkin.V_PAGE
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_stretch_ratio = ratio
	parent.add_child(page)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	page.add_child(box)
	var h := Label.new()
	h.text = heading
	h.theme_type_variation = UISkin.V_HEADING
	box.add_child(h)
	return box


func _scroll(content: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc


func _muted(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = UISkin.V_MUTED
	return l


func _button(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(action)
	parent.add_child(b)
	return b
