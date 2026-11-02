class_name ClassFeatures
extends RefCounted
## Class and subclass features as entries (TASK-69). A class page is one Markdown text: its
## features are the headings at one depth; their levels come from the page's level table
## ("| Level | ... | Features |", wiki links or plain names), else from the text ("Starting at
## 6th level", "when you choose this archetype at 3rd level"). Features with no level found get
## level 0: they are listed, not given to characters, until the DM sets one.
## A feature entry: {id, name, class, subclass, level, text, uses?, resource?, kind: "class"}.

const NOT_FEATURES := ["equipment", "hit points", "proficiencies", "class features", "quick build",
	"multiclassing", "creating a", "spellcasting focus"]


static func slug(s: String) -> String:
	var out := ""
	for ch in s.strip_edges().to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "-"
	while "--" in out:
		out = out.replace("--", "-")
	return out.trim_prefix("-").trim_suffix("-")


static func _key(name: String) -> String:
	return slug(name).replace("-", "")


## The level table: {name key: first level} (an empty one without a table).
static func levels_from_table(text: String) -> Dictionary:
	var out := {}
	var col := -1
	for raw: String in text.split("\n"):
		var line := raw.strip_edges()
		if not line.begins_with("|"):
			col = -1 if line != "" else col
			continue
		var cells := line.replace("\\|", "\u0001").trim_prefix("|").trim_suffix("|").split("|")
		if col < 0:
			for i in cells.size():
				if cells[i].strip_edges().to_lower() == "features" and cells[0].strip_edges().to_lower() == "level":
					col = i
			continue
		var lm := RegEx.create_from_string("^(\\d+)").search(cells[0].strip_edges())
		if lm == null or col >= cells.size():
			continue
		var lvl := int(lm.get_string(1))
		var cell := cells[col].replace("\u0001", "|")
		var names := []
		var links := RegEx.create_from_string("\\[\\[([^\\]]+)\\]\\]").search_all(cell)
		if not links.is_empty():
			for m: RegExMatch in links:
				var l := m.get_string(1)
				names.append(l.get_slice("|", 1) if "|" in l else l.get_slice("#", l.get_slice_count("#") - 1))
		else:
			for n: String in cell.split(","):
				names.append(n)
		for n: Variant in names:
			var k := _key(str(n))
			if k != "" and not out.has(k):
				out[k] = lvl
	return out


## The first level the text names ("at 3rd level", "6th-level"); 0 if none.
static func level_from_text(text: String) -> int:
	var m := RegEx.create_from_string("(?i)\\b(\\d{1,2})(?:st|nd|rd|th)[ -]level").search(text)
	return int(m.get_string(1)) if m != null and int(m.get_string(1)) <= 20 else 0


## Uses from the text ("until you finish a short or long rest"); {} for none or a class resource.
static func _uses_of(text: String) -> String:
	var t := text.to_lower()
	if "until you finish a short or long rest" in t:
		return "Recharges after a Short or Long Rest"
	if "until you finish a long rest" in t:
		return "1/Day"
	return ""


## The features of a class (or, with `subclass_id`, a subclass) page.
static func split(entry: Dictionary, class_id: String, subclass_id := "") -> Array:
	var text := str(entry.get("description", entry.get("text", "")))
	var table := levels_from_table(text) if subclass_id == "" else {}
	var lines := text.split("\n")
	var heads := []  # [line, depth, name]
	var re := RegEx.create_from_string("^\\s*(#{2,6})\\s+(.+?)\\s*$")
	for i in lines.size():
		var m := re.search(lines[i])
		if m != null:
			heads.append([i, m.get_string(1).length(), m.get_string(2).replace("*", "").strip_edges()])
	if heads.is_empty():
		return []
	# the features' depth: the one with most headings in the table (or naming a level)
	var score := {}
	for h: Array in heads:
		var sect := _section(lines, heads, h)
		if table.has(_key(str(h[2]))) or (table.is_empty() and level_from_text(sect) > 0):
			score[h[1]] = int(score.get(h[1], 0)) + 1
	if score.is_empty():
		return []
	var depth := -1
	for d: Variant in score:
		if depth < 0 or int(score[d]) > int(score[depth]) or (int(score[d]) == int(score[depth]) and int(d) < depth):
			depth = int(d)
	var resources := {}
	for r: Dictionary in Rules.core().get("class_resources", {}).get(Rules._class_id(class_id), []):
		resources[_key(str(r.name))] = str(r.id)
	var out := []
	var seen := {}
	for h: Array in heads:
		if int(h[1]) != depth:
			continue
		var name := str(h[2])
		var low := name.to_lower()
		if NOT_FEATURES.any(func(n: String) -> bool: return low.begins_with(n)):
			continue
		var sect := _section(lines, heads, h)
		var lvl := int(table.get(_key(name), 0))
		if lvl == 0:
			lvl = level_from_text(sect)
		if table.size() > 0 and not table.has(_key(name)) and lvl == 0:
			continue  # flavour headings between the features
		var id := slug("%s-%s" % [subclass_id if subclass_id != "" else class_id, name])
		if seen.has(id):
			continue
		seen[id] = true
		var f := {"id": id, "name": name, "class": class_id, "subclass": subclass_id, "level": lvl,
			"text": sect.strip_edges(), "kind": "class", "source": str(entry.get("source", ""))}
		if resources.has(_key(name)):
			f["resource"] = resources[_key(name)]
		else:
			var uses := _uses_of(sect)
			if uses != "":
				f["uses"] = uses
		out.append(f)
	if subclass_id != "":  # tenets, oath or circle spells: they come with the subclass
		var first := 0
		for f: Dictionary in out:
			if int(f.level) > 0 and (first == 0 or int(f.level) < first):
				first = int(f.level)
		for f: Dictionary in out:
			if int(f.level) == 0 and first > 0:
				f["level"] = first
				f["level_guessed"] = true
	return out


## The text under heading `h` (down to the next heading at its depth or above).
static func _section(lines: PackedStringArray, heads: Array, h: Array) -> String:
	var start := int(h[0]) + 1
	var stop := lines.size()
	for o: Array in heads:
		if int(o[0]) > int(h[0]) and int(o[1]) <= int(h[1]):
			stop = int(o[0])
			break
	return "\n".join(lines.slice(start, stop))


## The class features a sheet has: from its `classes` [{class, level, subclass}] and `index`
## (class id -> [feature]), up to each class's level. Returns feature entries.
static func granted(sheet: Dictionary, index: Dictionary) -> Array:
	var out := []
	for c: Variant in sheet.get("classes", []):
		if not c is Dictionary:
			continue
		var cls := str(c.get("class", "")).get_file()
		var sub := slug(str(c.get("subclass", "")).get_file())
		var lvl := int(c.get("level", 0))
		for f: Dictionary in index.get(cls, []):
			var fsub := str(f.get("subclass", ""))
			if int(f.get("level", 0)) > 0 and int(f.level) <= lvl and (fsub == "" or fsub == sub):
				out.append(f)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) < int(b.level))
	return out


## class id -> [feature] of `features` (an id -> entry dictionary or an array).
static func index_of(features: Variant) -> Dictionary:
	var out := {}
	var list: Array = (features as Dictionary).values() if features is Dictionary else features
	for f: Variant in list:
		if f is Dictionary and str(f.get("kind", "")) == "class" and str(f.get("class", "")) != "":
			if not out.has(str(f.class)):
				out[str(f.class)] = []
			(out[str(f.class)] as Array).append(f)
	return out
