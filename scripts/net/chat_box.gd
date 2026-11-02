class_name ChatBox
extends PanelContainer
## The chat of the calm table (TASK-46, Nico 2026-11-01): the session's messages and rolls in
## one feed (NetTable.rolls) and a line to write in. Enter sends and gives the keys back to the
## map; "/r 2d6+3" or "/r perception" rolls (for the active character when there is one).
## It docks like a panel in an IDE (TASK-50, Nico 2026-11-02): drag it by its title to the
## left, right or bottom edge (the zones light up), or let it go anywhere else to float,
## snapped to the HUD grid's cells. Its inner edge (floating: the lower right corner) resizes
## it. "Pop out" puts it in its own window (e.g. on a second screen); closing that window
## docks it back. Where it is belongs to the player, not the character: it is saved on this
## computer (`place_file`) and stays when the active character changes.

signal place_changed

const TOP := 2  ## rows left free at the top (the app's buttons)
const EDGE := 8.0  ## pixels at the inner edge that resize
const ZONE := 0.08  ## the dock zones: this part of the screen at each edge
const SIDE_CELLS := Vector2i(6, 24)  ## width of a side dock, min / max
const BOTTOM_CELLS := Vector2i(4, 14)  ## height of the bottom dock, min / max

var table: NetTable
var active_ref := Callable()  ## -> String: who "/r" rolls for (the HUD's active one)
var log_text: RichTextLabel
var line: LineEdit
## dock: "left" / "right" / "bottom" / "float"; side: cells of a side dock, bottom: rows of
## the bottom dock; r: the floating rect in cells; window: popped out.
var place := {"dock": "right", "side": 10, "bottom": 7, "r": [30, 6, 12, 16], "window": false}
var place_file := ""  ## "" = user://chat.cfg (a table with its own cache folder, e.g. in tests: there)
var window: Window  ## its own window while popped out
var _head: HBoxContainer
var _drag := ""  ## "move" / "resize" while the mouse is down
var _grab := Vector2.ZERO  ## where the title was grabbed
var _zones: Control  ## the dock zones while it is moved
var _home: Node  ## where it lives when docked
var _home_index := -1
var _restored := false  ## the first show: back into its own window if it was there last time


func _init() -> void:
	name = "Chat"
	theme_type_variation = UISkin.V_PAGE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	_head = HBoxContainer.new()
	_head.name = "Head"
	_head.mouse_filter = Control.MOUSE_FILTER_STOP
	_head.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_head.tooltip_text = "Drag: dock it left, right or at the bottom, or let it float"
	_head.gui_input.connect(_head_input)
	col.add_child(_head)
	var title := Label.new()
	title.text = "Chat"
	title.theme_type_variation = UISkin.V_HEADING
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.add_child(title)
	var pop := Button.new()
	pop.name = "PopOut"
	pop.text = "Pop out"
	pop.focus_mode = Control.FOCUS_NONE
	pop.add_theme_font_size_override("font_size", 12)
	pop.tooltip_text = "In its own window (close it to dock it back)"
	pop.pressed.connect(func() -> void:
		if window == null:
			pop_out()
		else:
			dock_back())
	_head.add_child(pop)
	log_text = RichTextLabel.new()
	log_text.name = "Log"
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.selection_enabled = true
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.meta_clicked.connect(func(meta: Variant) -> void:
		if str(meta).begins_with("cond:") and table != null:  # a roll card's creature: its conditions (TASK-56)
			table.condition_menu_requested.emit(str(meta).substr(5))
		elif str(meta).begins_with("init:") and table != null:  # an initiative prompt (TASK-58)
			table.answer_initiative(str(meta).substr(5))
		elif str(meta).begins_with("conc:") and table != null:  # a concentration save (TASK-59)
			table.answer_concentration(str(meta).substr(5))
		elif str(meta).begins_with("endconc:") and table != null:
			table.end_concentration(str(meta).substr(8), "failed the save")
		elif str(meta).begins_with("death:") and table != null:  # a death save prompt (TASK-57)
			table.roll_death_save(str(meta).substr(6))
		elif str(meta).begins_with("save:") and table != null:  # a save prompt (TASK-55)
			table.answer_save(int(str(meta).get_slice(":", 1)), str(meta).substr(str(meta).find(":", 5) + 1))
		elif str(meta).begins_with("undo:") and table != null:  # an attack card's damage (TASK-54)
			table.undo_card(int(str(meta).substr(5)))
		elif str(meta).begins_with("apply:") and table != null:
			table.apply_card(int(str(meta).get_slice(":", 1)), str(meta).substr(str(meta).find(":", 6) + 1))
		else:
			RollTables.handle_meta(str(meta)))
	col.add_child(log_text)
	line = LineEdit.new()
	line.name = "Line"
	line.placeholder_text = "Write something...  (/r 1d20+3 rolls)"
	line.text_submitted.connect(func(_t: String) -> void: send())
	col.add_child(line)
	visibility_changed.connect(_on_visibility)


