class_name Compendium
extends Control
## Browser for the core data packages (TASK-15), styled as a card collection book:
## bookmark tabs per kind on the left, a binder page of cards (picture, badge, name) in
## the middle that flips page by page, and the open card on the right with its key facts.
## The full text (stat block, Markdown) is folded away under "Full text".
## [[Wikilinks]] in it open the entry they name; Back returns.
## Document tabs (TASK-22) above the binder: "Browse" is the binder itself; double-click,
## middle-click, "Open" or Ctrl+click on a link opens an entry in its own full-view tab
## (EntryView). Tabs close (x, middle-click, Ctrl+W), switch (Ctrl+Tab), reorder by drag,
## keep their scroll position and come back on the next start (tabs_file).
## Packages load on a worker thread (PackageDB), so the window stays responsive.

signal tabs_restored  ## the saved tabs are open again (after loading)

const SEARCH_DELAY := 0.15
const GRID_GAP := 14
const SORTS := ["Name", "CR / Level", "Type", "Package"]
const DETAIL_WIDTH := 430
const KIND_ICONS := {"monsters": "icon_sword", "spells": "star", "items": "icon_chest",
	"features": "icon_dagger", "classes": "icon_helmet", "races": "icon_armor"}

var db := PackageDB.new()
## Where the open tabs are kept between runs ("" = don't keep them).
var tabs_file := "user://compendium_tabs.json"

var _status: Label
var _progress: ProgressBar
var _tabs: VBoxContainer
var _tab_group := ButtonGroup.new()
var _search: LineEdit
var _in_text: Button
var _package: OptionButton
var _level: OptionButton
var _type: OptionButton
var _sort: OptionButton
var _page_area: Control
var _grid: GridContainer
var _prev: TextureButton
var _next: TextureButton
var _page_label: Label
var _search_timer: Timer

var _detail_scroll: ScrollContainer
var _detail_box: VBoxContainer
var _back: Button
var _full_text := false

var _kind := ""
var _level_values: Array = []  ## option index - 1 -> value
var _type_values: Array = []
var _package_values: Array = []
var _matches: Array = []
var _page := 0
var _per_page := 12
var _columns := 4
var _current: Dictionary = {}
var _history: Array[Dictionary] = []

var _browse_button: Button
var _tab_bar: TabBar
var _views: Control  ## holds _browse and the EntryViews, one shown at a time
var _browse: Control
var _open_views := {}  ## key -> EntryView
var _saved_tabs: Variant = null  ## {tabs: [{key, scroll}], current} to restore after a load
var _restoring := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UISkin.theme()
	StatBlock.db = db
	_build()
	db.loaded.connect(_on_loaded)
	db.load_async()


# --- Layout --------------------------------------------------------------------------

