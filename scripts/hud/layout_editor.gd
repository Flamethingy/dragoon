class_name LayoutEditor
extends Control
## Puts a layout together on a grid (TASK-47, builder 2: TASK-48): the HUD over the whole
## screen or the sheet pages (F2 edits the open page, else the HUD). The screen (or the page)
## is shown smaller at the top, so the builder fits around it (Nico, 2026-11-01: "zoom a bit
## out"); the rest is blurred. Below, a catalog like the Sims' build bar / Android's widgets:
## tabs (Character, Checks, Spells, Items, App) with a live preview card per piece, every
## variant side by side (portrait as token / full picture / small, ...), one quick button per
## spell, item and check. Click a card to add it, or drag it onto the screen. On the screen
## (TASK-50): click selects a piece, Shift + click more of them, a drag on empty space selects
## with a box; dragging a selected piece moves them all, its lower right corner resizes it;
## double-click switches its variant, right-click or Delete removes. The inspector on the
## right shows the selection: variant, round, name, amount badge, size, position, what a
## quick button is for; with several selected, what they share (changes go to all of them).
## The sheet pages: one tab each, add / delete. Done saves (also F2 / Esc), Cancel drops
## the changes.
## One editor for the HUD and the pages (TASK-78): a set may bring its own `grid`, `canvas`
## and `backdrop` (the HUD: the screen behind it; a page: paper), and the one marked `home` is
## the HUD (its tab "HUD"). Keys 1-9 switch to editing that page, the same key again back to
## the HUD (show_page).

signal finished(sets: Array, saved: bool)
signal set_shown(index: int)  ## another set (the HUD, a page) is edited now

const HANDLE := 16.0  ## the resize corner, in screen pixels
const MARGIN := 16.0
const CARD_W := 150.0
const INSPECTOR_W := 250.0
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
var selected: Array = []  ## indices of the selected pieces (TASK-50)

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
var _press := Vector2.ZERO  ## where the mouse went down, canvas pixels
var _start := {}  ## index -> its rect when a move of the selection began
var _boxing := false
var _box := Rect2()  ## the selection box being drawn, canvas pixels
var _box_add := false  ## Shift: the box adds to the selection
var _inspector: VBoxContainer
var _paper: Panel
var _lines: Control
var _title: Label
var _delete_page: Button


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
	_paper = Panel.new()
	_paper.name = "Paper"
	_paper.theme_type_variation = UISkin.V_PAGE
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(_paper)
	var lines := Control.new()  # the grid, above the backdrop
	_lines = lines
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
	_build_inspector()
	resized.connect(_layout)
	_take_set()
	_layout()
	grab_focus()


## The current set's own grid, size and backdrop (TASK-78).
func _take_set() -> void:
	if current >= sets.size():
		return
	var s: Dictionary = sets[current]
	if s.get("grid") is Vector2i:
		grid = s.grid
	if s.get("canvas") is Vector2:
		canvas = s.canvas
	if s.has("backdrop"):
		screen_backdrop = bool(s.backdrop)
	if _paper != null:
		_paper.visible = not screen_backdrop
	if _lines != null:
		_lines.queue_redraw()
	if _title != null:
		_title.text = "HUD" if is_home(current) else ("Sheet page %d" % (pages().find(current) + 1) if multi else "HUD")
	if _delete_page != null:
		_delete_page.disabled = is_home(current) or pages().size() <= 1


func is_home(index: int) -> bool:
	return index >= 0 and index < sets.size() and bool((sets[index] as Dictionary).get("home", false))


## The sets that are sheet pages (indices), in order.
func pages() -> Array:
	var out := []
	for i in sets.size():
		if not is_home(i):
			out.append(i)
	return out


## The HUD's set (-1 if only pages are edited).
func home() -> int:
	for i in sets.size():
		if is_home(i):
			return i
	return -1


