extends SceneTree
## Headless check of area templates, the ruler and targeting (TASK-67): the five shapes'
## squares (centre or half covered), placing by clicks (a sphere at a grid corner, a cone aimed),
## templates shared with everyone, rotated and removed, an area's creatures becoming the attack
## bar's targets, the ruler in metres and range warnings on the cards.
## godot --headless --path . -s tools/test_areas.gd

const PORT := 47810
const ADDRESS := "127.0.0.1:47810"
const DIR := "user://test_areas"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const BORIN := "characters/borin"
const ARIA := "characters/aria"

var _failed := 0


func _init() -> void:
	# --- Geometry (cell units) ---------------------------------------------------------------
	var sphere := {"shape": "sphere", "size": 4.0, "origin": [10.0, 10.0], "angle": 0.0}
	var cells := AreaLayer.cells_of(sphere)
	_check(Vector2i(10, 10) in cells and Vector2i(9, 9) in cells and Vector2i(6, 10) in cells and not (Vector2i(14, 10) in cells) and cells.size() >= 44 and cells.size() <= 56,
		"a 6 m sphere: ~50 squares around its corner (%d)" % cells.size())
	var cone := {"shape": "cone", "size": 3.0, "origin": [5.0, 5.0], "angle": 0.0}
	cells = AreaLayer.cells_of(cone)
	_check(Vector2i(7, 5) in cells and Vector2i(7, 4) in cells and not (Vector2i(5, 7) in cells) and not (Vector2i(4, 5) in cells), "a 4.5 m cone to the east (%s)" % [cells])
	var down := cone.duplicate()
	down.angle = PI / 2
	_check(Vector2i(5, 7) in AreaLayer.cells_of(down) and not (Vector2i(7, 5) in AreaLayer.cells_of(down)), "turned 90°: it points south")
	var line := {"shape": "line", "size": 6.0, "width": 1.0, "origin": [0.0, 3.5], "angle": 0.0}
	cells = AreaLayer.cells_of(line)
	_check(cells.size() == 6 and cells.all(func(c: Vector2i) -> bool: return c.y == 3), "a 9 m line along a row: 6 squares (%s)" % [cells])
	var cube := {"shape": "cube", "size": 2.0, "origin": [0.0, 1.0], "angle": 0.0}
	cells = AreaLayer.cells_of(cube)
	cells.sort()
	_check(cells == [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1)], "a 3 m cube: 4 squares (%s)" % [cells])
	_check(AreaLayer.cells_of({"shape": "cylinder", "size": 2.0, "origin": [3.0, 3.0]}).size() == AreaLayer.cells_of({"shape": "sphere", "size": 2.0, "origin": [3.0, 3.0]}).size(), "a cylinder is a circle on the map")
	_check(AreaLayer.metres(Vector2(0.5, 0.5), Vector2(4.5, 2.5)) == 6.0, "the ruler: 4 squares (diagonals as moving) = 6 m")
	_check(Rules.range_of("24.4/97.5 m") == {"normal": 24.4, "long": 97.5} and Rules.range_of("1.5 m") == {"normal": 1.5, "long": 1.5} and Rules.range_of(18.0).long == 18.0, "ranges")

	# --- At the table -------------------------------------------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	tl.edit_entry("spells", {"id": "test-boom", "name": "Test Boom", "level": 1, "range_m": 9, "casting_time": "1 action",
		"description": "Each creature in a 3 m-radius sphere centered on a point you choose must make a dexterity saving throw, taking 2d6 fire damage on a failed save, or half as much damage on a successful one."})
	var borin := tl.entry(BORIN).duplicate(true)
	borin["spells"] = ["spells/test-boom"]
	tl.edit_entry("characters", borin)
	await process_frame
	var dm := _table("DM", "dm", true)
	var ann := _table("Ann", "ann", true)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(ann.join(ADDRESS, "Ann") == OK, "Ann joins")
	await _until(func() -> bool: return ann.grid.tokens.has(CHIEF) and dm.grid.tokens.has(BORIN) and ann.my_pc == ARIA)

	# placing by clicks: a sphere at the corner next to the chief
	var at := dm.grid.token_cell(CHIEF)
	var areas := dm.grid.areas
	areas.start_place("sphere", 3.0)
	_check(areas.mode == "place", "placing")
	var corner := Vector2(at) + Vector2(1, 1)
	_move(areas, dm.grid.offset + (corner + Vector2(0.1, -0.2)) * dm.grid.cell)
	_check(Vector2(areas.placing.origin[0], areas.placing.origin[1]) == corner, "it snaps to the grid corner")
	_click(areas, dm.grid.offset + corner * dm.grid.cell)
	_check(areas.mode == "" and dm.templates.size() == 1 and dm.templates[0].shape == "sphere" and is_equal_approx(float(dm.templates[0].size), 2.0), "placed: the table has it (%s)" % [dm.templates])
	await _until(func() -> bool: return ann.templates.size() == 1)
	_check(ann.templates.size() == 1 and ann.grid.areas.templates.size() == 1, "Ann sees it too")
	_check(CHIEF in AreaLayer.tokens_in(dm.templates[0], dm.grid), "the chief is inside")

	# a cone: origin, then aim
	areas.start_place("cone", 4.5)
	var o := Vector2(at) + Vector2(-3, 0)
	_move(areas, dm.grid.offset + o * dm.grid.cell)
	_click(areas, dm.grid.offset + o * dm.grid.cell)
	_check(areas.aiming and dm.templates.size() == 1, "a cone waits for its aim")
	_move(areas, dm.grid.offset + (o + Vector2(0, 3)) * dm.grid.cell)
	_check(is_equal_approx(float(areas.placing.angle), PI / 2), "aimed south")
	_click(areas, dm.grid.offset + (o + Vector2(0, 3)) * dm.grid.cell)
	_check(dm.templates.size() == 2 and is_equal_approx(float(dm.templates[1].angle), PI / 2), "the cone is placed")
	dm.rotate_template(str(dm.templates[1].id), -90.0)
	_check(is_equal_approx(float(dm.templates[1].angle), 0.0), "and turned")
	ann.remove_template(str(dm.templates[0].id))
	await process_frame
	await process_frame
	_check(dm.templates.size() == 2, "Ann can't remove the DM's area")
	dm.remove_template("")
	await _until(func() -> bool: return ann.templates.is_empty())
	_check(dm.templates.is_empty() and ann.templates.is_empty(), "the DM clears them all")

	# the ruler
	areas.start_ruler()
	var from := dm.grid.offset + (Vector2(2, 2) + Vector2(0.5, 0.5)) * dm.grid.cell
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	areas.ruler_from = Vector2(2.5, 2.5)
	areas.ruler_to = Vector2(2.5, 2.5)
	areas.measuring = true
	areas.ruler_to = Vector2(6.5, 4.5)
	_check(areas.ruler_metres() == 6.0, "measured: 6 m")
	areas.cancel()

	# a spell's area: its creatures become the targets; range warning
	dm.open_sheet(BORIN, false)
	_check((dm.sheets[BORIN]._refs["spells/test-boom"].area as Dictionary) == {"shape": "sphere", "size_m": 3.0}, "the spell knows its area")
	dm.cast(BORIN, "spells/test-boom")
	var ui := dm._ui
	_check(ui.attack.get("kind") == "save" and (ui.find_child("PlaceArea", true, false) as Button).visible, "the attack bar offers Place area")
	(ui.find_child("PlaceArea", true, false) as Button).pressed.emit()
	_check(areas.mode == "place" and is_equal_approx(float(areas.placing.size), 2.0), "a 3 m sphere to place")
	_move(areas, dm.grid.offset + corner * dm.grid.cell)
	_click(areas, dm.grid.offset + corner * dm.grid.cell)
	_check(CHIEF in (ui.attack.targets as Array) and not (BORIN in (ui.attack.targets as Array)), "the creatures in it are the targets (%s)" % [ui.attack.targets])
	var far := (ui.attack.targets as Array).filter(func(id: Variant) -> bool: return dm.distance_m(BORIN, str(id)) > 9.0).size()
	var label := (ui.find_child("What", true, false) as Label).text
	_check((far > 0) == label.contains("%d out of range" % far), "the bar warns about targets beyond 9 m (%d: %s)" % [far, label])
	ui.roll_attack()
	var card: Array = dm.rolls.filter(func(r: Dictionary) -> bool: return r.get("save") is Dictionary and str(r.save.name) == "Test Boom")
	_check(card.size() == 1, "rolled anyway")
	if card.size() == 1:
		_check(NetTable.roll_bbcode(card[0]).contains("out of range") == (far > 0), "the card says so too")
	# an attack beyond its range
	var aria_cell := dm.grid.token_cell(ARIA)
	var note := dm._range_note(ARIA, CHIEF, {"normal": 1.5, "long": 1.5})
	_check(note.is_empty() == (dm.distance_m(ARIA, CHIEF) <= 1.5) and (note.is_empty() or bool(note.far)), "a reach weapon out of reach is noted (%s from %s)" % [note, aria_cell])
	_check(NetTable._range_text({"m": 30.0, "normal": 24.4, "long": 97.5, "far": false}).contains("long range 30 m"), "long range: disadvantage noted")
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("areas: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


## The area layer reads the mouse from the viewport: put it there, then send the event.
func _move(areas: AreaLayer, world: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = areas.get_canvas_transform() * world
	areas.handle(ev)


func _click(areas: AreaLayer, world: Vector2) -> void:
	_move(areas, world)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = areas.get_canvas_transform() * world
	areas.handle(ev)


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
