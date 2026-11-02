extends SceneTree
## Headless check of the turn engine (TASK-63): durations running out at the start / end of
## a creature's turn (a log line, undoable; Assist only reminds), "save ends" saves (the DM's
## creatures roll, players are asked), recharge rolls, legendary actions back each turn and
## Legendary Resistance per day, regeneration and lair action reminders, and the in-world
## clock ending minute-long effects out of combat.
## godot --headless --path . -s tools/test_turn_engine.gd

const PORT := 47807
const DIR := "user://test_turn_engine"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const BORIN := "characters/borin"
const ARIA := "characters/aria"

var _failed := 0


func _init() -> void:
	# --- Rules -------------------------------------------------------------------------------
	_check(Rules.recharge_of({"name": "Fire Breath (Recharge 5-6)"}) == 5 and Rules.recharge_of({"uses": "Recharge 6"}) == 6 and Rules.recharge_of({"name": "Bite"}) == 0, "recharge 5-6 / 6")
	_check(Rules.legendary_count({"legendary_actions": ["a"], "legendary_intro": "The dragon can take 2 legendary actions"}) == 2 and Rules.legendary_count({"legendary_actions": ["a"]}) == 3
		and Rules.legendary_count({}) == 0, "legendary actions per round")
	_check(Rules.legendary_cost({"name": "Wing Attack (Costs 2 Actions)"}) == 2 and Rules.legendary_cost({"name": "Detect"}) == 1, "legendary costs")
	_check(Rules.legendary_resistance([{"name": "Legendary Resistance (3/Day)"}]) == 3 and Rules.legendary_resistance([]) == 0, "Legendary Resistance (3/Day)")
	var regen := Rules.regeneration([{"text": "The troll regains 10 hit points at the start of its turn. If the troll takes acid or fire damage, this trait doesn't function at the start of the troll's next turn."}])
	_check(regen == {"amount": 10, "stopped_by": "acid or fire"}, "regeneration (%s)" % [regen])
	var fx := Rules.save_effect({"name": "Gaze", "text": "DC 13 Wisdom saving throw or be frightened for 1 minute. The target can repeat the saving throw at the end of each of its turns, ending the effect on itself on a success."})
	_check(fx.duration == {"rounds": 10, "save_ends": true}, "save ends (%s)" % [fx.duration])

	# --- At the table -------------------------------------------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	tl.edit_entry("features", {"id": "breath-chief", "name": "Fire Breath (Recharge 5-6)", "uses": "Recharge 5-6", "save": {"dc": 12, "ability": "dex"},
		"text": "Each creature in a 4.5 m cone must make a DC 12 Dexterity saving throw, taking 7 (2d6) fire damage on a failed save, or half as much damage on a successful one."})
	tl.edit_entry("features", {"id": "lr-chief", "name": "Legendary Resistance (3/Day)", "text": "If the chief fails a saving throw, it can choose to succeed instead."})
	tl.edit_entry("features", {"id": "regen-chief", "name": "Regeneration", "text": "The chief regains 5 hit points at the start of its turn. If it takes fire damage, this trait doesn't function."})
	tl.edit_entry("features", {"id": "shout-chief", "name": "Shout (Costs 2 Actions)", "text": "The chief shouts."})
	var chief := tl.entry(CHIEF).duplicate(true)
	chief["actions"] = ["scimitar-chief", "breath-chief"]
	chief["traits"] = ["lr-chief", "regen-chief"]
	chief["legendary_actions"] = ["shout-chief"]
	chief["lair_actions"] = ["The cave shakes."]
	tl.edit_entry("creatures", chief)
	await process_frame
	var dm := _table("DM", "dm", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	await _until(func() -> bool: return dm.grid.tokens.has(BORIN) and dm.grid.tokens.has(CHIEF) and dm.grid.tokens.has(ARIA))
	dm.start_combat()
	var ids: Array = (dm.combat_state().order as Array).map(func(c: Dictionary) -> String: return str(c.entity))
	var rest := ids.filter(func(i: String) -> bool: return i not in [CHIEF, BORIN, ARIA])
	dm.set_order([CHIEF, BORIN, ARIA] + rest)
	_check(dm.combat_state().order[0].entity == CHIEF and int(dm.combat_state().turn) == 0, "the chief goes first")

	# the chief's turn: it poisons Borin until the end of Borin's next turn, frightens Aria for 2 rounds (its turns)
	dm.set_condition(BORIN, "poisoned", true, 0, {"rounds": 1, "ends": "turn_end"})
	dm.set_condition(ARIA, "frightened", true, 0, {"rounds": 2, "of": CHIEF})
	dm._handle_save_action(1, CHIEF, "Fire Breath (Recharge 5-6)", [BORIN], {})
	var u: Dictionary = dm.turn_usage(CHIEF)
	_check(u.get("spent", []) == ["Fire Breath (Recharge 5-6)"], "the breath is spent (%s)" % [u.get("spent")])
	_check(u.legendary == {"left": 3, "max": 3} and u.legendary_resistance == {"left": 3, "max": 3}, "3 legendary actions, 3 resistances (%s)" % [u])
	dm.mark_action(CHIEF, "legendary", true, "Shout (Costs 2 Actions)")
	dm.mark_action(CHIEF, "legendary_resistance", true, "")
	u = dm.turn_usage(CHIEF)
	_check(u.legendary.left == 1 and u.legendary_resistance.left == 2, "a Shout costs 2, a resistance is spent")

	_next_to(dm, BORIN)
	_check(_has(dm, BORIN, "poisoned"), "Borin's turn: still poisoned")
	_next_to(dm, ARIA)
	_check(not _has(dm, BORIN, "poisoned") and _line(dm, "poisoned ended (end of Borin"), "the end of Borin's next turn: poisoned ends, with a log line")
	_check(_has(dm, ARIA, "frightened"), "Aria still frightened")

	var lines := dm.rolls.size()
	_next_to(dm, CHIEF)
	_check(_line(dm, "Regeneration: regains 5 HP", lines), "the chief's turn: regeneration reminder")
	_check(_line(dm, "Fire Breath (Recharge 5-6): recharge", lines), "the chief's turn: a recharge roll")
	u = dm.turn_usage(CHIEF)
	var recharged := dm.rolls.slice(lines).any(func(r: Dictionary) -> bool: return "ready again" in str(r.get("text", "")))
	_check(recharged == (u.get("spent", []) as Array).is_empty(), "spent until the roll brings it back")
	_check(u.legendary.left == 3 and u.legendary_resistance.left == 2, "legendary actions are back, the resistance is not")
	_check(_has(dm, ARIA, "frightened"), "Aria: one of the chief's turns, still frightened")
	_next_to(dm, CHIEF)
	_check(not _has(dm, ARIA, "frightened") and _line(dm, "frightened ended (start of Goblin Chief"), "the second of the chief's turns: Aria's fear ends")
	for i in 10:  # until the breath is back (so the next check is clean)
		if (dm.turn_usage(CHIEF).get("spent", []) as Array).is_empty():
			break
		_next_to(dm, CHIEF)
	_check((dm.turn_usage(CHIEF).get("spent", []) as Array).is_empty(), "the breath recharges sooner or later")

	# Assist: only a reminder
	var settings := dm.rules_settings().duplicate(true)
	settings["automation"] = {"durations": "assist"}
	dm.set_rules_settings(settings)
	dm.set_condition(ARIA, "blinded", true, 0, {"rounds": 1, "of": CHIEF})
	_next_to(dm, BORIN)
	_next_to(dm, CHIEF)
	_check(_has(dm, ARIA, "blinded") and _line(dm, "blinded has run out"), "Assist: it stays, the DM is reminded")
	dm.set_condition(ARIA, "blinded", false)
	settings["automation"] = {}
	dm.set_rules_settings(settings)

	# save ends: the chief (the DM's) rolls at the end of its turn, Borin's player is asked
	dm.set_condition(CHIEF, "frightened", true, 0, {"rounds": 10, "save_ends": {"ability": "wis", "dc": 1}})
	dm.set_condition(BORIN, "frightened", true, 0, {"rounds": 10, "save_ends": {"ability": "wis", "dc": 1}})
	_next_to(dm, BORIN)
	var ended := dm.rolls.filter(func(r: Dictionary) -> bool: return r.get("save") is Dictionary and str(r.save.get("ends", "")) == "frightened" and NetTable.roll_bbcode(r).contains("frightened ends"))
	_check(not _has(dm, CHIEF, "frightened") and ended.size() == 1, "the end of the chief's turn: it saves, frightened ends")
	_next_to(dm, ARIA)
	var card: Array = dm.rolls.filter(func(r: Dictionary) -> bool: return r.get("ref", "") == BORIN and r.get("save") is Dictionary and str(r.save.get("ends", "")) == "frightened")
	_check(card.size() == 1 and card[0].save.targets[0].get("waiting", false) and _has(dm, BORIN, "frightened"), "Borin's player is asked to save")
	if not card.is_empty():
		dm.answer_save(int(card[0].id), BORIN)
	_check(not _has(dm, BORIN, "frightened"), "Borin's save ends it")

	_check(_line(dm, "Initiative 20: lair action"), "each round: the lair action reminder (initiative 20, losing ties)")

	# the clock: a minute out of combat
	dm.end_combat()
	dm.advance_clock(60, "a rest")
	dm.set_condition(ARIA, "poisoned", true, 0, {"rounds": 10})
	dm.advance_clock(1)
	_check(not _has(dm, ARIA, "poisoned") and _line(dm, "poisoned ended (after 1 min"), "after a minute on the clock: it ends")
	dm.mark_action(CHIEF, "legendary_resistance", true, "")
	_check(dm.turn_usage(CHIEF).legendary_resistance.left == 1, "Legendary Resistance counts per day, out of combat too")
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("turn_engine: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _next_to(dm: NetTable, who: String) -> void:
	for i in (dm.combat_state().order as Array).size() + 1:
		dm.next_turn()
		if str(dm.combat_state().current) == who:
			return


func _has(dm: NetTable, ref: String, cond: String) -> bool:
	return cond in (dm.sheet_for(Reveal.DM, ref).get("conditions", []) as Array)


func _line(dm: NetTable, text: String, from := 0) -> bool:
	return dm.rolls.slice(from).any(func(r: Dictionary) -> bool: return text in str(r.get("text", "")))


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
