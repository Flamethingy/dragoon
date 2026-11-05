class_name QuickSearch
extends Control
## Quick search (TASK-104, Nico 2026-11-04): Ctrl+K (or the 🔍 button) opens a search field in
## the middle of the table, like a command palette. Search as you type over every kind: items,
## spells, creatures, features, classes, rules, conditions ... and the world's characters and
## places. Fuzzy, grouped by kind, arrow keys + Enter. Prefixes filter ("i: rope", "s: fire").
## Enter opens the entry (EntryWindow), Shift+Enter gives it to the active character (the
## rights of TASK-94), a result can be dragged onto the map, a token or a sheet like a card of
## the Book. Esc or a click outside closes it; the last searches are remembered.
## What can be found: the core packages (read here); the DM also the world and the timeline;
## a player gets those names from the host, only what they may see (no drafts, names in a
## hidden passage stay hidden: NetTable.quick_index_for).

signal opened_entry(ref: String)

const PREFIXES := {"i": "items", "s": "spells", "c": "creatures", "f": "features", "cl": "classes",
	"r": "rules", "co": "conditions", "ch": "characters", "p": "places", "ft": "feats", "rc": "races", "t": "tables"}
const KIND_ICONS := {"items": "icon_chest", "spells": "star", "creatures": "icon_helmet", "characters": "icon_helmet",
	"features": "icon_sword", "classes": "icon_shield", "subclasses": "icon_shield", "rules": "ring",
	"conditions": "hex_red", "places": "icon_boot", "tables": "gem", "feats": "star", "races": "icon_armor"}
const LIMIT := 40
const PER_KIND := 8
const RECENT := 8

static var recent_file := "user://quick_search.cfg"

var table: NetTable
var hud: CharacterHud
var index: Array = []  ## [{name, kind, ref, source, entry, low}]
var _db: PackageDB
var _remote: Array = []  ## a player's world / timeline names from the host
var _field: LineEdit
var _list: VBoxContainer
var _scroll: ScrollContainer
var _hint: Label
var _rows: Array[Button] = []
var _results: Array = []
var _sel := 0
var _panel: PanelContainer


# --- Matching ------------------------------------------------------------------------------------

## "s: fire bolt" -> {kind: "spells", text: "fire bolt"}; unknown prefixes stay text.
static func parse(query: String) -> Dictionary:
	var q := query.strip_edges()
	var colon := q.find(":")
	if colon > 0 and colon <= 3:
		var p := q.left(colon).to_lower()
		if PREFIXES.has(p):
			return {"kind": PREFIXES[p], "text": q.substr(colon + 1).strip_edges().to_lower()}
	return {"kind": "", "text": q.to_lower()}


## How well `name` (lower case) fits `text`: whole name 1000, start 800, a word's start 600,
## inside 400, the letters in order (fuzzy) up to 200; -1 if not at all. Shorter names win ties.
static func score(name: String, text: String) -> int:
	if text == "":
		return 0
	if name == text:
		return 1000
	if name.begins_with(text):
		return 800 - mini(name.length(), 100)
	var at := name.find(text)
	if at > 0:
		var before := name[at - 1]
		return (600 if before in [" ", "-", "(", "'", "/"] else 400) - mini(name.length(), 100)
	# fuzzy: every letter in order, fewer gaps = better
	var i := 0
	var gaps := 0
	var last := -1
	for c in text:
		if c == " ":
			continue
		var found := name.find(c, i)
		if found < 0:
			return -1
		if last >= 0 and found > last + 1:
			gaps += found - last - 1
		last = found
		i = found + 1
	return maxi(1, 200 - gaps * 8 - mini(name.length(), 60))


## The best matches of `query` among `items` ({name, kind, ...}), at most PER_KIND of a kind,
## grouped: the kind of the best match first.
static func search(items: Array, query: String, limit := LIMIT) -> Array:
	var q := parse(query)
	var text := str(q.text)
	if text == "" and str(q.kind) == "":
		return []
	var scored := []
	for it: Dictionary in items:
		if str(q.kind) != "" and str(it.kind) != str(q.kind):
			continue
		var low := str(it.get("low", str(it.name).to_lower()))
		var sc := score(low, text) if text != "" else 1
		if sc >= 0:
			scored.append([sc, it])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] or (a[0] == b[0] and str(a[1].name) < str(b[1].name)))
	var per := {}
	var order := []
	var by_kind := {}
	for pair: Array in scored:
		var it: Dictionary = pair[1]
		var k := str(it.kind)
		if int(per.get(k, 0)) >= (limit if str(q.kind) != "" else PER_KIND):
			continue
		per[k] = int(per.get(k, 0)) + 1
		if not by_kind.has(k):
			by_kind[k] = []
			order.append(k)
		(by_kind[k] as Array).append(it)
	var out := []
	for k: String in order:
		for it: Dictionary in by_kind[k]:
			if out.size() < limit:
				out.append(it)
	return out


