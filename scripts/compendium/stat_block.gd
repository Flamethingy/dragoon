class_name StatBlock
## Compendium entries as BBCode: a stat block for monsters, the spell header for spells
## and a field table for every other kind. Text fields are Markdown (see Markdown).

const ACCENT := Color8(102, 42, 58)  ## headings and rules (UISkin.WINE)
const LABEL := Color8(150, 72, 80)
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const XP := {0.0: 10, 0.125: 25, 0.25: 50, 0.5: 100, 1: 200, 2: 450, 3: 700, 4: 1100, 5: 1800,
	6: 2300, 7: 2900, 8: 3900, 9: 5000, 10: 5900, 11: 7200, 12: 8400, 13: 10000, 14: 11500,
	15: 13000, 16: 15000, 17: 18000, 18: 20000, 19: 22000, 20: 25000, 21: 33000, 22: 41000,
	23: 50000, 24: 62000, 25: 75000, 26: 90000, 27: 105000, 28: 120000, 29: 135000, 30: 155000}
## Keys that are shown elsewhere or are bookkeeping.
const HIDDEN := ["id", "name", "source", "image", "description", "origin",
	"_kind", "_package", "_package_name", "_dir", "_key", "draft", "edited", "copy_of", "copy_number"]
const SINGULAR := {"classes": "Class", "subclasses": "Subclass", "races": "Race", "subraces": "Subrace",
	"items": "Item", "feats": "Feat", "backgrounds": "Background", "invocations": "Invocation",
	"infusions": "Infusion", "conditions": "Condition", "diseases": "Disease", "rules": "Rule",
	"tables": "Table", "features": "Creature feature"}
## Set by the compendium (and tests): resolves feature ids and used_by monsters.
static var db: PackageDB

const SCHOOLS_ORDINAL := ["cantrip", "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th"]


static func to_bbcode(e: Dictionary) -> String:
	match str(e.get("_kind", "")):
		"creatures":
			return monster(e)
		"spells":
			return spell(e)
		"features":
			return feature(e)
		"tables":
			return table(e)
		"packages":
			return package(e)
		_:
			return generic(e)


# --- Shared pieces -----------------------------------------------------------------

static func _title(e: Dictionary, subtitle: String) -> String:
	var draft := EntryStore.is_draft(e)  # drafts: italic, grey title (TASK-36)
	var bb := "[font_size=26][b]%s[color=#%s]%s[/color]%s[/b][/font_size]\n" % ["[i]" if draft else "", (UISkin.DRAFT_INK if draft else ACCENT).to_html(),
		Markdown.escape(str(e.get("name", "?"))), "[/i]" if draft else ""]
	if subtitle != "":
		bb += "[i]%s[/i]\n" % Markdown.escape(subtitle)
	return bb


static func _rule() -> String:
	return "[hr color=#%s height=2 width=100%%]\n" % ACCENT.to_html()


static func _field(label: String, value: String) -> String:
	return "[b][color=#%s]%s[/color][/b] %s\n" % [LABEL.to_html(), label, value]


static func _heading(text: String) -> String:
	return "\n[font_size=19][color=#%s]%s[/color][/font_size]\n[hr color=#%s height=1 width=100%%]\n" % [ACCENT.to_html(), text, ACCENT.to_html()]


static func _md(text: Variant) -> String:
	return Markdown.to_bbcode(str(text)) if text != null else ""


static func _footer(e: Dictionary) -> String:
	var src := str(e.get("source", ""))
	var pkg := str(e.get("_package_name", ""))
	var line := pkg if src == "" or src == pkg else "%s (package %s)" % [src, pkg]
	return "\n\n[font_size=12][color=#%s]Source: %s[/color][/font_size]" % [Markdown.MUTED.to_html(), Markdown.escape(line)]


static func _join(list: Variant) -> String:
	if list is Array:
		return ", ".join(PackedStringArray(list.map(func(x: Variant) -> String: return str(x))))
	return str(list) if list != null else ""


## A number without a trailing .0 (JSON numbers arrive as floats), or "—".
static func _num(v: Variant) -> String:
	if v == null or str(v) == "":
		return "—"
	if v is float and is_equal_approx(v, roundf(v)):
		return str(int(v))
	return str(v)


