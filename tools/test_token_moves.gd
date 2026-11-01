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
	var goblin := EntryStore.open(core_dir).find("monsters", "goblin")
	goblin.merge({"_kind": "monsters", "_layer": "core", "_package": "5e-core-rules", "_dir": core_dir}, true)
	var free := Vector2i(0, 0)
	for y in 6:
		for x in 6:
			if free == Vector2i.ZERO and Vector2i(x, y) != Vector2i.ZERO and not grid.tokens.values().any(func(t: Sprite2D) -> bool: return t.get_meta("cell") == Vector2i(x, y)):
				free = Vector2i(x, y)
	var copy_ref := table.drop_token(goblin, free)
	var ws := table.timeline.world_store()
	var wg := ws.find("monsters", "goblin")
	wg["token_style"] = {"border": "#00aa00", "background": "#112233", "faces": "left"}
	ws.save("monsters", wg)
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

	# Keys without a selection do nothing.
	grid.select([])
	_check(not grid.key_step(KEY_W, false, true), "no selection: keys are left alone")
	print("token moves: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
