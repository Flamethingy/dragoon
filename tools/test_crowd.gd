extends SceneTree
## Headless check of moving through other creatures (TASK-79): another creature's square is
## difficult terrain (it costs two squares), along the planned trail (going round costs
## nothing extra), in the move trail's count on the map too; the house rule turns it off or
## keeps it for hostile creatures only. It only counts, never blocks.
## godot --headless --path . -s tools/test_crowd.gd

const PORT := 47821
const DIR := "user://test_crowd"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	_check(Rules.crowded_squares({}) == "all" and Rules.crowded_squares({"house_rules": {"crowded_squares": "off"}}) == "off", "the house rule, 'all' by default")
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var holder := Node.new()
	holder.name = "DM"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/DM"))
	var dm := NetTable.new()
	dm.name = "Table"
	dm.timeline_dir = TIMELINE
	dm.cache_dir = DIR.path_join("cache")
	holder.add_child(dm)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	await _until(func() -> bool: return dm.grid.tokens.has(BORIN) and dm.grid.tokens.has(CHIEF))

	# a free row: Borin at b, the chief at b + (1, 0), room at b + (2, 0) and b + (1, 1)
	var b := Vector2i(-1, -1)
	for y in dm.grid.grid_size.y - 2:
		for x in dm.grid.grid_size.x - 3:
			var c := Vector2i(x, y)
			if [c, c + Vector2i(2, 0), c + Vector2i(1, 1)].all(func(v: Vector2i) -> bool: return dm.grid.can_place(BORIN, v)) and dm.grid.can_place(CHIEF, c + Vector2i(1, 0)) and dm.grid.can_place(BORIN, c + Vector2i(1, 0)):
				b = c
				break
		if b.x >= 0:
			break
	_check(b.x >= 0, "a free spot on the map")
	dm._handle_move(1, BORIN, b)
	dm._handle_move(1, CHIEF, b + Vector2i(1, 0))
	var chief_at := b + Vector2i(1, 0)
	_check(dm.grid.difficult_for(BORIN).has(chief_at) and not dm.grid.difficult_for(CHIEF).has(chief_at), "the chief's square is difficult for Borin, not for itself")
	_check(MovePlans.extra_cost([b, chief_at, b + Vector2i(2, 0)], dm.grid.difficult_for(BORIN)) == 1, "the trail on the map counts it")

	dm.start_combat()
	dm._handle_move(1, BORIN, b + Vector2i(2, 0), [b, chief_at, b + Vector2i(2, 0)])
	_check(is_equal_approx(float(dm.turn_usage(BORIN).moved), 4.5) and dm.grid.token_cell(BORIN) == b + Vector2i(2, 0), "through the chief: 2 squares cost 3 (4.5 m), the move happens (%s)" % dm.turn_usage(BORIN).moved)
	dm._handle_move(1, BORIN, b, [b + Vector2i(2, 0), b + Vector2i(1, 1), b])
	_check(is_equal_approx(float(dm.turn_usage(BORIN).moved), 7.5), "round the chief along the trail: nothing extra (%s)" % dm.turn_usage(BORIN).moved)
	dm._handle_move(1, BORIN, b + Vector2i(2, 0), [b, Vector2i(99, 99), b + Vector2i(2, 0)])
	_check(is_equal_approx(float(dm.turn_usage(BORIN).moved), 12.0), "a trail that makes no sense: the straight line counts (%s)" % dm.turn_usage(BORIN).moved)

	# the house rule
	var s := dm.rules_settings().duplicate(true)
	(s.house_rules as Dictionary)["crowded_squares"] = "off"
	dm.set_rules_settings(s)
	_check(dm.grid.difficult_for(BORIN).is_empty() or not dm.grid.difficult_for(BORIN).has(chief_at), "off: nothing extra")
	dm._handle_move(1, BORIN, b, [b + Vector2i(2, 0), chief_at, b])
	_check(is_equal_approx(float(dm.turn_usage(BORIN).moved), 15.0), "off: through the chief costs 2 squares (%s)" % dm.turn_usage(BORIN).moved)
	(s.house_rules as Dictionary)["crowded_squares"] = "hostile"
	dm.set_rules_settings(s)
	_check(dm.grid.difficult_for(BORIN).has(chief_at), "hostile: the goblin's square counts for Borin")
	var friends := dm.grid.occupied(BORIN, func(o: String) -> bool: return dm._crowd_side(o) != dm._crowd_side(BORIN))
	_check(not friends.keys().any(func(c: Vector2i) -> bool: return c == dm.grid.token_cell(BORIN)), "Borin's own square never counts")
	var allies := Array(dm.timeline.pcs()).filter(func(r: String) -> bool: return r != BORIN and dm.grid.tokens.has(r))
	if not allies.is_empty():
		var ally: String = allies[0]
		var ally_at := dm.grid.token_cell(ally)
		_check(not dm.grid.difficult_for(BORIN).has(ally_at), "hostile: an ally's square doesn't count")

	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("crowd: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
