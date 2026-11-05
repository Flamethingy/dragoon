class_name DockPanel
extends PanelContainer
## A panel that docks like one in an IDE (TASK-50, made shared for TASK-80): drag it by its
## title to the left, right or bottom edge (the zones light up), or let it go anywhere else to
## float, snapped to the HUD grid's cells. Its inner edge (floating: the lower right corner)
## resizes it.
## TASK-80 (Nico 2026-11-02): dragged by its title past the edge of the program's window it
## pops out into its own OS window (e.g. for a second screen) and goes on following the mouse;
## a popped-out one dragged by its title back over the program docks again where it is let go.
## TASK-91 (Nico 2026-11-04): no Pop out / Dock buttons, dragging does it; the popped-out
## window is borderless (no OS title bar that would move it without docking): its edges resize
## it, and minimise, maximise / restore and close sit at its top right (WindowButtons).
## Where it is (dock, size, floating rect, own window and that window's rect) belongs to the
## user on this computer: saved in `place_file` under `section`. The chat (ChatBox) and the
## books (Dock.float_panel) are DockPanels.

signal place_changed
signal closed  ## its own window was closed and `close_hides` is set

const TOP := 0  ## rows left free at the top (none: the app's buttons are in the Esc menu)
const EDGE := 8.0  ## pixels at the inner edge that resize
const ZONE := 0.08  ## the dock zones: this part of the screen at each edge
const SIDE_CELLS := Vector2i(6, 24)  ## width of a side dock, min / max
const BOTTOM_CELLS := Vector2i(4, 14)  ## height of the bottom dock, min / max
const TOP_CELLS := Vector2i(2, 10)  ## height of the top dock, min / max (the timeline bar, TASK-82)

## dock: "left" / "right" / "top" / "bottom" / "float"; side: cells of a side dock, bottom /
## top: rows of that dock; r: the floating rect in cells; window: popped out; win: that
## window's rect.
var place := {"dock": "right", "side": 10, "bottom": 7, "top": 3, "r": [30, 6, 12, 16], "window": false}
var place_file := "user://panels.cfg"
var section := "panel"
var window_title := "Dragoon"
var close_hides := false  ## closing its own window hides it (`closed`), else it docks back
## TASK-113 (Nico 2026-11-05): always in its own OS window, never docked in the program: shown,
## it opens straight in its window where it was last; dragged over the program it stays a
## window; closing it hides it. Only the chat still docks.
var always_window := false
## Own windows can be made (not in a headless run: the panels stay inside the program there).
static var native_windows := DisplayServer.get_name() != "headless"
var allow_top := false  ## it may dock at the top (a wide, low panel like the timeline bar)
## Nico 2026-11-02: a slim panel (the timeline bar): docked at a side it is as wide as it is high
## at the top (`place.top`), from the top of the screen, and the other panels at that side sit
## beside it.
var thin := false
var drag_anywhere := false  ## its background moves it too, not only the title
var window_min := Vector2i(320, 400)  ## its own window at least this big
var window: Window  ## its own window while popped out
var title_label: Label
var body: VBoxContainer  ## the head first, then what the panel shows
var _head: HBoxContainer
var _drag := ""  ## "move" / "resize" while the mouse is down
var _grab := Vector2.ZERO  ## where the title was grabbed
var _zones: Control  ## the dock zones while it is moved
var _home: Node  ## where it lives when docked
var _home_index := -1
var _restored := false  ## the first show: back into its own window if it was there last time
var _carrying := false  ## its own window follows the mouse (dragged by the title)
var _win_buttons: Control  ## minimise / maximise / close while popped out (TASK-91)
var _maxed := false  ## maximised by hand on its screen (toggle_maximized)
var _maxed_from := Rect2i()  ## its rect before that
## TASK-100: a close (X) at the top right while it is inside the program too (docked or
## floating), drawn like the popped-out window's; it hides the panel (`closed`).
var closable := false:
	set(value):
		closable = value
		_update_close()
var _close_button: Button


