class_name PackageContents
extends VBoxContainer
## The "Contents" overview in a package's full view (TASK-23): the package's entries as
## cards (same look as the binder), grouped by kind with a header and count, collapsible,
## with a search field inside the package. Big groups show PAGE cards at a time ("Show
## more"); features start collapsed, since they are mostly reached through their monsters.
## Cards open in their own tab (click; middle-click = background tab).

signal open_requested(entry: Dictionary)
signal background_requested(entry: Dictionary)

const PAGE := 24
const COLLAPSED := ["features"]

var package_id := ""
var groups := {}  ## kind -> [entries] (all of the package)
var shown := {}  ## kind -> how many cards are shown
var open := {}  ## kind -> expanded?
var show_drafts := false  ## the "Show drafts" tickbox (TASK-30)
var _db: PackageDB

var _search: LineEdit
var _body: VBoxContainer


func setup(db: PackageDB, id: String) -> void:
	package_id = id
	_db = db
	_group()
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var title := Label.new()
	title.text = "Contents"
	title.theme_type_variation = UISkin.V_HEADING
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_search = LineEdit.new()
	_search.name = "ContentsSearch"
	_search.placeholder_text = "Search in this package..."
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(280, 0)
	_search.text_changed.connect(func(_t: String) -> void:
		for k: String in shown:
			shown[k] = PAGE
		_render())
	head.add_child(_search)
	var drafts_box := CheckBox.new()
	drafts_box.name = "ShowDrafts"
	drafts_box.text = "Show drafts"
	drafts_box.tooltip_text = "Also show this package's unfinished entries"
	drafts_box.toggled.connect(set_show_drafts)
	head.add_child(drafts_box)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	add_child(_body)
	_render()


func _group() -> void:
	groups = {}
	for kind: String in _db.kinds_with(show_drafts):
		var list: Array = _db.list(kind, show_drafts).filter(func(e: Dictionary) -> bool: return e["_package"] == package_id)
		if not list.is_empty():
			groups[kind] = list
	for kind: String in groups:
		if not open.has(kind):
			open[kind] = kind not in COLLAPSED
		shown[kind] = PAGE


func set_show_drafts(on: bool) -> void:
	show_drafts = on
	_group()
	if _body:
		_render()


func set_query(text: String) -> void:
	_search.text = text
	_render()


## kind -> entries matching the search (all if empty).
func matches() -> Dictionary:
	var q := _search.text.strip_edges().to_lower() if _search != null else ""
	var out := {}
	for kind: String in groups:
		out[kind] = groups[kind] if q == "" else groups[kind].filter(func(e: Dictionary) -> bool: return e["_key"].contains(q))
	return out


func toggle(kind: String) -> void:
	open[kind] = not open.get(kind, true)
	_render()


func show_more(kind: String) -> void:
	shown[kind] = int(shown.get(kind, PAGE)) + PAGE
	_render()


func _render() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if groups.is_empty():
		var none := Label.new()
		none.theme_type_variation = UISkin.V_MUTED
		none.text = "No entries loaded from this package (switch it on to see them)."
		_body.add_child(none)
		return
	var searching := _search.text.strip_edges() != ""
	for kind: String in matches():
		var list: Array = matches()[kind]
		if searching and list.is_empty():
			continue
		var expanded: bool = open.get(kind, true) or (searching and kind in COLLAPSED and list.size() <= PAGE)
		var header := Button.new()
		header.name = "Group_" + kind
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.text = "%s %s  %d" % ["▾" if expanded else "▸", kind.capitalize(), list.size()]
		header.tooltip_text = "Show or hide the %s" % kind
		header.pressed.connect(toggle.bind(kind))
		_body.add_child(header)
		if not expanded:
			continue
		var flow := HFlowContainer.new()
		flow.name = "Cards_" + kind
		flow.add_theme_constant_override("h_separation", 12)
		flow.add_theme_constant_override("v_separation", 12)
		_body.add_child(flow)
		var count := mini(int(shown.get(kind, PAGE)), list.size())
		for i in count:
			var card := EntryCard.new()
			card.setup(list[i])
			card.pressed.connect(func(e: Dictionary) -> void: open_requested.emit(e))
			card.open_requested.connect(func(e: Dictionary) -> void: open_requested.emit(e))
			card.background_requested.connect(func(e: Dictionary) -> void: background_requested.emit(e))
			flow.add_child(card)
		if count < list.size():
			var more := Button.new()
			more.name = "More_" + kind
			more.text = "Show more (%d of %d shown)" % [count, list.size()]
			more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			more.pressed.connect(show_more.bind(kind))
			_body.add_child(more)
