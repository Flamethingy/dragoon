extends SceneTree
## Headless check of walls, doors, light, fog of war and difficult terrain (TASK-73): sight
## lines through walls and open doors, darkness, lights and darkvision, the movement cost of
## difficult terrain, the DM drawing walls with the map tools, and at the table: a player sees
## only what their token sees (hidden tokens are not even sent), remembers what they saw,
## opens a door next to them but not across the map, and moving through difficult terrain
## counts double in the budget.
## godot --headless --path . -s tools/test_vision.gd

const PORT := 47819
const ADDRESS := "127.0.0.1:47819"
const DIR := "user://test_vision"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	# geometry
	var wall := [{"a": [5, 0], "b": [5, 10]}]
	_check(not Vision.line_clear(Vector2(2.5, 5.5), Vector2(7.5, 5.5), Vision.blocking(wall, {})) and Vision.line_clear(Vector2(2.5, 5.5), Vector2(4.5, 1.5), Vision.blocking(wall, {})), "a wall blocks the line across it only")
	var map := {"walls": [{"a": [5, 0], "b": [5, 4]}, {"a": [5, 4], "b": [5, 6], "door": true}, {"a": [5, 6], "b": [5, 10]}]}
	var me := [{"cell": Vector2i(2, 5), "cells": 1.0, "darkvision": 0.0}]
	var seen := Vision.visible(map, me, {}, Vector2i(10, 10))
	_check(seen.has(Vector2i(3, 5)) and seen.has(Vector2i(2, 5)) and not seen.has(Vector2i(7, 5)), "behind the closed door: unseen")
	_check(Vision.visible(map, me, {1: true}, Vector2i(10, 10)).has(Vector2i(7, 5)), "the door open: seen")
	var dark := {"lighting": "dark", "lights": [{"at": [8, 8], "bright": 3.0, "dim": 3.0}]}
	seen = Vision.visible(dark, me, {}, Vector2i(10, 10))
	_check(seen.size() == 1 + Vision.visible(dark, [], {}, Vector2i(10, 10)).size() + _lit(dark) - 0 and seen.has(Vector2i(8, 8)) and not seen.has(Vector2i(3, 5)), "dark: only its own square and the lit ones (%d)" % seen.size())
	seen = Vision.visible(dark, [{"cell": Vector2i(2, 5), "cells": 1.0, "darkvision": 18.0}], {}, Vector2i(30, 30))
	_check(seen.has(Vector2i(3, 5)) and seen.has(Vector2i(13, 5)) and not seen.has(Vector2i(16, 5)), "darkvision 18 m: 12 squares")
	_check(Vision.light_at(Vector2(8.5, 9.5), dark.lights, "dark") == 2 and Vision.light_at(Vector2(8.5, 11.5), dark.lights, "dark") == 1 and Vision.light_at(Vector2(8.5, 14.5), dark.lights, "dark") == 0, "bright, then dim light")
	_check(Vision.darkvision_m({"senses": ["Darkvision 18 m"]}) == 18.0 and is_equal_approx(Vision.darkvision_m({"senses": ["darkvision 60 ft."]}), 18.0), "darkvision from the senses")
	var mud := {Vector2i(1, 0): true, Vector2i(2, 0): true}
	_check(Vision.move_cost(Vector2i(0, 0), Vector2i(3, 0), mud) == 5 and Vision.move_cost(Vector2i(0, 0), Vector2i(3, 3), mud) == 3, "difficult terrain: +1 per square entered")
	_check(MovePlans.extra_cost([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], mud) == 2, "the move trail counts it too")

	# at the table
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	await process_frame
	var dm := _table("DM", "dm", true)
	var bob := _table("Bob", "bob")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(bob.join(ADDRESS, "bob") == OK, "Bob joins")
	await _until(func() -> bool: return dm.grid.tokens.has(BORIN) and bob.grid.tokens.has(CHIEF) and bob.my_pc == BORIN)
	_check((dm._ui.find_child("MapTools", true, false) as Control).visible, "the DM has the map tools")

	# the DM draws a wall with the tool
	var layer := dm.grid.map_layer
	layer.start("wall")
	_click(layer, dm.grid, Vector2(0, 0))
	_click(layer, dm.grid, Vector2(0, 2))
	_check((dm.timeline.entry(dm.map_id).get("walls", []) as Array).size() == 1, "two corners: a wall, saved with the map")
	layer.cancel()

	# a box of walls around the chief, a door on Borin's side; fog on
	var c := dm.grid.token_cell(CHIEF)
	var b := dm.grid.token_cell(BORIN)
	var sides := {"left": [[c.x, c.y], [c.x, c.y + 1]], "right": [[c.x + 1, c.y], [c.x + 1, c.y + 1]], "top": [[c.x, c.y], [c.x + 1, c.y]], "bottom": [[c.x, c.y + 1], [c.x + 1, c.y + 1]]}
	var facing := ("left" if b.x < c.x else "right") if absi(b.x - c.x) >= absi(b.y - c.y) else ("top" if b.y < c.y else "bottom")
	var walls := []
	for k: String in sides:
		walls.append({"a": sides[k][0], "b": sides[k][1], "door": k == facing})
	dm.edit_map({"walls": walls, "fog": true})
	await _until(func() -> bool: return not bob.grid.tokens.has(CHIEF))
	_check(not bob.grid.tokens.has(CHIEF) and bob.grid.tokens.has(BORIN), "fog: the walled-in chief isn't even sent to Bob")
	_check(dm.grid.tokens.has(CHIEF) and not dm.grid.map_layer.fog, "the DM sees everything")
	_check(bob.grid.map_layer.fog and bob.grid.map_layer.seen.has(b) and not bob.grid.map_layer.seen.has(c), "Bob's fog: his square seen, the chief's not")
	_check(bob.grid.map_layer.doors.size() == 1 and bob.grid.map_layer.walls.is_empty(), "Bob gets the door, not the walls")
	var door := int(bob.grid.map_layer.doors[0].i)

	# Bob is far from the door: he can't open it; the DM can
	var far := Vector2(b).distance_to(Vector2(c)) > 2.5
	bob.toggle_door(door)
	for i in 20:
		await process_frame
	if far:
		_check(not bool(dm.doors_open(dm.map_id).get(door, false)), "a door across the map: not for Bob")
	dm.toggle_door(door)
	await _until(func() -> bool: return bob.grid.tokens.has(CHIEF))
	_check(bob.grid.tokens.has(CHIEF) and bob.grid.map_layer.seen.has(c), "the DM opens it: Bob sees the chief")
	dm.toggle_door(door)
	await _until(func() -> bool: return not bob.grid.tokens.has(CHIEF))
	_check(not bob.grid.tokens.has(CHIEF) and bob.grid.map_layer.explored.has(c) and not bob.grid.map_layer.seen.has(c), "closed again: hidden, but Bob remembers the room")
	_check((dm.explored[dm.map_id]["bob"] as Dictionary).has(c), "what Bob saw is kept by the table")

	# difficult terrain in a combat
	dm.edit_map({"fog": false, "walls": [], "terrain": [[b.x + 1, b.y]]})
	await process_frame
	dm.start_combat()
	var to := b + Vector2i(2, 0)
	if dm.grid.can_place(BORIN, to):
		dm._handle_move(1, BORIN, to)
		_check(is_equal_approx(float(dm.turn_usage(BORIN).moved), 4.5), "two squares, one of them difficult: 4.5 m (%s)" % dm.turn_usage(BORIN).moved)
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("vision: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


## How many squares the map's lights make visible (dark map, no viewer).
func _lit(map: Dictionary) -> int:
	var n := 0
	for y in 10:
		for x in 10:
			if Vision.light_at(Vector2(x + 0.5, y + 0.5), map.lights, "dark") > 0 and Vision.line_clear(Vector2(2.5, 5.5), Vector2(x + 0.5, y + 0.5), []):
				n += 1
	return n


func _click(layer: MapLayer, g: TokenGrid, corner: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = layer.get_canvas_transform() * (g.offset + corner * g.cell)
	layer.handle(ev)


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
