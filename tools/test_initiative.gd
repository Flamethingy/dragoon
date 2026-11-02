extends SceneTree
## Headless check of initiative (TASK-58): rolled per creature when a combat starts (the DM's
## creatures at once, the players get a prompt, the DM can roll for an absent one), groups
## sharing one roll and turn, the order by initiative then Dex, dragged by the DM, late
## joiners sorted in, surprise per edition.
## godot --headless --path . -s tools/test_initiative.gd

const PORT := 47793
const ADDRESS := "127.0.0.1:47793"
const DIR := "user://test_initiative"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"

var _failed := 0


func _init() -> void:
	# --- The order, offline ----------------------------------------------------------------------
	var w := Replay.world_state([
		{"type": "combat.started", "data": {"map": "m", "order": [{"entity": "a", "initiative": 0}, {"entity": "b", "initiative": 0}, {"entity": "c", "initiative": 0}]}},
		{"type": "initiative.rolled", "entity": "a", "data": {"total": 12, "dex": 10}},
		{"type": "initiative.rolled", "entity": "b", "data": {"total": 12, "dex": 16}}])
	_check(w.combat.order.map(func(c: Dictionary) -> String: return c.entity) == ["b", "a", "c"] and not w.combat.order[2].rolled,
		"ties: higher Dex first; not rolled yet at the end (%s)" % [w.combat.order])
	w = Replay.world_state([
		{"type": "combat.started", "data": {"map": "m", "order": [{"entity": "a", "initiative": 15}, {"entity": "b", "initiative": 10}]}},
		{"type": "combat.turn", "data": {"round": 1, "turn": 1}},
		{"type": "combat.order_set", "data": {"order": ["b", "a"]}},
		{"type": "combat.joined", "entity": "c", "data": {}},
		{"type": "initiative.rolled", "entity": "c", "data": {"total": 12}}])
	_check(w.combat.order.map(func(c: Dictionary) -> String: return c.entity) == ["c", "b", "a"] and w.combat.current == "b" and int(w.combat.turn) == 1,
		"the DM's order stays, a late joiner goes in front of the first it beats, the turn stays with its creature (%s, turn %d)" % [w.combat.order, w.combat.turn])
	w = Replay.world_state([
		{"type": "combat.started", "data": {"map": "m", "order": [{"entity": "a", "initiative": 15}, {"entity": "b", "initiative": 10}, {"entity": "c", "initiative": 5}]}},
		{"type": "combat.grouped", "data": {"group": "group:1", "name": "Goblins", "members": ["b", "c"]}},
		{"type": "initiative.rolled", "entity": "group:1", "data": {"total": 18}}])
	_check(w.combat.order.size() == 2 and w.combat.order[0].entity == "group:1" and w.combat.order[0].members == ["b", "c"] and w.combat.order[0].name == "Goblins",
		"a group: one roll, one slot, its members under it (%s)" % [w.combat.order])

	# --- At the table -------------------------------------------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	var late := tl.entry("creatures/dire-wolf").duplicate(true)
	late["id"] = "late-wolf"
	late["name"] = "Late Wolf"
	tl.edit_entry("creatures", late)
	await process_frame
	var dm := _table("DM", "dm", true)
	var ann := _table("Ann", "ann", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(ann.join(ADDRESS, "Ann") == OK, "Ann joins")
	await _until(func() -> bool: return ann.my_pc == "characters/aria" and ann.grid.tokens.has("characters/aria"))
	var npcs: Array = dm.grid.tokens.keys().filter(func(id: String) -> bool: return "/" in id and dm.owners.get(id, []).is_empty())
	_check(npcs.size() >= 2, "the DM's creatures on the map (%s)" % [npcs])

	dm.start_combat()
	var order: Array = dm.combat_state().order
	var aria: Array = order.filter(func(c: Dictionary) -> bool: return c.entity == "characters/aria")
	_check(not aria.is_empty() and not aria[0].rolled, "Aria waits for Ann's roll")
	_check(npcs.all(func(id: String) -> bool: return order.any(func(c: Dictionary) -> bool: return c.entity == id and c.rolled)), "the DM's creatures are rolled at once (%s)" % [order])
	_check(dm.event_log.events.filter(func(e: Dictionary) -> bool: return e.type == "initiative.rolled").size() == npcs.size(), "initiative.rolled per creature")
	_check(dm.rolls.any(func(r: Dictionary) -> bool: return r.get("action") == "prompt_dm" and r.ref == "characters/aria"), "the DM sees who it waits for")
	await _until(func() -> bool: return ann.rolls.any(func(r: Dictionary) -> bool: return r.get("action") == "prompt"))
	var prompt: Array = ann.rolls.filter(func(r: Dictionary) -> bool: return r.get("action") == "prompt")
	_check(not prompt.is_empty() and NetTable.roll_bbcode(prompt[0]).contains("[url=init:characters/aria]"), "Ann gets a prompt to roll")
	await _until(func() -> bool: return ann._ui.tracker.visible)
	_check(ann._ui.tracker.visible and not (ann._ui.tracker.find_child("Buttons", true, false) as Control).visible, "the players see the order, without the DM's buttons")
	ann.answer_initiative("characters/aria")
	await _until(func() -> bool: return dm.combat_state().order.any(func(c: Dictionary) -> bool: return c.entity == "characters/aria" and c.rolled))
	var rolled: Array = dm.event_log.events.filter(func(e: Dictionary) -> bool: return e.type == "initiative.rolled" and e.entity == "characters/aria")
	_check(rolled.size() == 1 and rolled[0].by == "ann", "Ann's roll is her initiative")
	# Bob isn't here: the DM rolls for Borin
	_check(dm.combat_state().order.any(func(c: Dictionary) -> bool: return c.entity == "characters/borin" and not c.rolled), "Borin waits for absent Bob")
	dm.answer_initiative("characters/borin")
	_check(dm.event_log.events.any(func(e: Dictionary) -> bool: return e.type == "initiative.rolled" and e.entity == "characters/borin" and e.by == "dm"), "the DM rolls for an absent player")
	await _until(func() -> bool: return (ann.combat_view().order as Array).all(func(c: Dictionary) -> bool: return c.rolled))
	_check((ann.combat_view().order as Array).all(func(c: Dictionary) -> bool: return c.rolled and str(c.name) != ""), "Ann's tracker has the whole order (%s)" % [ann.combat_view()])
	ann.roll("initiative", "characters/aria")  # a second roll is just a roll
	await _until(func() -> bool: return dm.rolls.filter(func(r: Dictionary) -> bool: return not (r.get("results", []) as Array).is_empty() and str(r.results[0].get("label", "")).begins_with("Initiative") and r.get("ref", "") == "characters/aria").size() >= 2)
	_check(dm.event_log.events.filter(func(e: Dictionary) -> bool: return e.type == "initiative.rolled" and e.entity == "characters/aria").size() == 1, "no second initiative")

	# groups
	var g := dm.group_creatures([npcs[0], npcs[1]], "Wolves")
	order = dm.combat_state().order
	var grp: Array = order.filter(func(c: Dictionary) -> bool: return c.entity == g)
	_check(g != "" and not grp.is_empty() and grp[0].rolled and grp[0].members.size() == 2 and not order.any(func(c: Dictionary) -> bool: return c.entity == npcs[0]),
		"grouped: one rolled slot (%s)" % [order])
	_check(dm.combat_view().order.any(func(c: Dictionary) -> bool: return c.entity == g and c.name == "Wolves" and c.members.size() == 2), "the tracker lists the members")
	await process_frame
	_check(dm._ui.tracker.find_child("Row_" + g.validate_node_name(), true, false) != null, "a tracker row for the group")
	# the DM drags: the last row to the top
	var n: int = order.size()
	dm._ui.tracker.move(n - 1, 0)
	_check(dm.combat_state().order[0].entity == order[n - 1].entity, "dragged to the top: combat.order_set")
	dm.ungroup(g)
	order = dm.combat_state().order
	_check(order.any(func(c: Dictionary) -> bool: return c.entity == npcs[0] and c.rolled) and not order.any(func(c: Dictionary) -> bool: return c.entity == g), "ungrouped: each rolls again")

	# 2014 surprise: no turn in round 1
	var first: String = dm.combat_state().order[0].entity
	var second: String = dm.combat_state().order[1].entity
	dm.set_surprised(second, true)
	dm.next_turn()
	_check(dm.combat_state().current != second and int(dm.combat_state().turn) == 2 % dm.combat_state().order.size(), "2014: the surprised one has no turn in round 1 (%s)" % dm.status)
	dm.end_combat()

	# 2024: surprised -> disadvantage on initiative
	var s := dm.rules_settings().duplicate(true)
	s["edition"] = "2024"
	dm.set_rules_settings(s)
	dm.start_combat([npcs[0]])
	var roll_of: Array = dm.rolls.filter(func(r: Dictionary) -> bool: return r.get("ref", "") == npcs[0] and not r.get("results", []).is_empty())
	_check(not roll_of.is_empty() and str(roll_of[-1].results[0].formula).begins_with("2d20kl1"), "2024: surprised rolls with disadvantage (%s)" % [roll_of[-1].results[0] if not roll_of.is_empty() else {}])
	# a creature put on the map mid-combat is rolled and sorted in
	var placed := "creatures/late-wolf"
	dm.join_combat(placed)
	_check(placed != "" and dm.combat_state().order.any(func(c: Dictionary) -> bool: return c.entity == placed and c.rolled), "a newcomer is rolled and sorted in (%s)" % [dm.combat_state().order])
	dm.end_combat()

	dm.queue_free()
	ann.queue_free()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("initiative: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
