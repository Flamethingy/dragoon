class_name LayoutEditor
extends Control
## Puts a layout together on a grid (TASK-47, builder 2: TASK-48): the HUD over the whole
## screen or the sheet pages (F2 edits the open page, else the HUD). The screen (or the page)
## is shown smaller at the top, so the builder fits around it (Nico, 2026-11-01: "zoom a bit
## out"); the rest is blurred. Below, a catalog like the Sims' build bar / Android's widgets:
## tabs (Character, Checks, Spells, Items, App) with a live preview card per piece, every
## variant side by side (portrait as token / full picture / small, ...), one quick button per
## spell, item and check (square or round). Click a card to add it, or drag it onto the
## screen. On the screen: drag a piece to move it, its lower right corner to resize it,
## double-click switches its variant, right-click removes it. The sheet pages: one tab each,
## add / delete. Done saves (also F2 / Esc), Cancel drops the changes.

signal finished(sets: Array, saved: bool)

const HANDLE := 16.0  ## the resize corner, in screen pixels
const MARGIN := 16.0
const CARD_W := 150.0
const BLUR := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 preview = vec4(0.0);  // the screen preview in UV: position, size
uniform bool show_screen = false;
void fragment() {
	vec2 local = (SCREEN_UV - preview.xy) / preview.zw;
	bool inside = show_screen && local.x >= 0.0 && local.y >= 0.0 && local.x <= 1.0 && local.y <= 1.0;
	if (inside) {
		COLOR = vec4(textureLod(screen_tex, local, 0.0).rgb * 0.9, 1.0);
	} else {
		COLOR = vec4(textureLod(screen_tex, SCREEN_UV, 3.0).rgb * 0.45, 1.0);
	}
}
"""

var grid := HudWidgets.HUD_GRID
var canvas := Vector2.ZERO  ## the real size of what is edited (the screen, a page), in pixels
var screen_backdrop := false  ## the HUD: the map shows behind the pieces, shrunk
var sets: Array = []  ## [{name, items}] (the HUD: one set)
var current := 0
var multi := false  ## pages: tabs, add and delete
var sheet := {}
var hud: CharacterHud
var tab := "Character"  ## the catalog tab shown
var shape := "square"  ## quick buttons from the catalog: square or round

var _blur: ColorRect
var _screen: Control  ## the edited area, real size, scaled down
var _layer: Control  ## the pieces
var _frames: Control  ## outlines and resize handles above them
var _tray: PanelContainer
var _cards: HBoxContainer
var _tab_buttons := {}
var _tabs: HBoxContainer  ## page tabs
var _drag := -1  ## index of the piece being moved / resized
var _resizing := false
var _grab := Vector2.ZERO  ## where in the piece it was grabbed (moving), canvas pixels


func _init() -> void:
	name = "LayoutEditor"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur = ColorRect.new()
	_blur.name = "Blur"
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = BLUR
	mat.shader = shader
	_blur.material = mat
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_blur)
	_screen = Control.new()
	_screen.name = "Screen"
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	if not screen_backdrop:
		var paper := Panel.new()
		paper.name = "Paper"
		paper.theme_type_variation = UISkin.V_PAGE
		paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_screen.add_child(paper)
	var lines := Control.new()  # the grid, above the backdrop
	lines.name = "Grid"
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.draw.connect(_draw_grid.bind(lines))
	_screen.resized.connect(lines.queue_redraw)
	_screen.add_child(lines)
	_layer = Control.new()
	_layer.name = "Pieces"
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(_layer)
	_frames = Control.new()
	_frames.name = "Frames"
	_frames.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frames.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frames.draw.connect(_draw_frames)
	_screen.add_child(_frames)
	_build_tray()
	resized.connect(_layout)
	_layout()
	grab_focus()


func items() -> Array:
	return sets[current].items if current < sets.size() else []


## A grid cell in canvas pixels.
func cell_size() -> Vector2:
	return _canvas() / Vector2(grid)


func _canvas() -> Vector2:
	return canvas if canvas.x > 0 and canvas.y > 0 else (size if size.x > 0 else Vector2(1600, 900))


## How much smaller the screen is shown.
func view_scale() -> float:
	return _screen.scale.x if _screen != null else 1.0


## Where the screen preview is, in this control's pixels.
func preview_rect() -> Rect2:
	return Rect2(_screen.position, _canvas() * view_scale()) if _screen != null else Rect2()


func _tray_height() -> float:
	return clampf(size.y * 0.28, 190.0, 300.0)


## The preview at the top, centred, as big as fits above the tray; the tray below it.
func _layout() -> void:
	if _screen == null:
		return
	var area := size if size.x > 0 and size.y > 0 else _canvas()
	var tray_h := _tray_height()
	var room := Vector2(area.x - MARGIN * 2, area.y - tray_h - MARGIN * 3)
	var c := _canvas()
	var k := minf(room.x / c.x, room.y / c.y)
	_screen.size = c
	_screen.scale = Vector2(k, k)
	_screen.position = Vector2(MARGIN + (room.x - c.x * k) * 0.5, MARGIN + (room.y - c.y * k) * 0.5)
	_tray.position = Vector2(MARGIN, area.y - tray_h - MARGIN)
	_tray.size = Vector2(area.x - MARGIN * 2, tray_h)
	var mat := _blur.material as ShaderMaterial
	mat.set_shader_parameter("preview", Vector4(_screen.position.x / area.x, _screen.position.y / area.y, c.x * k / area.x, c.y * k / area.y))
	mat.set_shader_parameter("show_screen", screen_backdrop)
	_rebuild()
	_fill_cards()


# --- The catalog tray ----------------------------------------------------------------------

func _build_tray() -> void:
	_tray = PanelContainer.new()
	_tray.name = "Tray"
	_tray.theme_type_variation = UISkin.V_PAGE
	_tray.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_tray)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_tray.add_child(row)
	var tabs := VBoxContainer.new()
	tabs.name = "Tabs"
	row.add_child(tabs)
	var group := ButtonGroup.new()
	for t: String in HudWidgets.TABS:
		var b := _tool_button(tabs, t, show_tab.bind(t))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t == tab
		_tab_buttons[t] = b
	var scroll := ScrollContainer.new()
	scroll.name = "Catalog"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_cards = HBoxContainer.new()
	_cards.name = "Cards"
	_cards.add_theme_constant_override("separation", 8)
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cards)
	var side := VBoxContainer.new()
	side.name = "Side"
	side.custom_minimum_size.x = 200
	side.add_theme_constant_override("separation", 4)
	row.add_child(side)
	var title := Label.new()
	title.text = "Sheet pages" if multi else "HUD"
	title.theme_type_variation = UISkin.V_HEADING
	side.add_child(title)
	if multi:
		_tabs = HBoxContainer.new()
		_tabs.name = "Pages"
		side.add_child(_tabs)
		var pages_row := HBoxContainer.new()
		side.add_child(pages_row)
		_tool_button(pages_row, "+ Page", add_page)
		_tool_button(pages_row, "Delete page", delete_page)
	var round := CheckButton.new()
	round.name = "Round"
	round.text = "Round buttons"
	round.focus_mode = Control.FOCUS_NONE
	round.toggled.connect(func(on: bool) -> void:
		shape = "round" if on else "square"
		_fill_cards())
	side.add_child(round)
	var hint := Label.new()
	hint.text = "Click or drag a card onto the screen\nDouble-click: variant · right-click: remove"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UISkin.INK_SOFT)
	side.add_child(hint)
	var end := HBoxContainer.new()
	side.add_child(end)
	_tool_button(end, "Reset", reset).tooltip_text = "Back to the default layout"
	_tool_button(end, "Cancel", finish.bind(false))
	_tool_button(end, "Done", finish.bind(true))


func show_tab(t: String) -> void:
	tab = t
	for key: String in _tab_buttons:
		(_tab_buttons[key] as Button).set_pressed_no_signal(key == t)
	_fill_cards()


## The cards of the tab: a live preview of each piece, scaled into the card.
func _fill_cards() -> void:
	if _cards == null:
		return
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	var thumb := Vector2(CARD_W - 16, maxf(_tray_height() - 64, 60))
	var cell := cell_size()
	for entry: Dictionary in HudWidgets.catalog(sheet, shape):
		if entry.tab != tab:
			continue
		var card := PanelContainer.new()
		card.name = "Card_" + (str(entry.w) + "_" + str(entry.v) + "_" + str(entry.ref)).validate_node_name().replace(" ", "_")
		card.custom_minimum_size = Vector2(CARD_W, 0)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.tooltip_text = "%s\nClick: add · drag it onto the screen" % entry.label
		card.add_theme_stylebox_override("panel", _card_box(false))
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(col)
		var box := Control.new()
		box.name = "Thumb"
		box.clip_contents = true
		box.custom_minimum_size = thumb
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(box)
		var cells: Array = HudWidgets.KINDS[entry.w].size
		var real := Vector2(float(cells[0]), float(cells[1])) * cell
		var piece := HudWidgets.build(str(entry.w), sheet, hud, real, entry)
		piece.size = real
		var k := minf(minf(thumb.x / real.x, thumb.y / real.y), 1.4)
		piece.scale = Vector2(k, k)
		piece.position = (thumb - real * k) * 0.5
		_ignore_mouse(piece)
		box.add_child(piece)
		var label := Label.new()
		label.text = str(entry.label)
		label.clip_text = true
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.x = CARD_W - 16
		label.add_theme_font_size_override("font_size", 12)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(label)
		card.gui_input.connect(_card_input.bind(entry))
		card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", _card_box(true)))
		card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", _card_box(false)))
		card.set_drag_forwarding(_card_drag.bind(entry, card), Callable(), Callable())
		_cards.add_child(card)
	if _cards.get_child_count() == 0:
		var none := Label.new()
		none.text = {"Spells": "No spells on this sheet", "Items": "Nothing in the inventory"}.get(tab, "Nothing here")
		none.add_theme_color_override("font_color", UISkin.INK_SOFT)
		_cards.add_child(none)


static func _card_box(hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UISkin.CREAM.darkened(0.04 if hover else 0.0)
	sb.border_color = Color(1.0, 0.55, 0.1) if hover else UISkin.TAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(6)
	return sb


func _card_input(event: InputEvent, entry: Dictionary) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			add_item(str(entry.w), str(entry.v), str(entry.ref))


func _card_drag(_at: Vector2, entry: Dictionary, card: Control) -> Variant:
	var ghost := Label.new()
	ghost.text = "  %s  " % entry.label
	var sb := _card_box(true)
	ghost.add_theme_stylebox_override("normal", sb)
	ghost.add_theme_color_override("font_color", UISkin.INK)
	card.set_drag_preview(ghost)
	return {"w": entry.w, "v": entry.v, "ref": entry.ref}


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return data is Dictionary and HudWidgets.KINDS.has(str((data as Dictionary).get("w", ""))) and preview_rect().has_point(at)


## A card dropped on the screen: the piece is put there (centred on the mouse).
func _drop_data(at: Vector2, data: Variant) -> void:
	var d := data as Dictionary
	var cells: Array = HudWidgets.KINDS[d.w].size
	var c := _to_canvas(at) / cell_size() - Vector2(float(cells[0]), float(cells[1])) * 0.5
	add_item(str(d.w), str(d.get("v", "")), str(d.get("ref", "")), Vector2i(c.round()))


func _tool_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


# --- Editing ------------------------------------------------------------------------------

## Adds a piece at the first free place for its default size (else top left).
func add(kind: String) -> void:
	add_item(kind)


## Adds a piece (a variant, a quick button's ref) at `at` (cells), or the first free place.
func add_item(kind: String, v := "", ref := "", at := Vector2i(-1, -1)) -> void:
	if not HudWidgets.KINDS.has(kind) or (kind in HudWidgets.QUICK and ref == ""):
		return
	if sets.is_empty():
		sets.append({"name": "Page 1", "items": []})
	var cells: Array = HudWidgets.KINDS[kind].size
	var w := mini(int(cells[0]), grid.x)
	var h := mini(int(cells[1]), grid.y)
	var pos := Vector2i(clampi(at.x, 0, grid.x - w), clampi(at.y, 0, grid.y - h))
	if at.x < 0 or at.y < 0:
		pos = Vector2i.ZERO
		var found := false
		for y in grid.y - h + 1:
			for x in grid.x - w + 1:
				if not found and _free(Rect2i(x, y, w, h), -1):
					pos = Vector2i(x, y)
					found = true
	var item := {"w": kind, "r": [pos.x, pos.y, w, h]}
	if v != "" and v in HudWidgets.VARIANTS.get(kind, []):
		item["v"] = v
	if ref != "":
		item["ref"] = ref
	items().append(item)
	_rebuild()


func remove(index: int) -> void:
	if index >= 0 and index < items().size():
		items().remove_at(index)
		_rebuild()


## The next variant of piece `index` (portrait: token -> full picture -> small -> token).
func cycle_variant(index: int) -> void:
	if index < 0 or index >= items().size():
		return
	var it: Dictionary = items()[index]
	var list: Array = HudWidgets.VARIANTS.get(str(it.w), [])
	if list.size() < 2:
		return
	it["v"] = list[(list.find(HudWidgets.variant(it)) + 1) % list.size()]
	_rebuild()


func reset() -> void:
	if multi:
		sets = HudWidgets.DEFAULT_PAGES.duplicate(true)
		current = 0
	else:
		sets = [{"name": "HUD", "items": HudWidgets.DEFAULT_HUD.duplicate(true)}]
	_rebuild()


func add_page() -> void:
	if sets.size() >= 9:
		return
	sets.append({"name": "Page %d" % (sets.size() + 1), "items": []})
	current = sets.size() - 1
	_rebuild()


func delete_page() -> void:
	if sets.size() <= 1:
		return
	sets.remove_at(current)
	current = clampi(current, 0, sets.size() - 1)
	_rebuild()


func show_set(index: int) -> void:
	current = clampi(index, 0, maxi(sets.size() - 1, 0))
	_rebuild()


func finish(save: bool) -> void:
	finished.emit(sets, save)
	queue_free()


## Moves / resizes piece `index` to `r` (cells), kept inside the grid.
func place(index: int, r: Rect2i) -> void:
	var w := clampi(r.size.x, 1, grid.x)
	var h := clampi(r.size.y, 1, grid.y)
	items()[index].r = [clampi(r.position.x, 0, grid.x - w), clampi(r.position.y, 0, grid.y - h), w, h]
	_rebuild()


func _free(r: Rect2i, skip: int) -> bool:
	var list := items()
	for i in list.size():
		var o: Array = list[i].r
		if i != skip and r.intersects(Rect2i(int(o[0]), int(o[1]), int(o[2]), int(o[3]))):
			return false
	return true


## A piece's rect in canvas pixels.
func _rect_px(r: Array) -> Rect2:
	var c := cell_size()
	return Rect2(Vector2(float(r[0]), float(r[1])) * c, Vector2(float(r[2]), float(r[3])) * c)


func _to_canvas(pos: Vector2) -> Vector2:
	return (pos - _screen.position) / view_scale()


func _rebuild() -> void:
	if _layer == null:
		return
	for c in _layer.get_children():
		_layer.remove_child(c)
		c.queue_free()
	var list := items()
	for i in list.size():
		var rect := _rect_px(list[i].r).grow(-2)
		var piece := HudWidgets.build(str(list[i].w), sheet, hud, rect.size, list[i])
		piece.position = rect.position
		piece.size = rect.size
		_ignore_mouse(piece)
		_layer.add_child(piece)
	if _tabs != null:
		for c in _tabs.get_children():
			_tabs.remove_child(c)
			c.queue_free()
		for i in sets.size():
			var b := _tool_button(_tabs, str(i + 1), show_set.bind(i))
			b.toggle_mode = true
			b.button_pressed = i == current
			b.tooltip_text = str(sets[i].get("name", ""))
	if _frames != null:
		_frames.queue_redraw()


static func _ignore_mouse(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in c.get_children():
		if child is Control:
			_ignore_mouse(child)


## The cells: thin lines, every 4th a stronger one, a frame around the whole grid.
func _draw_grid(on: Control) -> void:
	var a := Rect2(Vector2.ZERO, _canvas())
	var c := cell_size()
	var px := 1.0 / maxf(view_scale(), 0.05)  # one screen pixel
	on.draw_rect(a, Color(1, 1, 1, 0.04))
	for x in grid.x + 1:
		var strong := x % 4 == 0
		on.draw_line(Vector2(x * c.x, 0), Vector2(x * c.x, a.size.y), Color(1, 1, 1, 0.38 if strong else 0.18), (1.5 if strong else 1.0) * px)
	for y in grid.y + 1:
		var strong := y % 4 == 0
		on.draw_line(Vector2(0, y * c.y), Vector2(a.size.x, y * c.y), Color(1, 1, 1, 0.38 if strong else 0.18), (1.5 if strong else 1.0) * px)
	on.draw_rect(a, Color(1.0, 0.55, 0.1, 0.9), false, 2.0 * px)


## Outlines and resize handles above the pieces.
func _draw_frames() -> void:
	var px := 1.0 / maxf(view_scale(), 0.05)
	var handle := HANDLE * px
	var list := items()
	for i in list.size():
		var rect := _rect_px(list[i].r)
		var col := Color(1.0, 0.55, 0.1, 0.95) if i == _drag else Color(1, 1, 1, 0.85)
		_frames.draw_rect(rect, col, false, 2.0 * px)
		_frames.draw_rect(Rect2(rect.end - Vector2(handle, handle), Vector2(handle, handle)), col)


## The piece under a point (canvas pixels), the top one first.
func _piece_at(pos: Vector2) -> int:
	var list := items()
	for i in range(list.size() - 1, -1, -1):
		if _rect_px(list[i].r).has_point(pos):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var at := _to_canvas(mb.position)
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			remove(_piece_at(at))
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.double_click:
				cycle_variant(_piece_at(at))
				_drag = -1
			elif mb.pressed:
				_drag = _piece_at(at)
				if _drag >= 0:
					var rect := _rect_px(items()[_drag].r)
					var handle := HANDLE / maxf(view_scale(), 0.05)
					_resizing = Rect2(rect.end - Vector2(handle, handle), Vector2(handle, handle)).grow(handle * 0.3).has_point(at)
					_grab = at - rect.position
			else:
				_drag = -1
			_frames.queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and _drag >= 0:
		var mm := event as InputEventMouseMotion
		var c := cell_size()
		var r: Array = items()[_drag].r
		var local := _to_canvas(mm.position)
		if _resizing:
			var end := Vector2i((local / c).round())
			place(_drag, Rect2i(int(r[0]), int(r[1]), maxi(1, end.x - int(r[0])), maxi(1, end.y - int(r[1]))))
		else:
			var to := Vector2i(((local - _grab) / c).round())
			if to != Vector2i(int(r[0]), int(r[1])):
				place(_drag, Rect2i(to.x, to.y, int(r[2]), int(r[3])))
		accept_event()
