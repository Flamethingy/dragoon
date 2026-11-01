extends SceneTree
## Headless check of the compendium data side: loads every package, formats every entry
## (catches crashes on odd data) and resolves a few wikilinks.
## godot --headless --path . -s tools/test_compendium.gd

var _failed := 0


func _init() -> void:
	var db := PackageDB.new()
	db.load_async()
	await db.loaded
	print("loaded %d entries, %d packages in %d ms (%d problems)" % [db.count(), db.packages.size(), db.load_msec, db.errors.size()])
	for e in db.errors:
		printerr("  ", e)
	_check(db.count() > 4000, "more than 4000 entries")

	var started := Time.get_ticks_msec()
	var formatted := 0
	var links := 0
	var resolved := 0
	var re := RegEx.create_from_string("\\[url=wiki:([^#\\]]*)")
	for kind: String in db.entries:
		for e: Dictionary in db.entries[kind]:
			var bb := StatBlock.to_bbcode(e)
			formatted += 1
			if bb.is_empty():
				_check(false, "empty detail for %s/%s" % [kind, e.get("id")])
			for m in re.search_all(bb):
				if m.get_string(1) == "":
					continue
				links += 1
				if not db.resolve(m.get_string(1), e["_package"]).is_empty():
					resolved += 1
	print("formatted %d entries in %d ms; %d wikilinks, %d resolve to an entry" % [formatted, Time.get_ticks_msec() - started, links, resolved])

	var aboleth := db.resolve("Aboleth")
	_check(aboleth.get("_kind") == "monsters", "Aboleth is a monster")
	var bb := StatBlock.to_bbcode(aboleth)
	for part in ["Armor Class", "Hit Points", "STR", "21 (+5)", "Challenge", "10 (5,900 XP)", "Tentacle", "Legendary Actions"]:
		_check(bb.contains(part), "Aboleth block has '%s'" % part)
	var arrow := db.resolve("Acid Arrow")
	bb = StatBlock.to_bbcode(arrow)
	for part in ["2nd-level evocation", "Casting Time", "Range", "27 m", "V, S, M (", "Duration", "Instantaneous"]:
		_check(bb.contains(part), "Acid Arrow has '%s'" % part)
	_check(Markdown.to_bbcode("see [[Barbarian#Rage\\|Rage]]").contains("[url=wiki:Barbarian#Rage]"), "escaped-pipe wikilink")
	_check(Markdown.to_bbcode("[[Fireball]]").contains("[url=wiki:Fireball]"), "plain wikilink")
	_check(db.resolve("barbarian").get("_kind") == "classes", "Barbarian resolves to the class")

	print("compendium: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
