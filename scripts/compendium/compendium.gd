class_name Compendium
extends Control
## Browser for the core data packages (TASK-15): kinds on the left, a searchable and
## filterable list in the middle, the entry (stat block, Markdown text, image) on the
## right. [[Wikilinks]] open the entry they name; Back returns.
## Packages load on a worker thread (PackageDB), so the window stays responsive.

const SEARCH_DELAY := 0.12
const ALL := "All"
const COLUMNS := ["Name", "CR / Level", "Type", "Package"]

var db := PackageDB.new()

var _status: Label
var _progress: ProgressBar
var _kinds: ItemList
var _search: LineEdit
var _in_text: CheckBox
var _package: OptionButton
var _level: OptionButton
var _type: OptionButton
var _tree: Tree
var _count: Label
var _back: Button
var _image: TextureRect
var _detail: RichTextLabel
var _search_timer: Timer

var _kind := ""
var _level_values: Array = []  ## option index - 1 -> value
var _type_values: Array = []
var _package_values: Array = []
var _sort_column := 0
var _sort_desc := false
var _current: Dictionary = {}
var _history: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	db.loaded.connect(_on_loaded)
	db.load_async()


# --- Layout --------------------------------------------------------------------------

func _build() -> void:
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)

	var top := HBoxContainer.new()
	column.add_child(top)
	var title := Label.new()
	title.text = "Compendium"
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	_status = Label.new()
	_status.text = "Loading packages..."
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.7)
	top.add_child(_status)
	_progress = ProgressBar.new()
	_progress.indeterminate = true
	_progress.custom_minimum_size = Vector2(160, 0)
	_progress.show_percentage = false
	top.add_child(_progress)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(split)
	_kinds = ItemList.new()
	_kinds.custom_minimum_size = Vector2(170, 0)
	_kinds.item_selected.connect(func(i: int) -> void: _select_kind(_kinds.get_item_metadata(i)))
	split.add_child(_kinds)

	var split2 := HSplitContainer.new()
	split.add_child(split2)
	split2.add_child(_build_list())
	split2.add_child(_build_detail())

	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DELAY
	_search_timer.timeout.connect(_refresh_list)
	add_child(_search_timer)


func _build_list() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(540, 0)
	var row := HBoxContainer.new()
	box.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "Search names... (Ctrl+F)"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _search_timer.start())
	_search.text_submitted.connect(func(_t: String) -> void: _select_first())
	row.add_child(_search)
	_in_text = CheckBox.new()
	_in_text.text = "Search text too"
	_in_text.toggled.connect(func(_on: bool) -> void: _refresh_list())
	row.add_child(_in_text)

	var filters := HBoxContainer.new()
	box.add_child(filters)
	_package = _filter_button("Package")
	_level = _filter_button("CR / level")
	_type = _filter_button("Type")
	for b in [_package, _level, _type]:
		filters.add_child(b)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = COLUMNS.size()
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	for i in COLUMNS.size():
		_tree.set_column_title(i, COLUMNS[i])
		_tree.set_column_expand(i, i == 0)
		_tree.set_column_clip_content(i, true)
		if i > 0:
			_tree.set_column_custom_minimum_width(i, [0, 70, 110, 140][i])
	_tree.column_title_clicked.connect(_on_column_clicked)
	_tree.item_selected.connect(func() -> void: _show(_tree.get_selected().get_metadata(0)))
	box.add_child(_tree)
	_count = Label.new()
	_count.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_count)
	return box


func _filter_button(tooltip: String) -> OptionButton:
	var b := OptionButton.new()
	b.tooltip_text = tooltip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.fit_to_longest_item = false
	b.clip_text = true
	b.item_selected.connect(func(_i: int) -> void: _refresh_list())
	return b


func _build_detail() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	var bar := HBoxContainer.new()
	box.add_child(bar)
	_back = Button.new()
	_back.text = "< Back"
	_back.disabled = true
	_back.tooltip_text = "Back to the previous entry (Alt+Left)"
	_back.pressed.connect(_go_back)
	bar.add_child(_back)
	_image = TextureRect.new()
	_image.custom_minimum_size = Vector2(0, 180)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.visible = false
	box.add_child(_image)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.selection_enabled = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("paragraph_separation", 4)
	_detail.meta_underlined = false
	_detail.meta_clicked.connect(_on_meta)
	_detail.text = "[i]Pick an entry.[/i]"
	box.add_child(_detail)
	return box


# --- Loading and kinds -----------------------------------------------------------------

func _on_loaded() -> void:
	_progress.hide()
	_status.text = "  %d entries in %d packages (%.1f s)" % [db.count(), db.packages.size(), db.load_msec / 1000.0]
	if not db.errors.is_empty():
		_status.text += "  ·  %d problems (see Output)" % db.errors.size()
		for e in db.errors:
			push_warning(e)
	_kinds.clear()
	for k in db.kinds():
		var i := _kinds.add_item("%s  (%d)" % [k.capitalize(), db.entries[k].size()])
		_kinds.set_item_metadata(i, k)
	if _kinds.item_count > 0:
		_kinds.select(0)
		_select_kind(_kinds.get_item_metadata(0))


func _select_kind(kind: String) -> void:
	_kind = kind
	var list: Array = db.entries.get(kind, [])
	# Package filter: packages that have this kind.
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

	_tree.set_column_title(1, "CR" if kind == "monsters" else ("Level" if kind == "spells" else ""))
	_tree.set_column_title(2, "School" if kind == "spells" else ("Type" if not _type_values.is_empty() else ""))
	_refresh_list()