func _build() -> void:
	var cover := PanelContainer.new()
	cover.theme_type_variation = UISkin.V_COVER
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cover)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	cover.add_child(row)

	# Left: title and bookmark tabs on the cover.
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(190, 0)
	side.add_theme_constant_override("separation", 6)
	row.add_child(side)
	var title := Label.new()
	title.text = "Compendium"
	title.theme_type_variation = UISkin.V_PLATE_LABEL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(title)
	_status = Label.new()
	_status.text = "Opening the book..."
	_status.add_theme_color_override("font_color", UISkin.TAN)
	_status.add_theme_font_size_override("font_size", 12)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_status)
	_progress = ProgressBar.new()
	_progress.indeterminate = true
	_progress.show_percentage = false
	side.add_child(_progress)
	var tabs_scroll := ScrollContainer.new()
	tabs_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(tabs_scroll)
	_tabs = VBoxContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_constant_override("separation", 6)
	tabs_scroll.add_child(_tabs)
	var manage := Button.new()
	manage.text = "Packages..."
	manage.tooltip_text = "Import, export, switch on/off or remove source packages"
	manage.icon = UISkin.tex("icon_chest")
	manage.pressed.connect(_open_packages)
	side.add_child(manage)

	# Right of the cover: the document tabs over the binder (Browse) or a full view.
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)
	row.add_child(main)
	main.add_child(_build_tab_row())
	_views = Control.new()
	_views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_views)
	_browse = HBoxContainer.new()
	_browse.add_theme_constant_override("separation", 12)
	_browse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_views.add_child(_browse)

	# Browse, middle: the binder page.
	var page := PanelContainer.new()
	page.theme_type_variation = UISkin.V_PAGE
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browse.add_child(page)
	var page_box := VBoxContainer.new()
	page_box.add_theme_constant_override("separation", 10)
	page.add_child(page_box)
	page_box.add_child(_build_filters())
	_page_area = Control.new()
	_page_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_area.clip_contents = true
	_page_area.resized.connect(_on_page_resized)
	page_box.add_child(_page_area)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_grid.add_theme_constant_override("v_separation", GRID_GAP)
	_page_area.add_child(_grid)
	page_box.add_child(_build_pager())

	# Right: the open card.
	var detail := PanelContainer.new()
	detail.theme_type_variation = UISkin.V_PAGE
	detail.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	_browse.add_child(detail)
	var detail_col := VBoxContainer.new()
	detail.add_child(detail_col)
	var detail_bar := HBoxContainer.new()
	detail_col.add_child(detail_bar)
	_back = Button.new()
	_back.text = "Back"
	_back.icon = _flipped(UISkin.tex("arrow_right"))
	_back.disabled = true
	_back.tooltip_text = "Back to the previous card (Alt+Left)"
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back.pressed.connect(_go_back)
	detail_bar.add_child(_back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_bar.add_child(spacer)
	var open := Button.new()
	open.text = "Open"
	open.tooltip_text = "Open this card in its own tab (double-click a card)"
	open.pressed.connect(func() -> void: open_tab(_current))
	detail_bar.add_child(open)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_col.add_child(_detail_scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 10)
	_detail_scroll.add_child(_detail_box)
	_placeholder()

	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DELAY
	_search_timer.timeout.connect(_refresh_list)
	add_child(_search_timer)


func _build_tab_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_browse_button = Button.new()
	_browse_button.text = "Browse"
	_browse_button.icon = UISkin.tex("icon_chest")
	_browse_button.add_theme_constant_override("icon_max_width", 18)
	_browse_button.toggle_mode = true
	_browse_button.button_pressed = true
	_browse_button.tooltip_text = "The card binder (Ctrl+Tab switches tabs)"
	_browse_button.pressed.connect(show_browse)
	row.add_child(_browse_button)
	_tab_bar = TabBar.new()
	_tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tab_bar.deselect_enabled = true
	_tab_bar.drag_to_rearrange_enabled = true
	_tab_bar.clip_tabs = true
	_tab_bar.max_tab_width = 240
	_tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	_tab_bar.add_theme_constant_override("icon_max_width", 18)
	_tab_bar.tab_changed.connect(_on_tab_changed)
	_tab_bar.tab_close_pressed.connect(close_tab)
	_tab_bar.active_tab_rearranged.connect(func(_to: int) -> void: _save_tabs())
	_tab_bar.gui_input.connect(_on_tab_bar_input)
	row.add_child(_tab_bar)
	return row


func _build_filters() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "Search... (Ctrl+F)"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _search_timer.start())
	_search.text_submitted.connect(func(_t: String) -> void: _open_first())
	row.add_child(_search)
	_in_text = Button.new()
	_in_text.text = "Text too"
	_in_text.toggle_mode = true
	_in_text.tooltip_text = "Also search descriptions and actions"
	_in_text.toggled.connect(func(_on: bool) -> void: _refresh_list())
	row.add_child(_in_text)
	_sort = _filter_button("Sort")
	for s in SORTS:
		_sort.add_item("Sort: " + s)
	_sort.size_flags_horizontal = Control.SIZE_SHRINK_END
	_sort.custom_minimum_size = Vector2(170, 0)
	row.add_child(_sort)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	box.add_child(filters)
	_package = _filter_button("Package")
	_level = _filter_button("CR / level")
	_type = _filter_button("Type")
	for b in [_package, _level, _type]:
		filters.add_child(b)
	return box


func _filter_button(tooltip: String) -> OptionButton:
	var b := OptionButton.new()
	b.tooltip_text = tooltip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.fit_to_longest_item = false
	b.clip_text = true
	b.item_selected.connect(func(_i: int) -> void: _refresh_list())
	return b


