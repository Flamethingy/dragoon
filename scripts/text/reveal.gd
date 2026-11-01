class_name Reveal
extends RefCounted
## Who may see which passage of a Markdown text (TASK-18, reveal-visibility.md).
##
##     A silver amulet ...
##     <reveal id="r7" for="lena">**Function:** ...</reveal>
##     <reveal id="r8" for="dm">**Curse:** ...</reveal>
##
## - Untagged text is visible to everyone; the DM always sees everything.
## - `for`: comma-separated player ids, `party` (all players) or `dm` (DM only).
## - Tags nest; a passage is visible only if every enclosing tag allows it.
## - `%% ... %%` (Obsidian comment) is DM-only.
## - Unclosed tags hide everything after them (fail safe); stray `</reveal>` are dropped.
## - During play, `reveal.changed` events add or remove viewers (`grants`, see grants_from).
##
## filter() returns the text for one viewer: hidden passages are removed, visible tags stay
## (with the *current* `for`) so the client can draw the colored frames (TASK-19).

const DM := "dm"
const PARTY := "party"

static var _open_re := RegEx.create_from_string("<reveal\\b([^>]*)>")
static var _attr_re := RegEx.create_from_string("(\\w+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')")


## The text as a tree: an Array of Strings and passages {id, for: PackedStringArray,
## children: Array}. `%% %%` comments become passages with id "" for ["dm"].
static func parse(md: String) -> Array:
	var root := []
	var stack: Array = [root]
	var i := 0
	var n := md.length()
	var buf := ""
	while i < n:
		var c := md[i]
		if c == "%" and md.substr(i, 2) == "%%":
			var end := md.find("%%", i + 2)
			_flush(stack, buf)
			buf = ""
			var inner := md.substr(i + 2, (end if end >= 0 else n) - i - 2)
			stack.back().append({"id": "", "for": PackedStringArray([DM]), "children": [inner]})
			i = (end + 2) if end >= 0 else n
			continue
		if c == "<":
			if md.substr(i, 9) == "</reveal>":
				_flush(stack, buf)
				buf = ""
				if stack.size() > 1:
					stack.pop_back()
				i += 9
				continue
			var m := _open_re.search(md, i)
			if m and m.get_start() == i:
				_flush(stack, buf)
				buf = ""
				var attrs := _attrs(m.get_string(1))
				var node := {"id": str(attrs.get("id", "")), "for": viewers(str(attrs.get("for", DM))), "children": []}
				stack.back().append(node)
				stack.append(node.children)
				i = m.get_end()
				continue
		buf += c
		i += 1
	_flush(stack, buf)
	# Unclosed tags: their passages stay as parsed (they end with the text); nothing leaks
	# because a passage is only shown to its viewers.
	return root


static func _flush(stack: Array, buf: String) -> void:
	if buf != "":
		stack.back().append(buf)


static func _attrs(text: String) -> Dictionary:
	var out := {}
	for m in _attr_re.search_all(text):
		out[m.get_string(1).to_lower()] = m.get_string(2) if m.get_string(2) != "" or m.get_string(3) == "" else m.get_string(3)
	return out


