extends SceneTree
## Timing of the slow derived views in a fight (TASK-87): combat_view, turn_usage, sheet_for.
## Prints milliseconds; no pass/fail. godot --headless --path . -s tools/perf_combat.gd

const PORT := 47816
const DIR := "user://perf_combat"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const CHIEF := "creatures/goblin-chief"


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var holder := Node.new()
	holder.name = "DM"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/DM"))
	var dm := NetTable.new()
	dm.name = "Table"
	dm.auto_ui = true
	dm.timeline_dir = TIMELINE
	dm.cache_dir = DIR.path_join("cache_dm")
	holder.add_child(dm)
	await process_frame
	dm.host(PORT)
	for i in 400:
		if dm.grid.tokens.has(CHIEF):
			break
		await process_frame
	dm.start_combat()
	await process_frame
	print("combatants: ", (dm.combat_state().order as Array).size(), ", events: ", dm.event_log.effective().size())
	# cold: a new event each time (what a fight does), warm: the same state again (other callers)
	var at := dm.grid.token_cell(CHIEF)
	var t := Time.get_ticks_usec()
	for i in 10:
		dm._handle_move(1, CHIEF, at + Vector2i(1 + i % 2, 0))
		dm.combat_view()
	print("%-34s %8.2f ms" % ["combat_view after an event", (Time.get_ticks_usec() - t) / 10000.0])
	_time("combat_view again (same state)", func() -> void: dm.combat_view())
	_time("turn_usage again", func() -> void: dm.turn_usage(CHIEF))
	_time("sheet_for again", func() -> void: dm.sheet_for(Reveal.DM, CHIEF))
	quit(0)


func _time(what: String, f: Callable, reps := 20) -> void:
	var t := Time.get_ticks_usec()
	for i in reps:
		f.call()
	print("%-34s %8.2f ms" % [what, (Time.get_ticks_usec() - t) / 1000.0 / reps])
