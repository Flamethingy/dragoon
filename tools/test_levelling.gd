extends SceneTree
## Headless check of levelling up and XP (TASK-71): XP tables and CR, HP (average / roll +
## CON), the plan (features, slots, ASI, subclass, multiclass), level.gained with the HP and
## subclass, ASI and spells as sheet.changed, XP awarded (and from a combat's defeated
## creatures), milestones as a world setting, and the dialog on the sheet.
## godot --headless --path . -s tools/test_levelling.gd

const PORT := 47816
const DIR := "user://test_levelling"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	_check(Rules.xp_for_level(2) == 300 and Rules.level_for_xp(299) == 1 and Rules.level_for_xp(900) == 3, "XP per level")
	_check(Rules.xp_of({"cr": 0.5}) == 100 and Rules.xp_of({"cr": "1/4"}) == 50 and Rules.xp_of({"cr": 1}) == 200 and Rules.xp_of({"cr": 2, "xp": 7}) == 7, "XP by CR")
	_check(Rules.hp_gain(8, 2) == 7 and Rules.hp_gain(10, -3, 1) == 1 and Rules.hp_gain(12, 1, 9) == 10, "HP: average 8 -> 5 + CON, at least 1, a roll")
	var s := {"stats": {"con": 14, "wis": 16}, "classes": [{"class": "classes/cleric", "level": 3}]}
	var plan := Rules.level_up_plan(s, "classes/cleric")
	_check(int(plan.to) == 4 and bool(plan.asi) and int(plan.hp_average) == 7 and bool(plan.caster), "cleric 3 -> 4: ASI, 1d8 avg 5 + 2 (%s)" % [plan])
	_check(plan.slots_before == [4, 2] and plan.slots_after == [4, 3], "slots 4/2 -> 4/3 (%s)" % [plan.slots_after])
	_check(bool(plan.subclass), "no domain yet: it can be chosen")
	var multi := Rules.level_up_plan(s, "fighter")
	_check(int(multi.from) == 0 and int(multi.to) == 1 and int(multi.total) == 4 and int(multi.hit_die) == 10 and bool(multi.subclass) == false, "multiclass: fighter 1 (%s)" % [multi])
	_check(bool(Rules.level_up_plan({"classes": [{"class": "classes/fighter", "level": 2}]}, "fighter").subclass), "fighter 3: choose the archetype")
	_check(bool(Rules.level_up_plan({"classes": [{"class": "classes/fighter", "level": 5}]}, "fighter").asi), "fighter 6: an extra ASI")
	var st := Replay.entity_state({"hp": 20, "classes": [{"class": "classes/fighter", "level": 2}]}, [
		{"type": "level.gained", "data": {"class": "classes/fighter", "level": 3, "hp_gain": 8, "subclass": "subclasses/champion"}},
		{"type": "xp.awarded", "data": {"xp": 450}}, {"type": "level.granted", "data": {}}])
	_check(int(st.hp) == 28 and int(st.hp_max_gain) == 8 and st.classes[0].subclass == "subclasses/champion" and int(st.xp) == 450 and int(st.level_ready) == 1, "Replay: HP, subclass, XP, milestones (%s)" % [st])

	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	tl.edit_entry("spells", {"id": "test-glow", "name": "Test Glow", "level": 2, "description": "It glows."})
	var borin := tl.entry(BORIN).duplicate(true)
	borin["classes"] = [{"class": "classes/cleric", "level": 3}]
	borin["stats"] = {"str": 14, "dex": 10, "con": 14, "int": 10, "wis": 16, "cha": 12}
	borin.erase("xp")
	tl.edit_entry("characters", borin)
	await process_frame
	var dm := _table("DM", "dm", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	await _until(func() -> bool: return dm.grid.tokens.has(BORIN) and dm.grid.tokens.has(CHIEF))
	var sheet := dm.sheet_for(Reveal.DM, BORIN)
	var hp_max := int(sheet._hp_max)
	var hp := int(sheet.hp)
	_check(sheet._level.level == 3 and not bool(sheet._level.ready) and sheet._level.next == 2700, "level 3, not ready (%s)" % [sheet._level])
	dm.award_xp([BORIN], 2700, "the bridge")
	sheet = dm.sheet_for(Reveal.DM, BORIN)
	_check(int(sheet.xp) == 2700 and bool(sheet._level.ready) and dm.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")).contains("+2700 XP · can level up")), "XP awarded: ready")
	_check(SheetPanel._resources(sheet).contains("[url=levelup]Level up[/url]") and SheetPanel._resources(sheet).contains("(ready)"), "the sheet offers Level up")

	# the dialog
	dm.open_sheet(BORIN, false)
	var panel: SheetPanel = dm._ui.sheet
	panel.ref = BORIN
	panel.sheet = sheet
	var dlg := panel.level_up_dialog()
	var cls := dlg.find_child("Class", true, false) as OptionButton
	_check(cls.get_item_text(0) == "Cleric 3 → 4" and cls.item_count >= 1, "the class to level (%s)" % cls.get_item_text(0))
	_check((dlg.find_child("Asi", true, false) as Control).visible and (dlg.find_child("Plan", true, false) as RichTextLabel).text.contains("Spell slots"), "level 4: ASI and new slots shown")
	var sub := dlg.find_child("Subclass", true, false) as OptionButton
	_check(sub.visible and sub.selected == 0 and sub.get_item_text(0).contains("choose later") and sub.item_count > 1, "a domain to choose, none picked for the player")
	(dlg.find_child("AsiA", true, false) as OptionButton).select(5)  # +1 WIS
	(dlg.find_child("AsiB", true, false) as OptionButton).select(5)
	dlg.confirmed.emit()
	sheet = dm.sheet_for(Reveal.DM, BORIN)
	_check(Rules.class_level(sheet, "cleric") == 4 and int(sheet._hp_max) == hp_max + 7 and int(sheet.hp) == hp + 7, "cleric 4, +7 HP (average) to max and current (%d -> %d)" % [hp_max, int(sheet._hp_max)])
	_check(int(sheet.stats.wis) == 18, "WIS 16 -> 18")
	_check(dm.event_log.events.any(func(e: Dictionary) -> bool: return e.type == "level.gained" and e.data.get("hp_how") == "average") and dm.event_log.events.any(func(e: Dictionary) -> bool: return e.type == "sheet.changed" and e.data.path == "stats.wis"), "all as events")
	_check(dm.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")).begins_with("reaches Cleric 4 (+7 HP")), "posted for the table")
	_check(not bool(sheet._level.ready), "the XP is used up for now")

	# rolling HP, spells, without the XP: allowed, the DM told
	dm.level_up(BORIN, {"class": "classes/cleric", "hp": "roll", "spells": ["spells/test-glow"]})
	sheet = dm.sheet_for(Reveal.DM, BORIN)
	_check(Rules.class_level(sheet, "cleric") == 5 and "spells/test-glow" in (sheet.spells as Array), "level 5 with a new spell")
	_check(dm.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")).contains("levels up without the XP")), "not enough XP: the DM is told")
	var gained: Array = dm.event_log.events.filter(func(e: Dictionary) -> bool: return e.type == "level.gained")
	_check(str(gained[-1].data.hp_how).begins_with("rolled") and int(gained[-1].data.hp_gain) >= 3 and int(gained[-1].data.hp_gain) <= 10, "rolled 1d8 + 2")

	# milestones
	var rs := dm.rules_settings().duplicate(true)
	rs["house_rules"] = {"levelling": "milestone"}
	dm.set_rules_settings(rs)
	_check(not bool(dm.sheet_for(Reveal.DM, BORIN)._level.ready), "milestone: not ready")
	dm.grant_level([BORIN])
	_check(bool(dm.sheet_for(Reveal.DM, BORIN)._level.ready) and not SheetPanel._resources(dm.sheet_for(Reveal.DM, BORIN)).contains("XP "), "a milestone: ready, no XP shown")
	rs["house_rules"] = {"levelling": "xp"}
	dm.set_rules_settings(rs)

	# encounter XP: the defeated chief's XP for the party
	var xp_before := int(dm.sheet_for(Reveal.DM, BORIN).xp)
	dm.start_combat()
	dm.change_hp(CHIEF, -999, "test")
	dm.end_combat()
	var chief_xp := Rules.xp_of(dm.sheet_for(Reveal.DM, CHIEF))
	var party := dm.event_log.events.filter(func(e: Dictionary) -> bool: return e.type == "xp.awarded" and str(e.data.get("reason", "")).begins_with("defeated"))
	_check(chief_xp > 0 and party.size() >= 1 and int(dm.sheet_for(Reveal.DM, BORIN).xp) == xp_before + chief_xp / party.size(), "the chief's %d XP shared by %d after the fight (%d -> %d)" % [chief_xp, party.size(), xp_before, int(dm.sheet_for(Reveal.DM, BORIN).xp)])
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("levelling: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


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
