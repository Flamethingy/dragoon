extends SceneTree
## Headless check of the facing along a trail (TASK-76): a planned move glides square by square
## on every screen (the host sends the trail on), the facing triangle turns with each step while
## the token moves, and the token ends facing its last step (also in the log).
## godot --headless --path . -s tools/test_trail_facing.gd

const PORT := 47822
const ADDRESS := "127.0.0.1:47822"
const DIR := "user://test_trail_facing"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	await process_frame
	var dm := _table("DM", "dm")
	var bob := _table("Bob", "bob")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(bob.join(ADDRESS, "bob") == OK, "Bob joins")
	await _until(func() -> bool: return bob.grid.tokens.has(BORIN) and bob.my_pc == BORIN)

	# room for b -> b+(1,1) -> b+(2,1) -> b+(3,0): south-east, east, north-east
	var steps := [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 0)]
	var b := Vector2i(-1, -1)
	for y in dm.grid.grid_size.y - 2:
		for x in dm.grid.grid_size.x - 4:
			if steps.all(func(s: Vector2i) -> bool: return dm.grid.can_place(BORIN, Vector2i(x, y) + s)):
				b = Vector2i(x, y)
				break
		if b.x >= 0:
			break
	_check(b.x >= 0, "a free spot")
	dm._handle_move(1, BORIN, b)
	dm.grid.set_token_facing(BORIN, "w")
	await _until(func() -> bool: return bob.grid.token_cell(BORIN) == b)
	for i in 30:
		await process_frame
	var trail := steps.map(func(s: Vector2i) -> Vector2i: return b + s)

	# Bob plans the trail and lets it go (as Space does)
	bob.grid.glide_along(BORIN, trail)
	bob._on_move_requested(BORIN, b + Vector2i(3, 0))
	var seen_dm := []
	var seen_bob := []
	for i in 240:
		await process_frame
		for pair: Array in [[dm, seen_dm], [bob, seen_bob]]:
			var f: String = (pair[0] as NetTable).grid.token_facing(BORIN)
			var list: Array = pair[1]
			if list.is_empty() or list[list.size() - 1] != f:
				list.append(f)
		var t: Sprite2D = bob.grid.tokens[BORIN]
		if bob.grid.token_cell(BORIN) == b + Vector2i(3, 0) and t.position.distance_to(bob.grid.cell_center(b + Vector2i(3, 0), 1.0)) < 0.5 \
				and dm.grid.tokens[BORIN].position.distance_to(dm.grid.cell_center(b + Vector2i(3, 0), 1.0)) < 0.5:
			break
	for i in 5:
		await process_frame
	for who: Array in [["the DM", seen_dm, dm], ["Bob", seen_bob, bob]]:
		var list: Array = who[1]
		var se := list.find("se")
		var e := list.rfind("e")
		_check(se >= 0 and e > se and list[list.size() - 1] == "ne", "%s: the triangle turns se, e, then ne along the trail (%s)" % [who[0], list])
		_check((who[2] as NetTable).grid.token_facing(BORIN) == "ne", "%s: it ends facing the last step" % who[0])
	var last: Dictionary = dm.event_log.effective().filter(func(ev: Dictionary) -> bool: return ev.type == "token.moved" and str(ev.entity) == BORIN).back()
	_check(str(last.data.get("facing", "")) == "ne", "the log keeps the last step's facing, not the straight line's (%s)" % last.data.get("facing", ""))

	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("trail facing: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _table(branch: String, cache: String) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
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
