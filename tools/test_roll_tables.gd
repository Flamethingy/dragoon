extends SceneTree
## Headless check of rollable tables (TASK-25): ![[tables/<id>]] embeds render as the table
## with a Roll button (missing ones as a warning), rolling highlights the row and logs
## dice.rolled with table, value and row, rows can be picked by hand, formulas in cells are
## roll links; `tables` is a compendium kind with cards and a full view; at the table the
## host rolls and everyone sees it (the DM can roll hidden).
## godot --headless --path . -s tools/test_roll_tables.gd

const PORT := 47831
const DIR := "user://test_roll_tables"
const CAMPAIGN := DIR + "/campaign"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Campaign.install_example(CAMPAIGN)
	var db := PackageDB.new()
	db.load_now()
	StatBlock.db = db
	RollTables.resolver = func(id: String) -> Dictionary: return db.resolve_ref("tables/" + id)
	RollTables.roller = Callable()
	RollTables.formula_roller = Callable()
	var confusion := db.resolve_ref("tables/confusion-behavior")
	_check(confusion.get("dice") == "d10" and confusion.rows.size() == 4, "the core Confusion table is loaded")

	# --- Rendering ----------------------------------------------------------------------------------
	var bb := Markdown.to_bbcode("The creature acts at random.\n\n![[tables/confusion-behavior]]\n\nAt the end of its turn...")
	_check(bb.contains("Roll d10") and bb.contains("2–6") and bb.contains("tablerow:confusion-behavior#1"), "an embed renders the table with ranges and a Roll button")
	_check(not bb.contains("![["), "no raw embed text left")
	var inline := Markdown.to_bbcode("Roll on this: ![[tables/confusion-behavior]] now.")
	_check(inline.contains("Roll d10"), "an embed inside a paragraph too")
	var missing := Markdown.to_bbcode("![[tables/no-such-table]]")
	_check(missing.contains("Missing table: tables/no-such-table"), "a missing table is a warning (%s)" % missing)
	var spell := db.resolve_ref("spells/confusion")
	_check(str(spell.get("description", "")).contains("![[tables/confusion-behavior]]"), "the spell embeds its table")
	_check(StatBlock.to_bbcode(spell).contains("Roll d10"), "...and its stat block shows it")
	_check(RollTables.dice_links("takes 2d10 acid damage, roll a d8") == "takes [2d10](roll:2d10) acid damage, roll a [d8](roll:d8)", "formulas in cells become roll links")
	_check(RollTables.dice_links("[[Fireball]] and [4d6](roll:4d6)") == "[[Fireball]] and [4d6](roll:4d6)", "existing links stay")

	# --- Rolling here (standalone compendium) ----------------------------------------------------------
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/standalone"))
	var elog := EventLog.open(ProjectSettings.globalize_path(DIR + "/standalone/events.jsonl"))
	RollTables.event_log = elog
	var changed := []
	RollTables.hub.changed.connect(func(id: String) -> void: changed.append(id))
	var all_rows := {}
	for i in 60:
		var res := RollTables.roll("confusion-behavior")
		var row := RollTables.row_for(confusion, int(res.value))
		_check_quiet(int(res.row) == row and int(res.value) >= 1 and int(res.value) <= 10, "roll %d lands on its row" % i)
		all_rows[int(res.row)] = true
	_check(all_rows.size() == 4, "every row comes up (%s)" % [all_rows.keys()])
	_check(changed.size() == 60 and changed[0] == "confusion-behavior", "views are told to re-render")
	var ev: Dictionary = elog.events.back()
	_check(ev.type == "dice.rolled" and ev.data.table == "tables/confusion-behavior" and ev.data.has("value") and ev.data.has("row") and ev.data.formula == "d10", "logged as dice.rolled with table, value and row (%s)" % ev.data)
	var after := RollTables.bbcode("confusion-behavior")
	_check(after.contains(RollTables.HIGHLIGHT.to_html()) and after.contains("Rolled [b]%d[/b]" % int(ev.data.value)), "the rolled row is highlighted, the result shown")
	RollTables.handle_meta("tablerow:confusion-behavior#2")
	_check(RollTables.results["confusion-behavior"].row == 2 and RollTables.bbcode("confusion-behavior").contains("Picked"), "clicking a row picks it")
	var count := elog.events.size()
	_check(RollTables.handle_meta("roll:2d10") and elog.events.size() == count + 1 and elog.events.back().data.formula == "2d10", "a formula link rolls it")
	_check(not RollTables.handle_meta("wiki:Fireball"), "other links are not ours")
	var gaps := {}
	for k: Variant in db.entries.get("tables", []):
		if not bool(k.get("complete", true)):
			gaps = k
	_check(not gaps.is_empty() and RollTables.bbcode(str(gaps.id)).contains("Gaps in this table"), "an incomplete table says so (%s)" % gaps.get("id"))
	RollTables.event_log = null

	# --- The compendium kind --------------------------------------------------------------------------
	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	root.add_child(screen)
	var book := Compendium.new()
	book.tabs_file = ""
	screen.add_child(book)
	await book.db.loaded
	await process_frame
	_check("tables" in book.db.kinds(), "tables is a kind in the book")
	_check(CardData.badge(confusion) == ["d10", "tan"] and CardData.subtitle(confusion) == "Rollable table, 4 rows", "card: die badge, row count")
	var view := book.open_tab(book.db.resolve_ref("tables/confusion-behavior"))
	var text := _texts(view)
	_check(text.contains("Roll d10") and text.contains("Confusion"), "full view: the table and its parent (%s)" % text.left(200))
	var link := "entry:5e-core-rules/spells/confusion"
	_check(_bbcode(view).contains(link), "a link back to the spell")
	book._follow(link, view.entry, true)
	_check(book.current_tab_key() == "5e-core-rules/spells/confusion", "the link opens the spell")
	var spell_view := book.open_view("5e-core-rules/spells/confusion")
	book._follow("tableroll:confusion-behavior", spell_view.entry, true)
	_check(_texts(book.open_view("5e-core-rules/spells/confusion")).contains("Rolled"), "Roll in the spell's view: it re-renders with the result")

	# --- At the table -------------------------------------------------------------------------------------
	var dm := _table("DM", "dm", true)
	var ann := _table("Ann", "ann", true)
	await process_frame
	dm.host(PORT)
	ann.join("127.0.0.1:%d" % PORT, "Ann")
	await _until(func() -> bool: return ann.my_pc == "pcs/aria")
	_check(dm.tables.has("confusion-behavior") and ann.tables.has("confusion-behavior"), "both sides know the tables")
	ann.roll_table("confusion-behavior")
	await _until(func() -> bool: return ann.rolls.size() == 1)
	var entry: Dictionary = ann.rolls[0] if not ann.rolls.is_empty() else {}
	_check(entry.get("table") == "confusion-behavior" and entry.has("value") and entry.has("row"), "Ann's table roll in the log (%s)" % entry)
	_check(dm.event_log.events.back().data.table == "tables/confusion-behavior" and dm.event_log.events.back().by == "ann", "the host logged it")
	_check(int(RollTables.results["confusion-behavior"].value) == int(entry.value), "the row is highlighted from the roll")
	_check(NetTable.roll_bbcode(entry).contains("→"), "the log shows the row text")
	dm.roll_table("confusion-behavior", true)
	dm.roll("1d4")
	await _until(func() -> bool: return ann.rolls.size() == 2)
	_check(ann.rolls.size() == 2 and not ann.rolls[1].has("table"), "Ann doesn't get the DM's hidden table roll")
	_check(dm.rolls.size() == 3 and dm.rolls[1].hidden, "the DM has it")

	print("roll tables: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _texts(view: Control) -> String:
	var out := ""
	for c in view.find_children("*", "RichTextLabel", true, false):
		out += (c as RichTextLabel).get_parsed_text()
	return out


func _bbcode(view: Control) -> String:
	var out := ""
	for c in view.find_children("*", "RichTextLabel", true, false):
		out += (c as RichTextLabel).text
	return out


func _table(branch: String, cache: String, ui := false) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
	t.auto_ui = ui
	t.campaign_dir = CAMPAIGN
	t.cache_dir = DIR.path_join("cache_" + cache)
	holder.add_child(t)
	return t


func _until(done: Callable, frames := 400) -> bool:
	for i in frames:
		if done.call():
			return true
		await process_frame
	return false


func _check_quiet(ok: bool, what: String) -> void:
	if not ok:
		_check(ok, what)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