func _init() -> void:
	theme_type_variation = UISkin.V_PAGE
	mouse_filter = Control.MOUSE_FILTER_STOP
	body = VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 6)
	add_child(body)
	_head = HBoxContainer.new()
	_head.name = "Head"
	_head.mouse_filter = Control.MOUSE_FILTER_STOP
	_head.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_head.tooltip_text = "Drag: dock it left, right or at the bottom, let it float, or pull it out of the window (and back in)"
	_head.gui_input.connect(_head_input)
	body.add_child(_head)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.theme_type_variation = UISkin.V_HEADING
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.add_child(title_label)
	visibility_changed.connect(_on_visibility)
	add_to_group("dock_panels")
	set_process(false)


func _ready() -> void:
	if _home == null:
		_home = get_parent()
		if _home is Control and not (_home as Control).resized.is_connected(apply):
			(_home as Control).resized.connect(apply)
		load_place()


# --- Where it is -------------------------------------------------------------------------------

func load_place() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(place_file) == OK:
		var saved: Variant = cfg.get_value(section, "place", {})
		if saved is Dictionary:
			place.merge(saved, true)
	if str(place.dock) not in ["left", "right", "top", "bottom", "float"]:
		place.dock = "right"
	apply()
	_update_top_rows()


func save_place() -> void:
	var cfg := ConfigFile.new()
	cfg.load(place_file)
	cfg.set_value(section, "place", place)
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
	var top := TOP + top_rows()  # below a panel docked at the top
	if thin and str(place.dock) in ["left", "right"]:
		var tw := clampi(int(place.get("top", 2)), 3, TOP_CELLS.y)  # at a side at least 3: room for the dates
		return Rect2i(0 if place.dock == "left" else g.x - tw, TOP, tw, g.y - TOP)
	match str(place.dock):
		"left":
			var lw := clampi(int(place.side), SIDE_CELLS.x, SIDE_CELLS.y)
			return Rect2i(thin_cells("left"), top, lw, g.y - top)
		"right":
			var w := clampi(int(place.side), SIDE_CELLS.x, SIDE_CELLS.y)
			return Rect2i(g.x - w - thin_cells("right"), top, w, g.y - top)
		"top":
			return Rect2i(0, TOP, g.x, clampi(int(place.get("top", 3)), TOP_CELLS.x, TOP_CELLS.y))
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


## Rows taken by a panel docked at the top of the same home (under the app's buttons): the
## side docks start below it.
func top_rows() -> int:
	var rows := 0
	var home := _home if _home != null else get_parent()
	if home == null or not is_inside_tree():
		return 0
	for p: Node in get_tree().get_nodes_in_group("dock_panels"):
		var d := p as DockPanel
		if d != null and d != self and d.get_parent() == home and d.window == null and d.visible and str(d.place.dock) == "top":
			rows = maxi(rows, clampi(int(d.place.get("top", 3)), TOP_CELLS.x, TOP_CELLS.y))
	return rows


## Cells taken at `side` by slim panels docked there (the others sit beside them).
func thin_cells(side: String) -> int:
	var home := _home if _home != null else get_parent()
	if home == null or not is_inside_tree():
		return 0
	var cells := 0
	for p: Node in get_tree().get_nodes_in_group("dock_panels"):
		var d := p as DockPanel
		if d != null and d != self and d.thin and d.get_parent() == home and d.window == null and d.visible and str(d.place.dock) == side:
			cells = maxi(cells, clampi(int(d.place.get("top", 2)), 3, TOP_CELLS.y))
	return cells


## A panel docked at the top pushes the side docks of its home down: they follow when it
## docks, resizes, hides or pops out.
func _update_top_rows() -> void:
	if not is_inside_tree():
		return
	var home := _home if _home != null else get_parent()
	for p: Node in get_tree().get_nodes_in_group("dock_panels"):
		if p != self and p is DockPanel and p.get_parent() == home and str((p as DockPanel).place.dock) in ["left", "right"]:
			(p as DockPanel).apply()


## Docks it: "left", "right", "top", "bottom"; or "float" at `r` (cells).
func dock(where: String, r := Rect2i()) -> void:
	place.dock = where
	if where == "float" and r.has_area():
		place.r = [r.position.x, r.position.y, r.size.x, r.size.y]
	apply()
	_update_top_rows()
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
	if at.y < a.y * ZONE * 1.3 and allow_top:
		return "top"
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


