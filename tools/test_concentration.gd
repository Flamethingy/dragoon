extends SceneTree
## Headless check of concentration (TASK-59): a concentration spell marks the caster (token
## and HUD), a second one ends the first (asking first on my screen), damage asks for a CON
## save DC max(10, half), a failure / incapacitated / 0 HP ends it, and ending it takes off
## the conditions that spell put on others.
## godot --headless --path . -s tools/test_concentration.gd

const PORT := 47801
const ADDRESS := "127.0.0.1:47801"
const DIR := "user://test_concentration"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const ARIA := "characters/aria"
const WOLF := "creatures/dire-wolf"
const CHIEF := "creatures/goblin-chief"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	tl.edit_entry("spells", {"id": "hold-beast", "name": "Hold Beast", "level": 2, "concentration": true,
		"description": "Choose a beast. It must succeed on a Wisdom saving throw or be paralyzed for 1 minute."})
	tl.edit_entry("spells", {"id": "glow", "name": "Glow", "level": 1, "concentration": true, "description": "You glow."})
	await process_frame
	var dm := _table("DM", "dm", true)
	var ann := _table("Ann", "ann", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(ann.join(ADDRESS, "Ann") == OK, "Ann joins")
	await _until(func() -> bool: return ann.my_pc == ARIA and ann.grid.tokens.has(WOLF) and ann.sheets.has(ARIA))

	# a concentration spell with a save: Aria concentrates, the wolf's paralysis is linked
	var card := {}
	for seed in range(1, 80):  # until the wolf fails
		dm.rng.seed = seed
		card = dm._handle_save_action(1, ARIA, "spells/hold-beast", [WOLF], {})
		if not card.save.targets[0].success:
			break
		dm.end_concentration(ARIA)
	_check(dm.concentration_of(ARIA).get("name", "") == "Hold Beast" and "paralyzed" in dm.conditions_of(WOLF).conditions, "Aria concentrates, the wolf is paralyzed")
	_check("concentrating" in dm.conditions_of(ARIA).conditions, "the marker on her token")
	await _until(func() -> bool: return ann.sheets.get(ARIA, {}).get("concentration") is Dictionary)
	await process_frame
	var hud: CharacterHud = ann._ui.hud
	hud.refresh()
	_check(hud.find_child("Concentration", true, false) != null, "the HUD shows it")
	_check(SheetPanel.to_bbcode(ann.sheets[ARIA]).contains("Concentrating (Hold Beast)"), "the sheet says on what")

	# a second one: on my screen it asks first
	var asked := []
	ann.concentration_confirm.connect(func(_r: String, old: String, new: String, _go: Callable) -> void: asked.append([old, new]))
	ann.concentrate(ARIA, "spells/glow", "Glow", true)
	await process_frame
	_check(asked == [["Hold Beast", "Glow"]] and ann._ui.concentration_dialog != null and ann._ui.concentration_dialog.visible, "a confirm before the old one ends")
	ann._ui.concentration_dialog.confirmed.emit()
	await _until(func() -> bool: return dm.concentration_of(ARIA).get("name", "") == "Glow")
	_check(dm.concentration_of(ARIA).get("name", "") == "Glow" and "paralyzed" not in dm.conditions_of(WOLF).conditions, "the new one replaces it; the wolf is free again")

	# damage: CON save DC max(10, half), a prompt for Ann
	dm.change_hp(ARIA, -4)
	_check(int(dm._pending_conc.get(ARIA, 0)) == 10, "4 damage: DC 10")
	await _until(func() -> bool: return ann.rolls.any(func(r: Dictionary) -> bool: return r.get("action") == "conc_prompt"))
	var prompt: Array = ann.rolls.filter(func(r: Dictionary) -> bool: return r.get("action") == "conc_prompt")
	_check(not prompt.is_empty() and NetTable.roll_bbcode(prompt[0]).contains("CON save DC 10") and NetTable.roll_bbcode(prompt[0]).contains("[url=conc:%s]" % ARIA), "Ann's prompt")
	ann.answer_concentration(ARIA)
	await _until(func() -> bool: return dm.event_log.events.any(func(e: Dictionary) -> bool: return e.type == "dice.rolled" and e.data.has("concentration")))
	var conc: Array = dm.event_log.events.filter(func(e: Dictionary) -> bool: return e.type == "dice.rolled" and e.data.has("concentration"))
	_check(not conc.is_empty() and conc[0].by == "ann" and conc[0].data.concentration.dc == 10, "her CON save")
	_check(conc[0].data.concentration.kept == not dm.concentration_of(ARIA).is_empty(), "a failure ends it, a success keeps it")
	_check(dm._pending_conc.is_empty(), "nothing waits")

	# a creature: big damage, DC half of it, rolled at once
	dm.concentrate(CHIEF, "spells/glow", "Glow")
	dm.change_hp(CHIEF, -int(dm.sheet_for(Reveal.DM, CHIEF).hp) + 1)  # down to 1
	var chief_save: Array = dm.event_log.events.filter(func(e: Dictionary) -> bool: return e.type == "dice.rolled" and e.entity == CHIEF and e.data.has("concentration"))
	_check(not chief_save.is_empty() and chief_save[-1].by == "dm", "the DM's creature saves at once")
	# incapacitated ends it
	dm.concentrate(CHIEF, "spells/glow", "Glow")
	dm.set_condition(CHIEF, "stunned")
	_check(dm.concentration_of(CHIEF).is_empty(), "stunned (incapacitated) ends it")
	dm.set_condition(CHIEF, "stunned", false)
	# 0 HP ends it
	dm.concentrate(CHIEF, "spells/glow", "Glow")
	dm.change_hp(CHIEF, -50)
	_check(dm.concentration_of(CHIEF).is_empty(), "0 HP ends it")

	dm.queue_free()
	ann.queue_free()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("concentration: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
