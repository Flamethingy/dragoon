extends SceneTree
## Headless check of the dice (TASK-12): formulas, rolls by name from sheet stats (skills,
## saves, abilities, initiative, attacks, advantage), the shared roll log (host rolls,
## dice.rolled events, everyone sees it) and the DM's hidden rolls.
## godot --headless --path . -s tools/test_dice.gd

const PORT := 47821
const ADDRESS := "127.0.0.1:47821"
const DIR := "user://test_dice"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"

var _failed := 0


func _init() -> void:
	# --- Formulas -------------------------------------------------------------------------------
	_check(Dice.parse("2d6+3").size() == 2 and Dice.parse("d20").size() == 1 and Dice.parse("4d6kh3")[0].keep == 3, "formulas parse")
	for bad in ["", "abc", "2d", "d0", "2d6+", "1000d6", "2d6++3", "roll perception"]:
		_check(not Dice.is_formula(bad), "'%s' is no formula" % bad)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ok_range := true
	for i in 300:
		var r := Dice.roll("2d6+3", rng)
		ok_range = ok_range and int(r.total) >= 5 and int(r.total) <= 15 and r.dice[0].size() == 2
	_check(ok_range, "2d6+3 stays in 5..15")
	var r4 := Dice.roll("4d6kh3", rng)
	var four: Array = r4.dice[0].duplicate()
	four.sort()
	_check(int(r4.total) == int(four[1]) + int(four[2]) + int(four[3]), "4d6kh3 keeps the highest three (%s)" % r4.text)
	var neg := Dice.roll("1d4-10", rng)
	_check(int(neg.total) < 0 and str(neg.text).contains("- 10"), "minus works (%s)" % neg.text)
	var crits := {}
	for i in 400:
		crits[Dice.roll("1d20+2", rng).crit] = true
	_check(crits.has("20") and crits.has("1"), "natural 20 and 1 are marked")

	# --- By name, from a sheet ------------------------------------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var camp := Timeline.new(ProjectSettings.globalize_path(TIMELINE), null)
	var aria := camp.entry("characters/aria")
	var feats := camp.entries("features")
	_check(_f(aria, "Perception", feats) == ["1d20+4"], "Perception: the sheet's +4")
	_check(_f(aria, "roll perception", feats) == ["1d20+4"], "'roll perception'")
	_check(_f(aria, "Athletics", feats) == ["1d20"], "Athletics not listed: STR mod +0")
	_check(_f(aria, "Dex save", feats) == ["1d20+5"] and _f(aria, "dexterity saving throw", feats) == ["1d20+5"], "Dex save +5")
	_check(_f(aria, "wis save", feats) == ["1d20+2"], "Wis save not listed: WIS mod +2")
	_check(_f(aria, "Dex", feats) == ["1d20+3"] and _f(aria, "strength check", feats) == ["1d20"], "ability checks")
	_check(_f(aria, "initiative", feats) == ["1d20+3"], "initiative = DEX")
	_check(_f(aria, "stealth with advantage", feats) == ["2d20kh1+5"] and _f(aria, "stealth dis", feats) == ["2d20kl1+5"], "advantage / disadvantage")
	_check(_f(aria, "attack with Longbow", feats) == ["1d20+5", "1d8+3"] and _f(aria, "longbow", feats) == ["1d20+5", "1d8+3"], "attack: to hit and damage")
	_check(_f(aria, "sleight of hand", feats) == ["1d20+3"], "multi-word skills")
	_check(_f(camp.entry("creatures/goblin-chief"), "scimitar", feats) == ["1d20+4", "1d6+2"], "monster actions")
	_check(_f(aria, "dance", feats).is_empty(), "unknown names: nothing")

	# --- At the table -------------------------------------------------------------------------------
	await process_frame
	var dm := _table("DM", "dm", true)
	var ann := _table("Ann", "ann", true)
	await process_frame
	dm.host(PORT)
	ann.join(ADDRESS, "Ann")
	await _until(func() -> bool: return ann.my_pc == "characters/aria")
	ann.roll("Perception")
	await _until(func() -> bool: return ann.rolls.size() == 1)
	var entry: Dictionary = ann.rolls[0] if not ann.rolls.is_empty() else {}
	_check(entry.get("who") == "Aria Windrunner" and entry.get("by") == "ann" and entry.results[0].label == "Perception" and entry.results[0].formula == "1d20+4", "Ann rolls Perception for Aria (%s)" % entry)
	_check(dm.rolls.size() == 1 and dm.event_log.events.back().type == "dice.rolled", "the DM sees it, logged as dice.rolled")
	var ev: Dictionary = dm.event_log.events.back()
	_check(ev.entity == "characters/aria" and ev.data.roll == "Perception" and ev.data.formula == "1d20+4" and int(ev.data.result) == int(entry.results[0].total), "event data per doc-1 (%s)" % ev.data)
	var ui: TableUI = ann._ui
	_check(ui._rolls_text.get_parsed_text().contains("Perception") and ui._rolls_text.get_parsed_text().contains("Aria"), "Ann's roll log shows it")

	ann.roll("2d6+3")
	await _until(func() -> bool: return ann.rolls.size() == 2)
	_check(ann.rolls.size() == 2 and ann.rolls[1].results[0].formula == "2d6+3", "a plain formula")
	ann.roll("attack with longbow")
	await _until(func() -> bool: return ann.rolls.size() == 3)
	_check(ann.rolls.size() == 3 and ann.rolls[2].results.size() == 2, "attack: to hit + damage in one roll")
	ann.roll("fly to the moon")
	await _until(func() -> bool: return ann.status.contains("Can't roll"))
	_check(ann.status.contains("don't know how to roll") and ann.rolls.size() == 3, "unknown names are refused")
	ann.roll("perception", "creatures/goblin-chief")
	await _until(func() -> bool: return ann.status.contains("not your sheet"))
	_check(ann.status.contains("not your sheet"), "players roll only for their own PC")

	dm.roll("stealth", "creatures/goblin-chief", true)
	_check(dm.rolls.size() == 4 and dm.rolls[3].hidden and dm.rolls[3].results[0].formula == "1d20+6", "the DM rolls hidden for the chief")
	dm.roll("1d20")
	await _until(func() -> bool: return ann.rolls.size() == 4)
	_check(ann.rolls.size() == 4 and not ann.rolls.any(func(r: Dictionary) -> bool: return r.hidden), "Ann never gets the hidden roll")
	_check(not ui._rolls_text.get_parsed_text().contains("Stealth"), "...nor sees it in the log")

	# The roll box and sheet links.
	ann.open_sheet("characters/aria")
	await _until(func() -> bool: return ui.sheet.visible and ui.sheet.ref == "characters/aria")
	_check(ui.roll_ref() == "characters/aria", "the roll box rolls for the open sheet")
	_check(ui.sheet._body.get_parsed_text().contains("Longbow"), "the sheet lists its attacks")
	ui.sheet._on_meta("roll:dex save")
	await _until(func() -> bool: return ann.rolls.size() == 5)
	_check(ann.rolls.size() == 5 and ann.rolls[4].results[0].label == "DEX save", "clicking a save on the sheet rolls it")
	ui.roll_edit.text = "survival adv"
	ui._submit_roll()
	await _until(func() -> bool: return ann.rolls.size() == 6)
	_check(ann.rolls.size() == 6 and ann.rolls[5].results[0].formula == "2d20kh1+4", "the roll box")

	# A late joiner and a restart see this session's rolls (not the hidden one).
	var dm2 := _table("DM2", "dm2")
	await process_frame
	dm.multiplayer.multiplayer_peer.close()
	dm2.host(PORT + 1)
	_check(dm2.rolls.size() == 7, "a restarted host has the session's rolls (%d)" % dm2.rolls.size())
	var ann2 := _table("Ann2", "ann2")
	await process_frame
	ann2.join("127.0.0.1:%d" % (PORT + 1), "Ann")
	await _until(func() -> bool: return ann2.rolls.size() == 6)
	_check(ann2.rolls.size() == 6, "a joining player gets them, without the hidden one (%d)" % ann2.rolls.size())

	print("dice: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _f(sheet: Dictionary, query: String, feats: Dictionary) -> Array:
	return Dice.resolve(sheet, query, feats).map(func(x: Dictionary) -> String: return str(x.formula))


func _table(branch: String, cache: String, ui := false) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
	t.auto_ui = ui
	t.timeline_dir = TIMELINE
	t.cache_dir = DIR.path_join("cache_" + cache)
	holder.add_child(t)
	return t


func _until(done: Callable, frames := 400) -> bool:
	for i in frames:
		if done.call():
			return true
		await process_frame
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
