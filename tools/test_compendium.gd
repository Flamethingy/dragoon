extends SceneTree
## Headless check of the compendium data side: loads every package, formats every entry
## (catches crashes on odd data) and resolves a few wikilinks.
## godot --headless --path . -s tools/test_compendium.gd

var _failed := 0


func _init() -> void:
	var db := PackageDB.new()
	StatBlock.db = db
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
	var missing := 0
	for m: Dictionary in db.entries.get("monsters", []):
		for k in PackageDB.FEATURE_LISTS:
			for f: Dictionary in db.features_of(m, k):
				if f.get("_missing", false):
					missing += 1
					if missing <= 5:
						printerr("  missing feature %s in %s/%s" % [f.name, m._package, m.id])
	print("monster feature ids: %d missing" % missing)
	_check(missing == 0, "all feature ids resolve")
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
	var goblin := db.get_entry("5e-core-rules", "monsters", "goblin")
	bb = StatBlock.to_bbcode(goblin)
	print("goblin: ", goblin.get("actions"))
	for part in ["Scimitar", "Shortbow", "Nimble Escape"]:
		_check(bb.contains(part), "Goblin has '%s'" % part)
	var lord: Dictionary = db.entries["monsters"].filter(func(m: Dictionary) -> bool: return m._package == "tome-of-beasts-3" and m._key == "bone lord").front()
	bb = StatBlock.to_bbcode(lord)
	print("bone lord legendary_intro: ", str(lord.get("legendary_intro", "")).left(60))
	_check(bb.contains("Legendary Actions") and not bb.contains("Missing feature"), "Bone Lord legendary actions resolve")
	var with_intro: Dictionary = db.entries["monsters"].filter(func(m: Dictionary) -> bool: return str(m.get("legendary_intro", "")) != "").front()
	_check(StatBlock.to_bbcode(with_intro).contains(Markdown.to_bbcode(with_intro.legendary_intro).left(30)), "legendary_intro shown (%s)" % with_intro.name)
	var bow := db.feature("5e-core-rules", "shortbow")
	_check(StatBlock.to_bbcode(bow).contains("[url=entry:5e-core-rules/monsters/goblin]"), "Shortbow lists goblin in used_by")
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
