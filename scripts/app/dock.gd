class_name Dock
extends Control
## Panels around the table (TASK-37). Every view (books, notes, events, encounters, the
## sheet, the session log) is a panel: docked as a tab in the left, right or bottom area
## (drag the tabs between areas, drag the grip to resize), or detached into its own OS
## window (closing the window docks it back). The middle stays free for the map.
## Where each panel is, the area sizes and the window rectangles are kept in `layout_file`.
## A panel can also float over the table in a DockPanel (TASK-80, the calm table's books):
## moved and docked inside the program like the chat, popped out into its own window (also by
## dragging it past the program's edge) and docked again by dragging it back; its place is
## kept in panels.cfg beside `layout_file`.

signal panel_shown(id: String)
signal panel_hidden(id: String)

const AREAS := ["left", "right", "bottom"]
const TABS_GROUP := 4711  ## tabs can be dragged between the three areas
const MIN_SIZE := 220.0
const DEFAULT_SIZES := {"left": 420.0, "right": 480.0, "bottom": 280.0}

static var layout_file := "user://layout.json"

var top_margin := 96.0  ## room for the bars at the top
var close_hides := false  ## closing a panel's window hides the panel (else it docks back)
## TASK-113 (Nico 2026-11-05): every panel is its own OS window (a DockPanel that always pops
## out); the tab areas and docking are only left for a run without own windows (headless).
var windows_only := true
var sizes := DEFAULT_SIZES.duplicate()
var panels := {}  ## id -> {title, holder: Control, place: area|"window"|"hidden", last_area, window: Window, rect: Rect2i, screen}
var areas := {}  ## area -> TabContainer
var _frames := {}  ## area -> PanelContainer
var _grips := {}  ## area -> the resize handle on its inner edge
var _menu_for := ""  ## the panel a tab menu acts on
var _restoring := false
var _saved := {}  ## the loaded layout


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for a: String in AREAS:
		var frame := PanelContainer.new()
		frame.name = "Area_" + a
		frame.theme_type_variation = UISkin.V_PAGE
		add_child(frame)
		var col := VBoxContainer.new()
		frame.add_child(col)
		var tabs := TabContainer.new()
		tabs.name = "Tabs"
		tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tabs.drag_to_rearrange_enabled = true
		tabs.tabs_rearrange_group = TABS_GROUP
		tabs.child_entered_tree.connect(func(_n: Node) -> void: _changed.call_deferred())
		tabs.child_exiting_tree.connect(func(_n: Node) -> void: _changed.call_deferred())
		var menu := PopupMenu.new()
		for item: Array in [["Dock left", 0], ["Dock right", 1], ["Dock bottom", 2], ["Own window", 3], ["Close", 4]]:
			menu.add_item(item[0], item[1])
		menu.id_pressed.connect(func(id: int) -> void: _menu(a, id))
		tabs.set_popup(menu)
		col.add_child(tabs)
		areas[a] = tabs
		_frames[a] = frame
		var grip := ColorRect.new()
		grip.name = "Grip"
		grip.color = Color(UISkin.WINE, 0.35)
		grip.mouse_default_cursor_shape = Control.CURSOR_VSIZE if a == "bottom" else Control.CURSOR_HSIZE
		grip.gui_input.connect(_grip_input.bind(a))
		add_child(grip)  # beside the frame (a container would stretch it), placed by _layout
		_grips[a] = grip
	_saved = load_layout()
	sizes.merge(_saved.get("sizes", {}), true)
	resized.connect(_layout)
	_layout()


# --- Panels -------------------------------------------------------------------------------------

## Registers a view as a panel (not shown yet). `default_place`: an area or "window".
func add_panel(id: String, title: String, content: Control, default_place := "right") -> void:
	var holder := Control.new()  # not a container: a wide view must not push its area over the map
	holder.name = id
	holder.clip_contents = true
	holder.set_meta("title", title)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(content)
	var saved: Dictionary = (_saved.get("panels", {}) as Dictionary).get(id, {})
	var place := str(saved.get("place", default_place))
	panels[id] = {"title": title, "holder": holder, "place": "hidden", "default": default_place,
		"last_area": place if place in AREAS else (default_place if default_place in AREAS else "right"),
		"window": null, "rect": _rect_from(saved.get("rect")), "screen": int(saved.get("screen", -1)),
		"open": bool(saved.get("open", false)), "wanted": place, "frame": null}