func _build_pager() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_prev = _arrow(true)
	_prev.pressed.connect(func() -> void: _flip(-1))
	row.add_child(_prev)
	_page_label = Label.new()
	_page_label.custom_minimum_size = Vector2(220, 0)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_page_label)
	_next = _arrow(false)
	_next.pressed.connect(func() -> void: _flip(1))
	row.add_child(_next)
	return row


func _arrow(back: bool) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = _flipped(UISkin.tex("arrow_right")) if back else UISkin.tex("arrow_right")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(32, 32)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "Previous page (Page Up)" if back else "Next page (Page Down)"
	return b


## A horizontally mirrored copy of a sprite (for the back arrows).
func _flipped(t: Texture2D) -> Texture2D:
	var img := t.get_image()
	img.flip_x()
	return ImageTexture.create_from_image(img)


# --- Loading and kinds -----------------------------------------------------------------

func _on_loaded() -> void:
	_progress.hide()
	if _saved_tabs == null and tabs_file != "" and FileAccess.file_exists(tabs_file):
		_saved_tabs = JSON.parse_string(FileAccess.get_file_as_string(tabs_file))
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_status.text = "%d cards from %d packages" % [db.count(), db.packages.size()]
	if not db.errors.is_empty():
		_status.text += "\n%d problems (see Output)" % db.errors.size()
		for e in db.errors:
			push_warning(e)
	for k in db.kinds():
		var tab := Button.new()
		tab.theme_type_variation = UISkin.V_TAB
		tab.toggle_mode = true
		tab.button_group = _tab_group
		tab.text = "%s  %d" % [k.capitalize(), db.entries[k].size()]
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.pressed.connect(_select_kind.bind(k))
		_tabs.add_child(tab)
	if _tabs.get_child_count() > 0:
		var keep := db.kinds().find(_kind)  # after a reload, stay on the same kind
		var i := keep if keep >= 0 else 0
		(_tabs.get_child(i) as Button).button_pressed = true
		_select_kind(db.kinds()[i])
	else:
		_matches = []
		_render_page()
	var saved: Variant = _saved_tabs
	_saved_tabs = {}
	_restore_tabs(saved)


## The Packages window; after changes the book reloads.
func _open_packages() -> void:
	var panel := PackagesPanel.new()
	panel.manager = PackageManager.new(db.root)
	panel.changed.connect(_reload)
	add_child(panel)


func _reload() -> void:
	_progress.show()
	_status.text = "Re-reading packages..."
	_current = {}
	_history.clear()
	_saved_tabs = _tabs_state()
	_restoring = true
	_close_all_tabs()
	_restoring = false
	db.load_async(db.root)


func _select_kind(kind: String) -> void:
	show_browse()
	_kind = kind
	var list: Array = db.entries.get(kind, [])
	var pkgs := {}
	for e: Dictionary in list:
		pkgs[e["_package"]] = pkgs.get(e["_package"], 0) + 1
	_package_values = pkgs.keys()
	_package_values.sort_custom(func(a: String, b: String) -> bool: return db.package_name(a).to_lower() < db.package_name(b).to_lower())
	_package.clear()
	_package.add_item("All packages")
	for p: String in _package_values:
		_package.add_item("%s (%d)" % [db.package_name(p), pkgs[p]])

	_level_values = _distinct(list, _level_of)
	_level_values.sort()
	_level.clear()
	_level.add_item("Any CR" if kind == "monsters" else "Any level")
	for v: Variant in _level_values:
		_level.add_item(("CR " + StatBlock.cr_text(v)) if kind == "monsters" else StatBlock.level_text(v))
	_level.visible = not _level_values.is_empty()

	_type_values = _distinct(list, _types_of)
	_type_values.sort_custom(func(a: String, b: String) -> bool: return a.to_lower() < b.to_lower())
	_type.clear()
	_type.add_item("Any school" if kind == "spells" else "Any type")
	for v: String in _type_values:
		_type.add_item(v)
	_type.visible = not _type_values.is_empty()
	_page = 0
	_refresh_list()


func _distinct(list: Array, getter: Callable) -> Array:
	var seen := {}
	for e: Dictionary in list:
		for v: Variant in getter.call(e):
			seen[v] = true
	return seen.keys()


