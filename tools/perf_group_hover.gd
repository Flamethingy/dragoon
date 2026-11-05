extends SceneTree
## Perf check (2026-11-05, Nico: hovering / selecting a group token led by Aria froze the game for
## a moment): times hovering and clicking a group token in the full app, frame by frame.
## godot --path . --resolution 1600x950 -s tools/perf_group_hover.gd

const DIR := "user://perf_group_hover"


func _init() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	DirAccess.make_dir_recursive_absolute(base)
	App.settings_file = DIR.path_join("app.cfg")
	ServerStatus.servers_file = DIR.path_join("servers.json")
	Dock.layout_file = DIR.path_join("layout.json")
	var app := App.new()
	app.name = "App"
	var real := OS.get_cmdline_user_args()  # a copy of a real worlds folder, else the example
	app.worlds_root = real[0] if not real.is_empty() else base.path_join("worlds")
	root.add_child(app)
	await process_frame
	var red := ""
	for w: Dictionary in Worlds.list(app.worlds_root):
		red = str(w._dir).path_join("timelines/red-fang")
	app.host(red, 47816)
	await _frames(30)
	var g := app.table.grid
	var ref := ""
	for id: String in g.tokens:
		if id.begins_with(NetTable.GROUP_PREFIX):
			ref = id
	if ref == "":
		var pcs: Array = g.tokens.keys().filter(func(id: String) -> bool: return id.begins_with("characters/"))
		var others: Array = g.tokens.keys().filter(func(id: String) -> bool: return id.begins_with("creatures/"))
		app.table.group_tokens([pcs[0]] + others.slice(0, 1) + pcs.slice(1))
		await _frames(20)
	for id: String in g.tokens:
		if id.begins_with(NetTable.GROUP_PREFIX):
			ref = id
	print("group ", ref, " ", (g.tokens[ref].get_meta("info") as Dictionary).members)
	var t := Time.get_ticks_usec()
	g._hover(g.tokens[ref].position)
	print("hover call: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	await _timed_frames("after hover", 20)
	var hud: CharacterHud = app.table_ui.hud
	print("hud active before: ", hud.active, " controlled has group: ", ref in hud.controlled())
	t = Time.get_ticks_usec()
	hud.set_active(ref)
	print("hud.set_active(group): %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	await _timed_frames("after hud.set_active", 3)
	t = Time.get_ticks_usec()
	g.select([ref])
	g.token_clicked.emit(ref)
	print("select call: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	await _timed_frames("after select", 5)
	app.leave()
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _timed_frames(what: String, n: int) -> void:
	var worst := 0.0
	var total := 0.0
	for i in n:
		var t := Time.get_ticks_usec()
		await process_frame
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		worst = maxf(worst, ms)
		total += ms
	print("%s: worst frame %.1f ms, %d frames %.1f ms" % [what, worst, n, total])