func has_panel(id: String) -> bool:
	return panels.has(id)


## Where a panel is: left, right, bottom, window or hidden.
func place_of(id: String) -> String:
	if not panels.has(id):
		return "hidden"
	var p: Dictionary = panels[id]
	var holder: Control = p.holder
	var f: DockPanel = p.get("frame")
	if f != null and holder.get_parent() == f.body and f.visible:
		return "window" if f.window != null else "float"
	if p.window != null and holder.get_parent() == p.window:
		return "window"
	for a: String in AREAS:
		if holder.get_parent() == areas[a]:
			return a
	return "hidden"


func is_shown(id: String) -> bool:
	return place_of(id) != "hidden"


## Shows a panel where it was last (or `place`) and brings it to the front.
func show_panel(id: String, place := "") -> void:
	if not panels.has(id):
		return
	var p: Dictionary = panels[id]
	if place == "":
		place = place_of(id)
		if place == "hidden":
			place = str(p.wanted) if str(p.wanted) in AREAS or str(p.wanted) in ["window", "float"] else str(p.last_area)
	if windows_only and DockPanel.native_windows:
		place = "float"  # TASK-113: its own window (the DockPanel pops out by itself)
	if place == "float":
		float_panel(id)
	elif place == "window":
		detach(id)
	else:
		dock(id, place)
	panel_shown.emit(id)


func hide_panel(id: String) -> void:
	if not panels.has(id):
		return
	var p: Dictionary = panels[id]
	var was := place_of(id)
	_take_out(id)
	p.wanted = was if was != "hidden" else str(p.wanted)  # shown again where it was
	_changed()
	panel_hidden.emit(id)


## Docks a panel as a tab of an area (and selects it).
func dock(id: String, area: String) -> void:
	if not panels.has(id) or area not in AREAS:
		return
	var p: Dictionary = panels[id]
	_take_out(id)
	var tabs: TabContainer = areas[area]
	tabs.add_child(p.holder)
	tabs.set_tab_title(tabs.get_tab_idx_from_control(p.holder), str(p.title))
	tabs.current_tab = tabs.get_tab_idx_from_control(p.holder)
	p.last_area = area
	p.wanted = area
	_changed()


## The panel floating over the table in its DockPanel (TASK-80); it pops out into its own
## window by itself if it was there last time. Closing that window hides the panel.
func float_panel(id: String) -> DockPanel:
	if not panels.has(id):
		return null
	var p: Dictionary = panels[id]
	var f: DockPanel = p.get("frame")
	if f != null and (p.holder as Control).get_parent() == f.body and f.visible:
		if f.window != null:
			f.window.grab_focus()
		return f
	_take_out(id)
	if f == null:
		f = DockPanel.new()
		f.name = "Float_" + id
		f.section = "panel_" + id
		f.place_file = layout_file.get_base_dir().path_join("panels.cfg")
		f.window_title = "Dragoon · %s" % p.title
		f.title_label.text = str(p.title)
		f.close_hides = true
		f.always_window = windows_only  # TASK-113
		f.closable = true  # TASK-100: an X inside the program too
		f.window_min = Vector2i(900, 650)
		f.place = {"dock": "float", "side": 14, "bottom": 10, "r": [8, 3, 28, 21], "window": false}
		f.closed.connect(func() -> void: hide_panel(id))
		f.place_changed.connect(_save_soon)
		p.frame = f
		add_child(f)
	var holder: Control = p.holder
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.body.add_child(holder)
	f.visible = true
	p.wanted = "float"
	_changed()
	return f