## True if `at` (its home's pixels) is past the edge of the program's window (TASK-80).
func outside(at: Vector2) -> bool:
	return not Rect2(Vector2.ZERO, area()).grow(-2).has_point(at)


func _head_input(event: InputEvent) -> void:
	if window != null:  # its own window: dragged by the title it follows the mouse (TASK-80)
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if (event as InputEventMouseButton).double_click:
				toggle_maximized()  # TASK-91
			else:
				if is_maximized():  # pulled off a maximised one: it comes back to its size first
					var f := float(DisplayServer.mouse_get_position().x - window.position.x) / maxf(1.0, float(window.size.x))
					_restore_size()
					window.position = DisplayServer.mouse_get_position() - Vector2i(int(window.size.x * f), 12)
				start_carry(DisplayServer.mouse_get_position() - window.position)
			_head.accept_event()
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
		var at := _home_pos()
		if outside(at):  # past the program's edge: its own window, still in the hand
			pull_out(DisplayServer.mouse_get_position())
			_head.accept_event()
			return
		position = at - _grab
		if _zones != null:
			_zones.set_meta("hot", zone_at(at))
			_zones.queue_redraw()
		_head.accept_event()


## The inner edge (floating: the lower right corner) resizes it, by whole cells.
func _gui_input(event: InputEvent) -> void:
	if window != null:
		var edge := window_edge(get_local_mouse_position())
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and event.pressed and edge >= 0 and window.mode == Window.MODE_WINDOWED and not _maxed:
			window.start_resize(edge as DisplayServer.WindowResizeEdge)  # TASK-91: borderless, its edges resize it (the OS does it)
			accept_event()
		elif event is InputEventMouseMotion:
			var shape: int = EDGE_CURSORS[edge] if edge >= 0 else Control.CURSOR_ARROW
			mouse_default_cursor_shape = shape as Control.CursorShape
			if drag_anywhere:
				_head_input(event)
		elif drag_anywhere:
			_head_input(event)
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
		elif drag_anywhere:
			_head_input(event)
	elif event is InputEventMouseMotion:
		if _drag == "resize":
			_resize_to(_home_pos())
			accept_event()
		elif _drag == "move" and drag_anywhere:
			_head_input(event)
		else:
			mouse_default_cursor_shape = _edge_cursor() if _on_edge(local) else Control.CURSOR_ARROW


## Resizes it so its inner edge is at `at` (its home's pixels).
func _resize_to(at: Vector2) -> void:
	var c := cell()
	var g := HudWidgets.HUD_GRID
	match str(place.dock):
		"right" when thin:
			place.top = clampi(int(roundf(g.x - at.x / c.x)), TOP_CELLS.x, TOP_CELLS.y)
			_update_top_rows()
		"left" when thin:
			place.top = clampi(int(roundf(at.x / c.x)), TOP_CELLS.x, TOP_CELLS.y)
			_update_top_rows()
		"right":
			place.side = clampi(int(roundf(g.x - at.x / c.x)), SIDE_CELLS.x, SIDE_CELLS.y)
		"left":
			place.side = clampi(int(roundf(at.x / c.x)), SIDE_CELLS.x, SIDE_CELLS.y)
		"bottom":
			place.bottom = clampi(int(roundf(g.y - at.y / c.y)), BOTTOM_CELLS.x, BOTTOM_CELLS.y)
		"top":
			place.top = clampi(int(roundf(at.y / c.y)) - TOP, TOP_CELLS.x, TOP_CELLS.y)
			_update_top_rows()
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
		"top":
			return local.y > size.y - EDGE
	return local.x > size.x - EDGE * 2 and local.y > size.y - EDGE * 2


func _edge_cursor() -> Control.CursorShape:
	match str(place.dock):
		"left", "right":
			return Control.CURSOR_HSIZE
		"bottom", "top":
			return Control.CURSOR_VSIZE
	return Control.CURSOR_FDIAGSIZE


func _home_pos() -> Vector2:
	var home := _home if _home is Control else get_parent()
	return (home as Control).get_local_mouse_position() if home is Control else get_global_mouse_position()


