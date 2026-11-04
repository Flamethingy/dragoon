class_name BunnyTools
extends RefCounted
## The Table Bunny's tools (TASK-96, design: backlog doc-3): the one list of what the bunny
## (TASK-95) and the optional MCP server (TASK-99) may do at the table, each with a name, a
## description and a JSON schema for the model, and `run` to do it on the host.
##
## Every call runs as the asking player (`sender`: their peer id, 1 = the DM) through the same
## host handlers the buttons use, so it can't do more than that player could by hand: Reveal
## for what they may read, may_see_sheet / _editable_sheet for whose sheet, is_dm for the rest.
## The model never decides about rights; a refused call comes back as {"error": ...}.
## Changes are events in the event log (undo / set back / sync as usual). No files, no shell,
## no network: nothing here reaches outside the table.

const MAX_TEXT := 6000  ## characters of a long text a tool gives back
const MAX_RESULTS := 15

const TOOLS := [
	{"name": "rules_lookup",
		"description": "Look up a rule or a condition (e.g. 'grappled', 'cover', 'opportunity attack') in the table's rules. Returns matching rule texts.",
		"input_schema": {"type": "object", "properties": {
			"query": {"type": "string", "description": "What to look up"}}, "required": ["query"]}},
	{"name": "compendium_search",
		"description": "Search the table's compendium (monsters, spells, items, features, classes, rules, places, people ...) by name. Only what the asking player may see.",
		"input_schema": {"type": "object", "properties": {
			"query": {"type": "string", "description": "Part of the name"},
			"kind": {"type": "string", "description": "Optional: one kind, e.g. creatures, spells, items, features, classes, rules"}}, "required": ["query"]}},
	{"name": "compendium_get",
		"description": "Read one compendium entry by its ref ('spells/fire-bolt'), as far as the asking player may see it.",
		"input_schema": {"type": "object", "properties": {
			"ref": {"type": "string", "description": "kind/id, from compendium_search"}}, "required": ["ref"]}},
	{"name": "sheet_read",
		"description": "Read a character's sheet (HP, AC, abilities, inventory, spells, features, conditions ...). Players: only their own characters.",
		"input_schema": {"type": "object", "properties": {
			"character": {"type": "string", "description": "Name or ref; empty = the asking player's character"}}}},
	{"name": "add_to_sheet",
		"description": "Add an item (to the inventory), a spell (to the spell list) or a feature to a character, as if dropped from the book. Players: only their own characters.",
		"input_schema": {"type": "object", "properties": {
			"character": {"type": "string", "description": "Name or ref; empty = the asking player's character"},
			"kind": {"type": "string", "enum": ["items", "spells", "features"]},
			"entry": {"type": "string", "description": "The entry's id or name"}}, "required": ["kind", "entry"]}},
	{"name": "roll",
		"description": "Roll dice for everyone to see: a formula ('2d6+3') or a check, save or attack of a character ('Perception', 'Dex save', 'attack with Longsword', '... with advantage'). Players: only for their own characters.",
		"input_schema": {"type": "object", "properties": {
			"query": {"type": "string"},
			"character": {"type": "string", "description": "Name or ref; empty = the asking player's character"}}, "required": ["query"]}},
	{"name": "combat_state",
		"description": "The current combat: round, whose turn, the initiative order; hit points only of creatures the asking player may see them of.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "note_write",
		"description": "Write a note into the session notes, in the asking player's name.",
		"input_schema": {"type": "object", "properties": {
			"text": {"type": "string"}}, "required": ["text"]}},
]


## The tools as the Messages API wants them.
static func schemas() -> Array:
	return TOOLS.duplicate(true)


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for t: Dictionary in TOOLS:
		out.append(str(t.name))
	return out


