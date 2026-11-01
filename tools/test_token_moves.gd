extends SceneTree
## Headless check of selecting and steering tokens (TASK-42): click and box selection, WASD /
## arrows one cell (two keys together: diagonal), the facing triangle in 8 directions, Shift
## only turns, the picture mirrored by facing, moves and turns as events (facing kept by
## Replay.facings_on), blocked squares refused.
## godot --headless --path . -s tools/test_token_moves.gd

const DIR := "user://test_token_moves"
const PORT := 47812

var _failed := 0


func _init() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	var red := Worlds.install_example(base.path_join("worlds"))
	await process_frame
	var holder := Node.new()
	holder.name = "DM"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/DM"))
	var table := NetTable.new()
	table.name = "Table"
	table.timeline_dir = red
	table.cache_dir = DIR.path_join("cache")
	table.auto_ui = false  # no HUD: its active token would count as selected (tested in test_character_hud)
	holder.add_child(table)
	await process_frame
	_check(table.host(PORT) == OK, "DM hosts")
	table.maps_changed("maps/forest-road")
	var grid := table.grid
	var ids: Array = grid.tokens.keys().filter(func(id: String) -> bool: return id != NetTable.PARTY)
	_check(ids.size() >= 2, "tokens on the map (%s)" % [ids])
	var a: String = ids[0]
	var b: String = ids[1]

	# --- Selecting -------------------------------------------------------------------------------
	grid.select([a])
	_check(grid.selection() == [a] and (grid.tokens[a].get_node("Marks") as TokenMarks).selected, "a click selects, with a ring")
	grid.select([b], true)
	_check(grid.selection().size() == 2, "shift adds")
	grid.select([])
	_check(grid.selection().is_empty() and not (grid.tokens[a].get_node("Marks") as TokenMarks).selected, "a click on the empty map clears it")
	grid.select([a])

	# --- Steps and facing -----------------------------------------------------------------------
	var start := grid.token_cell(a)
	var free_dir := Vector2i(1, 0)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if grid.can_place(a, start + d) and grid.can_place(a, start + d + Vector2i(0, 1)) and grid.can_place(a, start + d + d):
			free_dir = d
			break
	grid.key_step(KEY_D if free_dir.x > 0 else KEY_A if free_dir.x < 0 else KEY_S if free_dir.y > 0 else KEY_W, false, true)
	_check(grid.token_cell(a) == start + free_dir, "a movement key steps one cell (%s -> %s)" % [start, grid.token_cell(a)])
	_check(grid.token_facing(a) == TokenGrid.facing_of(free_dir) and (grid.tokens[a].get_node("Marks") as TokenMarks).facing == TokenGrid.facing_of(free_dir), "and turns it that way, the triangle shows it")
	var last: Dictionary = table.event_log.events.back()
	_check(last.type == "token.moved" and last.data.get("facing") == TokenGrid.facing_of(free_dir), "a token.moved event with the facing")
	var here := grid.token_cell(a)
	grid.step_selection(Vector2i(-1, 1), true)
	_check(grid.token_cell(a) == here and grid.token_facing(a) == "sw", "Shift: only turns (south-west)")
	last = table.event_log.events.back()
	_check(last.type == "token.turned" and last.data.facing == "sw", "a token.turned event")
	_check(grid.tokens[a].flip_h, "looking left: a right-facing picture is mirrored")
	grid.step_selection(Vector2i(1, -1), true)
	_check(not grid.tokens[a].flip_h and grid.token_facing(a) == "ne", "looking right again: not mirrored")
	grid.step_selection(Vector2i(0, 1), true)
	_check(not grid.tokens[a].flip_h and grid.token_facing(a) == "s", "straight down keeps the last side")

	# Two keys pressed together: a diagonal.
	var before := grid.token_cell(a)
	grid._pending = Vector2i.ZERO
	grid.key_step(KEY_S, false)
	grid.key_step(KEY_D, false)
	await create_timer(TokenGrid.COMBINE_SECONDS * 3).timeout
	var moved := grid.token_cell(a) - before
	_check(moved == Vector2i(1, 1) or grid.token_facing(a) == "se", "S and D together: one diagonal step to the south-east (%s)" % moved)

	# The facing survives a rebuild (from the events).
	var facings := Replay.facings_on(table.map_id, table.event_log.effective())
	_check(facings.get(a) == grid.token_facing(a), "facings come back from the events")
	table.maps_changed("maps/forest-road")
	_check(grid.token_facing(a) == facings.get(a), "after rebuilding the map it still looks that way")

	# A blocked square is refused.
	grid.select([a])
	var cell_b := grid.token_cell(b)
	var next_to := cell_b - Vector2i(1, 0)
	if grid.can_place(a, next_to):
		table._handle_move(1, a, next_to)
		var count := table.event_log.events.size()
		grid.step_selection(Vector2i(1, 0))
		_check(grid.token_cell(a) == next_to and table.event_log.events.size() == count + 1 and table.event_log.events.back().type == "token.turned", "into another token: no move, but it turns")

	# A numbered copy follows the token look of its world entry (Nico: the settings didn't show).
	var core_dir := PackageDB.default_root().path_join("5e-core-rules")
	var goblin := EntryStore.open(core_dir).find("creatures", "goblin")
	goblin.merge({"_kind": "creatures", "_layer": "core", "_package": "5e-core-rules", "_dir": core_dir}, true)
	var free := Vector2i(0, 0)
	for y in 6:
		for x in 6:
			if free == Vector2i.ZERO and Vector2i(x, y) != Vector2i.ZERO and not grid.tokens.values().any(func(t: Sprite2D) -> bool: return t.get_meta("cell") == Vector2i(x, y)):
				free = Vector2i(x, y)
	var copy_ref := table.drop_token(goblin, free)
	var ws := table.timeline.world_store()
	var wg := ws.find("creatures", "goblin")
	wg["token_style"] = {"border": "#00aa00", "background": "#112233", "faces": "left"}
	ws.save("creatures", wg)
	table.refresh_tokens()
	var shown: Variant = (grid.tokens[copy_ref].get_meta("info", {}) as Dictionary).get("token_style")
	_check(shown is Dictionary and shown.border == "#00aa00", "a copy on the map takes the world goblin's new look (%s)" % [shown])

	# Arrow keys while a button has the focus (Nico: they only worked sometimes).
	var focus_box := VBoxContainer.new()
	var b1 := Button.new()
	var b2 := Button.new()
	focus_box.add_child(b1)
	focus_box.add_child(b2)
	root.add_child(focus_box)
	b1.grab_focus()
	grid.select([a])
	var cell_before := grid.token_cell(a)
	var arrow := Vector2i(-1, 0) if grid.can_place(a, cell_before + Vector2i(-1, 0)) else Vector2i(0, 1)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_LEFT if arrow.x < 0 else KEY_DOWN
	key.physical_keycode = key.keycode
	root.push_input(key)
	await create_timer(TokenGrid.COMBINE_SECONDS * 3).timeout
	_check(grid.token_cell(a) == cell_before + arrow and b1.has_focus(), "arrow keys move the token even when a button has the focus (%s -> %s)" % [cell_before, grid.token_cell(a)])
	var typing := LineEdit.new()
	root.add_child(typing)
	typing.grab_focus()
	var cell_typing := grid.token_cell(a)
	root.push_input(key)
	await create_timer(TokenGrid.COMBINE_SECONDS * 3).timeout
	_check(grid.token_cell(a) == cell_typing, "but not while typing")
	focus_box.queue_free()
	typing.queue_free()

	# --- Dragging a selection moves all of it (Nico, 2026-11-01) ---------------------------------
	var group: Array = grid.tokens.keys().filter(func(id: String) -> bool: return id != NetTable.PARTY)
	grid.select(group)
	var lead: String = group[0]
	var spot := Vector2i(-1, -1)
	for y in range(1, grid.grid_size.y - 4):
		for x in range(1, grid.grid_size.x - 4):
			if spot.x < 0 and grid.tokens.keys().all(func(id: String) -> bool:
					var c := grid.token_cell(id)
					return c.x < x - 2 or c.x > x + 5 or c.y < y - 2 or c.y > y + 5):
				spot = Vector2i(x, y)
	_check(spot.x >= 0, "a free spot to drag to")
	var lead_token: Sprite2D = grid.tokens[lead]
	var cells: float = lead_token.get_meta("cells")
	var goal := grid.cell_center(spot, cells)
	var screen := grid.get_canvas_transform() * lead_token.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen
	grid._unhandled_input(press)
	var zoom: Vector2 = grid._camera.zoom
	var motion := InputEventMouseMotion.new()
	motion.relative = (goal - lead_token.position) * zoom
	motion.position = screen + motion.relative
	grid._unhandled_input(motion)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.position = motion.position
	var starts := {}
	for id: String in group:
		starts[id] = grid.token_cell(id)
	grid._unhandled_input(release)
	await process_frame
	# planned, not moved yet (TASK-45): ghosts at the ends, a dotted trail with the distance
	_check(group.all(func(id: String) -> bool: return grid.token_cell(id) == starts[id]), "nothing moved yet")
	_check(grid.plans.has_plans() and grid.plans.plans.size() == group.size(), "a planned move per token (%s)" % [grid.plans.plans.keys()])
	var lead_path: Array = grid.plans.plans[lead].path
	_check(lead_path[0] == starts[lead] and lead_path.back() == spot and MovePlans.squares(lead_path) == maxi(absi(spot.x - starts[lead].x), absi(spot.y - starts[lead].y)),
		"the trail runs from the token to the drop, square by square (%s)" % [lead_path])
	var lead_ghost: Sprite2D = grid.plans.plans[lead].ghost
	_check(lead_ghost.visible and lead_ghost.modulate.a < 1.0 and lead_ghost.position == grid.cell_center(spot, cells), "a transparent ghost at the end")
	_check(grid.tokens[lead].position == grid.cell_center(starts[lead], cells), "the real token stays")
	# Space: they go, along the trail
	var space := InputEventKey.new()
	space.pressed = true
	space.physical_keycode = KEY_SPACE
	grid._input(space)
	await _until(func() -> bool: return not grid.plans.plans.has(lead), 600)
	_check(grid.token_cell(lead) == spot, "the dragged token lands under the mouse (%s, wanted %s)" % [grid.token_cell(lead), spot])
	await _until(func() -> bool: return grid.plans.plans.is_empty(), 600)
	_check(grid.plans.plans.is_empty() and grid.tokens[lead].position.distance_to(grid.cell_center(spot, cells)) < 0.5, "arrived: trails and ghosts gone")
	var rects: Array[Rect2i] = []
	var near := true
	for id: String in group:
		var c := grid.token_cell(id)
		var size := maxi(1, int(grid.tokens[id].get_meta("cells")))
		near = near and maxi(absi(c.x - spot.x), absi(c.y - spot.y)) <= 3
		for r in rects:
			near = near and not r.intersects(Rect2i(c, Vector2i(size, size)))
		rects.append(Rect2i(c, Vector2i(size, size)))
	_check(near, "the others gather on the closest free cells, none overlapping (%s)" % [group.map(func(id: String) -> Vector2i: return grid.token_cell(id))])
	_check(grid.selection().size() == group.size(), "still all selected")

	# Trails: one square at a time, going back shortens them; Esc drops plans
	_check(MovePlans.extend([Vector2i(0, 0)], Vector2i(3, 1)) == [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)], "diagonals first, one square each")
	_check(MovePlans.extend([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], Vector2i(1, 0)) == [Vector2i(0, 0), Vector2i(1, 0)], "going back shortens the trail")
	_check(MovePlans._metres(3) == "4.5" and MovePlans._metres(4) == "6", "1.5 m per square")
	grid.select([a])
	var a_from := grid.token_cell(a)
	grid.plans.begin_drag([a])
	grid.plans.drag_by(a, Vector2(grid.cell * 2, 0))
	grid.plans.end_drag(a, grid.plans.cell_under_ghost(a), {})
	_check(grid.plans.has_plans(), "a plan")
	# its ghost can be picked up again: the trail goes on from its end (Nico, 2026-11-02)
	var ghost_at := grid.get_canvas_transform() * (grid.plans.plans[a].ghost as Sprite2D).position
	var pick := InputEventMouseButton.new()
	pick.button_index = MOUSE_BUTTON_LEFT
	pick.pressed = true
	pick.position = ghost_at
	grid._unhandled_input(pick)
	var nudge := InputEventMouseMotion.new()
	nudge.relative = Vector2(0, grid.cell) * grid._camera.zoom
	nudge.position = ghost_at + nudge.relative
	grid._unhandled_input(nudge)
	var drop := pick.duplicate() as InputEventMouseButton
	drop.pressed = false
	drop.position = nudge.position
	grid._unhandled_input(drop)
	var again: Array = grid.plans.plans.get(a, {}).get("path", [])
	_check(again.size() == 4 and again[0] == a_from and again[2] == a_from + Vector2i(2, 0) and again[3] == a_from + Vector2i(2, 1),
		"a picked-up ghost adjusts its move, the trail goes on (%s)" % [again])
	_check(grid.token_cell(a) == a_from and grid.plans.plans.size() == 1, "the real token still waits, one plan")
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.physical_keycode = KEY_ESCAPE
	grid._input(esc)
	_check(not grid.plans.has_plans() and grid.token_cell(a) == a_from, "Esc drops it")
	# the ghost of a token dropped in from the Book
	grid.plans.show_spawn(TokenArt.compose(null, {}, "creatures"), 1.0, Vector2i(2, 2))
	_check(grid.plans.spawn_visible() and grid.plans._spawn.position == grid.cell_center(Vector2i(2, 2), 1.0), "spawn ghost on its cell")
	grid.plans.hide_spawn()
	_check(not grid.plans.spawn_visible(), "and gone after the drop")

	# Keys without a selection do nothing.
	grid.select([])
	_check(not grid.key_step(KEY_W, false, true), "no selection: keys are left alone")
	print("token moves: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


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