## The dock zones, lit while it is carried (the one under the mouse brighter).
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
	var zc := _zones  # not _zones: that is gone once it is let go, a draw may still come
	zc.draw.connect(func() -> void:
		var a := area()
		var hot := str(zc.get_meta("hot", ""))
		var rects := {"left": Rect2(0, 0, a.x * ZONE, a.y), "right": Rect2(a.x * (1.0 - ZONE), 0, a.x * ZONE, a.y),
			"bottom": Rect2(a.x * ZONE, a.y * (1.0 - ZONE * 1.3), a.x * (1.0 - ZONE * 2), a.y * ZONE * 1.3)}
		if allow_top:
			rects["top"] = Rect2(a.x * ZONE, 0, a.x * (1.0 - ZONE * 2), a.y * ZONE * 1.3)
		for z: String in rects:
			zc.draw_rect(rects[z], Color(1.0, 0.55, 0.1, 0.45 if z == hot else 0.15))
			zc.draw_rect(rects[z], Color(1.0, 0.55, 0.1, 0.9), false, 2.0))
	(_home as Control).add_child(_zones)
	(_home as Control).move_child(_zones, get_index())


# --- Its own window --------------------------------------------------------------------------

const WIN_EDGE := 6.0  ## pixels at the border of its own window that resize it
## DisplayServer.WindowResizeEdge -> cursor
const EDGE_CURSORS := [Control.CURSOR_FDIAGSIZE, Control.CURSOR_VSIZE, Control.CURSOR_BDIAGSIZE, Control.CURSOR_HSIZE,
	Control.CURSOR_HSIZE, Control.CURSOR_BDIAGSIZE, Control.CURSOR_VSIZE, Control.CURSOR_FDIAGSIZE]


## The resize edge of its own window under `local` (DisplayServer.WINDOW_EDGE_*), -1 for none.
func window_edge(local: Vector2) -> int:
	if window == null:
		return -1
	var left := local.x < WIN_EDGE
	var right := local.x > size.x - WIN_EDGE
	var top := local.y < WIN_EDGE
	var bottom := local.y > size.y - WIN_EDGE
	if top and left:
		return DisplayServer.WINDOW_EDGE_TOP_LEFT
	if top and right:
		return DisplayServer.WINDOW_EDGE_TOP_RIGHT
	if bottom and left:
		return DisplayServer.WINDOW_EDGE_BOTTOM_LEFT
	if bottom and right:
		return DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT
	if top:
		return DisplayServer.WINDOW_EDGE_TOP
	if bottom:
		return DisplayServer.WINDOW_EDGE_BOTTOM
	if left:
		return DisplayServer.WINDOW_EDGE_LEFT
	if right:
		return DisplayServer.WINDOW_EDGE_RIGHT
	return -1


## Its own window maximised on its screen, or back to its size. Done by hand (the screen's
## usable rect): the OS maximise of a borderless window overshoots onto the next screen
## (Nico 2026-11-04).
func toggle_maximized() -> void:
	if window == null:
		return
	if is_maximized():
		_restore_size()
		window.position = _maxed_from.position
	else:
		_keep_window_rect()
		_maxed_from = Rect2i(window.position, window.size)
		var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
		_maxed = true
		window.position = usable.position
		window.size = usable.size
	if _win_buttons != null:
		_win_buttons.queue_redraw()
		for b: Node in _win_buttons.get_children():
			(b as Control).queue_redraw()


func is_maximized() -> bool:
	return window != null and (_maxed or window.mode == Window.MODE_MAXIMIZED)


## Back to the size it had before maximising (the position is the caller's).
func _restore_size() -> void:
	if window.mode == Window.MODE_MAXIMIZED:
		window.mode = Window.MODE_WINDOWED
	if _maxed:
		_maxed = false
		window.size = _maxed_from.size


func minimize() -> void:
	if window != null:
		window.mode = Window.MODE_MINIMIZED


## The X inside the program (TASK-100): hidden, the place kept for the next time.
func close_panel() -> void:
	if window != null:
		close_window()
		return
	visible = false
	closed.emit()


func _update_close() -> void:
	if closable and _close_button == null:
		_close_button = WindowButton.new()
		_close_button.kind = "close"
		_close_button.name = "PanelClose"
		_close_button.panel = self
		_close_button.pressed.connect(close_panel)
		_head.add_child(_close_button)
	if _close_button != null:
		_close_button.visible = closable and window == null  # popped out: the window's own buttons