## Key n (0-based) in the editor: edit page n; on it already, back to the HUD.
func show_page(n: int) -> void:
	var list := pages()
	if n < 0 or n >= list.size():
		return
	if current == int(list[n]) and home() >= 0:
		show_set(home())
	else:
		show_set(int(list[n]))


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
	var room := Vector2(area.x - MARGIN * 3 - INSPECTOR_W, area.y - tray_h - MARGIN * 3)
	var c := _canvas()
	var k := maxf(minf(room.x / c.x, room.y / c.y), 0.05)
	_screen.size = c
	_screen.scale = Vector2(k, k)
	_screen.position = Vector2(MARGIN + (room.x - c.x * k) * 0.5, MARGIN + (room.y - c.y * k) * 0.5)
	_tray.position = Vector2(MARGIN, area.y - tray_h - MARGIN)
	_tray.size = Vector2(area.x - MARGIN * 2, tray_h)
	var panel := _inspector.get_parent().get_parent() as Control
	panel.position = Vector2(area.x - MARGIN - INSPECTOR_W, MARGIN)
	panel.size = Vector2(INSPECTOR_W, area.y - tray_h - MARGIN * 3)
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
	title.name = "Title"
	title.text = "Sheet pages" if multi else "HUD"
	title.theme_type_variation = UISkin.V_HEADING
	side.add_child(title)
	_title = title
	if multi:
		_tabs = HBoxContainer.new()
		_tabs.name = "Pages"
		side.add_child(_tabs)
		var pages_row := HBoxContainer.new()
		side.add_child(pages_row)
		_tool_button(pages_row, "+ Page", add_page)
		_delete_page = _tool_button(pages_row, "Delete page", delete_page)
	var hint := Label.new()
	hint.text = "Click or drag a card onto the screen.\nClick a piece: select · Shift: more\nDouble-click: variant · Del: remove" + ("\n1-9: edit that page · again: the HUD" if home() >= 0 else "")
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UISkin.INK_SOFT)
	side.add_child(hint)
	var end := HBoxContainer.new()
	side.add_child(end)
	_tool_button(end, "Reset", reset).tooltip_text = "Back to the default layout"
	_tool_button(end, "Cancel", finish.bind(false))
	_tool_button(end, "Done", finish.bind(true))


# --- The inspector (TASK-50) -----------------------------------------------------------------

func _build_inspector() -> void:
	var panel := PanelContainer.new()
	panel.name = "InspectorPanel"
	panel.theme_type_variation = UISkin.V_PAGE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_inspector = VBoxContainer.new()
	_inspector.name = "Inspector"
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.add_theme_constant_override("separation", 6)
	scroll.add_child(_inspector)


## The selected items.
func picked() -> Array:
	var list := items()
	return selected.filter(func(i: int) -> bool: return i < list.size()).map(func(i: int) -> Dictionary: return list[i])


## Selects pieces by index (`add`: to the ones selected; a selected one is then unselected).
func select(indices: Array, add := false) -> void:
	if not add:
		selected = []
	for i: int in indices:
		if i < 0 or i >= items().size():
			continue
		if add and i in selected:
			selected.erase(i)
		elif i not in selected:
			selected.append(i)
	_rebuild()


## Sets `key` on every selected piece (`value` null: back to the default, the key goes).
func set_attr(key: String, value: Variant) -> void:
	for it: Dictionary in picked():
		if value == null:
			it.erase(key)
		else:
			it[key] = value
	_rebuild(false)


## Round (or square) quick buttons.
func set_round(on: bool) -> void:
	for it: Dictionary in picked():
		if str(it.w) in HudWidgets.QUICK:
			it["v"] = "round" if on else "square"
	_rebuild(false)


## Every selected piece `w` x `h` cells (0 keeps that side), kept inside the grid.
func set_cells(w: int, h: int) -> void:
	for it: Dictionary in picked():
		var r: Array = it.r
		_set_rect(it, Rect2i(int(r[0]), int(r[1]), w if w > 0 else int(r[2]), h if h > 0 else int(r[3])))
	_rebuild(false)


func remove_selected() -> void:
	var order := selected.duplicate()
	order.sort()
	order.reverse()
	for i: int in order:
		if i < items().size():
			items().remove_at(i)
	selected = []
	_rebuild()


## The value all selected pieces share for `read` (a Callable on an item), else null (mixed).
func _shared(read: Callable) -> Variant:
	var list := picked()
	if list.is_empty():
		return null
	var first: Variant = read.call(list[0])
	for it: Dictionary in list:
		if read.call(it) != first:
			return null
	return first