static func _signed(n: int) -> String:
	return "+%d" % n if n >= 0 else str(n)


static func _metres(m: Variant) -> String:
	var f := float(m)
	return ("%d m" % int(f)) if is_equal_approx(f, roundf(f)) else ("%.1f m" % f)


## CR as printed: 1/8, 1/4, 1/2 or the number.
static func cr_text(cr: Variant) -> String:
	if cr == null:
		return "—"
	var f := float(cr)
	if is_equal_approx(f, 0.125):
		return "1/8"
	if is_equal_approx(f, 0.25):
		return "1/4"
	if is_equal_approx(f, 0.5):
		return "1/2"
	return str(int(f)) if is_equal_approx(f, roundf(f)) else str(f)


static func level_text(level: Variant) -> String:
	var n := int(level) if level != null else -1
	return "Cantrip" if n == 0 else ("Level %d" % n if n > 0 else "—")


# --- Monsters ----------------------------------------------------------------------

## `with_description` = false leaves out the description and source (the full view shows
## them in their own column).
static func monster(e: Dictionary, with_description := true) -> String:
	var kind := " ".join(PackedStringArray([str(e.get("size", "")), str(e.get("type", ""))])).strip_edges()
	if str(e.get("subtype", "")) != "":
		kind += " (%s)" % e.subtype
	var subtitle := kind + (", " + str(e.alignment) if str(e.get("alignment", "")) != "" else "")
	var bb := _title(e, subtitle) + _rule()

	var ac := _num(e.get("ac"))
	if str(e.get("armor", "")) != "":
		ac += " (%s)" % e.armor
	bb += _field("Armor Class", Markdown.escape(ac))
	bb += _field("Hit Points", _num(e.get("hp")))
	bb += _field("Speed", _speed(e))
	bb += _rule()

	var stats: Dictionary = e.get("stats", {}) if e.get("stats") is Dictionary else {}
	bb += "[table=6]"
	for a in ABILITIES:
		bb += "[cell padding=6,2,6,0][center][b]%s[/b][/center][/cell]" % a.to_upper()
	for a in ABILITIES:
		var score := int(stats.get(a, 10))
		bb += "[cell padding=6,0,6,2][center]%d (%s)[/center][/cell]" % [score, _signed(floori((score - 10) / 2.0))]
	bb += "[/table]\n" + _rule()

	bb += _bonuses("Saving Throws", e.get("saves"))
	bb += _bonuses("Skills", e.get("skills"))
	for pair in [["Damage Vulnerabilities", "vulnerabilities"], ["Damage Resistances", "resistances"],
			["Damage Immunities", "immunities"], ["Condition Immunities", "condition_immunities"]]:
		if e.get(pair[1]) is Array and not e[pair[1]].is_empty():
			bb += _field(pair[0], Markdown.inline(_join(e[pair[1]])))
	var senses := _join(e.get("senses", []))
	if e.get("passive_perception") != null:
		senses += ("" if senses == "" else ", ") + "passive Perception %s" % _num(e.passive_perception)
	if senses != "":
		bb += _field("Senses", Markdown.inline(senses))
	bb += _field("Languages", Markdown.inline(_join(e.get("languages", []))) if not _join(e.get("languages", [])).is_empty() else "—")
	var cr: Variant = e.get("cr")
	var xp: Variant = XP.get(float(cr) if cr != null and float(cr) < 1 else int(cr) if cr != null else -1)
	bb += _field("Challenge", cr_text(cr) + (" (%s XP)" % _thousands(xp) if xp != null else ""))
	bb += _rule()

	bb += _features(_resolve(e, "traits"))
	for pair in [["Actions", "actions"], ["Bonus Actions", "bonus_actions"], ["Reactions", "reactions"],
			["Legendary Actions", "legendary_actions"]]:
		if e.get(pair[1]) is Array and not e[pair[1]].is_empty():
			bb += _heading(pair[0])
			if pair[1] == "legendary_actions" and str(e.get("legendary_intro", "")).strip_edges() != "":
				bb += _md(e.legendary_intro) + "\n\n"
			bb += _features(_resolve(e, pair[1]))
	if e.get("spells") is Array and not e.spells.is_empty():
		bb += _field("\nSpells", Markdown.inline(_join(e.spells)))
	if e.get("environments") is Array and not e.environments.is_empty():
		bb += _field("\nEnvironments", Markdown.escape(_join(e.environments)))
	if not with_description:
		return bb
	if str(e.get("description", "")).strip_edges() != "":
		bb += _heading("Description") + _md(e.description)
	return bb + _footer(e)