func _level_of(e: Dictionary) -> Array:
	var v: Variant = e.get("cr") if e["_kind"] == "monsters" else e.get("level") if e["_kind"] == "spells" else null
	return [] if v == null else [float(v)]


func _types_of(e: Dictionary) -> Array:
	var v: Variant = e.get("school") if e["_kind"] == "spells" else e.get("type")
	if v is Array:
		return v.map(func(x: Variant) -> String: return str(x).strip_edges()).filter(func(s: String) -> bool: return s != "")
	var s := str(v).strip_edges() if v != null else ""
	return [s] if s != "" else []


# --- Matching and pages ----------------------------------------------------------------

func _refresh_list() -> void:
	if not db.is_loaded:
		return
	var query := _search.text.strip_edges().to_lower()
	var in_text := _in_text.button_pressed
	var pkg: String = _package_values[_package.selected - 1] if _package.selected > 0 else ""
	var level: Variant = _level_values[_level.selected - 1] if _level.visible and _level.selected > 0 else null
	var type: String = _type_values[_type.selected - 1] if _type.visible and _type.selected > 0 else ""
	_matches = []
	for e: Dictionary in db.entries.get(_kind, []):
		if pkg != "" and e["_package"] != pkg:
			continue
		if level != null and _level_of(e) != [level]:
			continue
		if type != "" and type not in _types_of(e):
			continue
		if query != "" and not e["_key"].contains(query):
			if not in_text or not _text_of(e).contains(query):
				continue
		_matches.append(e)
	_sort_matches()
	_page = 0
	_render_page()


func _text_of(e: Dictionary) -> String:
	if not e.has("_text"):
		var parts := PackedStringArray([str(e.get("description", ""))])
		parts.append(str(e.get("text", "")))
		for k in PackageDB.FEATURE_LISTS:
			for f: Dictionary in db.features_of(e, k):
				parts.append(str(f.get("name", "")) + " " + str(f.get("text", "")))
		e["_text"] = "\n".join(parts).to_lower()
	return e["_text"]


func _sort_matches() -> void:
	var col := _sort.selected
	var key := func(e: Dictionary) -> Variant:
		match col:
			1:
				var lv := _level_of(e)
				return -1.0 if lv.is_empty() else lv[0]
			2:
				return ", ".join(PackedStringArray(_types_of(e))).to_lower()
			3:
				return str(e["_package_name"]).to_lower()
		return e["_key"]
	_matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka: Variant = key.call(a)
		var kb: Variant = key.call(b)
		return a["_key"] < b["_key"] if ka == kb else ka < kb)


## How many cards fit: recompute the grid when the page area changes size.
func _on_page_resized() -> void:
	var area := _page_area.size
	var cols := maxi(1, int((area.x + GRID_GAP) / (EntryCard.SIZE.x + GRID_GAP)))
	var rows := maxi(1, int((area.y + GRID_GAP) / (EntryCard.SIZE.y + GRID_GAP)))
	if cols * rows == _per_page and cols == _columns:
		_center_grid()
		return
	var first := _page * _per_page
	_columns = cols
	_per_page = cols * rows
	_page = first / _per_page
	_render_page()


func _center_grid() -> void:
	var w := _columns * EntryCard.SIZE.x + (_columns - 1) * GRID_GAP
	_grid.position = Vector2(maxf(0.0, (_page_area.size.x - w) * 0.5), 0)


func _pages() -> int:
	return maxi(1, ceili(float(_matches.size()) / _per_page))


func _flip(by: int) -> void:
	var to := clampi(_page + by, 0, _pages() - 1)
	if to != _page:
		_page = to
		_render_page()


func _render_page() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_grid.columns = _columns
	var from := _page * _per_page
	for i in range(from, mini(from + _per_page, _matches.size())):
		var card := EntryCard.new()
		card.setup(_matches[i])
		card.selected = _matches[i] == _current
		card.pressed.connect(_show)
		card.open_requested.connect(open_tab)
		_grid.add_child(card)
	_center_grid()
	_prev.disabled = _page == 0
	_next.disabled = _page >= _pages() - 1
	_prev.modulate.a = 0.3 if _prev.disabled else 1.0
	_next.modulate.a = 0.3 if _next.disabled else 1.0
	var total: int = db.entries.get(_kind, []).size()
	if _matches.is_empty():
		_page_label.text = "No cards match" if total > 0 else ""
	else:
		_page_label.text = "Page %d / %d  ·  %d cards" % [_page + 1, _pages(), _matches.size()]