func _fill_inspector() -> void:
	if _inspector == null:
		return
	for c in _inspector.get_children():
		_inspector.remove_child(c)
		c.queue_free()
	var head := Label.new()
	head.theme_type_variation = UISkin.V_HEADING
	_inspector.add_child(head)
	var list := picked()
	if list.is_empty():
		head.text = "Inspector"
		_inspector.add_child(_note("Click a piece to change it.\nShift + click or a box on empty space: several at once."))
		return
	var kinds := {}
	for it: Dictionary in list:
		kinds[str(it.w)] = true
	var one: Dictionary = list[0]
	if list.size() == 1:
		head.text = HudWidgets.quick_name(str(one.w), str(one.ref), sheet) if one.has("ref") else str(HudWidgets.KINDS[one.w].label)
		if one.has("ref"):
			_inspector.add_child(_note(str(HudWidgets.KINDS[one.w].label)))
	else:
		head.text = "%d pieces" % list.size()
		_inspector.add_child(_note("Changes go to all of them" + ("" if kinds.size() == 1 else " (what they share)")))
	var quick := kinds.keys().all(func(k: String) -> bool: return k in HudWidgets.QUICK)
	# the variant: one kind with variants (quick buttons: Round below)
	if kinds.size() == 1 and HudWidgets.VARIANTS.has(one.w) and not quick:
		var opts := OptionButton.new()
		opts.name = "Variant"
		var names: Array = HudWidgets.VARIANTS[one.w]
		for v: String in names:
			opts.add_item(str(HudWidgets.VARIANT_LABELS.get(v, v)).capitalize())
		var now: Variant = _shared(func(it: Dictionary) -> String: return HudWidgets.variant(it))
		opts.select(names.find(now) if now != null else -1)
		opts.item_selected.connect(func(i: int) -> void: set_attr("v", names[i]))
		_row("Variant", opts)
	if quick:
		var round_now: Variant = _shared(func(it: Dictionary) -> bool: return HudWidgets.variant(it) == "round")
		_tick("Round", "Round" + (" (mixed)" if round_now == null else ""), round_now == true, set_round)
		var badge_now: Variant = _shared(func(it: Dictionary) -> bool: return it.get("badge", true) != false)
		_tick("Badge", "Amount badge" + (" (mixed)" if badge_now == null else ""), badge_now != false,
			func(on: bool) -> void: set_attr("badge", null if on else false))
	if kinds.keys().all(func(k: String) -> bool: return k in HudWidgets.QUICK or k == "portrait"):
		var name_now: Variant = _shared(func(it: Dictionary) -> bool: return it.get("name", true) != false)
		_tick("ShowName", "Show the name" + (" (mixed)" if name_now == null else ""), name_now != false,
			func(on: bool) -> void: set_attr("name", null if on else false))
	# size (all), position (one)
	var w_now: Variant = _shared(func(it: Dictionary) -> int: return int(it.r[2]))
	var h_now: Variant = _shared(func(it: Dictionary) -> int: return int(it.r[3]))
	var size_row := HBoxContainer.new()
	size_row.add_child(_spin("W", int(one.r[2]) if w_now == null else int(w_now), grid.x, func(v: float) -> void: set_cells(int(v), 0)))
	size_row.add_child(_spin("H", int(one.r[3]) if h_now == null else int(h_now), grid.y, func(v: float) -> void: set_cells(0, int(v))))
	_row("Size" + (" (mixed)" if w_now == null or h_now == null else ""), size_row)
	if list.size() == 1:
		var pos_row := HBoxContainer.new()
		var move_x := func(v: float) -> void:
			var r: Array = one.r
			_set_rect(one, Rect2i(int(v), int(r[1]), int(r[2]), int(r[3])))
			_rebuild(false)
		var move_y := func(v: float) -> void:
			var r: Array = one.r
			_set_rect(one, Rect2i(int(r[0]), int(v), int(r[2]), int(r[3])))
			_rebuild(false)
		pos_row.add_child(_spin("X", int(one.r[0]), grid.x - 1, move_x, 0))
		pos_row.add_child(_spin("Y", int(one.r[1]), grid.y - 1, move_y, 0))
		_row("Position", pos_row)
	# what a quick button is for
	if list.size() == 1 and one.has("ref"):
		var refs := OptionButton.new()
		refs.name = "Ref"
		var choices := HudWidgets.catalog(sheet).filter(func(c: Dictionary) -> bool: return c.w == one.w)
		var at := -1
		for c: Dictionary in choices:
			refs.add_item(str(c.label))
			if c.ref == one.ref:
				at = refs.item_count - 1
		if at < 0:  # not on the sheet any more: still shown
			refs.add_item(HudWidgets.quick_name(str(one.w), str(one.ref), sheet))
			at = refs.item_count - 1
		refs.select(at)
		refs.item_selected.connect(func(i: int) -> void:
			if i < choices.size():
				one["ref"] = choices[i].ref
				_rebuild())
		_row({"spell": "Spell", "item": "Item", "check": "Check"}[one.w], refs)
	var remove_button := _tool_button(_inspector, "Remove" + (" all %d" % list.size() if list.size() > 1 else ""), remove_selected)
	remove_button.name = "Remove"


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UISkin.INK_SOFT)
	return l


