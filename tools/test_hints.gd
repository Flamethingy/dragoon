extends SceneTree
## Headless check of encounter difficulty and reaction hints (TASK-72): 2014 thresholds with
## the count multiplier (and small parties), the 2024 budget, the DM's Start combat button;
## with reaction hints on, Shield / Uncanny Dodge after a hit, Counterspell when a foe casts
## and opportunity attacks when a token leaves a foe's reach, only for that creature's players.
## godot --headless --path . -s tools/test_hints.gd

const PORT := 47817
const ADDRESS := "127.0.0.1:47817"
const DIR := "user://test_hints"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const BORIN := "characters/borin"
const ARIA := "characters/aria"

var _failed := 0


func _init() -> void:
	var d := Rules.encounter_difficulty([3, 3, 3, 3], [200, 200])
	_check(d.xp == 400 and d.adjusted == 600 and d.rating == "medium" and d.thresholds.hard == 900, "4 × level 3 vs 2 CR 1: 600 adjusted, medium (%s)" % [d])
	_check(Rules.encounter_difficulty([1], [200]).rating == "deadly", "a lone level 1 vs CR 1: deadly (one step up)")
	_check(Rules.encounter_difficulty([5, 5, 5, 5, 5, 5], [450]).adjusted == 450, "6 characters: one step down (×1 stays ×1... at the first step)")
	var d24 := Rules.encounter_difficulty([3, 3, 3, 3], [200, 200, 200], "2024")
	_check(d24.adjusted == 600 and d24.rating == "low" and d24.thresholds.has("moderate"), "2024: no multiplier, low (%s)" % [d24])
	_check(Rules.encounter_difficulty([], [200]).rating == "none", "no party: nothing to say")

	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	tl.edit_entry("spells", {"id": "shield", "name": "Shield", "level": 1, "casting_time": "1 reaction", "description": "+5 AC."})
	tl.edit_entry("spells", {"id": "counterspell", "name": "Counterspell", "level": 3, "casting_time": "1 reaction", "description": "You interrupt a spell."})
	tl.edit_entry("spells", {"id": "test-hex", "name": "Test Hex", "level": 1, "casting_time": "1 action", "description": "The target must succeed on a Wisdom saving throw or be frightened for 1 minute."})
	tl.edit_entry("features", {"id": "uncanny-dodge", "name": "Uncanny Dodge", "text": "When an attacker that you can see hits you with an attack, you can use your reaction to halve the attack's damage against you."})
	var borin := tl.entry(BORIN).duplicate(true)
	borin["classes"] = [{"class": "classes/wizard", "level": 5}]
	borin["spells"] = ["spells/shield", "spells/counterspell"]
	borin["features"] = ["uncanny-dodge"]
	tl.edit_entry("characters", borin)
	var chief := tl.entry(CHIEF).duplicate(true)
	chief["spells"] = ["spells/test-hex"]
	tl.edit_entry("creatures", chief)
	await process_frame
	var dm := _table("DM", "dm", true)
	var bob := _table("Bob", "bob")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(bob.join(ADDRESS, "bob") == OK, "Bob joins")
	await _until(func() -> bool: return dm.grid.tokens.has(BORIN) and dm.grid.tokens.has(CHIEF) and bob.grid.tokens.has(BORIN))
	var diff := dm.encounter_difficulty()
	_check(str(diff.get("rating", "none")) != "none" and int(diff.xp) > 0, "the fight on this map (%s)" % [diff])
	dm._ui._refresh()
	_check((dm._ui.find_child("Combat", true, false) as Button).text.begins_with("Start combat ("), "the DM's button shows it (%s)" % (dm._ui.find_child("Combat", true, false) as Button).text)

	# hints are off by default
	var row := {"hit": true, "crit": false, "total": 14, "ac": 12}
	var lines := dm.rolls.size()
	dm._attack_hints(BORIN, dm.sheet_for(Reveal.DM, BORIN), row)
	_check(dm.rolls.size() == lines, "reaction hints: off by default")
	var rs := dm.rules_settings().duplicate(true)
	rs["automation"] = {"reactions": "assist"}
	dm.set_rules_settings(rs)
	dm._attack_hints(BORIN, dm.sheet_for(Reveal.DM, BORIN), row)
	var shield := dm.rolls.filter(func(r: Dictionary) -> bool: return str(r.get("text", "")).begins_with("Shield (reaction"))
	_check(shield.size() == 1 and (shield[0].private as Array) == ["bob"], "Shield: 14 vs AC 12 + 5 would miss, for Bob (%s)" % [shield])
	_check(dm.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")).begins_with("Uncanny Dodge")), "Uncanny Dodge")
	await _until(func() -> bool: return bob.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")).begins_with("Shield (reaction")))
	_check(bob.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")).begins_with("Shield (reaction")), "Bob gets it")
	row.total = 18
	lines = dm.rolls.filter(func(r: Dictionary) -> bool: return str(r.get("text", "")).begins_with("Shield")).size()
	dm._attack_hints(BORIN, dm.sheet_for(Reveal.DM, BORIN), row)
	_check(dm.rolls.filter(func(r: Dictionary) -> bool: return str(r.get("text", "")).begins_with("Shield")).size() == lines, "18 vs 17: Shield would not help, no hint")

	# in a combat: counterspell, opportunity attacks
	dm.start_combat()
	var at := dm.grid.token_cell(CHIEF)
	dm._handle_move(1, BORIN, at + Vector2i(1, 0))
	await process_frame
	dm.cast(CHIEF, "spells/test-hex")
	dm._ui._toggle_target(BORIN)
	dm._ui.roll_attack()  # the slot (and the hint) when it is cast
	_check(dm.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")).begins_with("Counterspell (reaction") and r.get("private") == ["bob"]), "the chief casts: Bob could Counterspell")
	var free := at + Vector2i(4, 0)
	dm._handle_move(1, BORIN, free)
	_check(dm.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")).contains("leaves your reach") and str(r.get("who", "")) == dm.timeline.name_of(CHIEF)), "Borin leaves the chief's reach: the DM is reminded")
	var chief_name := dm.timeline.name_of(CHIEF)
	var oa := dm.rolls.filter(func(r: Dictionary) -> bool: return str(r.get("text", "")).contains("leaves your reach") and str(r.get("who", "")) == chief_name).size()
	dm._handle_move(1, BORIN, free + Vector2i(1, 0))
	var others := dm.rolls.filter(func(r: Dictionary) -> bool: return str(r.get("text", "")).contains("leaves your reach")).map(func(r: Dictionary) -> String: return str(r.who))
	_check(dm.rolls.filter(func(r: Dictionary) -> bool: return str(r.get("text", "")).contains("leaves your reach") and str(r.get("who", "")) == chief_name).size() == oa, "moving on far away: not again from the chief (%s)" % [others])
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("hints: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
