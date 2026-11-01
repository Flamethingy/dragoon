class_name RollTables
extends RefCounted
## Rollable tables (TASK-25, package-format.md "Rollable table"): `![[tables/<id>]]` embeds in
## Markdown render as the table with a Roll button; Roll rolls the table's die, highlights the
## row and shows the result; clicking a row's range picks it by hand. Formulas in the cells
## ("2d10 acid damage") are roll links too.
## Who resolves and who rolls is set by whoever owns the screen: the compendium (local rolls,
## logged in the campaign's event log if one is open) or the table (the host rolls, everyone
## sees it in the roll log, the DM can roll hidden with Shift).

signal changed(table_id: String)  ## a table got a result: views showing it re-render
signal rolled(text: String)  ## a local roll happened (for a status line)

## Meta prefixes of the links in the rendered tables.
const ROLL := "tableroll:"
const ROW := "tablerow:"
const FORMULA := "roll:"
const HIGHLIGHT := Color(0.79, 0.63, 0.37, 0.45)  ## UISkin.GOLD, see-through
const EMBED := "^!\\[\\[tables/([^\\]|#]+)(?:[|#][^\\]]*)?\\]\\]$"

static var hub := RollTables.new()
## id -> the table entry ({} if there is none).
static var resolver: Callable
## (id, hidden) -> void: roll a table somewhere else (the table's host). Unset = roll here.
static var roller: Callable
## (formula) -> void: roll a formula somewhere else. Unset = roll here.
static var formula_roller: Callable
## Local rolls are logged here when set (the compendium's campaign log).
static var event_log: EventLog
static var results := {}  ## id -> {value, row, manual}

static var _formula_re := RegEx.create_from_string("(?<![\\w\\[/:])(\\d*d\\d+(?:\\s*[+-]\\s*\\d+)?)(?![\\w\\]])")


static func find(id: String) -> Dictionary:
	if not resolver.is_valid():
		return {}
	var t: Variant = resolver.call(id)
	return t if t is Dictionary else {}


## The row a value lands on (-1 if none: a gap).
static func row_for(t: Dictionary, value: int) -> int:
	var rows: Array = t.get("rows", [])
	for i in rows.size():
		if rows[i] is Dictionary and value >= int(rows[i].get("min", 0)) and value <= int(rows[i].get("max", 0)):
			return i
	return -1


## A row's text (its cells joined), "" for no row.
static func row_text(t: Dictionary, row: int) -> String:
	var rows: Array = t.get("rows", [])
	if row < 0 or row >= rows.size():
		return ""
	return " · ".join(PackedStringArray(rows[row].get("cells", []).map(func(c: Variant) -> String: return str(c))))


## Rolls a table: by the roller if one is set, else here (logged if `log` is set).
static func roll(id: String, hidden := false) -> Dictionary:
	if roller.is_valid():
		roller.call(id, hidden)
		return {}
	var t := find(id)
	if t.is_empty():
		return {}
	var r := Dice.roll(str(t.get("dice", "d20")))
	if r.is_empty():
		return {}
	var row := row_for(t, int(r.total))
	if event_log != null:
		event_log.append("dice.rolled", "", event_data(id, t, r, row, hidden, ""), "dm")
	set_result(id, int(r.total), row)
	hub.rolled.emit("%s: %s → %s" % [t.get("name", id), r.text, row_text(t, row) if row >= 0 else "no row (gap)"])
	return results[id]


## The dice.rolled data of a table roll (doc-1: roll, formula, result, dice + table, value, row).
static func event_data(id: String, t: Dictionary, r: Dictionary, row: int, hidden: bool, who: String) -> Dictionary:
	var one := r.duplicate()
	one["label"] = str(t.get("name", id))
	one["row_text"] = row_text(t, row)
	return {"roll": str(t.get("name", id)), "formula": r.formula, "result": r.total, "dice": r.dice,
		"table": "tables/" + id, "value": r.total, "row": row, "results": [one], "who": who, "hidden": hidden}


static func pick(id: String, row: int) -> void:
	set_result(id, -1, row, true)


static func set_result(id: String, value: int, row: int, manual := false) -> void:
	results[id] = {"value": value, "row": row, "manual": manual}
	hub.changed.emit(id)