## Its own window closed: hidden (`close_hides`) or docked back.
func close_window() -> void:
	if window == null:
		return
	if close_hides or always_window:
		_keep_window_rect()
		visible = false
		save_place()
		closed.emit()
	else:
		dock_back()


## Minimise, maximise / restore, close at the top right of its own window: in the head when it
## has one, else over the panel's corner.
func _add_window_buttons() -> void:
	var box := HBoxContainer.new()
	box.name = "WindowButtons"
	box.add_theme_constant_override("separation", 2)
	for kind: String in ["min", "max", "close"]:
		var b := WindowButton.new()
		b.kind = kind
		b.name = kind.capitalize()
		b.panel = self
		box.add_child(b)
	(box.get_node("Min") as Button).pressed.connect(minimize)
	(box.get_node("Max") as Button).pressed.connect(toggle_maximized)
	(box.get_node("Close") as Button).pressed.connect(close_window)
	if _head.visible:
		_head.add_child(box)
	else:
		window.add_child(box)
		box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 6)
	_win_buttons = box


## A small window button drawn in the page's ink: a dash, a square (two when maximised) or a cross.
class WindowButton extends Button:
	var kind := "close"
	var panel: DockPanel

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(24, 22)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _ready() -> void:
		tooltip_text = {"min": "Minimise", "max": "Maximise / restore", "close": "Close"}[kind]

	func _draw() -> void:
		var ink := get_theme_color("font_color", "Label")
		if is_hovered():
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.75, 0.2, 0.15, 0.85) if kind == "close" else Color(ink, 0.12))
			if kind == "close":
				ink = Color.WHITE
		var c := size * 0.5
		var r := 5.0
		match kind:
			"min":
				draw_line(c + Vector2(-r, 3), c + Vector2(r, 3), ink, 1.5)
			"max":
				var maxed := panel != null and panel.is_maximized()
				if maxed:  # restore: two squares
					draw_polyline(PackedVector2Array([c + Vector2(-r + 3, -r + 2), c + Vector2(-r + 3, -r), c + Vector2(r, -r), c + Vector2(r, r - 3), c + Vector2(r - 2, r - 3)]), ink, 1.2)
					draw_rect(Rect2(c + Vector2(-r, -r + 3), Vector2(r * 2 - 3, r * 2 - 3)), ink, false, 1.2)
				else:
					draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2), ink, false, 1.2)
			_:
				draw_line(c + Vector2(-r, -r), c + Vector2(r, r), ink, 1.5)
				draw_line(c + Vector2(-r, r), c + Vector2(r, -r), ink, 1.5)

	func _notification(what: int) -> void:
		if what in [NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT]:
			queue_redraw()

