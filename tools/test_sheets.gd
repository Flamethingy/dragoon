extends SceneTree
## Headless check of character sheets at the table (TASK-10): clicking a token opens its
## sheet; players get their own PC's full sheet, other creatures only the info page; the DM
## sees all; HP / AC edits become events (hp.changed, sheet.changed), the entries stay as they are.
## godot --headless --path . -s tools/test_sheets.gd

const PORT := 47811
const ADDRESS := "127.0.0.1:47811"
const DIR := "user://test_sheets"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var world_file := ProjectSettings.globalize_path(DIR + "/worlds/westmarch/npcs.json")
	var world_before := FileAccess.get_file_as_string(world_file)
	var pc_before: Dictionary = Timeline.new(ProjectSettings.globalize_path(TIMELINE)).created("pcs").get("aria", {}).duplicate(true)
	await process_frame
	var dm := _table("DM", "dm", true)
	var ann := _table("Ann", "ann", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	ann.join(ADDRESS, "Ann")
	await _until(func() -> bool: return ann.my_pc == "pcs/aria" and ann.grid.tokens.has("monsters/goblin-chief"))

	# --- A click on a token opens the sheet -----------------------------------------------------
	var token: Sprite2D = ann.grid.tokens["pcs/aria"]
	var at := token.get_global_transform_with_canvas().origin
	_click(ann.grid, at)
	await _until(func() -> bool: return ann.sheets.has("pcs/aria"))
	var mine: Dictionary = ann.sheets.get("pcs/aria", {})
	_check(mine.get("_full") == true and int(mine.get("hp", 0)) == 27 and int(mine.get("ac", 0)) == 15 and mine.has("stats"), "a click on my token: my full sheet (%s)" % [mine.keys()])
	_check(mine.get("_class") == "Ranger 3" and int(mine.get("_hp_max", 0)) == 27, "class and max HP")
	var panel: SheetPanel = ann._ui.sheet
	_check(panel.visible and panel.ref == "pcs/aria" and panel._controls.visible, "the sheet panel shows it with HP controls")
	_check(panel._body.get_parsed_text().contains("27 / 27") and panel._body.get_parsed_text().contains("DEX"), "HP, abilities in the layout")
	_check(not str(mine.get("description", "")).contains("brother"), "DM-only %% comment cut from my own sheet")

	ann.open_sheet("monsters/goblin-chief")
	await _until(func() -> bool: return ann.sheets.has("monsters/goblin-chief"))
	var chief: Dictionary = ann.sheets.get("monsters/goblin-chief", {})
	_check(chief.get("_full") == false and not chief.has("hp") and not chief.has("stats") and not chief.has("ac"), "a monster: info page only (%s)" % [chief.keys()])
	_check(chief.get("name") == "Goblin Chief" and str(chief.get("description", "")) != "", "...with name and description")
	_check(not panel._controls.visible and panel._body.get_parsed_text().contains("Only its player"), "no controls on the info page")
	ann.open_sheet("pcs/borin")
	await _until(func() -> bool: return ann.sheets.has("pcs/borin"))
	_check(ann.sheets.get("pcs/borin", {}).get("_full") == false, "another player's PC: info page only")

	dm.open_sheet("monsters/goblin-chief")
	_check(dm.sheets.get("monsters/goblin-chief", {}).get("_full") == true and int(dm.sheets["monsters/goblin-chief"].hp) == 21, "the DM sees every sheet")
	_check(dm.sheets.has("monsters/goblin-chief") and (dm._ui.sheet as SheetPanel).ref == "monsters/goblin-chief", "the DM's panel")

	# --- Edits become events --------------------------------------------------------------------
	ann.open_sheet("pcs/aria")
	await _until(func() -> bool: return ann._ui.sheet.ref == "pcs/aria")
	var events_before := dm.event_log.events.size()
	panel._amount.value = 5
	(panel.find_child("Damage", true, false) as Button).pressed.emit()
	await _until(func() -> bool: return int(ann.sheets["pcs/aria"].get("hp", 0)) == 22)
	var ev: Dictionary = dm.event_log.events.back()
	_check(ev.type == "hp.changed" and ev.entity == "pcs/aria" and int(ev.data.hp) == 22 and int(ev.data.delta) == -5 and ev.by == "ann", "damage -> hp.changed by ann (%s)" % ev)
	_check(panel._body.get_parsed_text().contains("22 / 27"), "the sheet updates")
	await _until(func() -> bool: return int(ann.grid.tokens["pcs/aria"].get_meta("info").get("hp", 0)) == 22)
	_check(int(ann.grid.tokens["pcs/aria"].get_meta("info").get("hp", 0)) == 22, "the token hover shows the new HP")
	ann.change_field("pcs/aria", "temp_hp", 4)
	await _until(func() -> bool: return int(ann.sheets["pcs/aria"].get("temp_hp", 0)) == 4)
	ann.change_hp("pcs/aria", -6)
	await _until(func() -> bool: return int(ann.sheets["pcs/aria"].get("hp", 0)) == 20)
	_check(int(ann.sheets["pcs/aria"].get("temp_hp", -1)) == 0 and int(ann.sheets["pcs/aria"].hp) == 20, "damage takes temp HP first")
	ann.change_hp("pcs/aria", 50)
	await _until(func() -> bool: return int(ann.sheets["pcs/aria"].get("hp", 0)) == 27)
	_check(int(ann.sheets["pcs/aria"].hp) == 27, "healing stops at max HP")
	ann._ui.sheet._ac.value = 17
	await _until(func() -> bool: return int(ann.sheets["pcs/aria"].get("ac", 0)) == 17)
	ev = dm.event_log.events.back()
	_check(ev.type == "sheet.changed" and ev.data.path == "ac" and int(ev.data.from) == 15 and int(ev.data.to) == 17, "AC -> sheet.changed (%s)" % ev)

	# --- Not mine: refused ------------------------------------------------------------------------
	var count := dm.event_log.events.size()
	ann.change_hp("monsters/goblin-chief", -3)
	await _until(func() -> bool: return ann.status.contains("not your sheet"))
	_check(ann.status.contains("not your sheet") and dm.event_log.events.size() == count, "a player can't damage the chief")
	ann.change_field("pcs/aria", "player", "bob")
	await _until(func() -> bool: return ann.status.contains("can't be changed"))
	_check(dm.event_log.events.size() == count, "locked fields stay")
	dm.change_hp("monsters/goblin-chief", -30)
	_check(int(dm.sheets["monsters/goblin-chief"].hp) == 0, "the DM damages the chief (HP not below 0)")

	# --- The file never changes; a restart replays ----------------------------------------------
	_check(FileAccess.get_file_as_string(world_file) == world_before, "world files untouched")
	_check(Timeline.new(ProjectSettings.globalize_path(TIMELINE)).created("pcs").get("aria", {}) == pc_before, "the PC entry itself is untouched (play is events)")
	_check(dm.event_log.events.size() > events_before, "all of it is in events.jsonl")
	var dm2 := _table("DM2", "dm2")
	await process_frame
	dm.multiplayer.multiplayer_peer.close()
	dm2.host(PORT + 1)
	_check(int(dm2.sheet_for("dm", "pcs/aria").hp) == 27 and int(dm2.sheet_for("dm", "pcs/aria").ac) == 17, "a restarted host has the same sheet")
	_check(int(dm2.sheet_for("dm", "monsters/goblin-chief").hp) == 0, "...and the chief at 0")

	print("sheets: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


## Left press + release at a screen position (no drag).
func _click(grid: TokenGrid, at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		grid._unhandled_input(e)


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