## Runs `tool` with `args` as the player of peer `sender` on the host: {"result": ...} or
## {"error": "..."}.
static func run(table: NetTable, tool: String, args: Variant, sender: int) -> Dictionary:
	if table == null or not table.is_dm() or table.timeline == null:
		return _err("the table isn't running here")
	var player := table._sender_player(sender)
	if player == "":
		return _err("unknown player")
	var a: Dictionary = args if args is Dictionary else {}
	match tool:
		"rules_lookup":
			return _rules_lookup(table, player, str(a.get("query", "")))
		"compendium_search":
			return _search(table, player, str(a.get("query", "")), str(a.get("kind", "")))
		"compendium_get":
			return _get_entry(table, player, str(a.get("ref", "")))
		"sheet_read":
			return _sheet_read(table, player, str(a.get("character", "")))
		"add_to_sheet":
			return _add_to_sheet(table, sender, player, str(a.get("character", "")), str(a.get("kind", "")), str(a.get("entry", "")))
		"roll":
			return _roll(table, sender, player, str(a.get("query", "")), str(a.get("character", "")))
		"combat_state":
			return _combat(table, player)
		"note_write":
			return _note(table, sender, str(a.get("text", "")))
	return _err("no such tool: %s" % tool)


static func _err(text: String) -> Dictionary:
	return {"error": text}


# --- Reading --------------------------------------------------------------------------------------

static func _rules_lookup(table: NetTable, player: String, query: String) -> Dictionary:
	var q := query.strip_edges().to_lower()
	if q == "":
		return _err("what should I look up?")
	var out := []
	var edition := str(table.rules_settings().get("edition", "2014"))
	for id: String in Rules.conditions():
		var c := Rules.condition(id, edition)
		if q in str(c.name).to_lower() or str(c.name).to_lower() in q:
			out.append({"name": c.name, "kind": "condition", "text": _cut(str(c.text))})
	for e: Dictionary in table.catalog_list("rules"):
		if out.size() >= MAX_RESULTS:
			break
		if q in str(e.get("name", "")).to_lower() and _visible(table, player, "rules", e):
			var seen := _seen_as(table, player, "rules", e)
			out.append({"name": seen.get("name", ""), "ref": "rules/%s" % seen.get("id", ""), "text": _cut(str(seen.get("description", seen.get("text", ""))))})
	if out.is_empty():
		return _err("nothing found for \"%s\"" % query)
	return {"result": out}


static func _search(table: NetTable, player: String, query: String, kind: String) -> Dictionary:
	var q := query.strip_edges().to_lower()
	if q == "":
		return _err("what should I search for?")
	var kinds: Array = [kind] if kind != "" else Schema.KINDS.keys()
	if kind != "" and not Schema.KINDS.has(kind):
		return _err("no such kind: %s" % kind)
	var out := []
	for k: String in kinds:
		for e: Dictionary in table.catalog_list(k):
			if out.size() >= MAX_RESULTS:
				break
			if q in str(e.get("name", "")).to_lower() and _visible(table, player, k, e):
				var seen := _seen_as(table, player, k, e)
				out.append({"ref": "%s/%s" % [k, seen.get("id", "")], "name": seen.get("name", ""), "about": CardData.subtitle(seen)})
	return {"result": out}


static func _get_entry(table: NetTable, player: String, ref: String) -> Dictionary:
	var kind := ref.get_slice("/", 0)
	var e := table.catalog_entry(ref)
	if e.is_empty() or not _visible(table, player, kind, e):
		return _err("no entry %s" % ref)  # hidden ones look like missing ones
	return {"result": _clean(_seen_as(table, player, kind, e))}


static func _sheet_read(table: NetTable, player: String, who: String) -> Dictionary:
	var ref := _creature(table, player, who)
	if ref == "":
		return _err("which character?")
	if not table.may_see_sheet(player, ref):
		return _err("not allowed: that's not your character")
	var s := table.sheet_for(player, ref)
	if s.is_empty():
		return _err("no sheet for %s" % who)
	var out := _clean(s)
	out["ref"] = ref
	if s.has("_hp_max"):
		out["hp_max"] = s._hp_max
	if s.has("_class"):
		out["class"] = s._class
	return {"result": out}


static func _combat(table: NetTable, player: String) -> Dictionary:
	if not table.in_combat():
		return {"result": {"active": false}}
	var c := table.combat_view()
	var rows := []
	for o: Dictionary in c.get("order", []):
		var row := {"name": str(o.get("name", "")), "initiative": o.get("initiative"), "current": bool(o.get("current", false))}
		var ref := str(o.get("entity", ""))
		if ref != "" and table.may_see_sheet(player, ref):
			var s := table.sheet_for(player, ref)
			row["hp"] = s.get("hp")
			row["hp_max"] = s.get("_hp_max")
		rows.append(row)
	return {"result": {"active": true, "round": c.get("round"), "order": rows}}