func _open_first() -> void:
	if not _matches.is_empty():
		_show(_matches[_page * _per_page] if _page * _per_page < _matches.size() else _matches[0])


# --- The open card ---------------------------------------------------------------------

func _placeholder() -> void:
	var hint := Label.new()
	hint.text = "Pick a card to open it."
	hint.theme_type_variation = UISkin.V_MUTED
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_box.add_child(hint)


func _show(e: Dictionary, remember := true) -> void:
	if e.is_empty() or e == _current:
		return
	if remember and not _current.is_empty():
		_history.append(_current)
	_current = e
	_back.disabled = _history.is_empty()
	for card: EntryCard in _grid.get_children():
		card.selected = card.entry == e
	_build_detail(e)
	_detail_scroll.scroll_vertical = 0


func _build_detail(e: Dictionary) -> void:
	for c in _detail_box.get_children():
		_detail_box.remove_child(c)
		c.queue_free()

	# Title plate with the name and subtitle.
	var plate := PanelContainer.new()
	plate.theme_type_variation = UISkin.V_PLATE
	_detail_box.add_child(plate)
	var plate_box := VBoxContainer.new()
	plate_box.add_theme_constant_override("separation", 0)
	plate.add_child(plate_box)
	var name := Label.new()
	name.theme_type_variation = UISkin.V_PLATE_LABEL
	name.text = str(e.get("name", "?"))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plate_box.add_child(name)
	var sub := Label.new()
	sub.text = CardData.subtitle(e)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", UISkin.TAN)
	sub.add_theme_font_size_override("font_size", 13)
	plate_box.add_child(sub)

	# The picture in a framed card.
	var frame := PanelContainer.new()
	frame.theme_type_variation = UISkin.V_CARD
	_detail_box.add_child(frame)
	var art := CardArt.new()
	art.custom_minimum_size = Vector2(0, 250)
	art.show_entry(e)
	frame.add_child(art)
	var b := CardData.badge(e)
	if not b.is_empty():
		var hex := UISkin.hex_badge(b[0], b[1], 15)
		hex.tooltip_text = CardData.badge_label(e)
		hex.position = Vector2(-2, -2)
		hex.scale = Vector2(1.3, 1.3)
		art.add_child(hex)

	# Tags (concentration, ritual).
	var tags := CardData.tags(e)
	if not tags.is_empty():
		var tag_row := HFlowContainer.new()
		tag_row.add_theme_constant_override("h_separation", 6)
		for t in tags:
			tag_row.add_child(_chip("", "", t))
		_detail_box.add_child(tag_row)

	# Stat chips.
	var chips := CardData.chips(e)
	if not chips.is_empty():
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for c: Array in chips:
			var chip := _chip(c[0], c[1], c[2])
			chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(chip)
		_detail_box.add_child(grid)

	# Ability scores as hexes.
	if e.get("_kind") == "monsters" and e.get("stats") is Dictionary:
		var abilities := HBoxContainer.new()
		abilities.alignment = BoxContainer.ALIGNMENT_CENTER
		abilities.add_theme_constant_override("separation", 4)
		for a in StatBlock.ABILITIES:
			var score := int(e.stats.get(a, 10))
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 0)
			var label := Label.new()
			label.text = a.to_upper()
			label.theme_type_variation = UISkin.V_MUTED
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(label)
			var hex := UISkin.hex_badge(str(score), "cream", 15)
			hex.tooltip_text = "%s %d (%s)" % [a.to_upper(), score, StatBlock._signed(floori((score - 10) / 2.0))]
			col.add_child(hex)
			var mod := Label.new()
			mod.text = StatBlock._signed(floori((score - 10) / 2.0))
			mod.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mod.add_theme_font_size_override("font_size", 13)
			col.add_child(mod)
			abilities.add_child(col)
		_detail_box.add_child(abilities)

	var source := Label.new()
	source.theme_type_variation = UISkin.V_MUTED
	source.text = "From " + str(e.get("_package_name", ""))
	source.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_box.add_child(source)

	# The full text, folded away.
	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = _full_text
	toggle.text = "Full text"
	toggle.icon = UISkin.tex("arrow_down")
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail_box.add_child(toggle)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.selection_enabled = true
	text.meta_underlined = false
	text.add_theme_constant_override("paragraph_separation", 4)
	text.meta_clicked.connect(_on_meta)
	text.visible = _full_text
	if _full_text:
		text.text = StatBlock.to_bbcode(e)
	toggle.toggled.connect(func(on: bool) -> void:
		_full_text = on
		if on and text.text == "":
			text.text = StatBlock.to_bbcode(e)
		text.visible = on)
	_detail_box.add_child(text)