func _ready() -> void:
	if table != null and not table.rolls_changed.is_connected(refresh):
		table.rolls_changed.connect(refresh)
		table.accounts_changed.connect(refresh)
	if place_file == "":
		place_file = "user://chat.cfg" if table == null or table.cache_dir == "user://cache/assets" else table.cache_dir.path_join("chat.cfg")
	if _home == null:
		_home = get_parent()
		if _home is Control and not (_home as Control).resized.is_connected(apply):
			(_home as Control).resized.connect(apply)
		load_place()
	refresh()


## Sends the line: a message, or a roll with "/r".
func send() -> void:
	var text := line.text.strip_edges()
	line.text = ""
	line.release_focus()  # the map gets its keys back (WASD, Q / E)
	if text == "" or table == null:
		return
	table.say(text, str(active_ref.call()) if active_ref.is_valid() else "")


func refresh() -> void:
	if table == null:
		return
	var parts := PackedStringArray()
	for r: Dictionary in table.rolls:
		parts.append(NetTable.roll_bbcode(r, table.notes.names))
	log_text.text = "\n\n".join(parts) if not parts.is_empty() else "[color=#%s]Nothing said yet.[/color]" % Markdown.MUTED.to_html(false)


# --- Where it is -------------------------------------------------------------------------------

func load_place() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(place_file) == OK:
		var saved: Variant = cfg.get_value("chat", "place", {})
		if saved is Dictionary:
			place.merge(saved, true)
	if str(place.dock) not in ["left", "right", "bottom", "float"]:
		place.dock = "right"
	apply()


func save_place() -> void:
	var cfg := ConfigFile.new()
	cfg.load(place_file)
	cfg.set_value("chat", "place", place)
	cfg.save(place_file)
	place_changed.emit()


## The screen it docks on (its home's size) and one grid cell of it.
func area() -> Vector2:
	var home := _home if _home != null else get_parent()
	if home is Control and (home as Control).size.x > 0:
		return (home as Control).size
	return get_viewport_rect().size if is_inside_tree() else Vector2(1600, 900)


func cell() -> Vector2:
	return area() / Vector2(HudWidgets.HUD_GRID)


## Its rect in cells, from the dock.
func cells_rect() -> Rect2i:
	var g := HudWidgets.HUD_GRID
	match str(place.dock):
		"left":
			return Rect2i(0, TOP, clampi(int(place.side), SIDE_CELLS.x, SIDE_CELLS.y), g.y - TOP)
		"right":
			var w := clampi(int(place.side), SIDE_CELLS.x, SIDE_CELLS.y)
			return Rect2i(g.x - w, TOP, w, g.y - TOP)
		"bottom":
			var h := clampi(int(place.bottom), BOTTOM_CELLS.x, BOTTOM_CELLS.y)
			return Rect2i(0, g.y - h, g.x, h)
	var r: Array = place.r
	var fw := clampi(int(r[2]), 6, g.x)
	var fh := clampi(int(r[3]), 4, g.y)
	return Rect2i(clampi(int(r[0]), 0, g.x - fw), clampi(int(r[1]), 0, g.y - fh), fw, fh)


## Puts it where `place` says (nothing to do in its own window).
func apply() -> void:
	if window != null:
		return
	var r := cells_rect()
	var c := cell()
	var px := Rect2(Vector2(r.position) * c, Vector2(r.size) * c).grow(-4)
	position = px.position
	size = px.size


## Docks it: "left", "right", "bottom"; or "float" at `r` (cells).
func dock(where: String, r := Rect2i()) -> void:
	place.dock = where
	if where == "float" and r.has_area():
		place.r = [r.position.x, r.position.y, r.size.x, r.size.y]
	apply()
	save_place()


## The dock zone under `at` (its home's pixels), "" for none.
func zone_at(at: Vector2) -> String:
	var a := area()
	if at.x < a.x * ZONE:
		return "left"
	if at.x > a.x * (1.0 - ZONE):
		return "right"
	if at.y > a.y * (1.0 - ZONE * 1.3):
		return "bottom"
	return ""


## A move ended with the mouse at `at`: it docks on a zone, else floats where it is.
func end_move(at: Vector2) -> void:
	var z := zone_at(at)
	if z != "":
		dock(z)
		return
	var c := cell()
	var r: Array = place.r
	dock("float", Rect2i(Vector2i((position / c).round()), Vector2i(int(r[2]), int(r[3]))))


func _head_input(event: InputEvent) -> void:
	if window != null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var at := _home_pos()
		if event.pressed:
			_drag = "move"
			var r: Array = place.r  # it takes its floating size while it is carried
			size = Vector2(float(r[2]), float(r[3])) * cell() - Vector2(8, 8)
			_grab = Vector2(minf(at.x - position.x, size.x - 40), clampf(at.y - position.y, 4, 30))
			_show_zones(true)
		elif _drag == "move":
			_drag = ""
			_show_zones(false)
			end_move(at)
		_head.accept_event()
	elif event is InputEventMouseMotion and _drag == "move":
		position = _home_pos() - _grab
		if _zones != null:
			_zones.set_meta("hot", zone_at(_home_pos()))
			_zones.queue_redraw()
		_head.accept_event()