func _row(label: String, field: Control) -> void:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 13)
	_inspector.add_child(l)
	_inspector.add_child(field)


func _tick(id: String, text: String, on: bool, action: Callable) -> void:
	var c := CheckBox.new()
	c.name = id
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(v: bool) -> void: action.call(v))
	_inspector.add_child(c)


func _spin(id: String, value: int, max_value: int, action: Callable, min_value := 1) -> SpinBox:
	var sp := SpinBox.new()
	sp.name = id
	sp.prefix = id
	sp.min_value = min_value
	sp.max_value = max_value
	sp.value = value
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.value_changed.connect(func(v: float) -> void: action.call(v))
	return sp


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
	selected = [items().size() - 1]  # the new piece is selected: the inspector shows it
	_rebuild()


func remove(index: int) -> void:
	if index >= 0 and index < items().size():
		items().remove_at(index)
		selected = []
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


## Back to the default: the HUD's (on the HUD), else the default pages.
func reset() -> void:
	if is_home(current) or not multi:
		(sets[current] as Dictionary)["items"] = HudWidgets.DEFAULT_HUD.duplicate(true)
	else:
		var keep := _page_keys()
		var out := []
		var h := home()
		if h >= 0:
			out.append(sets[h])
		for p: Dictionary in HudWidgets.DEFAULT_PAGES.duplicate(true):
			p.merge(keep)
			out.append(p)
		sets = out
		current = pages()[0]
	selected = []
	_rebuild()


## What a page set brings besides its name and pieces (grid, canvas, backdrop).
func _page_keys() -> Dictionary:
	var out := {}
	var list := pages()
	if not list.is_empty():
		var p: Dictionary = sets[list[0]]
		for k: String in ["grid", "canvas", "backdrop"]:
			if p.has(k):
				out[k] = p[k]
	return out


func add_page() -> void:
	if pages().size() >= 9:
		return
	var p := {"name": "Page %d" % (pages().size() + 1), "items": []}
	p.merge(_page_keys())
	sets.append(p)
	show_set(sets.size() - 1)


func delete_page() -> void:
	if is_home(current) or pages().size() <= 1:
		return
	sets.remove_at(current)
	show_set(clampi(current, 0, sets.size() - 1) if not is_home(clampi(current, 0, sets.size() - 1)) else pages()[0])


func show_set(index: int) -> void:
	var before := current
	current = clampi(index, 0, maxi(sets.size() - 1, 0))
	selected = []
	if _screen != null:
		_take_set()
		_layout()
	else:
		_rebuild()
	if current != before:
		set_shown.emit(current)


func finish(save: bool) -> void:
	finished.emit(sets, save)
	queue_free()


## Moves / resizes piece `index` to `r` (cells), kept inside the grid.
func place(index: int, r: Rect2i) -> void:
	_set_rect(items()[index], r)
	_rebuild(false)


func _set_rect(it: Dictionary, r: Rect2i) -> void:
	var w := clampi(r.size.x, 1, grid.x)
	var h := clampi(r.size.y, 1, grid.y)
	it.r = [clampi(r.position.x, 0, grid.x - w), clampi(r.position.y, 0, grid.y - h), w, h]


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


## Builds the pieces again; `inspect`: the inspector too (not while one of its fields is
## being changed: it would lose the field).
func _rebuild(inspect := true) -> void:
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
		var n := 0
		for i in sets.size():
			if not is_home(i):
				n += 1
			var b := _tool_button(_tabs, "HUD" if is_home(i) else str(n), show_set.bind(i))
			b.name = "Set_%d" % i
			b.toggle_mode = true
			b.button_pressed = i == current
			b.tooltip_text = "The HUD over the screen" if is_home(i) else "%s (key %d)" % [sets[i].get("name", ""), n]
	if _frames != null:
		_frames.queue_redraw()
	if inspect:
		_fill_inspector()


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