## A rounded paper chip: optional icon, small label, value.
func _chip(icon_name: String, label: String, value: String) -> Control:
	return chip(icon_name, label, value)


static func chip(icon_name: String, label: String, value: String) -> Control:
	var chip := PanelContainer.new()
	chip.theme_type_variation = UISkin.V_CHIP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	chip.add_child(row)
	if icon_name != "":
		row.add_child(UISkin.icon(icon_name, Color.WHITE if icon_name in ["coin_gold", "gem"] else Color(0.55, 0.3, 0.35), 20))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	if label != "":
		var l := Label.new()
		l.text = label
		l.theme_type_variation = UISkin.V_MUTED
		l.add_theme_font_size_override("font_size", 11)
		col.add_child(l)
	var v := Label.new()
	v.text = value
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_theme_font_size_override("font_size", 15)
	col.add_child(v)
	return chip


func _go_back() -> void:
	if _history.is_empty():
		return
	_show(_history.pop_back(), false)
	_back.disabled = _history.is_empty()


## A link in the quick card: opens there, or in a new tab with Ctrl.
func _on_meta(meta: Variant) -> void:
	_follow(str(meta), _current, Input.is_key_pressed(KEY_CTRL))


## Follows a link from `from`: entry:/wiki: links open the entry (quick card or new tab),
## web links the browser.
func _follow(link: String, from: Dictionary, in_tab: bool) -> void:
	var e := {}
	if link.begins_with("entry:"):
		var parts := link.substr(6).split("/")
		if parts.size() == 3:
			e = db.get_entry(parts[0], parts[1], parts[2])
	elif link.begins_with(Markdown.WIKI):
		var target := link.substr(Markdown.WIKI.length()).get_slice("#", 0)
		if target == "":
			return
		e = db.resolve(target, str(from.get("_package", "")))
		if e.is_empty():
			_status.text = "No card named \"%s\"" % target
			return
	elif link.begins_with("https://") or link.begins_with("http://"):
		OS.shell_open(link)
		return
	if e.is_empty():
		return
	if in_tab:
		open_tab(e)
	else:
		_show(e)


# --- Document tabs (TASK-22) ------------------------------------------------------------

## Opens an entry in its own full-view tab, or focuses the tab it already has.
func open_tab(e: Dictionary) -> EntryView:
	if e.is_empty():
		return null
	var key := EntryView.key_of(e)
	if _open_views.has(key):
		_tab_bar.current_tab = _tab_index(key)
		return _open_views[key]
	var view := EntryView.new()
	view.setup(e)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.hide()
	view.link_clicked.connect(func(link: String) -> void: _follow(link, view.entry, true))
	_views.add_child(view)
	_open_views[key] = view
	_tab_bar.add_tab(str(e.get("name", "?")), UISkin.tex(KIND_ICONS.get(e.get("_kind"), "dot_wine")))
	var i := _tab_bar.tab_count - 1
	_tab_bar.set_tab_metadata(i, key)
	_tab_bar.set_tab_tooltip(i, "%s\n%s · %s" % [e.get("name", "?"), CardData.subtitle(e), e.get("_package_name", "")])
	_tab_bar.current_tab = i
	_on_tab_changed(i)  # tab_changed isn't sent when the first tab is selected on its own
	return view


func close_tab(index: int) -> void:
	if index < 0 or index >= _tab_bar.tab_count:
		return
	var key: String = _tab_bar.get_tab_metadata(index)
	var view: EntryView = _open_views.get(key)
	_open_views.erase(key)
	if view:
		_views.remove_child(view)
		view.queue_free()
	_tab_bar.remove_tab(index)
	_on_tab_changed(_tab_bar.current_tab)


