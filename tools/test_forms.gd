extends SceneTree
## Headless check of summons, Wild Shape and Polymorph (TASK-74): Wild Shape CR limits, the
## beast's stats over the character's (Wild Shape keeps INT/WIS/CHA and features, Polymorph
## not), the beast's attacks, its own HP with damage carried over at 0 (2014), temp HP (2024),
## a summon owned by the caster's player, sorted into the combat and gone when concentration
## ends or at 0 HP, and the pickers on the sheet.
## godot --headless --path . -s tools/test_forms.gd

const PORT := 47818
const DIR := "user://test_forms"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	_check(Rules.wild_shape_cr({"classes": [{"class": "classes/druid", "level": 1}]}) == 0.0 and Rules.wild_shape_cr({"classes": [{"class": "classes/druid", "level": 4}]}) == 0.5
		and Rules.wild_shape_cr({"classes": [{"class": "classes/druid", "level": 9, "subclass": "subclasses/circle-of-the-moon"}]}) == 3.0, "Wild Shape CR limits")
	_check(Rules.cr_of({"cr": "1/4"}) == 0.25 and Rules.cr_of({"cr": 2}) == 2.0, "CR as a number")
	var own := {"stats": {"str": 10, "dex": 12, "con": 13, "int": 14, "wis": 18, "cha": 9}, "features": ["wild-shape"], "spells": ["spells/x"], "ac": 13}
	var bear := {"name": "Bear", "stats": {"str": 19, "dex": 10, "con": 16, "int": 2, "wis": 13, "cha": 7}, "ac": 11, "speed": {"walk": 12}, "actions": ["bite"]}
	var ws := Rules.form_sheet(own, bear, "wild_shape")
	_check(ws.stats.str == 19 and ws.stats.wis == 18 and ws.ac == 11 and ws.features == ["wild-shape"] and ws.actions == ["bite"], "Wild Shape: STR from the bear, WIS and features kept")
	var poly := Rules.form_sheet(own, bear, "polymorph")
	_check(poly.stats.wis == 13 and (poly.features as Array).is_empty() and (poly.spells as Array).is_empty(), "Polymorph: everything from the bear")

	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	tl.edit_entry("features", {"id": "test-bite", "name": "Bite", "attack": {"kind": "Melee Weapon Attack", "to_hit": 6, "damage": [{"dice": "2d8+4", "type": "piercing"}], "range": "1.5 m"}})
	tl.edit_entry("creatures", {"id": "test-bear", "name": "Test Bear", "type": "Beast", "cr": "1", "hp": 34, "ac": 11, "stats": {"str": 19, "dex": 10, "con": 16, "int": 2, "wis": 13, "cha": 7}, "actions": ["test-bite"]})
	tl.edit_entry("creatures", {"id": "test-wolf", "name": "Test Wolf", "type": "Beast", "cr": "1/4", "hp": 11, "ac": 13, "stats": {"str": 12, "dex": 15, "con": 12, "int": 3, "wis": 12, "cha": 6}})
	tl.edit_entry("spells", {"id": "test-call", "name": "Test Call", "level": 3, "concentration": true, "casting_time": "1 action", "description": "You call a beast."})
	var borin := tl.entry(BORIN).duplicate(true)
	borin["classes"] = [{"class": "classes/druid", "level": 8}]
	borin["stats"] = {"str": 10, "dex": 12, "con": 14, "int": 12, "wis": 18, "cha": 10}
	borin["spells"] = ["spells/test-call"]
	tl.edit_entry("characters", borin)
	await process_frame
	var dm := _table("DM", "dm", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	await _until(func() -> bool: return dm.grid.tokens.has(BORIN) and dm.grid.tokens.has(CHIEF))
	var hp := int(dm.sheet_for(Reveal.DM, BORIN).hp)

	# Wild Shape (2014): the bear's HP, its bite
	dm.assume_form(BORIN, "creatures/test-bear")
	var s := dm.sheet_for(Reveal.DM, BORIN)
	_check(s.get("_form") is Dictionary and int(s.hp) == 34 and int(s._hp_max) == 34 and int(s.stats.str) == 19 and int(s.stats.wis) == 18, "Borin is a bear: 34 HP, STR 19, WIS 18 (%s)" % [s.get("_form")])
	_check("Bite" in (s._attacks as Array) and not Dice.attack_of(s, "Bite", dm._features()).is_empty(), "the bite is an attack (%s)" % [s._attacks])
	_check(dm.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")).begins_with("becomes Test Bear (Wild Shape)")), "the table sees it")
	_check(dm.event_log.events.any(func(e: Dictionary) -> bool: return e.type == "resource.used" and e.data.resource == "wild_shape"), "a Wild Shape use spent")
	_check(SheetPanel._resources(s).contains("Back to own shape") and SheetPanel._resources(s).contains("own HP %d" % hp), "the sheet shows the shape")
	dm.change_hp(BORIN, -30, "test")
	_check(int(dm.sheet_for(Reveal.DM, BORIN).hp) == 4 and int(dm.sheet_for(Reveal.DM, BORIN).get("_form", {}).get("own", {}).get("hp", 0)) == hp, "damage goes to the bear")
	dm.change_hp(BORIN, -10, "test")
	s = dm.sheet_for(Reveal.DM, BORIN)
	_check(not s.get("_form") is Dictionary and int(s.hp) == hp - 6, "0 HP: back as Borin, 6 carried over (%d -> %d)" % [hp, int(s.hp)])
	dm.assume_form(BORIN, "creatures/test-bear")
	dm.end_form(BORIN)
	_check(not dm.sheet_for(Reveal.DM, BORIN).get("_form") is Dictionary, "back by hand")
	var lines := dm.rolls.size()
	borin["classes"] = [{"class": "classes/druid", "level": 2}]
	dm.timeline.edit_entry("characters", borin)
	await process_frame
	dm.assume_form(BORIN, "creatures/test-bear")
	_check(dm.rolls.slice(lines).any(func(r: Dictionary) -> bool: return str(r.get("text", "")).contains("Wild Shape into CR 1 (the limit is 1/4)")), "druid 2 into a CR 1 bear: warned, not blocked")
	dm.end_form(BORIN)
	borin["classes"] = [{"class": "classes/druid", "level": 8}]
	dm.timeline.edit_entry("characters", borin)

	# 2024: temporary HP instead
	var rs := dm.rules_settings().duplicate(true)
	rs["edition"] = "2024"
	dm.set_rules_settings(rs)
	await process_frame
	dm.assume_form(BORIN, "creatures/test-wolf")
	s = dm.sheet_for(Reveal.DM, BORIN)
	_check(s.get("_form") is Dictionary and not (s._form as Dictionary).has("hp") and int(s.get("temp_hp", 0)) == 8 and int(s.hp) == hp - 6, "2024: own HP, 8 temporary HP (druid 8)")
	dm.end_form(BORIN)
	rs["edition"] = "2014"
	dm.set_rules_settings(rs)

	# Polymorph on the chief, ended with the caster's concentration
	dm._handle_concentrate(1, BORIN, "spells/test-call", "Test Call")
	dm.assume_form(CHIEF, "creatures/test-wolf", "polymorph", {"caster": BORIN, "spell": "spells/test-call"})
	_check(str(dm.sheet_for(Reveal.DM, CHIEF).get("_form", {}).get("kind", "")) == "polymorph" and int(dm.sheet_for(Reveal.DM, CHIEF).stats.int) == 3, "the chief is a wolf, INT 3")

	# a summon
	dm.start_combat()
	dm.summon(BORIN, "creatures/test-wolf", "spells/test-call")
	var mine := dm.summons_of(BORIN)
	_check(mine.size() == 1 and dm.grid.tokens.has(str(mine[0])), "a wolf next to Borin (%s)" % [mine])
	var wolf := str(mine[0]) if not mine.is_empty() else ""
	_check(dm.owners.get(wolf, []) == dm.owners.get(BORIN, []) and not (dm.owners.get(BORIN, []) as Array).is_empty(), "owned by Borin's player (%s)" % [dm.owners.get(wolf)])
	_check(dm.combat_state().order.any(func(o: Dictionary) -> bool: return o.entity == wolf), "sorted into the combat")
	_check(str(dm.sheet_for(Reveal.DM, wolf).get("attitude", "")) == "friendly" and dm.timeline.name_of(wolf) == "Test Wolf (Borin Stoneshield)", "on Borin's side, named for him")
	dm.end_concentration(BORIN, "test")
	_check(not dm.grid.tokens.has(wolf) and not dm.combat_state().order.any(func(o: Dictionary) -> bool: return o.entity == wolf), "concentration ends: the wolf is gone, out of the order")
	_check(not dm.sheet_for(Reveal.DM, CHIEF).get("_form") is Dictionary, "and the chief's Polymorph ends")
	dm.summon(BORIN, "creatures/test-wolf")
	wolf = str(dm.summons_of(BORIN)[0])
	dm.change_hp(wolf, -50, "test")
	_check(not dm.grid.tokens.has(wolf), "a summon at 0 HP vanishes")

	# the pickers
	dm.open_sheet(BORIN, false)
	var panel: SheetPanel = dm._ui.sheet
	panel.ref = BORIN
	panel.sheet = dm.sheet_for(Reveal.DM, BORIN)
	var pick := panel.creature_picker("wild_shape")
	var list := pick.find_child("Creatures", true, false) as ItemList
	var names := []
	for i in list.item_count:
		names.append(list.get_item_text(i))
	_check(names.any(func(n: String) -> bool: return n.begins_with("Test Bear (CR 1)")) and names.any(func(n: String) -> bool: return n.begins_with("Test Wolf")), "Wild Shape: beasts up to CR 1 (%d)" % names.size())
	(pick.find_child("Filter", true, false) as LineEdit).text_changed.emit("test wolf")
	list.select(0)
	pick.confirmed.emit()
	_check(str(dm.sheet_for(Reveal.DM, BORIN).get("_form", {}).get("creature", "")) == "creatures/test-wolf", "picked: a wolf")
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("forms: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