static func _speed(e: Dictionary) -> String:
	var speed: Variant = e.get("speed")
	if not speed is Dictionary:
		return Markdown.escape(str(speed)) if speed != null else "—"
	var parts := PackedStringArray()
	if float(speed.get("walk", 0)) > 0 or speed.size() == 0:
		parts.append(_metres(speed.get("walk", 0)))
	for mode in ["burrow", "climb", "fly", "swim"]:
		if float(speed.get(mode, 0)) > 0:
			var text := "%s %s" % [mode, _metres(speed[mode])]
			if mode == "fly" and bool(e.get("hover", false)):
				text += " (hover)"
			parts.append(text)
	return ", ".join(parts) if not parts.is_empty() else "0 m"


static func _bonuses(label: String, values: Variant) -> String:
	if not values is Dictionary or values.is_empty():
		return ""
	var parts := PackedStringArray()
	for k: String in values:
		var name := k.to_upper() if k in ABILITIES else k.replace("_", " ").capitalize()
		parts.append("%s %s" % [name, _signed(int(values[k]))])
	return _field(label, ", ".join(parts))


## A monster's feature list as feature dicts (ids resolved through db).
static func _resolve(e: Dictionary, key: String) -> Array:
	if db != null:
		return db.features_of(e, key)
	var list: Variant = e.get(key)
	if not list is Array:
		return []
	return list.map(func(f: Variant) -> Dictionary: return f if f is Dictionary else {"name": str(f), "_missing": true})


## Features as "***Name (uses).*** text" paragraphs.
static func _features(list: Variant) -> String:
	if not list is Array:
		return ""
	var bb := ""
	for f: Variant in list:
		if not f is Dictionary:
			continue
		if f.get("_missing", false):
			bb += "[color=#%s][i]Missing feature \"%s\" (not in this package's features.json)[/i][/color]\n\n" % [Markdown.MUTED.to_html(), Markdown.escape(str(f.name))]
			continue
		var name := str(f.get("name", ""))
		var extra := PackedStringArray()
		for k in ["uses", "cost"]:
			if f.get(k) != null and str(f[k]) != "":
				extra.append(("Costs %s Actions" % f[k]) if k == "cost" else str(f[k]))
		if not extra.is_empty():
			name += " (%s)" % ", ".join(extra)
		var text := str(f.get("text", "")).strip_edges()
		bb += "[b][i]%s.[/i][/b] %s\n\n" % [Markdown.escape(name), Markdown.to_bbcode(text)]
	return bb


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


# --- Monster features ----------------------------------------------------------------

static func feature(e: Dictionary) -> String:
	var bb := _title(e, "Creature feature") + _rule()
	bb += _features([e])
	var atk: Variant = e.get("attack")
	if atk is Dictionary:
		var parts := PackedStringArray()
		if str(atk.get("kind", "")) != "":
			parts.append(str(atk.kind).capitalize())
		if atk.get("to_hit") != null:
			parts.append(_signed(int(atk.to_hit)) + " to hit")
		if str(atk.get("range", "")) != "":
			parts.append(str(atk.range))
		bb += _field("Attack", Markdown.escape(", ".join(parts)))
		var dmg := damage_text(atk.get("damage"))
		if dmg != "":
			bb += _field("Damage", dmg)
	var save: Variant = e.get("save")
	if save is Dictionary:
		bb += _field("Save", "DC %s %s" % [_num(save.get("dc")), str(save.get("ability", "")).to_upper()])
	var extra := damage_text(e.get("damage"))
	if extra != "":
		bb += _field("Damage", extra)
	var users: Variant = e.get("used_by")
	if users is Array and not users.is_empty():
		var links := PackedStringArray()
		for id: Variant in users:
			var m: Dictionary = db.get_entry(str(e["_package"]), "creatures", str(id)) if db != null else {}
			var label := str(m.get("name", id))
			links.append("[url=entry:%s/creatures/%s][color=#%s]%s[/color][/url]" % [e["_package"], id, Markdown.LINK.to_html(), Markdown.escape(label)])
		bb += _heading("Used by %d monster%s" % [users.size(), "" if users.size() == 1 else "s"]) + ", ".join(links)
	return bb + _footer(e)


