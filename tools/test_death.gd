extends SceneTree
## Headless check of 0 HP (TASK-57): a character drops Unconscious with death saves (a prompt
## on their turn), damage at 0 is a failure (two on a crit), healing gets them up, a natural
## 20 / three failures, massive damage only warns; a creature at 0 is marked dead (greyed),
## the DM can make it knocked out instead, and defeated ones are skipped in the turn order.
## godot --headless --path . -s tools/test_death.gd

const PORT := 47799
const ADDRESS := "127.0.0.1:47799"
const DIR := "user://test_death"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const ARIA := "characters/aria"
const WOLF := "creatures/dire-wolf"
const CHIEF := "creatures/goblin-chief"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	await process_frame
	var dm := _table("DM", "dm", true)
	var ann := _table("Ann", "ann", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(ann.join(ADDRESS, "Ann") == OK, "Ann joins")
	await _until(func() -> bool: return ann.my_pc == ARIA and ann.grid.tokens.has(WOLF))
	var hp := int(dm.sheet_for(Reveal.DM, ARIA).hp)

	# down to 0: Unconscious, death saves
	dm.change_hp(ARIA, -(hp + 3))
	var s := dm.sheet_for(Reveal.DM, ARIA)
	_check(int(s.hp) == 0 and "unconscious" in s.conditions, "0 HP: Unconscious")
	_check(SheetPanel.to_bbcode(s).contains("Death Saves") and SheetPanel.to_bbcode(s).contains("[url=death]roll[/url]"), "the sheet offers the death save")
	# damage at 0: a failure, a crit two
	dm.change_hp(ARIA, -2)
	_check(int(dm.sheet_for(Reveal.DM, ARIA).death_saves.failures) == 1, "damage at 0 HP: one failed save")
	dm._handle_hp(1, ARIA, -2, "crit", true)
	_check(int(dm.sheet_for(Reveal.DM, ARIA).death_saves.failures) == 3 and "dead" in dm.sheet_for(Reveal.DM, ARIA).conditions, "a crit: two more, three = dead")
	_check(dm.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")).contains("three failed death saves")), "the DM is told (and can undo)")
	var dead_id := 0
	for e: Dictionary in dm.event_log.events:
		if e.type == "condition.applied" and e.entity == ARIA and e.data.condition == "dead":
			dead_id = int(e.id)
	dm.event_log.undo(dead_id)
	_check("dead" not in dm.sheet_for(Reveal.DM, ARIA).get("conditions", []), "undo takes Dead off")
	# healing: up again, saves start over
	dm.change_hp(ARIA, 5)
	s = dm.sheet_for(Reveal.DM, ARIA)
	_check(int(s.hp) == 5 and "unconscious" not in s.conditions and not s.has("death_saves"), "healed: awake, the saves start over")
	# massive damage only warns
	dm.change_hp(ARIA, -(5 + hp))
	_check(dm.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")).contains("massive damage")) and "dead" not in dm.sheet_for(Reveal.DM, ARIA).conditions,
		"massive damage: a warning, not death")
	# rolling death saves until something happens (a player's roll)
	var lucky := 0  # a seed whose first d20 is a 20
	for seed in range(1, 2000):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed
		if int(Dice.roll("1d20", probe).total) == 20:
			lucky = seed
			break
	dm.change_hp(ARIA, 1)
	dm.change_hp(ARIA, -1)  # back at 0, the saves fresh
	dm.rng.seed = lucky
	var natural20 := int(dm._handle_death_save(1, ARIA).results[0].total) == 20
	s = dm.sheet_for(Reveal.DM, ARIA)
	_check(natural20 and int(s.hp) == 1 and "unconscious" not in s.conditions, "a natural 20: back up with 1 HP")

	# her turn at 0 HP: a prompt for Ann
	dm.change_hp(ARIA, -1)
	dm.start_combat()
	ann.answer_initiative(ARIA)
	await _until(func() -> bool: return dm.combat_state().order.all(func(c: Dictionary) -> bool: return c.rolled or c.entity != ARIA))
	var guard := 0
	while dm.combat_state().current != ARIA and guard < 20:
		dm.next_turn()
		guard += 1
	await _until(func() -> bool: return ann.rolls.any(func(r: Dictionary) -> bool: return r.get("action") == "death_prompt"))
	var prompt: Array = ann.rolls.filter(func(r: Dictionary) -> bool: return r.get("action") == "death_prompt")
	_check(not prompt.is_empty() and NetTable.roll_bbcode(prompt[0]).contains("[url=death:%s]" % ARIA), "Ann gets her death save prompt on her turn (%s, %s, dm %s, hp %s)" % [dm.combat_state().current, dm.combat_state().order, dm.rolls.filter(func(r: Dictionary) -> bool: return r.get("action") == "death_prompt").size(), dm.sheet_for(Reveal.DM, ARIA).hp])
	ann.roll_death_save(ARIA)
	await _until(func() -> bool: return dm.event_log.events.any(func(e: Dictionary) -> bool: return e.type == "death_save.rolled" and e.by == "ann"))
	_check(dm.event_log.events.any(func(e: Dictionary) -> bool: return e.type == "death_save.rolled" and e.by == "ann"), "her own death save")

	# a creature at 0: dead, greyed, skipped
	dm.change_hp(WOLF, -999)
	var wolf := dm.sheet_for(Reveal.DM, WOLF)
	_check("dead" in wolf.conditions and "unconscious" not in wolf.conditions, "a creature at 0 is marked dead")
	_check(dm.grid.tokens[WOLF].self_modulate != Color.WHITE, "its token is greyed")
	for i in 8:
		dm.next_turn()
		_check(dm.combat_state().current != WOLF, "defeated: skipped in the order")
	# the DM's choice: knocked out instead
	dm.set_condition(WOLF, "dead", false)
	dm.set_condition(WOLF, "unconscious", true)
	_check("unconscious" in dm.sheet_for(Reveal.DM, WOLF).conditions and dm.grid.tokens[WOLF].self_modulate != Color.WHITE, "knocked out instead, still greyed")
	var menu := dm._ui.open_condition_menu(WOLF)
	var has_dead := false
	for i in menu.item_count:
		if str(menu.get_item_metadata(i)) == "dead":
			has_dead = true
	_check(has_dead, "Dead is in the condition menu")
	menu.hide()
	dm.end_combat()

	dm.queue_free()
	ann.queue_free()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("death: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
