class_name TokenField
extends VBoxContainer
## A field edited by clicking tokens (TASK-29): the values this field already has in the loaded
## packages (most used first) plus its base list, as toggle chips. One value (`token`): click
## another to switch, click the selected one to clear. A list (`tokens`): click to toggle.
## Long lists show the top SHOWN plus a search; the "+" token / Enter adds what was typed, but
## an existing value in another spelling is picked instead of a second one. Ref fields offer
## the entries of their kind; Ctrl+click opens the entry.

signal open_requested(option: Dictionary)  ## Ctrl+click on a ref token
signal changed

const SHOWN := 12

var multi := false
var is_ref := false
var options: Array = []  ## [{label, value, count, entry?}]
var selected: Array = []  ## values, in the order picked
var flow: HFlowContainer
var search: LineEdit
var _all := false  ## "show all" pressed


## Options for a field: the field's values in `db` (most used first), then its base values;
## for refs the entries of `ref_kind` (stored as "kind/id" or by name), most used first.
static func build_options(field: Dictionary, kind: String, db: PackageDB) -> Array:
	var out := []
	var seen := {}
	var used := {}  ## lower value -> count
	if db != null:
		for v: Dictionary in db.field_values(kind, str(field.key)):
			used[str(v.value).to_lower()] = int(v.count)
	if field.has("ref_kind"):
		if db == null:
			return out
		var by_name: bool = field.get("ref_store", "ref") == "name"
		for e: Dictionary in db.entries.get(str(field.ref_kind), []):
			var value := str(e.get("name", e.id)) if by_name else "%s/%s" % [field.ref_kind, e.id]
			if seen.has(value.to_lower()):
				continue
			seen[value.to_lower()] = true
			var count := int(used.get(value.to_lower(), 0))
			if not by_name:
				count = maxi(count, int(used.get(str(e.get("name", "")).to_lower(), 0)))
			out.append({"label": str(e.get("name", e.id)), "value": value, "count": count, "entry": e})
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.count > b.count if a.count != b.count else a.label.to_lower() < b.label.to_lower())
		return out
	if db != null:
		for v: Dictionary in db.field_values(kind, str(field.key)):
			seen[str(v.value).to_lower()] = true
			out.append({"label": str(v.value), "value": str(v.value), "count": int(v.count)})
	for b: Variant in field.get("base", []):
		if not seen.has(str(b).to_lower()):
			seen[str(b).to_lower()] = true
			out.append({"label": str(b), "value": str(b), "count": 0})
	return out


func setup(field: Dictionary, field_options: Array, value: Variant) -> void:
	multi = field.type == "tokens"
	is_ref = field.has("ref_kind")
	options = field_options.duplicate()
	selected = []
	for v: Variant in (value if value is Array else [value]):
		if str(v).strip_edges() != "":
			_select(str(v).strip_edges())
	add_theme_constant_override("separation", 4)
	flow = HFlowContainer.new()
	flow.name = "Tokens"
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	add_child(flow)
	search = LineEdit.new()
	search.name = "Search"
	search.placeholder_text = "Search or add a value (Enter adds)" if not is_ref else "Search (Enter picks)"
	search.clear_button_enabled = true
	search.visible = options.size() > SHOWN
	search.text_changed.connect(func(_t: String) -> void: _render())
	search.text_submitted.connect(func(t: String) -> void: add_value(t))
	add_child(search)
	_render()


## The value to save: one string, or a list.
func value() -> Variant:
	if multi:
		return selected.duplicate()
	return selected[0] if not selected.is_empty() else ""


func option_for(text: String) -> Dictionary:
	var low := text.strip_edges().to_lower()
	for o: Dictionary in options:
		if str(o.value).to_lower() == low or str(o.label).to_lower() == low:
			return o
	return {}


## Clicking a token: switch (one value) or toggle (list).
func toggle(value_text: String) -> void:
	if value_text in selected:
		selected.erase(value_text)
	elif multi:
		selected.append(value_text)
	else:
		selected = [value_text]
	_render()
	changed.emit()


## Adds typed text: an existing value in any spelling is picked, else a new token is made.
func add_value(text: String) -> void:
	var t := text.strip_edges()
	if t == "":
		return
	var o := option_for(t)
	if o.is_empty():
		var hits := matches(t)
		if is_ref and hits.size() == 1:
			o = hits[0]  # refs: the only match is meant
		else:
			o = {"label": t, "value": t, "count": 0}
			options.push_front(o)
	if str(o.value) not in selected:
		toggle(str(o.value))
	search.text = ""
	_render()


## Options matching a search text (by label), in list order.
func matches(text: String) -> Array:
	var q := text.strip_edges().to_lower()
	return options.filter(func(o: Dictionary) -> bool: return q == "" or str(o.label).to_lower().contains(q))


## What is shown: the selected ones, then the top SHOWN of the rest (search filters).
func visible_options() -> Array:
	var q := search.text if search != null else ""
	var out := []
	for v: String in selected:
		var o := option_for(v)
		out.append(o if not o.is_empty() else {"label": v, "value": v, "count": 0})
	var rest := matches(q).filter(func(o: Dictionary) -> bool: return str(o.value) not in selected)
	return out + (rest if _all else rest.slice(0, SHOWN))


func _render() -> void:
	for c in flow.get_children():
		flow.remove_child(c)
		c.queue_free()
	var shown := visible_options()
	for o: Dictionary in shown:
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = str(o.value) in selected
		b.text = str(o.label)
		b.name = "Token_" + str(o.label).validate_node_name()
		b.tooltip_text = ("used %d×" % o.count if int(o.count) > 0 else "") + \
			("\nCtrl+click opens it" if o.has("entry") else "")
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			if o.has("entry") and Input.is_key_pressed(KEY_CTRL):
				b.set_pressed_no_signal(not b.button_pressed)
				open_requested.emit(o)
				return
			toggle(str(o.value)))
		flow.add_child(b)
	var hidden := matches(search.text).filter(func(o: Dictionary) -> bool: return str(o.value) not in selected).size() \
		- (shown.size() - selected.size())
	if hidden > 0:
		var more := Button.new()
		more.name = "More"
		more.flat = true
		more.text = "%d more…" % hidden
		more.tooltip_text = "Show all values (or search)"
		more.pressed.connect(func() -> void:
			_all = true
			_render())
		flow.add_child(more)
	var plus := Button.new()
	plus.name = "Add"
	plus.text = "+"
	plus.tooltip_text = "Add a new value"
	plus.pressed.connect(func() -> void:
		search.visible = true
		if search.text.strip_edges() != "":
			add_value(search.text)
		else:
			search.grab_focus.call_deferred())
	flow.add_child(plus)


func _select(v: String) -> void:
	var o := option_for(v)
	if o.is_empty():
		o = {"label": v.get_file().replace("-", " ").capitalize() if is_ref and "/" in v else v, "value": v, "count": 0}
		options.push_front(o)
	if str(o.value) not in selected:
		selected.append(str(o.value))