## "12 (2d6 + 5) bludgeoning + 3 (1d6) fire" from [{dice, average, type}].
static func damage_text(list: Variant) -> String:
	if not list is Array:
		return ""
	var parts := PackedStringArray()
	for d: Variant in list:
		if d is Dictionary:
			parts.append(("%s (%s) %s" % [_num(d.get("average")), d.get("dice", ""), d.get("type", "")]).strip_edges())
	return Markdown.escape(" + ".join(parts))


# --- Spells ------------------------------------------------------------------------

static func spell(e: Dictionary) -> String:
	var level := int(e.get("level", 0)) if e.get("level") != null else 0
	var school := str(e.get("school", ""))
	var subtitle := ("%s cantrip" % school) if level == 0 else ("%s-level %s" % [SCHOOLS_ORDINAL[clampi(level, 1, 9)], school.to_lower()])
	if bool(e.get("ritual", false)):
		subtitle += " (ritual)"
	var bb := _title(e, subtitle.strip_edges()) + _rule()
	bb += _field("Casting Time", Markdown.escape(str(e.get("casting_time", "—"))))
	var range_m: Variant = e.get("range_m")
	bb += _field("Range", "Self / Touch" if range_m == null or float(range_m) == 0 else _metres(range_m))
	bb += _field("Components", _components(e.get("components")))
	var duration := str(e.get("duration", "—"))
	if bool(e.get("concentration", false)) and not duration.to_lower().contains("concentration"):
		duration = "Concentration, " + duration
	bb += _field("Duration", Markdown.escape(duration))
	if e.get("classes") is Array and not e.classes.is_empty():
		bb += _field("Classes", Markdown.inline(_join(e.classes)))
	bb += _rule()
	bb += _md(e.get("description", ""))
	return bb + _footer(e)


static func _components(c: Variant) -> String:
	if not c is Dictionary:
		return Markdown.escape(str(c)) if c != null else "—"
	var parts := PackedStringArray()
	if bool(c.get("verbal", false)):
		parts.append("V")
	if bool(c.get("somatic", false)):
		parts.append("S")
	if bool(c.get("material", false)):
		var m := str(c.get("material_text", "")).strip_edges()
		parts.append("M" + (" (%s)" % Markdown.inline(m) if m != "" else ""))
	return ", ".join(parts) if not parts.is_empty() else "—"


# --- Everything else ---------------------------------------------------------------

## A package (TASK-23): kind, version, description (its PDF links open the PDFs), the counts per
## kind (each a link to Browse filtered to this package and kind), origin and dependencies.
static func package(e: Dictionary) -> String:
	var id := str(e.get("id", ""))
	var kind := "World package" if str(e.get("kind", "")) == "world" else "Source package"
	var bb := _title(e, "%s · version %s" % [kind, e.get("version", "?")]) + _rule()
	if not bool(e.get("_enabled", true)):
		bb += "[color=#%s][i]Switched off: its entries don't show in the book.[/i][/color]\n" % Markdown.MUTED.to_html()
	var desc := str(e.get("description", "")).strip_edges()
	if desc != "":
		bb += _md(pdf_links(desc, id)) + "\n"
	var counts: Variant = e.get("_counts", e.get("counts", {}))
	if counts is Dictionary and not counts.is_empty():
		bb += _heading("Entries")
		var keys: Array = counts.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(counts[a]) > int(counts[b]))
		var parts := PackedStringArray()
		for k: Variant in keys:
			parts.append("[url=pkgkind:%s/%s][color=#%s]%s %s[/color][/url]" % [id, k, Markdown.LINK.to_html(), str(k).capitalize(), _thousands(int(counts[k]))])
		bb += ", ".join(parts) + "\n"
	var origin := str(e.get("imported_from", e.get("origin", "")))
	if origin != "" or str(e.get("created", "")) != "":
		bb += _field("\nImported from", Markdown.escape(origin if origin != "" else "—") + (" (%s)" % str(e.created).replace("T", " ") if str(e.get("created", "")) != "" else ""))
	var deps: Variant = e.get("dependencies", [])
	bb += _field("Dependencies", Markdown.escape(_join(deps)) if deps is Array and not deps.is_empty() else "none")
	return bb


