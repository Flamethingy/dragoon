extends SceneTree
## Headless check of group tokens (TASK-115): G / the menu groups the selected tokens into one
## stack token (the leader's picture, the members at its edge), it moves as one at the slowest
## speed keeping the formation, a member is dragged out of its ring, Ungroup splits all, the
## events (undo), a player's rights, the sync to a player and the split when a combat starts.
## TASK-116: G toggles, a token dropped onto a token groups, members come straight out of the fan.
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
	_check(stack != null and stack.fanned, "a short grace time after leaving it")
	await create_timer(GroupStack.GRACE + 0.15).timeout
	_check(stack != null and not stack.fanned, "then it closes")

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

	# --- A member dragged straight out of the fan (TASK-116: no ring) -----------------------------
	_check(not "open_ring" in grid and grid.find_child("GroupRing", true, false) == null, "the ring is gone")
	var out_cell := _free_cell(grid, target + Vector2i(0, 4))
	var tok: Sprite2D = grid.tokens[ref]
	for i in 90:  # the group's glide ends
		await process_frame
	grid._hover(tok.position)
	var c_at := tok.position + _spot_of(stack, c)
	grid._hover(c_at)
	_check(stack.hot == c, "hovering a face in the fan makes it the hot one")
	for i in 30:
		await process_frame
	_check(float(stack.grow.get(c, 1.0)) > 1.1, "it grows (%s)" % stack.grow.get(c, 1.0))
	_mouse(grid, c_at, true)
	_check(grid.member_drag != null and grid.member_drag.visible and grid.member_drag.member == c, "pressing it takes it out of the fan")
	_mouse(grid, tok.position, false)  # let go on its group: nothing happens
	_check(dm.groups_on(dm.map_id).get(gid, {}).get("members") == [aria, b, c], "let go on its group: it stays in")
	grid._hover(tok.position)
	_mouse(grid, c_at, true)
	_motion(grid, grid.cell_center(out_cell, 1.0))
	_check(grid.member_drag.position.distance_to(grid.cell_center(out_cell, 1.0)) < 1.0, "it follows the mouse")
	_mouse(grid, grid.cell_center(out_cell, 1.0), false)
	_check(not grid.member_drag.visible, "let go")
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

	# --- G toggles: a group alone ungroups, a group plus singles takes them in -------------------
	grid.select([ref, c])
	_key_g(grid)
	var both := dm.groups_on(dm.map_id)
	_check(both.size() == 1 and (both.values()[0].members as Array).size() == 3 and both.values()[0].leader == aria and c in both.values()[0].members,
		"G on a group plus a single: it joins, the leader stays (%s)" % [both])
	var ref3: String = NetTable.GROUP_PREFIX + str(both.keys()[0]) if both.size() == 1 else ""
	grid.select([ref3])
	_key_g(grid)
	_check(dm.groups_on(dm.map_id).is_empty() and grid.tokens.has(aria) and grid.tokens.has(b) and grid.tokens.has(c), "G on a group alone ungroups it")
	grid.select([aria, b])
	_key_g(grid)
	_check(dm.groups_on(dm.map_id).size() == 1, "G on two singles groups them")

	# --- A combat splits groups ------------------------------------------------------------------
	dm.start_combat()
	_check(dm.groups_on(dm.map_id).is_empty() and grid.tokens.has(aria) and grid.tokens.has(b), "a combat splits the groups")
	dm.group_tokens([aria, b])
	_check(dm.groups_on(dm.map_id).is_empty(), "no groups during a combat")
	_check(grid.join_target(grid.tokens[aria].position, b, []) == "", "no dropping onto a token to group during a combat")
	dm.end_combat()

	# --- Drop a token exactly onto another one: they group (no Alt, TASK-116) -------------------
	grid.select([])
	await process_frame
	_mouse(grid, grid.tokens[b].position, true)
	_motion(grid, grid.tokens[aria].position, grid.tokens[aria].position - grid.tokens[b].position)
	_check(grid.join_hint != null and grid.join_hint.visible and grid.join_hint.position == grid.tokens[aria].position, "over a token: the + hint on it")
	_mouse(grid, grid.tokens[aria].position, false)
	var alt_groups := dm.groups_on(dm.map_id)
	_check(alt_groups.size() == 1 and alt_groups.values()[0].members == [aria, b] and alt_groups.values()[0].leader == aria,
		"dropped onto Aria they group, Aria leads (%s)" % [alt_groups])
	_check(grid.plans.plans.is_empty() and not grid.join_hint.visible, "no ghost or hint left behind")
	var gref0: String = NetTable.GROUP_PREFIX + str(alt_groups.keys()[0]) if alt_groups.size() == 1 else ""
	# a single onto a group token joins it
	_mouse(grid, grid.tokens[c].position, true)
	_motion(grid, grid.tokens[gref0].position, grid.tokens[gref0].position - grid.tokens[c].position)
	_mouse(grid, grid.tokens[gref0].position, false)
	var joined := dm.groups_on(dm.map_id)
	_check(joined.size() == 1 and joined.values()[0].members == [aria, b, c], "dropped onto a group it joins (%s)" % [joined])
	# beside a token: a normal move
	var gref1: String = NetTable.GROUP_PREFIX + str(joined.keys()[0]) if joined.size() == 1 else ""
	grid.select([gref1])
	_key_g(grid)
	var free_to := _free_cell(grid, grid.token_cell(c) + Vector2i(0, 3), c)
	_mouse(grid, grid.tokens[c].position, true)
	var c_size: float = grid.tokens[c].get_meta("cells", 1.0)
	_motion(grid, grid.cell_center(free_to, c_size), grid.cell_center(free_to, c_size) - grid.tokens[c].position)
	_check(not grid.join_hint.visible, "no hint over an empty square")
	_mouse(grid, grid.cell_center(free_to, c_size), false)
	await _until(func() -> bool: return grid.token_cell(c) == free_to)
	_check(grid.token_cell(c) == free_to and dm.groups_on(dm.map_id).is_empty(), "beside a token it's a normal move")
	grid.select([])
	dm.group_tokens([aria, b])
	alt_groups = dm.groups_on(dm.map_id)

	# --- Hovering up to the fanned faces keeps them open; a face is grabbed and dragged out --------
	var gref: String = NetTable.GROUP_PREFIX + str(alt_groups.keys()[0]) if alt_groups.size() == 1 else ""
	if grid.tokens.has(gref):
		var gtok: Sprite2D = grid.tokens[gref]
		var st := gtok.get_node("Stack") as GroupStack
		grid._hover(gtok.position)
		_check(st.fanned, "hover fans out")
		var spot: Dictionary = st.spots()[0]
		var gap := gtok.position + Vector2(0, -st.radius - 2.0)  # between the token and the faces
		grid._hover(gap)
		_check(st.fanned, "the way up to the faces keeps them open")
		grid._hover(gtok.position + (spot.at as Vector2))
		_check(st.fanned, "over a face too")
		_mouse(grid, gtok.position + (spot.at as Vector2), true)
		_check(grid.member_drag != null and grid.member_drag.member == b, "pressing a fanned face takes that member")
		var to := _free_cell(grid, grid.token_cell(gref) + Vector2i(0, 4))
		var mv := InputEventMouseMotion.new()
		mv.position = grid.get_canvas_transform() * grid.cell_center(to, 1.0)
		grid._unhandled_input(mv)
		var let_go := InputEventMouseButton.new()
		let_go.button_index = MOUSE_BUTTON_LEFT
		let_go.pressed = false
		let_go.position = mv.position
		grid._unhandled_input(let_go)
		_check(grid.tokens.has(b) and grid.token_cell(b) == to and dm.groups_on(dm.map_id).is_empty(), "dropped it stands there, the group is gone")
	else:
		_check(false, "no group to fan out")

	print("group tokens: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _spot_of(stack: GroupStack, member: String) -> Vector2:
	for sp: Dictionary in stack.spots():
		if str(sp.face.id) == member:
			return sp.at
	return Vector2.ZERO


func _mouse(grid: TokenGrid, at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = grid.get_canvas_transform() * at
	grid._unhandled_input(e)


func _motion(grid: TokenGrid, at: Vector2, by := Vector2.ZERO) -> void:
	var e := InputEventMouseMotion.new()
	e.position = grid.get_canvas_transform() * at
	e.relative = by * grid._camera.zoom
	grid._unhandled_input(e)


func _key_g(grid: TokenGrid) -> void:
	var g := InputEventKey.new()
	g.pressed = true
	g.keycode = KEY_G
	g.physical_keycode = KEY_G
	grid._input(g)


## A shift that puts all three on free squares.
func _free_delta(grid: TokenGrid, ref: String, start: Dictionary) -> Vector2i:
	for d: Vector2i in [Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2), Vector2i(3, 1), Vector2i(1, 3)]:
		if start.values().all(func(at: Vector2i) -> bool: return _free(grid, at + d, ref)) and grid.can_place(ref, start.values()[0] + d):
			return d
	return Vector2i(1, 0)


func _free(grid: TokenGrid, at: Vector2i, except: String) -> bool:
	return at.x >= 0 and at.y >= 0 and at.x < grid.grid_size.x and at.y < grid.grid_size.y and not grid.occupied(except).has(at)


func _free_cell(grid: TokenGrid, near: Vector2i, who := "x") -> Vector2i:
	for r in 6:
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var at := near + Vector2i(dx, dy)
				if _free(grid, at, "") and grid.can_place(who, at):
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
