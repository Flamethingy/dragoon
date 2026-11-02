extends SceneTree
## Headless check of the test filler (Esc menu "Test: fill with random events"): it writes moves,
## rolls, chat and time into the log, and the timeline gets boxes for them.
## godot --headless --path . -s tools/test_fill.gd

const PORT := 47861
const DIR := "user://test_fill"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	await process_frame
	var holder := Node.new()
	holder.name = "DM"
	root.add_child(holder)
	var dm := NetTable.new()
	dm.name = "Table"
	dm.timeline_dir = TIMELINE
	dm.cache_dir = DIR.path_join("cache")
	holder.add_child(dm)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	for i in 20:
		await process_frame
	var boxes := (dm.timeline_sync.data.get("moments", []) as Array).size()
	var clock := dm.event_log.day * 1440 + maxi(dm.event_log.time, 0)
	var n: int = await TestFill.fill(dm, 120, 7)
	for i in 5:
		await process_frame
	var types := {}
	for e: Dictionary in dm.event_log.events.slice(dm.event_log.events.size() - n):
		types[str(e.type)] = int(types.get(str(e.type), 0)) + 1
	_check(n >= 100, "it wrote events (%d: %s)" % [n, types])
	_check(types.has("token.moved") and types.has("dice.rolled") and types.has("chat.message") and types.has("time.advanced"), "moves, rolls, chat and time (%s)" % [types])
	_check(dm.event_log.day * 1440 + dm.event_log.time > clock, "time went on")
	_check((dm.timeline_sync.data.moments as Array).size() > boxes + 5, "the timeline got boxes (%d -> %d)" % [boxes, (dm.timeline_sync.data.moments as Array).size()])
	_check(dm.rolls.size() > 20, "and the chat its lines (%d)" % dm.rolls.size())
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("fill: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
