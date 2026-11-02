extends SceneTree
## Headless check of class features as entries (TASK-69): a class page split at its feature
## headings, levels from its level table (wiki links) or the text, subclass features (one with
## no level comes with the subclass), uses and class resources linked, and a character getting
## the features of its classes and levels (plus its own), shown by name, not stored.
## godot --headless --path . -s tools/test_class_features.gd

const PORT := 47814
const DIR := "user://test_class_features"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const BORIN := "characters/borin"

const PAGE := """A fighter.

| Level | Proficiency Bonus | Features |
| ----- | ----------------- | -------- |
| 1st   | +2 | [[Tester#Second Wind\\|Second Wind]], [[Tester#Steady Hands\\|Steady Hands]] |
| 2nd   | +2 | [[Tester#Action Surge\\|Action Surge]] |
| 3rd   | +2 | Martial Path |
| 9th   | +4 | [[Tester#Iron Will\\|Iron Will]] |

#### A Life of Steel
Flavour text.

### Equipment
A sword.

### Second Wind
You can use a bonus action to regain hit points. Once you use this feature, you must finish a short or long rest before you can use it again.

### Steady Hands
You don't drop things.

#### Options
A sub-heading stays in the text.

### Action Surge
Take one additional action.

### Martial Path
Choose a path.

### Iron Will
You can reroll a saving throw. Once you do, you can't use it again until you finish a long rest.
"""

const SUB := """The path of the test.

##### Path Tenets
Be tested.

##### Keen Eye
Starting when you choose this path at 3rd level, you see far.

##### Sharper Eye
Beginning at 7th level, you see farther.
"""

var _failed := 0


func _init() -> void:
	var table := ClassFeatures.levels_from_table(PAGE)
	_check(table.get("secondwind") == 1 and table.get("actionsurge") == 2 and table.get("martialpath") == 3 and table.get("ironwill") == 9, "the level table (%s)" % [table])
	_check(ClassFeatures.level_from_text("Beginning at 7th level, you") == 7 and ClassFeatures.level_from_text("No level.") == 0, "a level in the text")
	var feats := ClassFeatures.split({"description": PAGE, "source": "Test"}, "fighter")
	var names := feats.map(func(f: Dictionary) -> String: return str(f.name))
	_check(names == ["Second Wind", "Steady Hands", "Action Surge", "Martial Path", "Iron Will"], "the features, not the flavour or equipment (%s)" % [names])
	var by := {}
	for f: Dictionary in feats:
		by[str(f.name)] = f
	_check(str(by["Steady Hands"].text).contains("A sub-heading stays"), "sub-headings stay in their feature")
	_check(by["Second Wind"].get("resource") == "second_wind" and by["Action Surge"].get("resource") == "action_surge", "class resources are linked (dragoon-core)")
	_check(by["Iron Will"].get("uses") == "1/Day" and Rules.feature_uses(by["Iron Will"]) == {"max": 1, "reset": "long"}, "uses from the text")
	_check(str(by["Second Wind"].id) == "fighter-second-wind" and by["Second Wind"].kind == "class" and int(by["Iron Will"].level) == 9, "ids, kind and levels")
	var sub := ClassFeatures.split({"description": SUB}, "fighter", "path-of-testing")
	var sub_by := {}
	for f: Dictionary in sub:
		sub_by[str(f.name)] = f
	_check(sub.size() == 3 and int(sub_by["Keen Eye"].level) == 3 and int(sub_by["Sharper Eye"].level) == 7, "subclass levels from the text (%s)" % [sub.map(func(f: Dictionary) -> String: return "%s %d" % [f.name, f.level])])
	_check(int(sub_by["Path Tenets"].level) == 3 and bool(sub_by["Path Tenets"].get("level_guessed", false)), "no level: it comes with the subclass")
	var index := ClassFeatures.index_of(feats + sub)
	var lvl3 := ClassFeatures.granted({"classes": [{"class": "classes/fighter", "level": 3, "subclass": "subclasses/path-of-testing"}]}, index).map(func(f: Dictionary) -> String: return str(f.name))
	_check(lvl3 == ["Second Wind", "Steady Hands", "Action Surge", "Martial Path", "Path Tenets", "Keen Eye"] or (lvl3.size() == 6 and not "Iron Will" in lvl3 and not "Sharper Eye" in lvl3), "a level 3 fighter of the path (%s)" % [lvl3])
	_check(ClassFeatures.granted({"classes": [{"class": "classes/fighter", "level": 9}]}, index).size() == 5, "no subclass: only the class's")
	_check(Rules.resources({"classes": [{"class": "classes/fighter", "level": 13}]}).any(func(r: Dictionary) -> bool: return r.id == "indomitable" and int(r.max) == 2), "Indomitable: 2 uses at 13")

	# at the table
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	for f: Dictionary in feats + sub:
		var e := f.duplicate()
		e["class"] = "tester"
		tl.edit_entry("features", e)
	tl.edit_entry("features", {"id": "lucky-charm", "name": "Lucky Charm", "text": "You are lucky.", "uses": "1/Day"})
	var borin := tl.entry(BORIN).duplicate(true)
	borin["classes"] = [{"class": "classes/tester", "level": 2}]
	borin["features"] = ["lucky-charm"]
	tl.edit_entry("characters", borin)
	await process_frame
	var dm := _table("DM", "dm")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	await _until(func() -> bool: return dm.grid.tokens.has(BORIN))
	var sheet := dm.sheet_for(Reveal.DM, BORIN)
	var list: Array = sheet.get("features", [])
	_check("lucky-charm" in list and "fighter-second-wind" in list and "fighter-action-surge" in list and not "fighter-martial-path" in list, "level 2: its own feature and the class's up to 2 (%s)" % [list])
	_check(sheet._class_features == ["fighter-second-wind", "fighter-steady-hands", "fighter-action-surge"], "the given ones are known (%s)" % [sheet._class_features])
	_check(str(sheet._refs["fighter-second-wind"].name) == "Second Wind" and HudWidgets._list_bbcode(sheet, ["features"]).contains("• Steady Hands"), "shown by name")
	_check((sheet._resources as Array).any(func(r: Dictionary) -> bool: return r.id == "feature.lucky-charm"), "its own feature's uses still count")
	var change := EntryDrag.sheet_change(sheet, {"_kind": "features", "id": "new-trick", "name": "New Trick"})
	_check(change.size() == 2 and (change[1] as Array) == ["lucky-charm", "features/new-trick"], "dropping a feature stores only its own (%s)" % [change])
	borin["classes"] = [{"class": "classes/tester", "level": 9}]
	tl.edit_entry("characters", borin)
	await process_frame
	_check("fighter-iron-will" in (dm.sheet_for(Reveal.DM, BORIN).features as Array), "level 9: Iron Will")
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("class features: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