## Outlines and resize handles above the pieces: the selected ones orange; the box.
func _draw_frames() -> void:
	var px := 1.0 / maxf(view_scale(), 0.05)
	var handle := HANDLE * px
	var list := items()
	for i in list.size():
		var rect := _rect_px(list[i].r)
		var on := i in selected
		var col := Color(1.0, 0.55, 0.1, 0.95) if on else Color(1, 1, 1, 0.85)
		if on:
			_frames.draw_rect(rect, Color(1.0, 0.55, 0.1, 0.12))
		_frames.draw_rect(rect, col, false, (3.0 if on else 2.0) * px)
		_frames.draw_rect(Rect2(rect.end - Vector2(handle, handle), Vector2(handle, handle)), col)
	if _boxing and _box.has_area():
		_frames.draw_rect(_box, Color(1.0, 0.55, 0.1, 0.12))
		_frames.draw_rect(_box, Color(1.0, 0.55, 0.1, 0.9), false, 1.5 * px)


## The piece under a point (canvas pixels), the top one first.
func _piece_at(pos: Vector2) -> int:
	var list := items()
	for i in range(list.size() - 1, -1, -1):
		if _rect_px(list[i].r).has_point(pos):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode in [KEY_DELETE, KEY_BACKSPACE]:
		remove_selected()
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var at := _to_canvas(mb.position)
		if mb.pressed:
			grab_focus()
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			remove(_piece_at(at))
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.double_click:
				cycle_variant(_piece_at(at))
				_drag = -1
			elif mb.pressed:
				_press = at
				_drag = _piece_at(at)
				if _drag < 0:  # empty space: a selection box
					_boxing = true
					_box_add = mb.shift_pressed
					_box = Rect2(at, Vector2.ZERO)
					if not mb.shift_pressed and not selected.is_empty():
						select([])
				else:
					var rect := _rect_px(items()[_drag].r)
					var handle := minf(HANDLE / maxf(view_scale(), 0.05), minf(rect.size.x, rect.size.y) * 0.4)  # never most of a small piece
					_resizing = Rect2(rect.end - Vector2(handle, handle), Vector2(handle, handle)).grow(handle * 0.3).has_point(at)
					if mb.shift_pressed:
						select([_drag], true)
						if _drag not in selected:
							_drag = -1  # Shift + click took it out again
					elif _drag not in selected:
						select([_drag])
					_start = {}
					for i: int in selected:
						_start[i] = (items()[i].r as Array).duplicate()
			else:
				if _boxing:
					_boxing = false
					var hits := []
					if _box.size.length() > 4.0 / maxf(view_scale(), 0.05):
						for i in items().size():
							if _box.intersects(_rect_px(items()[i].r)):
								hits.append(i)
					if _box_add:
						for i: int in hits:
							if i not in selected:
								selected.append(i)
						_rebuild()
					else:
						select(hits)
				elif _drag >= 0:
					_fill_inspector()  # the new position / size
				_drag = -1
			_frames.queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion:
		var local := _to_canvas((event as InputEventMouseMotion).position)
		if _boxing:
			_box = Rect2(_press, local - _press).abs()
			_frames.queue_redraw()
			accept_event()
		elif _drag >= 0:
			var c := cell_size()
			var r: Array = items()[_drag].r
			if _resizing:
				var end := Vector2i((local / c).round())
				place(_drag, Rect2i(int(r[0]), int(r[1]), maxi(1, end.x - int(r[0])), maxi(1, end.y - int(r[1]))))
			else:  # the whole selection moves by whole cells, kept inside the grid together
				var step := Vector2i(((local - _press) / c).round())
				for i: int in _start:
					var s: Array = _start[i]
					step.x = clampi(step.x, -int(s[0]), grid.x - int(s[0]) - int(s[2]))
					step.y = clampi(step.y, -int(s[1]), grid.y - int(s[1]) - int(s[3]))
				for i: int in _start:
					var s: Array = _start[i]
					_set_rect(items()[i], Rect2i(int(s[0]) + step.x, int(s[1]) + step.y, int(s[2]), int(s[3])))
				_rebuild(false)
			accept_event()
