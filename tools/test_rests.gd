extends SceneTree
## Headless check of uses and rests (TASK-64): feature uses ("1/Day", "Recharges after a Short
## or Long Rest") spent with the action, hit dice, item charges back at dawn, the short rest
## (hit dice + CON, short-rest resources back, its dialog) and the party's long rest (full HP,
## half the hit dice, exhaustion -1, 8 hours on the clock).
## godot --headless --path . -s tools/test_rests.gd

const PORT := 47808
const DIR := "user://test_rests"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	# --- Rules -------------------------------------------------------------------------------
	_check(Rules.feature_uses({"uses": "3/Day"}) == {"max": 3, "reset": "long"} and Rules.feature_uses({"name": "Spellcasting (1/day each)"}).max == 1
		and Rules.feature_uses({"name": "Second Wind (Recharges after a Short or Long Rest)"}) == {"max": 1, "reset": "short"}
		and Rules.feature_uses({"uses": "Recharge 5-6"}).is_empty() and Rules.feature_uses({"uses": "1/Turn"}).is_empty(), "feature uses")
	_check(Rules.item_charges({"description": "This wand has 7 charges. It regains 1d6 + 1 expended charges daily at dawn."}) == {"max": 7, "regain": "1d6+1", "reset": "dawn"}
		and Rules.item_charges({"description": "A rope."}).is_empty(), "item charges")
	_check(Rules.hit_dice_back(5) == 2 and Rules.hit_dice_back(1) == 1 and Rules.hit_dice_back(5, "2024") == 5, "hit dice back: 2014 half, 2024 all")

	# --- At the table -------------------------------------------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	tl.edit_entry("features", {"id": "cry-chief", "name": "Battle Cry (1/Day)", "uses": "1/Day", "text": "Each enemy within 9 m must succeed on a DC 12 Wisdom saving throw or be frightened."})
	var chief := tl.entry(CHIEF).duplicate(true)
	chief["actions"] = ["scimitar-chief", "cry-chief"]
	tl.edit_entry("creatures", chief)
	tl.edit_entry("items", {"id": "wand-test", "name": "Wand of Testing", "description": "This wand has 7 charges. It regains 1d6 + 1 expended charges daily at dawn."})
	await process_frame
	var dm := _table("DM", "dm", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	await _until(func() -> bool: return dm.grid.tokens.has(BORIN) and dm.grid.tokens.has(CHIEF))
	dm.advance_clock(22 * 60)  # 22:00
	dm.change_item(BORIN, "items/wand-test", 1)
	var res := _res(dm, BORIN)
	_check(res.has("hit_dice.d8") and res["hit_dice.d8"].max == 3 and res.has("channel_divinity") and res["channel_divinity"].reset == "short", "Borin: 3 d8 hit dice, Channel Divinity (%s)" % [res.keys()])
	_check(res.has("charges.items/wand-test") and res["charges.items/wand-test"].max == 7, "the wand's 7 charges")
	dm.use_resource(BORIN, "charges.items/wand-test", 3)
	dm.use_resource(BORIN, "channel_divinity", 1)
	var bb := SheetPanel.to_bbcode(dm.sheet_for(Reveal.DM, BORIN))
	_check(bb.contains("[url=res:use:hit_dice.d8]") and bb.contains("●●●●○○○") and bb.contains("[url=rest:short]"), "the sheet: uses as pips, the rests")

	# a feature's use goes with its action
	dm._handle_save_action(1, CHIEF, "Battle Cry (1/Day)", [BORIN], {})
	_check(_res(dm, CHIEF)["feature.cry-chief"].used == 1, "Battle Cry spends its use")
	var lines := dm.rolls.size()
	dm._handle_save_action(1, CHIEF, "Battle Cry (1/Day)", [BORIN], {})
	_check(dm.rolls.slice(lines).any(func(r: Dictionary) -> bool: return "no uses left (used anyway)" in str(r.get("text", ""))), "none left: used anyway, the DM is told")

	# a short rest
	var hp_max := int(dm.sheet_for(Reveal.DM, BORIN)._hp_max)
	dm._handle_hp(1, BORIN, -15, "test")
	var hp0 := int(dm.sheet_for(Reveal.DM, BORIN).hp)
	var panel := SheetPanel.new()
	panel.table = dm
	root.add_child(panel)
	panel.show_sheet(dm.sheet_for(Reveal.DM, BORIN))
	var dlg := panel.short_rest_dialog()
	var spin := dlg.find_child("Dice_d8", true, false) as SpinBox
	_check(spin != null and spin.max_value == 3, "the short rest dialog: up to 3 d8")
	spin.value = 2
	dlg.confirmed.emit()
	var s := dm.sheet_for(Reveal.DM, BORIN)
	res = _res(dm, BORIN)
	_check(res["hit_dice.d8"].used == 2 and int(s.hp) >= hp0 + 2 * (1 + 2) and int(s.hp) <= mini(hp0 + 2 * (8 + 2), hp_max), "2 hit dice + CON healed (%d → %d)" % [hp0, int(s.hp)])
	_check(res["channel_divinity"].used == 0 and res["charges.items/wand-test"].used == 3, "Channel Divinity back, the wand not")
	_check(dm.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")).begins_with("short rest: healed") and not r.hidden), "everyone sees the short rest")
	panel.free()

	# the party's long rest
	dm.set_condition(BORIN, "exhaustion", true, 2)
	dm._handle_hp(1, BORIN, -5, "test")
	var day0 := dm.event_log.day
	lines = dm.rolls.size()
	dm.long_rest()
	s = dm.sheet_for(Reveal.DM, BORIN)
	res = _res(dm, BORIN)
	_check(int(s.hp) == hp_max and res["hit_dice.d8"].used == 1, "long rest: full HP, 1 of 3 hit dice back (%d used)" % res["hit_dice.d8"].used)
	_check(int(s.get("exhaustion", 0)) == 1 and "exhaustion" in (s.conditions as Array), "exhaustion 2 → 1")
	_check(dm.event_log.day == day0 + 1 and dm.event_log.time == 6 * 60, "8 hours later: 06:00 the next day")
	_check(res["charges.items/wand-test"].used < 3 and dm.rolls.slice(lines).any(func(r: Dictionary) -> bool: return str(r.get("text", "")).begins_with("dawn: Wand of Testing charges")), "the wand regains charges at dawn")
	_check(_res(dm, CHIEF)["feature.cry-chief"].used == 1, "the long rest is the party's (the chief keeps its)")
	dm.long_rest([BORIN])
	_check(not "exhaustion" in (dm.sheet_for(Reveal.DM, BORIN).conditions as Array), "another: exhaustion gone")
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("rests: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _res(dm: NetTable, ref: String) -> Dictionary:
	var out := {}
	for r: Dictionary in dm.resources_of(dm.sheet_for(Reveal.DM, ref)):
		out[r.id] = r
	return out


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