## Into its own (native) window, e.g. for a second screen; where it was last, else over
## where it is now.
func pop_out() -> void:
	if window != null or _home == null:
		return
	_maxed = false
	var at := global_position
	_home_index = get_index()
	window = Window.new()
	window.name = name + "Window"
	window.title = window_title
	window.visible = false  # force_native can only be set on a hidden window
	window.force_native = true
	window.borderless = true  # TASK-91: moved by its title (docks again over the program), own buttons
	window.theme = UISkin.theme()
	window.size = Vector2i(maxi(int(size.x), window_min.x), maxi(int(size.y), window_min.y))
	if is_inside_tree():
		window.position = get_window().position + Vector2i(at)
	var saved: Variant = place.get("win")
	if saved is Array and (saved as Array).size() == 4 and int(saved[2]) >= 200 and int(saved[3]) >= 150:
		window.position = Vector2i(int(saved[0]), int(saved[1]))
		window.size = Vector2i(int(saved[2]), int(saved[3]))
	if always_window:
		window.transient = true  # TASK-113: belongs to the program's window (minimised with it, Alt-Tab)
		window.position = _on_a_screen(Rect2i(window.position, window.size))
	window.close_requested.connect(close_window)
	var bg := Panel.new()  # the window's paper
	bg.theme_type_variation = UISkin.V_PAGE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(bg)
	_home.remove_child(self)
	window.add_child(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_home.add_child(window)
	_add_window_buttons()
	_update_close()
	window.visible = visible
	place.window = true
	_update_top_rows()  # out of the top dock: the side docks take the room back
	save_place()


## Where a window at `r` stays seen: on the screen it was on, else on the program's screen.
func _on_a_screen(r: Rect2i) -> Vector2i:
	for i in DisplayServer.get_screen_count():
		var screen := DisplayServer.screen_get_usable_rect(i)
		if screen.grow(-40).intersects(r):
			return r.position
	var main := get_tree().root if is_inside_tree() else null
	var at := DisplayServer.screen_get_usable_rect(main.current_screen if main != null else DisplayServer.get_primary_screen())
	return at.position + (at.size - r.size).maxi(0) / 2


## Back from its own window to its dock.
func dock_back() -> void:
	if window == null:
		return
	if always_window and native_windows:  # TASK-113: it has no place in the program
		close_window()
		return
	_keep_window_rect()
	_carrying = false
	set_process(false)
	var w := window
	window = null
	if _win_buttons != null:
		_win_buttons.get_parent().remove_child(_win_buttons)
		_win_buttons.queue_free()
		_win_buttons = null
	w.remove_child(self)
	_home.add_child(self)
	if _home_index >= 0:
		_home.move_child(self, mini(_home_index, _home.get_child_count() - 1))
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	w.hide()  # a freed window must not stay shown until the frame ends
	w.queue_free()
	place.window = false
	_update_close()
	apply()
	_update_top_rows()
	save_place()


## Its own window's rect, for the next time it pops out.
func _keep_window_rect() -> void:
	if window != null and window.mode == Window.MODE_WINDOWED and not _maxed:
		place.win = [window.position.x, window.position.y, window.size.x, window.size.y]


## Dragged past the program's edge (TASK-80): its own window, under the mouse (`screen`:
## where the mouse is on the desktop), carried on until the button is let go.
func pull_out(screen: Vector2i) -> void:
	_drag = ""
	_show_zones(false)
	var grab := _grab
	pop_out()
	if window == null:
		return
	window.position = screen - Vector2i(grab)
	start_carry(Vector2i(grab))


## Its own window follows the mouse (`grab`: where in the window it is held) until let go.
func start_carry(grab: Vector2i) -> void:
	_grab = Vector2(grab)
	_carrying = true
	set_process(true)


func _process(_delta: float) -> void:
	if not _carrying:
		set_process(false)
		return
	var at := DisplayServer.mouse_get_position()
	if DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT:
		carry_to(at)
	else:
		drop_at(at)


## The carried window moves with the mouse (`screen`: the mouse on the desktop).
func carry_to(screen: Vector2i) -> void:
	if window != null:
		window.position = screen - Vector2i(_grab)


## The carried window is let go at `screen`: over the program's window it docks there again
## (on a dock zone, else floating where it was let go), else it stays where it is.
func drop_at(screen: Vector2i) -> void:
	_carrying = false
	set_process(false)
	if window == null or _home == null or not _home.is_inside_tree():
		return
	var main := (_home as Node).get_window()
	if main == null or not Rect2i(main.position, main.size).has_point(screen) or always_window:  # TASK-113: stays a window
		_keep_window_rect()
		save_place()
		return
	var in_main: Vector2 = main.get_final_transform().affine_inverse() * Vector2(screen - main.position)
	var at := in_main - ((_home as Control).get_global_rect().position if _home is Control else Vector2.ZERO)
	var grab := _grab
	dock_back()
	var r: Array = place.r
	size = Vector2(float(r[2]), float(r[3])) * cell() - Vector2(8, 8)
	position = at - Vector2(minf(grab.x, size.x - 40), clampf(grab.y, 4, 30))
	end_move(at)


func _on_visibility() -> void:
	if is_inside_tree():
		_update_top_rows.call_deferred()  # a top-docked panel shown or hidden moves the side docks
	if window != null:
		window.visible = visible
	elif visible and is_inside_tree() and always_window and native_windows:
		_restored = true
		pop_out.call_deferred()  # TASK-113: straight into its own window
	elif visible and is_inside_tree() and not _restored:
		_restored = true
		if bool(place.get("window", false)):
			pop_out.call_deferred()  # it was in its own window last time
