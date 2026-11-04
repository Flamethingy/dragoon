extends SceneTree
## Headless check of the bunny's MCP server for local assistants (TASK-99): off by default;
## when the host switches it on it listens on 127.0.0.1 only, wants the token, turns away
## foreign browser pages, answers initialize / tools/list and runs the bunny's tools with the
## DM's rights.
## godot --headless --path . -s tools/test_bunny_mcp.gd

const PORT := 47857
const MCP_PORT := 47858
const DIR := "user://test_bunny_mcp"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	BunnyBrain.settings_file = DIR.path_join("bunny_settings.cfg")
	BunnyBrain.set_setting("mcp_port", MCP_PORT)
	await process_frame
	var holder := Node.new()
	holder.name = "DM"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/DM"))
	var dm := NetTable.new()
	dm.name = "Table"
	dm.timeline_dir = TIMELINE
	dm.cache_dir = DIR.path_join("cache_dm")
	dm.auto_ui = false
	holder.add_child(dm)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(dm.bunny_mcp == null, "off by default")
	var none := await _post("/mcp", {"jsonrpc": "2.0", "id": 1, "method": "ping"}, "x")
	_check(int(none.code) == 0, "nothing listens (%s)" % none.code)

	# on in the settings
	var dialog := BunnySettings.new()
	dialog.brain = dm.bunny
	root.add_child(dialog)
	dialog.fill()
	var token := BunnyMcp.ensure_token()
	_check(token.length() == 48 and token in dialog.mcp_info.text and str(MCP_PORT) in dialog.mcp_info.text, "the settings show address and token")
	dialog.mcp_on.button_pressed = true
	dialog.save()
	_check(dm.bunny_mcp != null and dm.bunny_mcp.is_running(), "switched on: it runs")
	_check(dm.bunny_mcp.port == MCP_PORT, "on the port from the settings")

	var bad := await _post("/mcp", {"jsonrpc": "2.0", "id": 1, "method": "ping"}, "")
	_check(int(bad.code) == 401, "no token: 401 (%s)" % bad.code)
	bad = await _post("/mcp", {"jsonrpc": "2.0", "id": 1, "method": "ping"}, "wrong")
	_check(int(bad.code) == 401, "a wrong token: 401")
	bad = await _post("/mcp", {"jsonrpc": "2.0", "id": 1, "method": "ping"}, token, "https://evil.example")
	_check(int(bad.code) == 403, "a foreign web page: 403 (%s)" % bad.code)
	bad = await _post("/other", {"jsonrpc": "2.0", "id": 1, "method": "ping"}, token)
	_check(int(bad.code) == 404, "another path: 404")

	var init := await _post("/mcp", {"jsonrpc": "2.0", "id": 1, "method": "initialize",
		"params": {"protocolVersion": BunnyMcp.PROTOCOL, "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}}, token)
	_check(int(init.code) == 200 and str(init.json.result.protocolVersion) == BunnyMcp.PROTOCOL and init.json.result.capabilities.has("tools"), "initialize (%s)" % [init])
	var note := await _post("/mcp", {"jsonrpc": "2.0", "method": "notifications/initialized"}, token)
	_check(int(note.code) == 202, "a notification: 202")
	var listed := await _post("/mcp", {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, token)
	var tools: Array = listed.json.result.tools if int(listed.code) == 200 else []
	_check(tools.size() == BunnyTools.names().size() and tools.all(func(t: Dictionary) -> bool: return t.has("inputSchema")), "tools/list: the bunny's tools (%d)" % tools.size())

	# the DM's rights
	var sheet := await _call(token, "sheet_read", {"character": "Mira"})
	_check(not sheet.isError and "Mira" in str(sheet.text), "sheet_read: any sheet, as the DM (%s)" % str(sheet.text).left(120))
	var notes_before := dm.notes.entries.size()
	var wrote := await _call(token, "note_write", {"text": "Prepared: the goblin ambush"})
	_check(not wrote.isError and dm.notes.entries.size() == notes_before + 1 and str(dm.notes.entries[-1].by) == "dm", "note_write: a note by the DM (%s)" % wrote.text)
	var unknown := await _post("/mcp", {"jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": {"name": "shell", "arguments": {}}}, token)
	_check(int(unknown.code) == 200 and unknown.json.has("error"), "an unknown tool: an error")
	var odd := await _post("/mcp", {"jsonrpc": "2.0", "id": 10, "method": "resources/list"}, token)
	_check(odd.json.has("error") and int(odd.json.error.code) == -32601, "an unknown method: -32601")

	# only 127.0.0.1
	var addrs: Array = Array(IP.get_local_addresses()).filter(func(a: String) -> bool: return a.count(".") == 3 and a != "127.0.0.1" and not a.begins_with("169.254"))
	if not addrs.is_empty():
		var outside := await _post("/mcp", {"jsonrpc": "2.0", "id": 1, "method": "ping"}, token, "", str(addrs[0]))
		_check(int(outside.code) == 0, "not reachable from %s" % addrs[0])

	# off again
	dialog.mcp_on.button_pressed = false
	dialog.save()
	_check(dm.bunny_mcp == null, "switched off")
	none = await _post("/mcp", {"jsonrpc": "2.0", "id": 1, "method": "ping"}, token)
	_check(int(none.code) == 0, "and gone")

	dialog.queue_free()
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("bunny mcp: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _call(token: String, tool: String, args: Dictionary) -> Dictionary:
	var r := await _post("/mcp", {"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": tool, "arguments": args}}, token)
	if int(r.code) != 200 or not r.json.has("result"):
		return {"isError": true, "text": str(r)}
	return {"isError": bool(r.json.result.isError), "text": str(r.json.result.content[0].text)}


## One HTTP POST: {code (0: no connection), json}.
func _post(path: String, msg: Dictionary, token: String, origin := "", host := "127.0.0.1") -> Dictionary:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host(host, MCP_PORT) != OK:
		return {"code": 0, "json": {}}
	for i in 100:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			break
		await process_frame
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return {"code": 0, "json": {}}
	var body := JSON.stringify(msg).to_utf8_buffer()
	var head := "POST %s HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: %d\r\n" % [path, body.size()]
	if token != "":
		head += "Authorization: Bearer %s\r\n" % token
	if origin != "":
		head += "Origin: %s\r\n" % origin
	peer.put_data((head + "\r\n").to_utf8_buffer())
	peer.put_data(body)
	var got := PackedByteArray()
	for i in 300:
		await process_frame
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var n := peer.get_available_bytes()
		if n > 0:
			got.append_array(peer.get_partial_data(n)[1])
	var text := got.get_string_from_utf8()
	if text == "":
		return {"code": 0, "json": {}}
	var code := int(text.get_slice(" ", 1))
	var at := text.find("\r\n\r\n")
	var rest := text.substr(at + 4) if at >= 0 else ""
	var parsed: Variant = JSON.parse_string(rest) if rest != "" else null
	return {"code": code, "json": parsed if parsed is Dictionary else {}}


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
