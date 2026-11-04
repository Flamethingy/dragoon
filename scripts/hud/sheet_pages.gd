class_name SheetPages
extends Control
## The character sheet as pages (TASK-47, Nico 2026-11-01): keys 1-9 open page 1-9 of the
## active character (the same key again, or Esc, closes it); F2 edits the open one like home screens
## (LayoutEditor). A page is a grid (HudWidgets.PAGE_GRID) of the same pieces as the HUD,
## saved in the character (`sheet_pages`), for creatures in their template in the Book.
## TASK-92 (Nico 2026-11-04): its head dragged out of the program's window pulls the page out
## into its own window (DetachedPage), pinned to that character; several may be open. Which
## ones are open (character, page, window rect) is remembered per player (`detached_file`)
## and they come back with the session.

const MARGIN := 16.0
const HEAD := 44.0

var hud: CharacterHud
var current := 0
var _book: PanelContainer
var _tabs: HBoxContainer
var _pieces: Control
var detached: Array[DetachedPage] = []
var _pulling := false
var _restored := false


func _init() -> void:
	name = "SheetPages"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_book = PanelContainer.new()
	_book.name = "Book"
	_book.theme_type_variation = UISkin.V_PAGE
	_book.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_book)
	var col := VBoxContainer.new()
	_book.add_child(col)
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.custom_minimum_size.y = HEAD - 8
	_tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	_tabs.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_tabs.tooltip_text = "Drag it out of the program: this page in its own window, for this character"
	_tabs.gui_input.connect(_tabs_input)
	col.add_child(_tabs)
	_pieces = Control.new()
	_pieces.name = "Pieces"
	_pieces.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pieces)


func _ready() -> void:
	resized.connect(refresh)
	if hud != null and hud.table != null:  # TASK-94: drop items etc. on the pages
		EntryDrag.accept_on(self, hud.table, func() -> String: return hud.active)
		hud.table.table_changed.connect(restore_detached)  # TASK-92: once the table is there
		hud.table.pcs_changed.connect(restore_detached)


# --- Detached pages (TASK-92) ------------------------------------------------------------------

## The head dragged past the program's edge: the open page in its own window, in the hand.
func _tabs_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_pulling = event.pressed
	elif event is InputEventMouseMotion and _pulling:
		var at := get_viewport().get_mouse_position()
		if not get_viewport().get_visible_rect().grow(-2).has_point(at):
			_pulling = false
			detach(hud.active, current, DisplayServer.mouse_get_position())
			_tabs.accept_event()


## May this user pull out `ref`'s pages? The DM any creature's, a player those they control.
func may_detach(ref: String) -> bool:
	if hud == null or hud.table == null or ref == "" or ref == NetTable.PARTY:
		return false
	if ref.get_slice("/", 0) not in Timeline.CREATURES:
		return false
	return hud.table.is_dm() or ref in hud.controlled()


## Page `index` of `ref` in its own window; carried by the mouse when `screen` (the mouse on
## the desktop) is given. `win`: its window's rect from last time. Null if it may not.
func detach(ref: String, index: int, screen := Vector2i(-1, -1), win: Array = []) -> DetachedPage:
	if not may_detach(ref):
		return null
	if not _restored:
		restore_detached()  # last time's first, so this one is saved beside them
	var dp := DetachedPage.new()
	dp.setup(self, ref, index)
	var g := grid_rect()  # the page at its design size
	dp.size = g.size + Vector2(MARGIN * 2, HEAD + MARGIN)
	if win.size() == 4:
		dp.place.win = win
	get_parent().add_child(dp)
	dp.gone.connect(_on_gone)
	detached.append(dp)
	dp.pop_out()
	if screen.x >= 0 and dp.window != null:
		var grab := Vector2i(60, 14)
		dp.window.position = screen - grab
		dp.start_carry(grab)
	if visible and hud.active == ref:
		close()  # it's out now
	save_detached()
	return dp


func _on_gone(dp: DetachedPage) -> void:
	detached.erase(dp)
	save_detached()


## Where the open detached pages are kept: per player, beside their cache.
func detached_file() -> String:
	var t := hud.table if hud != null else null
	if t == null or t.cache_dir == "user://cache/assets":
		return "user://pages.cfg"
	return t.cache_dir.path_join("pages.cfg")