static func item_of(e: Dictionary, source := "") -> Dictionary:
	var kind := str(e.get("_kind", ""))
	var name := str(e.get("name", e.get("id", "?")))
	return {"name": name, "low": name.to_lower(), "kind": kind, "ref": "%s/%s" % [kind, e.get("id", "")],
		"source": source if source != "" else str(e.get("_package_name", "")), "entry": e}


# --- Index ---------------------------------------------------------------------------------------

## Reads what can be found (the packages in the background); the DM's includes the world and
## the timeline, a player asks the host for those.
func build_index() -> void:
	if _db == null:
		_db = PackageDB.new()
		_db.root = PackageDB.default_root()
		_db.world_filter = ""  # the worlds come from the table (the DM) or the host (players)
		_db.loaded.connect(_reindex)
		_db.load_async()
	if table != null and not table.is_dm() and table.is_online():
		table.request_quick_index()
	_reindex()


func _reindex() -> void:
	index.clear()
	if _db != null and _db.is_loaded:
		for kind: String in _db.entries:
			for e: Dictionary in _db.entries[kind]:
				index.append(item_of(e))
	if table != null and table.is_dm() and table.timeline != null:
		for kind: String in PackageDB.KINDS + ["characters", "places", "npcs", "factions", "locations"]:
			for id: String in table.timeline.entries(kind):
				var e: Dictionary = table.timeline.entries(kind)[id]
				if EntryStore.is_draft(e):
					continue
				var full := e.duplicate()
				full["_kind"] = kind
				full["id"] = id
				index.append(item_of(full, "World"))
	else:
		index.append_array(_remote)
	if visible:
		_refresh()


## A player: the host's names of the world and the timeline (NetTable.quick_index_for).
func set_remote(list: Array) -> void:
	_remote.clear()
	for it: Variant in list:
		if it is Dictionary:
			var d: Dictionary = (it as Dictionary).duplicate()
			d["low"] = str(d.get("name", "")).to_lower()
			d["source"] = "World"
			d["entry"] = {"_kind": d.get("kind", ""), "id": str(d.get("ref", "")).get_slice("/", 1), "name": d.get("name", "")}
			_remote.append(d)
	_reindex()


# --- UI ------------------------------------------------------------------------------------------

func _init() -> void:
	name = "QuickSearch"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.25)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.theme_type_variation = UISkin.V_PAGE
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.14
	_panel.offset_left = -310
	_panel.offset_right = 310
	_panel.custom_minimum_size = Vector2(620, 0)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	_field = LineEdit.new()
	_field.name = "Input"
	_field.placeholder_text = "Search items, spells, creatures, rules ...   (i: s: c: f: r: to filter)"
	_field.clear_button_enabled = true
	_field.add_theme_font_size_override("font_size", 18)
	_field.text_changed.connect(func(_t: String) -> void: _refresh())
	_field.gui_input.connect(_on_key)
	col.add_child(_field)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.theme_type_variation = UISkin.V_MUTED
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.text = "Enter: open · Shift+Enter: give to the active character · drag onto the map or a sheet · Esc: close"
	col.add_child(_hint)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 380)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "Results"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 1)
	_scroll.add_child(_list)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not _panel.get_global_rect().has_point(get_global_mouse_position()):
		close()  # a click outside
		accept_event()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if code == KEY_K and k.ctrl_pressed and not k.alt_pressed and (table == null or table.is_online()):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif visible and code == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func open(query := "") -> void:
	build_index()
	visible = true
	move_to_front()
	_field.text = query
	_refresh()
	_field.grab_focus()
	_field.caret_column = query.length()


func close() -> void:
	if visible and _field.text.strip_edges() != "":
		remember(_field.text.strip_edges())
	visible = false
	_field.release_focus()


func _on_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var k := event as InputEventKey
	match k.keycode:
		KEY_DOWN:
			_select(_sel + 1)
		KEY_UP:
			_select(_sel - 1)
		KEY_ENTER, KEY_KP_ENTER:
			if k.shift_pressed:
				give(_sel)
			else:
				activate(_sel)
		_:
			return
	_field.accept_event()