static func roll_formula(formula: String) -> void:
	if formula_roller.is_valid():
		formula_roller.call(formula)
		return
	var r := Dice.roll(formula)
	if not r.is_empty():
		if event_log != null:
			event_log.append("dice.rolled", "", {"roll": formula, "formula": r.formula, "result": r.total, "dice": r.dice,
				"results": [r], "who": "", "hidden": false}, "dm")
		hub.rolled.emit("%s: %s" % [formula, r.text])


## Handles the links of rendered tables; false if `meta` is something else.
static func handle_meta(meta: String) -> bool:
	if meta.begins_with(ROLL):
		roll(meta.substr(ROLL.length()), Input.is_key_pressed(KEY_SHIFT))
		return true
	if meta.begins_with(ROW):
		var rest := meta.substr(ROW.length())
		pick(rest.get_slice("#", 0), int(rest.get_slice("#", 1)))
		return true
	if meta.begins_with(FORMULA) and Dice.is_formula(meta.substr(FORMULA.length())):
		roll_formula(meta.substr(FORMULA.length()))
		return true
	return false


## True if a Markdown text embeds this table (to re-render after a roll).
static func embeds(text: String, id: String) -> bool:
	return text.contains("![[tables/" + id)


## The table as BBCode: die column with ranges (click = pick the row), the other columns as
## Markdown, the rolled/picked row highlighted, a Roll button and the result. A missing
## table is a small warning.
static func bbcode(id: String) -> String:
	var t := find(id)
	if t.is_empty():
		return "[color=#%s]⚠ Missing table: tables/%s[/color]" % [UISkin.RED.to_html(false), Markdown.escape(id)]
	var columns: Array = t.get("columns", [])
	var res: Dictionary = results.get(id, {})
	var border := "border=#%s" % Markdown.TABLE_BORDER.to_html()
	var pad := "padding=7,3,7,3 " + border
	var bb := "[table=%d]" % (columns.size() + 1)
	bb += "[cell bg=#%s %s][b]%s[/b][/cell]" % [Markdown.TABLE_HEAD.to_html(), pad, Markdown.escape(str(t.get("dice", "")))]
	for c: Variant in columns:
		bb += "[cell bg=#%s %s][b]%s[/b][/cell]" % [Markdown.TABLE_HEAD.to_html(), pad, Markdown.inline(str(c))]
	var rows: Array = t.get("rows", [])
	for i in rows.size():
		var row: Dictionary = rows[i] if rows[i] is Dictionary else {}
		var bg := "bg=#%s" % HIGHLIGHT.to_html() if int(res.get("row", -2)) == i else "bg=#%s,#%s" % [Markdown.TABLE_ODD.to_html(), Markdown.TABLE_EVEN.to_html()]
		var lo := int(row.get("min", 0))
		var hi := int(row.get("max", 0))
		var range_text := str(lo) if lo == hi else "%d–%d" % [lo, hi]
		bb += "[cell %s %s][url=%s%s#%d]%s[/url][/cell]" % [bg, pad, ROW, id, i, range_text]
		var cells: Array = row.get("cells", [])
		for c in columns.size():
			bb += "[cell %s %s]%s[/cell]" % [bg, pad, Markdown.inline(dice_links(str(cells[c]) if c < cells.size() else ""))]
	bb += "[/table]\n"
	bb += "[url=%s%s][bgcolor=#%s][color=#%s][b] Roll %s [/b][/color][/bgcolor][/url]" % [ROLL, id,
		UISkin.WINE.to_html(false), UISkin.CREAM.to_html(false), Markdown.escape(str(t.get("dice", "")))]
	if not res.is_empty():
		var label := "Picked" if res.get("manual", false) else "Rolled [b]%d[/b]" % int(res.value)
		var text := row_text(t, int(res.row))
		bb += "  %s%s" % [label, (": " + Markdown.inline(text)) if text != "" else ": no row (a gap in the table)"]
	if not bool(t.get("complete", true)):
		bb += "\n[color=#%s][i]Gaps in this table: some results have no row.[/i][/color]" % Markdown.MUTED.to_html(false)
	return bb


## Dice formulas in a cell's Markdown become roll links: "2d10 acid" -> "[2d10](roll:2d10) acid".
static func dice_links(md: String) -> String:
	var out := ""
	var from := 0
	for m in _formula_re.search_all(md):
		out += md.substr(from, m.get_start() - from)
		out += "[%s](%s%s)" % [m.get_string(1), FORMULA, m.get_string(1).replace(" ", "")]
		from = m.get_end()
	return out + md.substr(from)