## Forgets a panel (a session's views when it is left); its places stay saved.
func remove_panel(id: String) -> void:
	if not panels.has(id):
		return
	var p: Dictionary = panels[id]
	_take_out(id)
	panels.erase(id)
	(p.holder as Control).queue_free()
	var f: DockPanel = p.get("frame")
	if f != null:
		if f.window != null:
			f.window.queue_free()
		else:
			f.queue_free()


## Moves a panel into its own OS window (closing the window docks it back).
func detach(id: String) -> Window:
	if not panels.has(id):
		return null
	var p: Dictionary = panels[id]
	if p.window != null and (p.holder as Control).get_parent() == p.window:
		(p.window as Window).grab_focus()
		return p.window
	_take_out(id)
	var w := Window.new()
	w.name = "Window_" + id
	w.title = "Dragoon · %s" % p.title
	w.theme = UISkin.theme()
	w.wrap_controls = false
	w.visible = false  # force_native can only be set while hidden
	w.force_native = true  # a real OS window, also when dialogs are embedded
	w.min_size = Vector2i(360, 260)
	var rect: Rect2i = p.rect
	if rect.size.x < 100:
		rect = Rect2i(get_window().position + Vector2i(80, 80), Vector2i(1280, 820))
	w.size = rect.size
	w.position = rect.position
	w.close_requested.connect(func() -> void:
		if close_hides:
			hide_panel(id)
		else:
			dock(id, str(p.last_area)))
	w.size_changed.connect(_save_soon)
	var bg := Panel.new()
	bg.theme_type_variation = UISkin.V_PAGE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	w.add_child(bg)
	w.add_child(p.holder)
	(p.holder as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.window = w
	p.wanted = "window"
	add_child(w)
	if int(p.screen) >= 0 and int(p.screen) < DisplayServer.get_screen_count() and w.current_screen != int(p.screen):
		w.current_screen = int(p.screen)
		w.position = rect.position
	w.show()
	_changed()
	return w


## The panel out of wherever it is (a closed window is freed, its rectangle kept).
func _take_out(id: String) -> void:
	var p: Dictionary = panels[id]
	var holder: Control = p.holder
	var w: Window = p.window
	if w != null:
		p.rect = Rect2i(w.position, w.size)
		p.screen = w.current_screen
	var f: DockPanel = p.get("frame")
	if f != null and holder.get_parent() == f.body:
		f.visible = false  # its window (if popped out) hides with it
	if holder.get_parent() != null:
		holder.get_parent().remove_child(holder)
	if w != null:
		p.window = null
		w.queue_free()


func _menu(area: String, id: int) -> void:
	var tabs: TabContainer = areas[area]
	var holder := tabs.get_current_tab_control()
	if holder == null:
		return
	var pid := str(holder.name)
	match id:
		0, 1, 2:
			dock(pid, AREAS[id])
		3:
			detach(pid)
		4:
			hide_panel(pid)


# --- Layout -------------------------------------------------------------------------------------

func _changed() -> void:
	if not is_inside_tree():
		return
	for a: String in AREAS:
		(_frames[a] as Control).visible = (areas[a] as TabContainer).get_tab_count() > 0
		var tabs: TabContainer = areas[a]
		for i in tabs.get_tab_count():  # titles after a tab was dragged in from another area
			tabs.set_tab_title(i, str(tabs.get_tab_control(i).get_meta("title", tabs.get_tab_control(i).name)))
	for id: String in panels:
		var where := place_of(id)
		if where in AREAS:
			panels[id].last_area = where
	_layout()
	_save_soon()


## Places the areas: left and right full height (below the bars), bottom between them.
func _layout() -> void:
	if areas.is_empty():
		return
	var w := size.x
	var h := size.y
	var left_on: bool = (_frames.left as Control).visible
	var right_on: bool = (_frames.right as Control).visible
	var lw: float = clampf(float(sizes.left), MIN_SIZE, w * 0.6) if left_on else 0.0
	var rw: float = clampf(float(sizes.right), MIN_SIZE, w * 0.6) if right_on else 0.0
	var bh: float = clampf(float(sizes.bottom), MIN_SIZE * 0.6, (h - top_margin) * 0.7)
	_place(_frames.left, Rect2(8, top_margin, lw, h - top_margin - 8))
	_place(_frames.right, Rect2(w - rw - 8, top_margin, rw, h - top_margin - 8))
	_place(_frames.bottom, Rect2(lw + 16, h - bh - 8, w - lw - rw - 32, bh))
	for a: String in AREAS:
		var grip: ColorRect = _grips[a]
		var r := (_frames[a] as Control).get_rect()
		grip.visible = (_frames[a] as Control).visible
		grip.set_anchors_preset(Control.PRESET_TOP_LEFT)
		match a:
			"left":
				grip.position = Vector2(r.end.x, r.position.y)
				grip.size = Vector2(6, r.size.y)
			"right":
				grip.position = Vector2(r.position.x - 6, r.position.y)
				grip.size = Vector2(6, r.size.y)
			"bottom":
				grip.position = Vector2(r.position.x, r.position.y - 6)
				grip.size = Vector2(r.size.x, 6)


func _place(c: Control, r: Rect2) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = r.position
	c.size = r.size


## The free middle (where the map shows), in this control's coordinates.
func free_rect() -> Rect2:
	var r := Rect2(Vector2(0, top_margin), size - Vector2(0, top_margin))
	if (_frames.left as Control).visible:
		r = r.grow_side(SIDE_LEFT, -(_frames.left as Control).size.x - 8)
	if (_frames.right as Control).visible:
		r = r.grow_side(SIDE_RIGHT, -(_frames.right as Control).size.x - 8)
	if (_frames.bottom as Control).visible:
		r = r.grow_side(SIDE_BOTTOM, -(_frames.bottom as Control).size.y - 8)
	return r


func _grip_input(event: InputEvent, area: String) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		var d: Vector2 = event.relative
		match area:
			"left":
				sizes.left = float(sizes.left) + d.x
			"right":
				sizes.right = float(sizes.right) - d.x
			"bottom":
				sizes.bottom = float(sizes.bottom) - d.y
		_layout()
		_save_soon()


# --- Saving -------------------------------------------------------------------------------------

## {sizes, panels: {id: {place, open, rect: [x, y, w, h], screen}}}.
func layout() -> Dictionary:
	var out := {}
	for id: String in panels:
		var p: Dictionary = panels[id]
		var where := place_of(id)
		var w: Window = p.window
		var rect: Rect2i = Rect2i(w.position, w.size) if w != null and where == "window" else p.rect
		var keep := str(p.wanted) if str(p.wanted) in AREAS or str(p.wanted) in ["window", "float"] else str(p.last_area)
		out[id] = {"place": where if where != "hidden" else keep, "open": where != "hidden",
			"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"screen": w.current_screen if w != null and where == "window" else int(p.screen)}
	return {"sizes": sizes.duplicate(), "panels": out}


func save_layout() -> Error:
	if _restoring:
		return OK
	var f := FileAccess.open(layout_file, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(layout(), " "))
	return OK


func _save_soon() -> void:
	if not is_inside_tree():
		return
	var t := get_node_or_null("SaveTimer") as Timer
	if t == null:
		t = Timer.new()
		t.name = "SaveTimer"
		t.one_shot = true
		t.wait_time = 0.5
		t.timeout.connect(save_layout)
		add_child(t)
	t.start()


static func load_layout() -> Dictionary:
	if not FileAccess.file_exists(layout_file):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_file))
	return d if d is Dictionary else {}


## Shows the panels that were open last time, where they were.
func restore_open(only: Array = []) -> void:
	_restoring = true
	for id: String in panels:
		var p: Dictionary = panels[id]
		if bool(p.open) and (only.is_empty() or id in only) and not is_shown(id):
			show_panel(id)
	_restoring = false


## Puts every panel away (leaving a session); their places are remembered.
func hide_all() -> void:
	if panels.keys().any(is_shown):
		save_layout()
	_restoring = true
	for id: String in panels:
		if is_shown(id):
			_take_out(id)
	_restoring = false
	_changed()


static func _rect_from(v: Variant) -> Rect2i:
	if v is Array and (v as Array).size() == 4:
		return Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
	return Rect2i()