## The results for the field's text (the last searches while it is empty).
func _refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	var q := _field.text
	if q.strip_edges() == "":
		_results = []
		for r: String in recent():
			var b := _plain_row("↺  " + r, "Recent")
			b.pressed.connect(func() -> void:
				_field.text = r
				_refresh())
			_list.add_child(b)
		if index.is_empty():
			_list.add_child(_note("Reading the packages ..."))
		return
	_results = search(index, q)
	if _results.is_empty():
		_list.add_child(_note("Nothing found." if _db != null and _db.is_loaded else "Reading the packages ..."))
	var group := ""
	for i in _results.size():
		var it: Dictionary = _results[i]
		if str(it.kind) != group:
			group = str(it.kind)
			var h := Label.new()
			h.text = Compendium.kind_label(group)
			h.theme_type_variation = UISkin.V_MUTED
			h.add_theme_font_size_override("font_size", 11)
			_list.add_child(h)
		var row := _row(it, i)
		_list.add_child(row)
		_rows.append(row)
	_select(0)


func _row(it: Dictionary, i: int) -> Button:
	var b := Button.new()
	b.name = "Result_%d" % i
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 30)
	b.text = "  " + str(it.name)
	b.icon = UISkin.tex(str(KIND_ICONS.get(str(it.kind), "dot_wine")))
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 20)
	b.tooltip_text = "%s · %s" % [Compendium.kind_label(str(it.kind)), str(it.source)]
	var src := Label.new()
	src.text = str(it.source)
	src.theme_type_variation = UISkin.V_MUTED
	src.add_theme_font_size_override("font_size", 11)
	src.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	src.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	src.offset_right = -8
	src.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(src)
	b.mouse_entered.connect(func() -> void: _select(i, false))
	b.pressed.connect(func() -> void: activate(i))
	b.set_drag_forwarding(func(_at: Vector2) -> Variant: return _drag(i), Callable(), Callable())
	return b


func _plain_row(text: String, tip: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = text
	b.tooltip_text = tip
	return b


func _note(text: String) -> Label:
	var l := Label.new()
	l.name = "Note"
	l.text = text
	l.theme_type_variation = UISkin.V_MUTED
	return l


func _select(i: int, scroll := true) -> void:
	if _rows.is_empty():
		_sel = 0
		return
	_sel = clampi(i, 0, _rows.size() - 1)
	for n in _rows.size():
		var hi := n == _sel
		_rows[n].add_theme_color_override("font_color", UISkin.WINE if hi else UISkin.INK)
		var sb := StyleBoxFlat.new()  # the same margins for every row, only the chosen one tinted
		sb.bg_color = UISkin.TAN.lerp(UISkin.CREAM, 0.1) if hi else Color(0, 0, 0, 0)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		for st: String in ["normal", "hover", "pressed"]:
			_rows[n].add_theme_stylebox_override(st, sb)
	if scroll and is_inside_tree():
		_scroll.ensure_control_visible(_rows[_sel])


func selected() -> Dictionary:
	return _results[_sel] if _sel < _results.size() else {}


## Enter: the entry opens (its view in a window).
func activate(i: int) -> void:
	if i >= _results.size():
		return
	var it: Dictionary = _results[i]
	remember(_field.text.strip_edges())
	close()
	opened_entry.emit(str(it.ref))
	var e: Dictionary = it.get("entry", {})
	if e.has("description") or e.has("text") or e.has("effects"):  # the whole entry is here
		EntryWindow.show_for(get_parent(), str(it.ref), e)
	elif hud != null:
		hud.show_entry(str(it.ref))  # a player: the host sends what they may see


## Shift+Enter: the active character gets it (an item, spell or feature; TASK-94's rights).
func give(i: int) -> bool:
	if i >= _results.size() or table == null or hud == null or hud.active == "":
		return false
	var e: Dictionary = _results[i].get("entry", {})
	if not table.can_take_entry(hud.active, e):
		return false
	table.add_entry_to(hud.active, e)
	remember(_field.text.strip_edges())
	close()
	return true


## Dragging a result: like a card of the Book (EntryDrag); the search closes so the map and
## the sheets under it take the drop.
func _drag(i: int) -> Variant:
	if i >= _results.size():
		return null
	var e: Dictionary = _results[i].get("entry", {})
	if e.is_empty():
		return null
	set_drag_preview(EntryDrag.preview(e))
	EntryDrag.start(e, get_viewport())
	close.call_deferred()
	return EntryDrag.data(e)


# --- Recent searches -----------------------------------------------------------------------------

static func recent() -> PackedStringArray:
	var cfg := ConfigFile.new()
	cfg.load(recent_file)
	return PackedStringArray(cfg.get_value("search", "recent", []))


static func remember(q: String) -> void:
	if q == "":
		return
	var list := Array(recent())
	list.erase(q)
	list.push_front(q)
	var cfg := ConfigFile.new()
	cfg.load(recent_file)
	cfg.set_value("search", "recent", list.slice(0, RECENT))
	cfg.save(recent_file)