func show_browse() -> void:
	if _tab_bar == null:
		return
	if _tab_bar.current_tab != -1:
		_tab_bar.current_tab = -1
	_on_tab_changed(-1)


## Key of the shown tab ("" = Browse).
func current_tab_key() -> String:
	var i := _tab_bar.current_tab
	return str(_tab_bar.get_tab_metadata(i)) if i >= 0 and i < _tab_bar.tab_count else ""


## Keys of the open tabs in tab order.
func tab_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for i in _tab_bar.tab_count:
		out.append(str(_tab_bar.get_tab_metadata(i)))
	return out


func open_view(key: String) -> EntryView:
	return _open_views.get(key)


func _tab_index(key: String) -> int:
	for i in _tab_bar.tab_count:
		if _tab_bar.get_tab_metadata(i) == key:
			return i
	return -1


func _on_tab_changed(_index: int) -> void:
	var key := current_tab_key()
	_browse.visible = key == ""
	_browse_button.set_pressed_no_signal(key == "")
	for k: String in _open_views:
		_open_views[k].visible = k == key
	_save_tabs()


## Ctrl+Tab / Ctrl+Shift+Tab: Browse, then the tabs in order, round.
func _cycle_tab(by: int) -> void:
	var count := _tab_bar.tab_count + 1  # + Browse
	var to := posmod(_tab_bar.current_tab + 1 + by, count) - 1
	if to < 0:
		show_browse()
	else:
		_tab_bar.current_tab = to
		_on_tab_changed(to)


func _on_tab_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		var i := _tab_bar.get_tab_idx_at_point(event.position)
		if i >= 0:
			close_tab(i)
			_tab_bar.accept_event()


func _tabs_state() -> Dictionary:
	var list := []
	for key in tab_keys():
		list.append({"key": key, "scroll": _open_views[key].scroll_vertical})
	return {"tabs": list, "current": current_tab_key()}


func _save_tabs() -> void:
	if tabs_file == "" or _restoring or _tab_bar == null:
		return
	var f := FileAccess.open(tabs_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_tabs_state(), "  "))


## Reopens saved tabs (after a start or a reload); entries that are gone are skipped.
func _restore_tabs(state: Variant) -> void:
	if not state is Dictionary or state.is_empty():
		return
	_restoring = true
	var scrolls := {}
	for t: Variant in state.get("tabs", []):
		if not t is Dictionary:
			continue
		var parts := str(t.get("key", "")).split("/")
		if parts.size() != 3:
			continue
		var view := open_tab(db.get_entry(parts[0], parts[1], parts[2]))
		if view:
			scrolls[view] = int(t.get("scroll", 0))
	var current := str(state.get("current", ""))
	if _open_views.has(current):
		_tab_bar.current_tab = _tab_index(current)
		_on_tab_changed(_tab_bar.current_tab)
	else:
		show_browse()
	# Scroll once the views have their size (texts lay out over a frame or two).
	for i in 3:
		await get_tree().process_frame
	for view: EntryView in scrolls:
		if is_instance_valid(view):
			view.scroll_vertical = scrolls[view]
	_restoring = false
	_save_tabs()
	tabs_restored.emit()


func _close_all_tabs() -> void:
	while _tab_bar.tab_count > 0:
		close_tab(_tab_bar.tab_count - 1)


func _exit_tree() -> void:
	_save_tabs()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_tabs()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and event.ctrl_pressed) or not is_visible_in_tree():
		return
	if event.keycode == KEY_TAB:
		_cycle_tab(-1 if event.shift_pressed else 1)
	elif event.keycode == KEY_W:
		if _tab_bar.current_tab >= 0:
			close_tab(_tab_bar.current_tab)
	else:
		return
	get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed:
		return
	var handled := true
	if event.keycode == KEY_F and event.ctrl_pressed:
		_search.grab_focus()
		_search.select_all()
	elif event.keycode == KEY_LEFT and event.alt_pressed:
		_go_back()
	elif event.keycode == KEY_PAGEDOWN and _browse.visible:
		_flip(1)
	elif event.keycode == KEY_PAGEUP and _browse.visible:
		_flip(-1)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()
