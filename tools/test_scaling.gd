extends SceneTree
## Headless check of upcasting and cantrip scaling (TASK-68): a save spell's dice per slot
## above its level (8d6 at 3 -> 10d6 at 5), a cantrip's dice by the caster's level (1d10 ->
## 2d10 at level 5), extra targets noted, scaling from effects or the text, and the roll
## cards showing what was added.
## godot --headless --path . -s tools/test_scaling.gd

const PORT := 47813
const DIR := "user://test_scaling"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	var lvl1 := {"classes": [{"class": "classes/cleric", "level": 1}]}
	var lvl5 := {"classes": [{"class": "classes/cleric", "level": 5}]}
	var lvl11 := {"classes": [{"class": "classes/cleric", "level": 11}]}
	var fire := [{"dice": "8d6", "type": "fire"}]
	var sc := Rules.scaled(fire, {"per_slot": "1d6", "above": 3}, 3, 5, lvl5)
	_check(sc.damage[0].dice == "10d6" and sc.note == "+2d6, slot 5", "8d6 at slot 5: 10d6 (%s)" % [sc])
	_check(Rules.scaled(fire, {"per_slot": "1d6", "above": 3}, 3, 3, lvl5).note == "" and fire[0].dice == "8d6", "at its own level: nothing, the input untouched")
	sc = Rules.scaled([{"dice": "1d8+3", "type": ""}], {"per_slot": "1d8", "above": 1}, 1, 3, lvl5)
	_check(sc.damage[0].dice == "3d8+3", "a heal keeps its modifier (%s)" % [sc.damage])
	sc = Rules.scaled([{"dice": "3d4", "type": "force"}], {"per_slot": "1d6", "above": 1}, 1, 2, lvl5)
	_check(sc.damage[0].dice == "3d4+1d6", "another die is added on (%s)" % [sc.damage])
	_check(Rules.scaled([{"dice": "1d10", "type": "fire"}], {"cantrip": "1d10"}, 0, 0, lvl1).damage[0].dice == "1d10", "a cantrip at level 1: 1d10")
	sc = Rules.scaled([{"dice": "1d10", "type": "fire"}], {"cantrip": "1d10"}, 0, 0, lvl5)
	_check(sc.damage[0].dice == "2d10" and sc.note == "2d10, level 5", "at level 5: 2d10 (%s)" % [sc])
	_check(Rules.scaled([{"dice": "1d10", "type": "fire"}], {"cantrip": "1d10"}, 0, 0, lvl11).damage[0].dice == "3d10", "at level 11: 3d10")
	sc = Rules.scaled([], {"targets_per_slot": 1, "above": 1}, 1, 3, lvl5)
	_check(sc.targets == 2 and sc.note == "+2 targets, slot 3", "extra targets are noted (%s)" % [sc])
	_check(Rules.scaling_of({"level": 3, "description": "Boom.\n\n**At Higher Levels.** When you cast this spell using a spell slot of 4th level or higher, the damage increases by 1d6 for each slot level above 3rd."}) == {"per_slot": "1d6", "above": 3}, "scaling from the text")
	_check(Rules.scaling_of({"level": 3, "effects": [{"save": {"ability": "dex"}, "scaling": {"per_slot": "2d6", "above": 3}}]}).per_slot == "2d6", "effects win")

	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	tl.edit_entry("spells", {"id": "test-blast", "name": "Test Blast", "level": 1, "casting_time": "1 action",
		"description": "Each creature must make a Dexterity saving throw, taking 2d6 thunder damage on a failed save, or half as much damage on a successful one.\n\n**At Higher Levels.** When you cast this spell using a spell slot of 2nd level or higher, the damage increases by 1d6 for each slot level above 1st."})
	tl.edit_entry("spells", {"id": "test-bolt", "name": "Test Bolt", "level": 0, "casting_time": "1 action",
		"description": "Make a ranged spell attack against the target. On a hit, the target takes 1d10 fire damage.\n\nThis spell's damage increases by 1d10 when you reach 5th level (2d10), 11th level (3d10), and 17th level (4d10)."})
	var borin := tl.entry(BORIN).duplicate(true)
	borin["spells"] = ["spells/test-blast", "spells/test-bolt"]
	borin["classes"] = [{"class": "classes/cleric", "level": 5}]
	tl.edit_entry("characters", borin)
	await process_frame
	var dm := _table("DM", "dm", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	await _until(func() -> bool: return dm.grid.tokens.has(BORIN) and dm.grid.tokens.has(CHIEF))
	dm.open_sheet(BORIN, false)

	# a save spell upcast to 3: 2d6 + 2d6
	dm.cast(BORIN, "spells/test-blast", 3)
	dm._ui._toggle_target(CHIEF)
	dm._ui.roll_attack()
	var saves: Array = dm.rolls.filter(func(r: Dictionary) -> bool: return r.get("save") is Dictionary and str(r.save.name) == "Test Blast")
	_check(saves.size() == 1, "Test Blast rolled")
	if saves.size() == 1:
		var s: Dictionary = saves[0].save
		_check(str(s.note) == "+2d6, slot 3" and str((s.damage as Array)[0].get("formula", (s.damage as Array)[0].get("dice", ""))).begins_with("4d6"), "4d6 at slot 3 (%s)" % [s.damage])
		_check(NetTable.roll_bbcode(saves[0]).contains("+2d6, slot 3"), "the card shows it")

	# a cantrip attack at level 5: 2d10
	dm.cast(BORIN, "spells/test-bolt")
	dm._ui._toggle_target(CHIEF)
	dm._ui.roll_attack()
	var atks: Array = dm.rolls.filter(func(r: Dictionary) -> bool: return r.get("attack") is Dictionary and str(r.attack.get("name", "")) == "Test Bolt")
	_check(atks.size() == 1, "Test Bolt rolled")
	if atks.size() == 1:
		_check(str(atks[0].attack.note) == "2d10, level 5", "a level 5 cleric's cantrip: 2d10 (%s)" % [atks[0].attack])
		_check(NetTable.roll_bbcode(atks[0]).contains("2d10, level 5"), "the card shows it")
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("scaling: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