## The description's PDF links "[Title](<docs/x.pdf>)" become "pdf:" links the book opens.
static func pdf_links(md: String, package_id: String) -> String:
	var re := RegEx.create_from_string("\\]\\(\\s*<?(docs/[^)>]+?)>?\\s*\\)")
	var out := ""
	var from := 0
	for m in re.search_all(md):
		out += md.substr(from, m.get_start() - from) + "](pdf:%s/%s)" % [package_id, m.get_string(1).uri_encode().replace("%2F", "/")]
		from = m.get_end()
	return out + md.substr(from)


## A rollable table (TASK-25): the table with its Roll button and a link to where it comes from.
static func table(e: Dictionary) -> String:
	var rows: int = e.rows.size() if e.get("rows") is Array else 0
	var bb := _title(e, "Rollable table · %s · %d rows" % [e.get("dice", "?"), rows]) + _rule()
	bb += RollTables.bbcode(str(e.get("id", ""))) + "\n"
	var parent := str(e.get("parent", ""))
	if parent != "":
		var p := {}
		if db != null:
			p = db.get_entry(str(e.get("_package", "")), parent.get_slice("/", 0), parent.get_slice("/", 1))
		var label := str(p.get("name", parent)) if not p.is_empty() else parent
		var link := "[url=entry:%s/%s][color=#%s]%s[/color][/url]" % [e.get("_package", ""), parent, Markdown.LINK.to_html(), Markdown.escape(label)] \
			if not p.is_empty() else Markdown.escape(label)
		bb += "\n" + _field("From", link + (" (%s)" % str(e.field).replace("_", " ") if str(e.get("field", "")) not in ["", "description"] else ""))
	if str(e.get("description", "")).strip_edges() != "":
		bb += _md(e.description)
	return bb + _footer(e)


static func generic(e: Dictionary) -> String:
	var kind := str(e.get("_kind", ""))
	var bb := _title(e, SINGULAR.get(kind, kind.capitalize())) + _rule()
	var keys: Array = e.keys().filter(func(k: Variant) -> bool: return str(k) not in HIDDEN and not str(k).begins_with("_"))
	var long_text := []
	for k: Variant in keys:
		var v: Variant = e[k]
		if v == null or (v is String and v.strip_edges() == "") or ((v is Array or v is Dictionary) and v.is_empty()):
			continue
		if v is String and (v.contains("\n") or v.length() > 160):
			long_text.append([k, v])  # Markdown sections after the fields
			continue
		bb += _field(str(k).replace("_", " ").capitalize(), _value(v))
	for pair: Array in long_text:
		bb += _heading(str(pair[0]).replace("_", " ").capitalize()) + _md(pair[1])
	if str(e.get("description", "")).strip_edges() != "":
		if not keys.is_empty():
			bb += _rule()
		bb += _md(e.description)
	return bb + _footer(e)


static func _value(v: Variant) -> String:
	if v is bool:
		return "yes" if v else "no"
	if v is float and is_equal_approx(v, roundf(v)):
		return str(int(v))
	if v is Array:
		if v.all(func(x: Variant) -> bool: return not (x is Array or x is Dictionary)):
			return Markdown.inline(_join(v))
		return Markdown.escape(JSON.stringify(v))
	if v is Dictionary:
		var parts := PackedStringArray()
		for k: Variant in v:
			parts.append("%s: %s" % [k, v[k] if not (v[k] is Array or v[k] is Dictionary) else JSON.stringify(v[k])])
		return Markdown.inline(", ".join(parts))
	return Markdown.inline(str(v))