## "lena, party" -> ["lena", "party"] (lower case, no blanks); empty -> ["dm"].
static func viewers(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in text.split(","):
		var v := part.strip_edges().to_lower()
		if v != "" and v not in out:
			out.append(v)
	if out.is_empty():
		out.append(DM)
	return out


## Applies the changes from events to a passage's starting viewers.
## `ops`: [{add: [...], remove: [...]}] in event order.
static func current_viewers(start: PackedStringArray, ops: Array) -> PackedStringArray:
	var out := start.duplicate()
	for op: Dictionary in ops:
		for v: Variant in op.get("add", []):
			if str(v) not in out:
				out.append(str(v))
		for v: Variant in op.get("remove", []):
			var k := out.find(str(v))
			if k >= 0:
				out.remove_at(k)
	return out


## May `viewer` ("dm" or a player id) see a passage for these viewers?
static func can_see(viewer: String, for_list: PackedStringArray) -> bool:
	if viewer == DM:
		return true
	return viewer in for_list or (PARTY in for_list and viewer != "")


## The text as `viewer` may see it. `grants`: reveal id -> ops (see grants_from) for this
## text. Visible passages keep their tag with the current `for`; `%%` comments are kept
## for the DM only (as they were).
static func filter(md: String, viewer: String, grants := {}) -> String:
	if not ("reveal" in md or "%%" in md):
		return md
	return _render(parse(md), viewer, grants)


static func _render(nodes: Array, viewer: String, grants: Dictionary) -> String:
	var out := ""
	for node: Variant in nodes:
		if node is String:
			out += node
			continue
		var id: String = node.id
		var start: PackedStringArray = node.for
		var who: PackedStringArray = current_viewers(start, grants.get(id, [])) if id != "" else start
		if not can_see(viewer, who):
			continue
		var inner := _render(node.children, viewer, grants)
		if id == "":  # a %% comment: only the DM gets here
			out += "%%" + inner + "%%"
		else:
			out += "<reveal id=\"%s\" for=\"%s\">%s</reveal>" % [id, ",".join(who), inner]
	return out


## Every reveal id in the text with its starting viewers (for the editor / frames).
static func passages(md: String) -> Dictionary:
	var out := {}
	_collect(parse(md), out)
	return out


static func _collect(nodes: Array, out: Dictionary) -> void:
	for node: Variant in nodes:
		if node is Dictionary:
			if node.id != "":
				out[node.id] = node.for
			_collect(node.children, out)


# --- Events ----------------------------------------------------------------------------

## The reveal changes for one entity from events (already cut at the moment wanted, e.g.
## EventLog.effective(entity, day, time)): field -> reveal id -> [ops].
static func grants_from(events: Array, entity: String) -> Dictionary:
	var out := {}
	for e: Dictionary in events:
		if e.get("type") != "reveal.changed" or e.get("entity") != entity:
			continue
		var d: Dictionary = e.get("data", {})
		var field := str(d.get("field", "description"))
		if not out.has(field):
			out[field] = {}
		var id := str(d.get("reveal", ""))
		if not out[field].has(id):
			out[field][id] = []
		out[field][id].append({"add": d.get("add", []), "remove": d.get("remove", [])})
	return out


## A whole entry as `viewer` may see it: every string inside is filtered, with the grants
## of its top-level field (field -> id -> ops from grants_from).
static func filter_entry(entry: Dictionary, viewer: String, grants := {}) -> Dictionary:
	var out := {}
	for key: Variant in entry:
		out[key] = _filter_value(entry[key], viewer, grants.get(str(key), {}))
	return out


static func _filter_value(v: Variant, viewer: String, grants: Dictionary) -> Variant:
	if v is String:
		return filter(v, viewer, grants)
	if v is Dictionary:
		var d := {}
		for k: Variant in v:
			d[k] = _filter_value(v[k], viewer, grants)
		return d
	if v is Array:
		var a := []
		for x: Variant in v:
			a.append(_filter_value(x, viewer, grants))
		return a
	return v


# --- Editing (TASK-19) -----------------------------------------------------------------

## The <reveal> tags in a text with their character positions, outer ones first:
## [{id, for, open: [start, end], close: [start, end]}] (unclosed tags are left out).
static func spans(md: String) -> Array:
	var out := []
	var stack := []
	var i := 0
	while i < md.length():
		var close := md.find("</reveal>", i)
		var m := _open_re.search(md, i)
		if m != null and (close < 0 or m.get_start() < close):
			var attrs := _attrs(m.get_string(1))
			var span := {"id": str(attrs.get("id", "")), "for": viewers(str(attrs.get("for", DM))),
				"open": [m.get_start(), m.get_end()], "close": []}
			out.append(span)
			stack.append(span)
			i = m.get_end()
		elif close >= 0:
			if not stack.is_empty():
				stack.pop_back().close = [close, close + 9]
			i = close + 9
		else:
			break
	return out.filter(func(s: Dictionary) -> bool: return not s.close.is_empty())


## A reveal id not used in any of the texts: r1, r2 ...
static func next_id(texts: Array) -> String:
	var used := 0
	var re := RegEx.create_from_string(r"""<reveal\b[^>]*\bid\s*=\s*["']r(\d+)["']""")
	for t: Variant in texts:
		for m in re.search_all(str(t)):
			used = maxi(used, int(m.get_string(1)))
	return "r%d" % (used + 1)


## The passage a selection [from, to) means: one whose content or whole tag it covers
## (blanks around ignored), innermost first; {} if none.
static func span_at(md: String, from: int, to: int) -> Dictionary:
	var best := {}
	for s: Dictionary in spans(md):
		var inner := md.substr(s.open[1], s.close[0] - s.open[1])
		var lead := inner.length() - inner.lstrip(" \n\t").length()
		var trail := inner.length() - inner.rstrip(" \n\t").length()
		var content := [s.open[1] + lead, s.close[0] - trail]
		var whole := [s.open[0], s.close[1]]
		if (from == content[0] and to == content[1]) or (from == whole[0] and to == whole[1]) \
				or (from == to and from >= s.open[1] and from <= s.close[0]):
			best = s  # later spans are nested deeper
	return best


## Sets who may see the selection [from, to): an existing passage there gets the new `for`
## (an empty list removes the tag: visible to all), otherwise the selection is wrapped in a
## new tag with id `new_id`. Returns {text, id, old_for (PackedStringArray, empty if new)}.
static func apply(md: String, from: int, to: int, who: PackedStringArray, new_id: String) -> Dictionary:
	var s := span_at(md, from, to)
	if not s.is_empty():
		var inner := md.substr(s.open[1], s.close[0] - s.open[1])
		var text: String
		if who.is_empty():
			text = md.left(s.open[0]) + inner + md.substr(s.close[1])
		else:
			text = md.left(s.open[0]) + tag(s.id, who) + inner + md.substr(s.close[0])
		return {"text": text, "id": s.id, "old_for": s.for}
	if who.is_empty() or from >= to:
		return {"text": md, "id": "", "old_for": PackedStringArray()}
	var text := md.left(from) + tag(new_id, who) + md.substr(from, to - from) + "</reveal>" + md.substr(to)
	return {"text": text, "id": new_id, "old_for": PackedStringArray()}


static func tag(id: String, who: PackedStringArray) -> String:
	return "<reveal id=\"%s\" for=\"%s\">" % [id, ",".join(who)]