## Values of `getter` over the entries (getter returns an Array of values), unique.
func _distinct(list: Array, getter: Callable) -> Array:
	var seen := {}
	for e: Dictionary in list:
		for v: Variant in getter.call(e):
			seen[v] = true
	return seen.keys()


## CR (monsters) or spell level, as a one-element Array (or empty).
func _level_of(e: Dictionary) -> Array:
	var v: Variant = e.get("cr") if e["_kind"] == "monsters" else e.get("level") if e["_kind"] == "spells" else null
	return [] if v == null else [float(v)]


## Monster type, spell school, item types... (whatever the kind has), as strings.
func _types_of(e: Dictionary) -> Array:
	var v: Variant = e.get("school") if e["_kind"] == "spells" else e.get("type")
	if v is Array:
		return v.map(func(x: Variant) -> String: return str(x).strip_edges()).filter(func(s: String) -> bool: return s != "")
	var s := str(v).strip_edges() if v != null else ""
	return [s] if s != "" else []


# --- List ----------------------------------------------------------------------------

func _refresh_list() -> void:
	if not db.is_loaded:
		return
	var query := _search.text.strip_edges().to_lower()
	var in_text := _in_text.button_pressed
	var pkg: String = _package_values[_package.selected - 1] if _package.selected > 0 else ""
	var level: Variant = _level_values[_level.selected - 1] if _level.visible and _level.selected > 0 else null
	var type: String = _type_values[_type.selected - 1] if _type.visible and _type.selected > 0 else ""

	var matches: Array = []
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
		matches.append(e)
	_sort(matches)

	_tree.clear()
	var root := _tree.create_item()
	var selected: TreeItem = null
	for e: Dictionary in matches:
		var item := _tree.create_item(root)
		item.set_text(0, str(e.get("name", "?")))
		item.set_metadata(0, e)
		var lv := _level_of(e)
		item.set_text(1, "" if lv.is_empty() else (StatBlock.cr_text(lv[0]) if _kind == "monsters" else StatBlock.level_text(lv[0])))
		item.set_text(2, ", ".join(PackedStringArray(_types_of(e))))
		item.set_text(3, e["_package_name"])
		item.set_tooltip_text(3, e["_package_name"])
		if e == _current:
			selected = item
	if selected != null:
		selected.select(0)
		_tree.scroll_to_item(selected)
	_count.text = "%d of %d" % [matches.size(), db.entries.get(_kind, []).size()]


## Lower-case searchable text of an entry (description and features), cached.
func _text_of(e: Dictionary) -> String:
	if not e.has("_text"):
		var parts := PackedStringArray([str(e.get("description", ""))])
		for k in ["traits", "actions", "bonus_actions", "reactions", "legendary_actions"]:
			if e.get(k) is Array:
				for f: Variant in e[k]:
					if f is Dictionary:
						parts.append(str(f.get("name", "")) + " " + str(f.get("text", "")))
		e["_text"] = "\n".join(parts).to_lower()
	return e["_text"]


func _sort(list: Array) -> void:
	var col := _sort_column
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
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka: Variant = key.call(a)
		var kb: Variant = key.call(b)
		if ka == kb:
			return a["_key"] < b["_key"]
		return (ka > kb) if _sort_desc else (ka < kb))


func _on_column_clicked(column: int, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT:
		return
	_sort_desc = not _sort_desc if column == _sort_column else false
	_sort_column = column
	for i in COLUMNS.size():
		var t := _tree.get_column_title(i).trim_suffix(" ▲").trim_suffix(" ▼")
		_tree.set_column_title(i, t + ((" ▼" if _sort_desc else " ▲") if i == column and t != "" else ""))
	_refresh_list()


func _select_first() -> void:
	var first := _tree.get_root().get_first_child() if _tree.get_root() else null
	if first:
		first.select(0)


# --- Detail ----------------------------------------------------------------------------

func _show(e: Dictionary, remember := true) -> void:
	if e.is_empty() or e == _current:
		return
	if remember and not _current.is_empty():
		_history.append(_current)
	_current = e
	_back.disabled = _history.is_empty()
	_detail.text = StatBlock.to_bbcode(e)
	_detail.scroll_to_line(0)
	var tex := _load_image(e)
	_image.texture = tex
	_image.visible = tex != null


func _load_image(e: Dictionary) -> Texture2D:
	var rel := str(e.get("image", ""))
	if rel == "":
		return null
	var path := str(e["_dir"]).path_join(rel)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null


func _go_back() -> void:
	if _history.is_empty():
		return
	_show(_history.pop_back(), false)
	_back.disabled = _history.is_empty()


func _on_meta(meta: Variant) -> void:
	var link := str(meta)
	if link.begins_with(Markdown.WIKI):
		var target := link.substr(Markdown.WIKI.length()).get_slice("#", 0)
		if target == "":
			return  # a section of this page
		var e := db.resolve(target, str(_current.get("_package", "")))
		if e.is_empty():
			_status.text = "  No entry named \"%s\"" % target
		else:
			_show(e)
	elif link.begins_with("https://") or link.begins_with("http://"):
		OS.shell_open(link)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed:
		return
	if event.keycode == KEY_F and event.ctrl_pressed:
		_search.grab_focus()
		_search.select_all()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_LEFT and event.alt_pressed:
		_go_back()
		get_viewport().set_input_as_handled()
