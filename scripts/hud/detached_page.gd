class_name DetachedPage
extends DockPanel
## A sheet page pulled out of the program into its own window (TASK-92, Nico 2026-11-04): the
## same borderless window as the other panels (TASK-91: its edges resize it, minimise /
## maximise / close at the top right, dragged by its title), but pinned to the character it was
## opened for: it keeps showing (and updating) that one's page whatever token is selected.
## Several can be open. Dragged back over the program it closes (and the in-program page opens
## when that character is the active one). SheetPages remembers them per player.
## The page is laid out on its grid at the window's size (an even scale, no reflow).

signal gone(page: DetachedPage)

var ref := ""
var page := 0
var pages: SheetPages
var table: NetTable
var pinned: PinnedHud
var view: Control  ## the page's pieces
var _turn_piece := false


func setup(from: SheetPages, who: String, index: int) -> void:
	pages = from
	table = from.hud.table
	ref = who
	page = index
	name = "DetachedPage"
	close_hides = false
	window_min = Vector2i(240, 200)
	remove_from_group("dock_panels")  # never docks: the docks don't count it
	_head.tooltip_text = "Drag it back over the program to close it"
	pinned = PinnedHud.new()
	pinned.table = table
	pinned.active = ref
	pinned.pages = from
	add_child(pinned)
	view = Control.new()
	view.name = "Page"
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.clip_contents = true
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(view)
	view.resized.connect(refresh)
	table.sheet_received.connect(func(r: String) -> void:
		if r == ref:
			refresh())
	table.table_changed.connect(func() -> void:  # the turn piece follows the combat
		if _turn_piece:
			refresh())
	table.keep_sheet(ref, true)
	table.open_sheet(ref, false)
	_title()


func _ready() -> void:
	_home = get_parent()  # no dock place of its own: always in its window
	EntryDrag.accept_on(self, table, func() -> String: return ref)  # TASK-94: drops go to its character


## "Borin – Spells".
func title_text() -> String:
	var list := pinned.page_list()
	var page_name := str(list[page].name) if page < list.size() else "Page %d" % (page + 1)
	return "%s – %s" % [pinned.label(ref), page_name]


func _title() -> void:
	title_label.text = title_text()
	window_title = title_label.text
	if window != null:
		window.title = window_title


func refresh() -> void:
	if view == null or not is_instance_valid(pinned):
		return
	for c in view.get_children():
		view.remove_child(c)
		c.queue_free()
	var list := pinned.page_list()
	if list.is_empty():
		return
	page = clampi(page, 0, list.size() - 1)
	_title()
	var s: Dictionary = table.sheets.get(ref, {})
	_turn_piece = (list[page].items as Array).any(func(it: Dictionary) -> bool: return str(it.w) == "turn")
	if s.is_empty():
		var wait := Label.new()
		wait.name = "Waiting"
		wait.text = "Waiting for the sheet…"
		wait.theme_type_variation = UISkin.V_MUTED
		view.add_child(wait)
		return
	var cell := view.size / Vector2(HudWidgets.PAGE_GRID)
	for it: Dictionary in list[page].items:
		var r: Array = it.r
		var rect := Rect2(Vector2(float(r[0]), float(r[1])) * cell, Vector2(float(r[2]), float(r[3])) * cell).grow(-3)
		var w := HudWidgets.build(str(it.w), s, pinned, rect.size, it)
		w.position = rect.position
		w.size = rect.size
		view.add_child(w)


func pop_out() -> void:
	super()
	if window != null:
		window.size_changed.connect(func() -> void:
			_keep_window_rect()
			save_place())


## Where it is goes into SheetPages' list (per player), not a panel place of its own.
func save_place() -> void:
	if pages != null and is_instance_valid(pages):
		pages.save_detached()


func load_place() -> void:
	pass


## Never docks: closing (its button, the OS) or dragging it back over the program closes it.
func dock_back() -> void:
	close_page()


func close_window() -> void:
	close_page()


## Let go over the program: closed; that character's page opens there if it is the active one.
func drop_at(screen: Vector2i) -> void:
	var main := pages.get_window() if pages != null and pages.is_inside_tree() else null
	if window != null and main != null and Rect2i(main.position, main.size).has_point(screen):
		_carrying = false
		set_process(false)
		var back := page
		var who := ref
		close_page()
		if pages.hud != null and pages.hud.active == who:
			pages.open(back)
		return
	super(screen)


func close_page() -> void:
	if ref == "":
		return
	_carrying = false
	set_process(false)
	table.keep_sheet(ref, false)
	if ref != table.hud_ref:
		table.close_sheet(ref)
	ref = ""
	var w := window
	window = null
	gone.emit(self)
	if w != null:
		w.hide()
		w.queue_free()
	else:
		queue_free()