## May `player` see entry `e` of `kind` at all? No drafts; timeline / world entries as Reveal says.
static func _visible(table: NetTable, player: String, kind: String, e: Dictionary) -> bool:
	if EntryStore.is_draft(e) and player != Reveal.DM:
		return false
	var ref := "%s/%s" % [kind, e.get("id", "")]
	if not table.timeline.entry(ref).is_empty():
		return not table.entry_for(player, ref).is_empty()
	return true


## The entry as `player` sees it (<reveal> passages and %% comments cut out).
static func _seen_as(table: NetTable, player: String, kind: String, e: Dictionary) -> Dictionary:
	var ref := "%s/%s" % [kind, e.get("id", "")]
	if not table.timeline.entry(ref).is_empty():
		return table.entry_for(player, ref)
	return Reveal.filter_entry(e, player)


## Without the table's own bookkeeping (keys starting with _), long texts cut.
static func _clean(d: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in d:
		if str(k).begins_with("_"):
			continue
		var v: Variant = d[k]
		out[k] = _cut(v) if v is String else v
	return out


static func _cut(text: String) -> String:
	return text if text.length() <= MAX_TEXT else text.left(MAX_TEXT) + " …"


## A creature by ref or name ("" = the player's own character).
static func _creature(table: NetTable, player: String, who: String) -> String:
	var w := who.strip_edges()
	if w == "":
		return table._pc_of(player) if player != Reveal.DM else table.hud_ref
	if "/" in w:
		return w if w.get_slice("/", 0) in Timeline.CREATURES else ""
	var refs: Array = table.owners.keys()
	if table.grid != null:
		refs.append_array(table.grid.tokens.keys())
	for kind: String in Timeline.CREATURES:  # the world's and the timeline's, also off the map
		for id: String in table.timeline.entries(kind):
			refs.append("%s/%s" % [kind, id])
	for ref: String in refs:
		var name := table.timeline.name_of(ref).to_lower()
		if name == w.to_lower() or name.begins_with(w.to_lower() + " "):
			return ref
	return ""


# --- Changing ---------------------------------------------------------------------------------------

static func _add_to_sheet(table: NetTable, sender: int, player: String, who: String, kind: String, entry: String) -> Dictionary:
	if not EntryDrag.SHEET_LISTS.has(kind):
		return _err("kind must be items, spells or features")
	var ref := _creature(table, player, who)
	if ref == "":
		return _err("which character?")
	if not table.may_see_sheet(player, ref):
		return _err("not allowed: that's not your character")
	var e := table.catalog_entry("%s/%s" % [kind, entry])
	if e.is_empty():
		for one: Dictionary in table.catalog_list(kind):
			if str(one.get("name", "")).to_lower() == entry.to_lower():
				e = one
				break
	if e.is_empty() or not _visible(table, player, kind, e):
		return _err("no %s called %s" % [kind.trim_suffix("s"), entry])
	var text := table._handle_add_entry(sender, ref, kind, str(e.get("id", "")), str(e.get("name", entry)))
	if text == "":
		return _err("not allowed")
	return {"result": text}


static func _roll(table: NetTable, sender: int, player: String, query: String, who: String) -> Dictionary:
	if query.strip_edges() == "":
		return _err("what should I roll?")
	var ref := ""
	if who.strip_edges() != "":
		ref = _creature(table, player, who)
		if ref == "":
			return _err("which character?")
		if not table.may_see_sheet(player, ref):
			return _err("not allowed: that's not your character")
	var r := table._handle_roll(sender, query.left(200), ref, false)
	if r.is_empty():
		return _err("can't roll \"%s\"" % query)
	return {"result": {"roll": r.get("roll"), "formula": r.get("formula"), "result": r.get("result"), "who": r.get("who")}}


static func _note(table: NetTable, sender: int, text: String) -> Dictionary:
	if text.strip_edges() == "":
		return _err("an empty note")
	table._handle_note(sender, text.left(4000))
	return {"result": "noted"}
