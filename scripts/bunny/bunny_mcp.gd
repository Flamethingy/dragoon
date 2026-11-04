class_name BunnyMcp
extends Node
## The Table Bunny's tools over MCP for a local assistant (TASK-99, doc-3): e.g. Tamago on the
## DM's computer prepares encounters, writes session notes and looks things up with the DM's
## rights. Off by default (the host switches it on in the Table Bunny settings).
##
## Streamable HTTP, JSON responses only: POST /mcp with one JSON-RPC message (initialize, ping,
## tools/list, tools/call; notifications get 202). Only on 127.0.0.1, only with the token
## (`Authorization: Bearer <token>`), and a browser page from elsewhere (an Origin that isn't
## localhost) is turned away. The tools are BunnyTools, nothing more, run as the DM (peer 1):
## the same checks, changes through the event log.

const PROTOCOL := "2025-06-18"
const DEFAULT_PORT := 8770  ## 8765 / 8766 are taken on Nico's computer (Tamago, Material Maker)
const MAX_BODY := 1_000_000

var table: NetTable
var port := DEFAULT_PORT
var token := ""
var _server := TCPServer.new()
var _clients: Array = []  ## [{peer: StreamPeerTCP, buf: PackedByteArray, since: msec}]


## The token for the settings (made once, kept in the bunny settings in user://).
static func ensure_token() -> String:
	var t := str(BunnyBrain.setting("mcp_token"))
	if t.length() < 32:
		var crypto := Crypto.new()
		t = crypto.generate_random_bytes(24).hex_encode()
		BunnyBrain.set_setting("mcp_token", t)
	return t


func start(at_port := DEFAULT_PORT) -> Error:
	port = at_port
	if token == "":
		token = ensure_token()
	var err := _server.listen(port, "127.0.0.1")
	set_process(err == OK)
	return err


func stop() -> void:
	for c: Dictionary in _clients:
		(c.peer as StreamPeerTCP).disconnect_from_host()
	_clients.clear()
	_server.stop()
	set_process(false)


func is_running() -> bool:
	return _server.is_listening()


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "buf": PackedByteArray(), "since": Time.get_ticks_msec()})
	for c: Dictionary in _clients.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got: Array = peer.get_partial_data(n)
			if int(got[0]) == OK:
				var buf: PackedByteArray = c.buf  # a value type: append, then store back
				buf.append_array(got[1])
				c.buf = buf
		var req := _parse(c.buf)
		if req.is_empty():
			if Time.get_ticks_msec() - int(c.since) > 10000 or (c.buf as PackedByteArray).size() > MAX_BODY + 16384:
				peer.disconnect_from_host()
				_clients.erase(c)
			continue
		var res := handle(req)
		_reply(peer, int(res.code), str(res.get("body", "")))
		_clients.erase(c)


## A whole HTTP request from the bytes so far: {method, path, headers (lower-case), body}, or {} if
## it isn't all there yet.
static func _parse(buf: PackedByteArray) -> Dictionary:
	var text := buf.get_string_from_utf8()
	var head_end := text.find("\r\n\r\n")
	if head_end < 0:
		return {}
	var lines := text.substr(0, head_end).split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		return {"method": "BAD", "path": "", "headers": {}, "body": ""}
	var headers := {}
	for i in range(1, lines.size()):
		var at := lines[i].find(":")
		if at > 0:
			headers[lines[i].substr(0, at).strip_edges().to_lower()] = lines[i].substr(at + 1).strip_edges()
	var length := int(headers.get("content-length", "0"))
	var body_bytes := buf.slice(text.substr(0, head_end + 4).to_utf8_buffer().size())
	if body_bytes.size() < length:
		return {}
	return {"method": first[0], "path": first[1], "headers": headers, "body": body_bytes.slice(0, length).get_string_from_utf8()}


## One request: {code, body}.
func handle(req: Dictionary) -> Dictionary:
	var headers: Dictionary = req.get("headers", {})
	var origin := str(headers.get("origin", ""))
	if origin != "" and not (origin.begins_with("http://localhost") or origin.begins_with("http://127.0.0.1")):
		return {"code": 403, "body": ""}
	if str(headers.get("authorization", "")) != "Bearer " + token or token == "":
		return {"code": 401, "body": ""}
	if str(req.get("path", "")).get_slice("?", 0) != "/mcp":
		return {"code": 404, "body": ""}
	if str(req.method) != "POST":
		return {"code": 405, "body": ""}
	var msg: Variant = JSON.parse_string(str(req.get("body", "")))
	if not msg is Dictionary:
		return {"code": 400, "body": JSON.stringify({"jsonrpc": "2.0", "id": null, "error": {"code": -32700, "message": "Parse error"}})}
	if not (msg as Dictionary).has("id"):
		return {"code": 202, "body": ""}  # a notification (e.g. notifications/initialized)
	return {"code": 200, "body": JSON.stringify(rpc_answer(msg))}


## The JSON-RPC answer to one request.
func rpc_answer(msg: Dictionary) -> Dictionary:
	var id: Variant = msg.get("id")
	var params: Dictionary = msg.get("params", {}) if msg.get("params") is Dictionary else {}
	match str(msg.get("method", "")):
		"initialize":
			return _ok(id, {"protocolVersion": PROTOCOL, "capabilities": {"tools": {}},
				"serverInfo": {"name": "dragoon-table", "version": "1.0"},
				"instructions": "The Dragoon tabletop's tools, with the DM's rights. Changes are events at the table (they can be undone)."})
		"ping":
			return _ok(id, {})
		"tools/list":
			var tools := []
			for t: Dictionary in BunnyTools.schemas():
				tools.append({"name": t.name, "description": t.description, "inputSchema": t.input_schema})
			return _ok(id, {"tools": tools})
		"tools/call":
			var tool := str(params.get("name", ""))
			if tool not in BunnyTools.names():
				return {"jsonrpc": "2.0", "id": id, "error": {"code": -32602, "message": "Unknown tool: %s" % tool}}
			var out := BunnyTools.run(table, tool, params.get("arguments", {}), 1)  # the DM's rights
			return _ok(id, {"content": [{"type": "text", "text": JSON.stringify(out.get("result", out.get("error", "")))}],
				"isError": out.has("error")})
	return {"jsonrpc": "2.0", "id": id, "error": {"code": -32601, "message": "Method not found"}}


static func _ok(id: Variant, result: Dictionary) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "result": result}


static func _reply(peer: StreamPeerTCP, code: int, body: String) -> void:
	var reason: String = {200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
		404: "Not Found", 405: "Method Not Allowed"}.get(code, "Error")
	var bytes := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, reason, bytes.size()]
	peer.put_data(head.to_utf8_buffer())
	if not bytes.is_empty():
		peer.put_data(bytes)
	peer.disconnect_from_host()