## The inner edge (floating: the lower right corner) resizes it, by whole cells.
func _gui_input(event: InputEvent) -> void:
	if window != null:
		return
	var local := get_local_mouse_position()
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _on_edge(local):
			_drag = "resize"
			accept_event()
		elif not event.pressed and _drag == "resize":
			_drag = ""
			save_place()
			accept_event()
	elif event is InputEventMouseMotion:
		if _drag == "resize":
			_resize_to(_home_pos())
			accept_event()
		else:
			mouse_default_cursor_shape = _edge_cursor() if _on_edge(local) else Control.CURSOR_ARROW


## Resizes it so its inner edge is at `at` (its home's pixels).
func _resize_to(at: Vector2) -> void:
	var c := cell()
	var g := HudWidgets.HUD_GRID
	match str(place.dock):
		"right":
			place.side = clampi(int(roundf(g.x - at.x / c.x)), SIDE_CELLS.x, SIDE_CELLS.y)
		"left":
			place.side = clampi(int(roundf(at.x / c.x)), SIDE_CELLS.x, SIDE_CELLS.y)
		"bottom":
			place.bottom = clampi(int(roundf(g.y - at.y / c.y)), BOTTOM_CELLS.x, BOTTOM_CELLS.y)
		_:
			var r: Array = place.r
			place.r = [r[0], r[1], maxi(6, int(roundf(at.x / c.x)) - int(r[0])), maxi(4, int(roundf(at.y / c.y)) - int(r[1]))]
	apply()


func _on_edge(local: Vector2) -> bool:
	match str(place.dock):
		"right":
			return local.x < EDGE
		"left":
			return local.x > size.x - EDGE
		"bottom":
			return local.y < EDGE
	return local.x > size.x - EDGE * 2 and local.y > size.y - EDGE * 2


func _edge_cursor() -> Control.CursorShape:
	match str(place.dock):
		"left", "right":
			return Control.CURSOR_HSIZE
		"bottom":
			return Control.CURSOR_VSIZE
	return Control.CURSOR_FDIAGSIZE


func _home_pos() -> Vector2:
	var home := _home if _home is Control else get_parent()
	return (home as Control).get_local_mouse_position() if home is Control else get_global_mouse_position()


## The dock zones, lit while the chat is carried (the one under the mouse brighter).
func _show_zones(on: bool) -> void:
	if not on:
		if _zones != null:
			_zones.queue_free()
			_zones = null
		return
	if _zones != null or not _home is Control:
		return
	_zones = Control.new()
	_zones.name = "DockZones"
	_zones.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zones.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_zones.draw.connect(func() -> void:
		var a := area()
		var hot := str(_zones.get_meta("hot", ""))
		var rects := {"left": Rect2(0, 0, a.x * ZONE, a.y), "right": Rect2(a.x * (1.0 - ZONE), 0, a.x * ZONE, a.y),
			"bottom": Rect2(a.x * ZONE, a.y * (1.0 - ZONE * 1.3), a.x * (1.0 - ZONE * 2), a.y * ZONE * 1.3)}
		for z: String in rects:
			_zones.draw_rect(rects[z], Color(1.0, 0.55, 0.1, 0.45 if z == hot else 0.15))
			_zones.draw_rect(rects[z], Color(1.0, 0.55, 0.1, 0.9), false, 2.0))
	(_home as Control).add_child(_zones)
	(_home as Control).move_child(_zones, get_index())


# --- Its own window --------------------------------------------------------------------------

## Into its own (native) window, e.g. for a second screen.
func pop_out() -> void:
	if window != null or _home == null:
		return
	var at := global_position
	_home_index = get_index()
	window = Window.new()
	window.name = "ChatWindow"
	window.title = "Dragoon · Chat"
	window.visible = false  # force_native can only be set on a hidden window
	window.force_native = true
	window.theme = UISkin.theme()
	window.size = Vector2i(maxi(int(size.x), 320), maxi(int(size.y), 400))
	if is_inside_tree():
		window.position = get_window().position + Vector2i(at)
	window.close_requested.connect(dock_back)
	var bg := Panel.new()  # the window's paper
	bg.theme_type_variation = UISkin.V_PAGE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(bg)
	_home.remove_child(self)
	window.add_child(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_home.add_child(window)
	window.visible = visible
	(_head.get_node("PopOut") as Button).text = "Dock"
	place.window = true
	save_place()


## Back from its own window to its dock.
func dock_back() -> void:
	if window == null:
		return
	var w := window
	window = null
	place.window = false
	w.remove_child(self)
	_home.add_child(self)
	if _home_index >= 0:
		_home.move_child(self, mini(_home_index, _home.get_child_count() - 1))
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	w.queue_free()
	(_head.get_node("PopOut") as Button).text = "Pop out"
	place.window = false
	apply()
	save_place()


func _on_visibility() -> void:
	if window != null:
		window.visible = visible
	elif visible and is_inside_tree() and not _restored:
		_restored = true
		if bool(place.get("window", false)):
			pop_out.call_deferred()  # it was in its own window last time