func _player_key() -> String:
	var t := hud.table if hud != null else null
	return "dm" if t != null and t.is_dm() else str(t.my_player) if t != null and str(t.my_player) != "" else "me"


func save_detached() -> void:
	if hud == null or hud.table == null or not _restored:
		return
	var list := []
	for dp in detached:
		if not is_instance_valid(dp) or dp.ref == "":
			continue
		var rect: Variant = dp.place.get("win", [])
		list.append({"ref": dp.ref, "page": dp.page, "win": rect if rect is Array else []})
	var cfg := ConfigFile.new()
	cfg.load(detached_file())
	cfg.set_value("detached", _player_key(), list)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(detached_file().get_base_dir()))
	cfg.save(detached_file())


## The pages that were out last time come out again (once, when the table is there).
func restore_detached() -> void:
	if _restored or hud == null or hud.table == null or not hud.table.is_online() or hud.controlled().is_empty():
		return
	_restored = true
	var cfg := ConfigFile.new()
	if cfg.load(detached_file()) != OK:
		return
	var saved: Variant = cfg.get_value("detached", _player_key(), [])
	if not saved is Array:
		return
	for one: Variant in saved:
		if one is Dictionary:
			var win: Variant = one.get("win", [])
			detach(str(one.get("ref", "")), int(one.get("page", 0)), Vector2i(-1, -1), win if win is Array else [])
	save_detached()  # the ones this player may no longer see are dropped


## The book's rect: centred, most of the screen.
func book_rect() -> Rect2:
	var area := size if size.x > 0 and size.y > 0 else get_viewport_rect().size
	var s := area * Vector2(0.72, 0.78)
	return Rect2((area - s) * 0.5, s)


## Where the page grid is (the book without its head), for the pieces and the editor.
func grid_rect() -> Rect2:
	var b := book_rect()
	return Rect2(b.position + Vector2(MARGIN, HEAD + MARGIN * 0.5), b.size - Vector2(MARGIN * 2, HEAD + MARGIN * 1.5))


func open(index: int) -> void:
	current = maxi(index, 0)
	visible = true
	refresh()


func close() -> void:
	visible = false


## Key n: opens page n; the same key again closes it. Pages that don't exist do nothing.
func toggle(index: int) -> void:
	if hud == null or index >= hud.page_list().size():
		return
	if visible and current == index:
		close()
	else:
		open(index)


func refresh() -> void:
	if not visible or hud == null:
		return
	if hud.active == "":
		close()
		return
	var list := hud.page_list()
	current = clampi(current, 0, list.size() - 1)
	var b := book_rect()
	_book.position = b.position
	_book.size = b.size
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	var title := Label.new()
	title.text = hud.label(hud.active)
	title.theme_type_variation = UISkin.V_HEADING
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_child(title)
	for i in list.size():
		var t := Button.new()
		t.text = "%d  %s" % [i + 1, list[i].name]
		t.toggle_mode = true
		t.button_pressed = i == current
		t.focus_mode = Control.FOCUS_NONE
		t.pressed.connect(open.bind(i))
		_tabs.add_child(t)
	var hint := Label.new()
	hint.text = "F2: edit"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UISkin.INK_SOFT)
	_tabs.add_child(hint)
	var x := DockPanel.WindowButton.new()  # TASK-100: closes like the window bar's X (Esc / the key too)
	x.kind = "close"
	x.name = "Close"
	x.pressed.connect(close)
	_tabs.add_child(x)
	for c in _pieces.get_children():
		_pieces.remove_child(c)
		c.queue_free()
	if hud.editor != null:
		return  # the editor shows the pieces while it is open
	var g := grid_rect()
	var cell := g.size / Vector2(HudWidgets.PAGE_GRID)
	var s: Dictionary = hud.table.sheets.get(hud.active, {})
	for it: Dictionary in list[current].items:
		var r: Array = it.r
		var rect := Rect2(g.position + Vector2(float(r[0]), float(r[1])) * cell, Vector2(float(r[2]), float(r[3])) * cell).grow(-3)
		var w := HudWidgets.build(str(it.w), s, hud, rect.size, it)
		w.position = rect.position
		w.size = rect.size
		_pieces.add_child(w)
