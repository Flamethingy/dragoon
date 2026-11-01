class_name SheetPages
extends Control
## The character sheet as pages (TASK-47, Nico 2026-11-01): keys 1-9 open page 1-9 of the
## active character (the same key again, or Esc, closes it); F2 edits the open one like home screens
## (LayoutEditor). A page is a grid (HudWidgets.PAGE_GRID) of the same pieces as the HUD,
## saved in the character (`sheet_pages`), for creatures in their template in the Book.

const MARGIN := 16.0
const HEAD := 44.0

var hud: CharacterHud
var current := 0
var _book: PanelContainer
var _tabs: HBoxContainer
var _pieces: Control


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
	col.add_child(_tabs)
	_pieces = Control.new()
	_pieces.name = "Pieces"
	_pieces.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pieces)


func _ready() -> void:
	resized.connect(refresh)


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
