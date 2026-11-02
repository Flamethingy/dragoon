extends SceneTree
## Times hosting a big timeline (a copy of a log put into the example's prologue):
## godot --headless --path . -s tools/prof_moments.gd -- <events.jsonl>

const DIR := "user://prof_moments"


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := ProjectSettings.globalize_path(DIR + "/worlds/westmarch/timelines/prologue")
	DirAccess.copy_absolute(OS.get_cmdline_user_args()[0], tl.path_join("events.jsonl"))
	var log := EventLog.open(tl.path_join("events.jsonl"))
	var t := Time.get_ticks_msec()
	var m := TimelineMoments.build(log.effective(), 24)
	print("moments %d of %d events: %d ms" % [m.moments.size(), log.events.size(), Time.get_ticks_msec() - t])
	await process_frame
	var holder := Node.new()
	holder.name = "DM"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/DM"))
	var table := NetTable.new()
	table.name = "Table"
	table.timeline_dir = tl
	table.cache_dir = DIR.path_join("cache")
	holder.add_child(table)
	t = Time.get_ticks_msec()
	table.host(47840)
	print("host: %d ms" % (Time.get_ticks_msec() - t))
	t = Time.get_ticks_msec()
	table.timeline_sync.rebuild()
	print("sync rebuild: %d ms" % (Time.get_ticks_msec() - t))
	t = Time.get_ticks_msec()
	var v := table.view_for("")
	print("view_for: %d ms (%d tokens)" % [Time.get_ticks_msec() - t, (v.get("tokens", []) as Array).size()])
	t = Time.get_ticks_msec()
	table._apply_state(v)
	print("apply_state: %d ms" % (Time.get_ticks_msec() - t))
	t = Time.get_ticks_msec()
	await process_frame
	await process_frame
	print("first frames (the bar's send): %d ms, %d moments" % [Time.get_ticks_msec() - t, (table.timeline_sync.data.get("moments", []) as Array).size()])
	t = Time.get_ticks_msec()
	table.event_log.change_hp("characters/borin", -1, 5, "prof")
	await process_frame
	await process_frame
	print("one more event: %d ms" % (Time.get_ticks_msec() - t))
	table.multiplayer.multiplayer_peer.close()
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	quit()
