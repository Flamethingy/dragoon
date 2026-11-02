extends SceneTree
## Headless check of conditions at the table (TASK-56): put on and taken off as events (token
## menu, sheet, roll cards), marks on the token for everyone, the sheet's list with the rules
## text, exhaustion levels per edition, an immunity warning (never a block), and conditions
## preselecting advantage / disadvantage on rolls.
## godot --headless --path . -s tools/test_conditions.gd

const PORT := 47791
const ADDRESS := "127.0.0.1:47791"
const DIR := "user://test_conditions"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"

var _failed := 0


func _init() -> void:
	# --- Rules and dice, offline ----------------------------------------------------------------
	var rogue := {"stats": {"dex": 16}, "classes": [{"class": "classes/rogue", "level": 1}], "skills": ["stealth"], "conditions": ["poisoned"]}
	var r := Dice.resolve(rogue, "stealth")
	_check(r[0].formula == "2d20kl1+5" and str(r[0].label).contains("disadvantage: poisoned"), "poisoned: disadvantage preselected, the label says why (%s)" % [r])
	_check(Dice.resolve(rogue, "stealth normal")[0].formula == "1d20+5" and Dice.resolve(rogue, "stealth with advantage")[0].formula == "2d20kh1+5",
		"never forced: an explicit choice wins")
	_check(Dice.resolve({"stats": {"dex": 16}, "conditions": ["restrained"]}, "dex save")[0].formula == "2d20kl1+3"
		and Dice.resolve({"stats": {"dex": 16}, "conditions": ["restrained"]}, "wis save")[0].formula == "1d20", "restrained: only Dex saves")
	var tired := {"stats": {"dex": 16}, "conditions": ["exhaustion"], "exhaustion": 2}
	_check(Dice.resolve(tired, "dex check", {}, {"edition": "2024"})[0].formula == "1d20+3-4" and Dice.resolve(tired, "dex check", {}, {"edition": "2014"})[0].formula == "2d20kl1+3",
		"exhaustion: 2014 disadvantage on checks, 2024 -2 per level (%s)" % Dice.resolve(tired, "dex check", {}, {"edition": "2024"})[0].formula)
	_check(Rules.immune_to({"condition_immunities": ["Poisoned"]}, "poisoned") and Rules.immune_to({"condition_immunities": ["conditions/charmed"]}, "charmed")
		and not Rules.immune_to({}, "charmed"), "condition immunities by name or ref")
	var st := Replay.entity_state({}, [{"type": "condition.applied", "data": {"condition": "exhaustion", "level": 3}},
		{"type": "condition.applied", "data": {"condition": "frightened", "duration": {"rounds": 10}}}])
	_check(st.exhaustion == 3 and st.condition_durations.frightened.rounds == 10, "exhaustion level and an optional duration in the state")
	st = Replay.entity_state(st, [{"type": "condition.removed", "data": {"condition": "exhaustion"}}, {"type": "condition.removed", "data": {"condition": "frightened"}}])
	_check(not st.has("exhaustion") and (st.conditions as Array).is_empty() and (st.condition_durations as Dictionary).is_empty(), "taken off again")

	# --- At the table -------------------------------------------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	var borin := tl.entry("characters/borin").duplicate(true)
	borin.erase("player")
	borin["owners"] = ["ann"]
	borin["condition_immunities"] = ["charmed"]
	tl.edit_entry("characters", borin)
	await process_frame
	var dm := _table("DM", "dm", true)
	var ann := _table("Ann", "ann", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(ann.join(ADDRESS, "Ann") == OK, "Ann joins")
	await _until(func() -> bool: return ann.my_pc == "characters/aria" and ann.grid.tokens.has("characters/aria") and ann.grid.tokens.has("characters/borin"))

	# Ann marks her own character poisoned: an event, marks on the token for everyone
	ann.set_condition("characters/aria", "poisoned")
	await _until(func() -> bool: return "poisoned" in ann.conditions_of("characters/aria").conditions)
	var ev := dm.event_log.events.filter(func(e: Dictionary) -> bool: return e.type == "condition.applied")
	_check(ev.size() == 1 and ev[0].entity == "characters/aria" and ev[0].data.condition == "poisoned" and ev[0].by == "ann", "condition.applied by Ann")
	var marks := ann.grid.tokens["characters/aria"].get_node("Marks") as TokenMarks
	var dm_marks := dm.grid.tokens["characters/aria"].get_node("Marks") as TokenMarks
	_check(marks.conditions.size() == 1 and marks.conditions[0].abbr != "" and dm_marks.conditions.size() == 1, "a mark on the token, for both (%s)" % [marks.conditions])
	_check(dm.rolls.any(func(e: Dictionary) -> bool: return e.get("action") == "log" and str(e.text) == "is poisoned"), "the DM sees it as a log line")
	# her stealth roll: disadvantage preselected
	ann.roll("stealth", "characters/aria")
	await _until(func() -> bool: return ann.rolls.any(func(e: Dictionary) -> bool: return str(e.get("results", [{}])[0].get("label", "")).contains("disadvantage")))
	var card: Array = ann.rolls.filter(func(e: Dictionary) -> bool: return not e.get("results", []).is_empty())
	_check(not card.is_empty() and str(card[-1].results[0].formula).begins_with("2d20kl1"), "rolls with disadvantage (%s)" % [card[-1].results[0] if not card.is_empty() else {}])
	_check(not card.is_empty() and NetTable.roll_bbcode(card[-1]).contains("[url=cond:characters/aria]"), "the roll card's name opens the conditions")

	# immune: applied anyway, the DM is warned
	ann.set_condition("characters/borin", "charmed")
	await _until(func() -> bool: return dm.rolls.any(func(e: Dictionary) -> bool: return str(e.get("text", "")).contains("immune")))
	_check("charmed" in dm.conditions_of("characters/borin").conditions and dm.rolls.any(func(e: Dictionary) -> bool: return str(e.get("text", "")).contains("immune to charmed")),
		"immunity: a warning, not a block")
	# not hers: nothing happens
	ann.set_condition("creatures/goblin-chief", "prone")
	await _until(func() -> bool: return ann.status.contains("not your sheet"), 60)
	_check(not dm.event_log.events.any(func(e: Dictionary) -> bool: return e.entity == "creatures/goblin-chief" and e.type == "condition.applied"), "only her own sheets")
	_check(ann._ui.open_condition_menu("creatures/goblin-chief") == null, "no menu for others' creatures")

	# exhaustion levels
	dm.set_condition("characters/aria", "exhaustion", true, 2)
	await _until(func() -> bool: return ann.conditions_of("characters/aria").exhaustion == 2)
	_check(ann.conditions_of("characters/aria").exhaustion == 2 and marks.conditions.any(func(c: Dictionary) -> bool: return str(c.abbr).ends_with("2")), "exhaustion 2, its level on the mark")
	dm.set_condition("characters/aria", "exhaustion", false, 0)
	await _until(func() -> bool: return "exhaustion" not in ann.conditions_of("characters/aria").conditions)
	_check("exhaustion" not in ann.conditions_of("characters/aria").conditions, "exhaustion 0 takes it off")

	# the token menu: ticked conditions, the rules text as tooltip; unticking takes it off
	var menu := ann._ui.open_condition_menu("characters/aria")
	_check(menu != null and menu.visible, "a right click opens the condition menu")
	var at := -1
	for i in menu.item_count:
		if str(menu.get_item_metadata(i)) == "poisoned":
			at = i
	_check(at >= 0 and menu.is_item_checked(at) and menu.get_item_tooltip(at) != "", "poisoned is ticked, with its rules text")
	menu.id_pressed.emit(menu.get_item_id(at))
	await _until(func() -> bool: return "poisoned" not in ann.conditions_of("characters/aria").conditions)
	_check(dm.event_log.events.any(func(e: Dictionary) -> bool: return e.type == "condition.removed" and e.data.condition == "poisoned"), "unticked: condition.removed")
	_check(marks.conditions.is_empty(), "the mark is gone")
	menu.hide()

	# the sheet: its list with tooltips and a × to take one off
	ann.set_condition("characters/aria", "prone")
	ann.open_sheet("characters/aria")
	await _until(func() -> bool: return "prone" in (ann.sheets.get("characters/aria", {}).get("conditions", []) as Array))
	var bb := SheetPanel.to_bbcode(ann.sheets["characters/aria"])
	_check(bb.contains("[hint=") and bb.contains("cond:off:prone") and bb.contains("cond:add"), "the sheet lists it with its text and a ×")
	ann._ui.sheet.ref = "characters/aria"
	ann._ui.sheet._on_meta("cond:off:prone")
	await _until(func() -> bool: return "prone" not in ann.conditions_of("characters/aria").conditions)
	_check("prone" not in ann.conditions_of("characters/aria").conditions, "the × takes it off")

	dm.queue_free()
	ann.queue_free()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("conditions: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
