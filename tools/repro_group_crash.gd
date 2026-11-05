extends SceneTree
## Repro for a crash after grouping tokens (2026-11-05), not headless: the full app, grouping
## by G, by dropping onto a token, hovering the fan, ungrouping, frames in between.
## godot --path . --resolution 1600x950 -s tools/repro_group_crash.gd

const DIR := "user://repro_group_crash"


func _init() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	DirAccess.make_dir_recursive_absolute(base)
	App.settings_file = DIR.path_join("app.cfg")
	ServerStatus.servers_file = DIR.path_join("servers.json")
	Dock.layout_file = DIR.path_join("layout.json")
	var app := App.new()
	app.name = "App"
	app.worlds_root = base.path_join("worlds")
	root.add_child(app)
	await process_frame
	var red := ""
	for w: Dictionary in Worlds.list(app.worlds_root):
		red = str(w._dir).path_join("timelines/red-fang")
	app.host(red, 47815)
	await _frames(30)
	var g := app.table.grid
	var ids: Array = g.tokens.keys().filter(func(id: String) -> bool: return id != NetTable.PARTY and "/" in id)
	print("step: tokens ", ids)
	g.select([ids[0], ids[1]])
	await _frames(5)
	print("step: G")
	_key(g, KEY_G)
	await _frames(30)
	var ref := _group(g)
	print("step: grouped ", ref)
	g._hover(g.tokens[ref].position)
	await _frames(10)
	g._hover(Vector2(-999, -999))  # the fan's close timer runs ...
	print("step: select group, G right away")
	g.select([ref])
	_key(g, KEY_G)  # ... and the group token is freed before it fires
	await _frames(60)
	print("step: drop onto")
	_mouse(g, g.tokens[ids[1]].position, true)
	_motion(g, g.tokens[ids[0]].position, g.tokens[ids[0]].position - g.tokens[ids[1]].position)
	_mouse(g, g.tokens[ids[0]].position, false)
	await _frames(40)
	ref = _group(g)
	print("step: dropped ", ref)
	g._hover(g.tokens[ref].position)
	await _frames(10)
	var st := g.tokens[ref].get_node("Stack") as GroupStack
	g._hover(g.tokens[ref].position + st.spots()[0].at)
	await _frames(20)
	print("step: drag member out")
	_mouse(g, g.tokens[ref].position + st.spots()[0].at, true)
	_motion(g, g.tokens[ref].position + Vector2(0, g.cell * 3))
	_mouse(g, g.tokens[ref].position + Vector2(0, g.cell * 3), false)
	await _frames(60)
	print("step: active + group")
	g.set_active(ids[0])
	g.select(ids.slice(0, 3))
	_key(g, KEY_G)
	await _frames(60)
	print("step: ungroup, long drag onto a token")
	ref = _group(g)
	if ref != "":
		g.select([ref])
		_key(g, KEY_G)
		await _frames(20)
	var from: Vector2 = g.tokens[ids[2]].position
	var to: Vector2 = g.tokens[ids[3]].position
	_mouse(g, from, true)
	for i in 30:
		var at := from.lerp(to, (i + 1) / 30.0)
		_motion(g, at, (to - from) / 30.0)
		await process_frame
	_mouse(g, to, false)
	await _frames(60)
	print("step: menu group")
	ref = _group(g)
	if ref != "":
		g.select([ref])
		_key(g, KEY_G)
		await _frames(20)
	g.select([ids[0], ids[1]])
	var m: PopupMenu = app.table_ui.open_condition_menu(ids[0])
	await _frames(10)
	m.id_pressed.emit(1002)
	await _frames(60)
	print("step: hover around a lot")
	ref = _group(g)
	for i in 120:
		var at: Vector2 = g.tokens[ref].position + Vector2(cos(i * 0.3), sin(i * 0.2)) * g.cell * 1.5
		g._hover(at)
		await process_frame
	print("step: done, no crash")
	app.leave()
	quit()


func _group(g: TokenGrid) -> String:
	for id: String in g.tokens:
		if id.begins_with(NetTable.GROUP_PREFIX):
			return id
	return ""


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _key(g: TokenGrid, code: Key) -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = code
	e.physical_keycode = code
	g._input(e)


func _mouse(g: TokenGrid, at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = g.get_canvas_transform() * at
	g._unhandled_input(e)


func _motion(g: TokenGrid, at: Vector2, by := Vector2.ZERO) -> void:
	var e := InputEventMouseMotion.new()
	e.position = g.get_canvas_transform() * at
	e.relative = by * g._camera.zoom
	g._unhandled_input(e)
