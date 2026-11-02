extends SceneTree
## Headless check of the action economy (TASK-62): Action / Bonus / Reaction / Object used this
## turn (an attack takes the action, a click marks a pip), the metres moved of the speed (Dash
## doubles it, restrained makes it 0), a new turn resets it, the tracker rows and the move trail
## carry the budget, and the HUD's turn piece. Display only: nothing is ever blocked.
## godot --headless --path . -s tools/test_turn_economy.gd

const PORT := 47806
const DIR := "user://test_turn_economy"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	# --- Speed --------------------------------------------------------------------------------
	_check(Rules.speed({"speed": {"walk": 9}}) == 9.0 and Rules.speed({"speed": "7.5 m"}) == 7.5 and Rules.speed({"speed": 12}) == 12.0 and Rules.speed({}) == 9.0, "speed from the sheet")
	_check(Rules.speed({"speed": {"walk": 9}, "conditions": ["restrained"]}) == 0.0 and Rules.speed({"speed": {"walk": 9}, "conditions": ["grappled"]}) == 0.0, "restrained / grappled: 0")
	_check(Rules.speed({"speed": {"walk": 9}, "conditions": ["exhaustion"], "exhaustion": 2}, "2024") == 6.0, "2024 exhaustion: 1.5 m per level")

	# --- At the table -------------------------------------------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var dm := _table("DM", "dm", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	await _until(func() -> bool: return dm.grid.tokens.has(BORIN) and dm.grid.tokens.has(CHIEF))
	_check(dm.turn_usage(CHIEF).moved == 0.0 and dm.grid.budget.call(CHIEF) == {}, "no combat: no budget on the trail")
	var rs := dm.rules_settings().duplicate(true)
	(rs.house_rules as Dictionary)["crowded_squares"] = "off"  # straight lines here may cross other goblins (TASK-79: test_crowd)
	dm.set_rules_settings(rs)
	dm.start_combat()
	var u := dm.turn_usage(CHIEF)
	_check(not u.action and not u.bonus and u.moved == 0.0 and u.speed == 9.0, "a fresh turn: nothing used, 9 m (%s)" % [u])
	var at := dm.grid.token_cell(CHIEF)
	dm._handle_move(1, CHIEF, at + Vector2i(3, 1))
	dm._handle_move(1, CHIEF, at + Vector2i(5, 1))
	u = dm.turn_usage(CHIEF)
	_check(u.moved == 7.5, "moved 3 + 2 squares = 7.5 m (%s)" % [u.moved])
	dm._handle_move(1, CHIEF, at + Vector2i(9, 1))
	u = dm.turn_usage(CHIEF)
	_check(u.moved == 13.5 and dm.grid.token_cell(CHIEF) == at + Vector2i(9, 1), "over the budget: it only warns, the move happens")
	dm.rng.seed = 3
	dm._handle_attack(1, CHIEF, "scimitar", [BORIN], {})
	_check(dm.turn_usage(CHIEF).action and not dm.turn_usage(CHIEF).bonus, "an attack takes the action")
	dm.mark_action(CHIEF, "bonus")
	dm.mark_action(CHIEF, "action", false)
	u = dm.turn_usage(CHIEF)
	_check(u.bonus and not u.action, "pips are marked and unmarked by hand")
	dm.mark_action(CHIEF, "action", true, "dash")
	u = dm.turn_usage(CHIEF)
	_check(u.dash and u.action and u.speed == 18.0, "Dash: the action, double speed (%s)" % [u])
	var row: Dictionary = (dm.combat_view().order as Array).filter(func(c: Dictionary) -> bool: return c.entity == CHIEF)[0]
	_check(row.usage.moved == 13.5 and row.usage.speed == 18.0 and dm.grid.budget.call(CHIEF).speed == 18.0, "the tracker row and the move trail carry it")
	dm.set_condition(CHIEF, "restrained")
	_check(dm.turn_usage(CHIEF).speed == 0.0, "restrained: speed 0 (even dashing)")
	dm.set_condition(CHIEF, "restrained", false)

	# the HUD's turn piece
	var hud := CharacterHud.new()
	hud.table = dm
	hud.active = CHIEF
	var w := HudWidgets._turn(hud)
	_check((w.get_node("Pip_action") as Button).button_pressed and (w.get_node("Pip_bonus") as Button).button_pressed and not (w.get_node("Pip_reaction") as Button).button_pressed, "the HUD's pips")
	_check((w.get_node("Move") as Label).text == "13.5 / 18 m" and (w.get_node("Dash") as Button).button_pressed, "the HUD: moved / speed, Dash (%s)" % (w.get_node("Move") as Label).text)
	(w.get_node("Pip_reaction") as Button).button_pressed = true
	_check(dm.turn_usage(CHIEF).reaction, "a click on a pip marks it")
	w.free()
	hud.active = "characters/nobody"
	w = HudWidgets._turn(hud)
	_check(w.get_node_or_null("Pip_action") == null, "not in the combat: no pips")
	w.free()
	hud.free()

	# a new turn of the chief resets it
	for i in (dm.combat_state().order as Array).size() + 1:
		dm.next_turn()
		if str(dm.combat_state().order[int(dm.combat_state().turn)].entity) == CHIEF:
			break
	u = dm.turn_usage(CHIEF)
	_check(not u.action and not u.bonus and not u.reaction and u.moved == 0.0 and u.speed == 9.0, "its next turn starts fresh (%s)" % [u])
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("turn_economy: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
