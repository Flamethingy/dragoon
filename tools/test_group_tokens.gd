extends SceneTree
## Headless check of group tokens (TASK-115): G / the menu groups the selected tokens into one
## stack token (the leader's picture, the members at its edge), it moves as one at the slowest
## speed keeping the formation, a member is dragged out of its ring, Ungroup splits all, the
## events (undo), a player's rights, the sync to a player and the split when a combat starts.
## godot --headless --path . -s tools/test_group_tokens.gd

const PORT := 47823
const ADDRESS := "127.0.0.1:47823"
const DIR := "user://test_group_tokens"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	await process_frame
	var dm := _table("DM", "dm")
	var ann := _table("Ann", "ann")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(ann.join(ADDRESS, "Ann") == OK, "Ann joins")
	await _until(func() -> bool: return ann.my_pc == "characters/aria" and ann.grid.tokens.has("characters/aria"))
	var grid := dm.grid
	var aria := "characters/aria"
	var others: Array = grid.tokens.keys().filter(func(id: String) -> bool: return id != aria and id != NetTable.PARTY and "/" in id)
	_check(others.size() >= 2, "tokens on the map (%s)" % [others])
	var b: String = others[0]
	var c: String = others[1]
	var start := {aria: grid.token_cell(aria), b: grid.token_cell(b), c: grid.token_cell(c)}

	# --- A player may only group her own tokens ----------------------------------------------------
	ann.group_tokens([aria, b])
	for i in 20:
		await process_frame
	_check(dm.groups_on(dm.map_id).is_empty(), "Ann can't group a token that isn't hers")

	# --- G groups the selection ----------------------------------------------------------------
	grid.select([aria, b, c])
	var g := InputEventKey.new()
	g.pressed = true
	g.keycode = KEY_G
	g.physical_keycode = KEY_G
	grid._input(g)
	var groups := dm.groups_on(dm.map_id)
	_check(groups.size() == 1, "G groups the selected tokens (%s)" % [groups])
	var gid: String = groups.keys()[0] if not groups.is_empty() else ""
	var ref := NetTable.GROUP_PREFIX + gid
	_check(grid.tokens.has(ref) and not grid.tokens.has(aria) and not grid.tokens.has(b) and not grid.tokens.has(c), "one token instead of three")
	_check(grid.token_cell(ref) == start[aria], "at the leader's square")
	var info: Dictionary = grid.tokens[ref].get_meta("info", {}) if grid.tokens.has(ref) else {}
	_check(info.get("members", []) == [aria, b, c] and info.get("kind") == "group", "the members, the first leads (%s)" % [info.get("members")])
	var stack := grid.tokens[ref].get_node_or_null("Stack") as GroupStack if grid.tokens.has(ref) else null
	_check(stack != null and stack.faces.size() == 3 and stack.faces[0].texture != null, "the members' faces at its edge")
	var formed := dm.event_log.effective().filter(func(e: Dictionary) -> bool: return e.type == "group.formed")
	_check(formed.size() == 1 and formed[0].data.members == [aria, b, c], "a group.formed event")
	await _until(func() -> bool: return ann.grid.tokens.has(ref))
	_check(ann.grid.tokens.has(ref) and not ann.grid.tokens.has(aria), "Ann sees the group token too")
	_check(ann._may_drag(ref), "and may move it (Aria is in it)")

	# --- Hover fans out, the menu --------------------------------------------------------------
	grid._hover(grid.tokens[ref].position)
	_check(stack != null and stack.fanned, "hovering fans the members out")
	grid._hover(Vector2(-9999, -9999))
	_check(stack != null and not stack.fanned, "and back")

	# --- Moves as one: the slowest speed, the formation kept ------------------------------------
	var slowest := INF
	for m: String in [aria, b, c]:
		var v: float = grid.speed.call(m)
		if v > 0.0:
			slowest = minf(slowest, v)
	_check(is_equal_approx(float(grid.speed.call(ref)), slowest), "the group's speed is its slowest member's (%s, %s)" % [grid.speed.call(ref), slowest])
	var delta := _free_delta(grid, ref, start)
	var target: Vector2i = start[aria] + delta
	ann.request_move.rpc_id(1, ref, target, [])
	await _until(func() -> bool: return grid.token_cell(ref) == target)
	_check(grid.token_cell(ref) == target, "Ann moves the group (%s -> %s)" % [start[aria], target])
	var placed := Replay.tokens_on(dm.map_id, dm.event_log.effective())
	_check(placed.get(aria) == start[aria] + delta and placed.get(b) == start[b] + delta and placed.get(c) == start[c] + delta,
		"every member moved the same way (%s)" % [placed])
	var moves := dm.event_log.effective().filter(func(e: Dictionary) -> bool: return e.type == "token.moved" and str(e.data.get("group", "")) == ref)
	_check(moves.size() == 3, "one token.moved per member, with the group (%d)" % moves.size())
	await _until(func() -> bool: return ann.grid.token_cell(ref) == target)
	_check(ann.grid.token_cell(ref) == target, "Ann sees it there")

	# --- A member dragged out of the ring --------------------------------------------------------
	grid.open_ring(ref)
	_check(grid.ring != null and grid.ring.is_open() and grid.ring.members.size() == 3, "a double-click opens the ring")
	var out_cell := _free_cell(grid, target + Vector2i(0, 4))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	var c_at: Vector2 = grid.ring.position + (grid.ring.members[2].at as Vector2)
	press.position = grid.get_canvas_transform() * c_at
	grid._unhandled_input(press)
	_check(grid.ring.dragged == c, "pressing a member in the ring takes it (%s)" % grid.ring.dragged)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = grid.get_canvas_transform() * grid.cell_center(out_cell, 1.0)
	grid._unhandled_input(release)
	_check(not grid.ring.is_open(), "the ring closes")
	_check(grid.tokens.has(c) and grid.token_cell(c) == out_cell, "the member stands where it was dropped (%s)" % [grid.token_cell(c) if grid.tokens.has(c) else "gone"])
	_check(dm.groups_on(dm.map_id).get(gid, {}).get("members") == [aria, b] and grid.tokens.has(ref), "the others stay grouped")

	# --- Ungroup splits all; undo brings it back -------------------------------------------------
	dm.split_group(ref)
	_check(dm.groups_on(dm.map_id).is_empty() and grid.tokens.has(aria) and grid.tokens.has(b) and not grid.tokens.has(ref), "Ungroup splits everyone")
	_check(grid.token_cell(aria) == start[aria] + delta and grid.token_cell(b) == start[b] + delta, "where they stood in the formation")
	var split := dm.event_log.effective().filter(func(e: Dictionary) -> bool: return e.type == "group.split")
	dm.event_log.undo(int(split[-1].id))
	_check(dm.groups_on(dm.map_id).get(gid, {}).get("members") == [aria, b], "undoing the split groups them again")
	dm._groups_changed()
	_check(grid.tokens.has(ref), "and the table shows it")

	# --- A combat splits groups ------------------------------------------------------------------
	dm.start_combat()
	_check(dm.groups_on(dm.map_id).is_empty() and grid.tokens.has(aria) and grid.tokens.has(b), "a combat splits the groups")
	dm.group_tokens([aria, b])
	_check(dm.groups_on(dm.map_id).is_empty(), "no groups during a combat")
	dm.end_combat()

	# --- Alt + drop onto a token groups them ------------------------------------------------------
	grid.select([])
	await process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = grid.get_canvas_transform() * grid.tokens[b].position
	grid._unhandled_input(down)
	var move := InputEventMouseMotion.new()
	move.relative = (grid.tokens[aria].position - grid.tokens[b].position) * grid._camera.zoom
	move.position = grid.get_canvas_transform() * grid.tokens[aria].position
	grid._unhandled_input(move)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.alt_pressed = true
	up.position = grid.get_canvas_transform() * grid.tokens[aria].position
	grid._unhandled_input(up)
	var alt_groups := dm.groups_on(dm.map_id)
	_check(alt_groups.size() == 1 and alt_groups.values()[0].members == [aria, b] and alt_groups.values()[0].leader == aria,
		"Alt + drop onto Aria groups them, Aria leads (%s)" % [alt_groups])
	_check(grid.plans.plans.is_empty(), "no ghost left behind")

	print("group tokens: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


## A shift that puts all three on free squares.
func _free_delta(grid: TokenGrid, ref: String, start: Dictionary) -> Vector2i:
	for d: Vector2i in [Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2), Vector2i(3, 1), Vector2i(1, 3)]:
		if start.values().all(func(at: Vector2i) -> bool: return _free(grid, at + d, ref)) and grid.can_place(ref, start.values()[0] + d):
			return d
	return Vector2i(1, 0)


func _free(grid: TokenGrid, at: Vector2i, except: String) -> bool:
	return at.x >= 0 and at.y >= 0 and at.x < grid.grid_size.x and at.y < grid.grid_size.y and not grid.occupied(except).has(at)


func _free_cell(grid: TokenGrid, near: Vector2i) -> Vector2i:
	for r in 6:
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var at := near + Vector2i(dx, dy)
				if _free(grid, at, "") and grid.can_place("x", at):
					return at
	return near


func _table(branch: String, cache: String) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
	t.auto_ui = false
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
