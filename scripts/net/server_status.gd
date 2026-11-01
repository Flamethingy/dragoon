class_name ServerStatus
extends RefCounted
## The heartbeat of a table (TASK-38). A hosting table answers a small status request over
## TCP on the same port number as its game (the game itself is ENet over UDP, so the two
## don't clash): one line "DRAGOON STATUS <protocol>" in, one JSON line out:
## {app, protocol, world, timeline, dm, players: [names], online, max}.
## The start screen probes its saved servers with it (Probe) and keeps them in `servers_file`.

const PROTOCOL := 1  ## bump when host and players can no longer talk to each other
const REQUEST := "DRAGOON STATUS"
const TIMEOUT_MSEC := 3000

static var servers_file := "user://servers.json"


# --- Host side ----------------------------------------------------------------------------------

## Answers status requests while hosting. `info` is called for the current status.
class Responder:
	var server := TCPServer.new()
	var info: Callable
	var _open: Array = []  ## [{peer: StreamPeerTCP, since: msec}]

	func start(port: int) -> Error:
		return server.listen(port)

	func stop() -> void:
		for c: Dictionary in _open:
			(c.peer as StreamPeerTCP).disconnect_from_host()
		_open.clear()
		server.stop()

	## Call every frame.
	func poll() -> void:
		if not server.is_listening():
			return
		while server.is_connection_available():
			_open.append({"peer": server.take_connection(), "since": Time.get_ticks_msec()})
		for c: Dictionary in _open.duplicate():
			var peer: StreamPeerTCP = c.peer
			peer.poll()
			var done := peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - int(c.since) > TIMEOUT_MSEC
			if not done and not c.has("answered") and peer.get_available_bytes() > 0:
				var line := peer.get_utf8_string(peer.get_available_bytes())
				if line.begins_with(REQUEST):
					var status: Dictionary = info.call() if info.is_valid() else {}
					status["app"] = "dragoon"
					status["protocol"] = PROTOCOL
					peer.put_data((JSON.stringify(status) + "\n").to_utf8_buffer())
					c["answered"] = true  # the asker hangs up; closing first loses the answer
				else:
					done = true
			if done:
				peer.disconnect_from_host()
				_open.erase(c)


# --- Player side ---------------------------------------------------------------------------------

## Asks one server for its status, without blocking. Poll until `state` is not "checking".
class Probe:
	var address := ""
	var port := 0
	var state := "checking"  ## checking, online, offline, mismatch
	var info := {}
	var _peer := StreamPeerTCP.new()
	var _sent := false
	var _buffer := ""
	var _since := 0

	func _init(host: String, p: int) -> void:
		address = host
		port = p
		_since = Time.get_ticks_msec()
		var ip := host if host.is_valid_ip_address() else IP.resolve_hostname(host)
		if ip == "" or _peer.connect_to_host(ip, p) != OK:
			state = "offline"

	## Returns true once it knows.
	func poll() -> bool:
		if state != "checking":
			return true
		_peer.poll()
		var s := _peer.get_status()
		if s == StreamPeerTCP.STATUS_CONNECTED:
			if not _sent:
				_peer.put_data(("%s %d\n" % [REQUEST, PROTOCOL]).to_utf8_buffer())
				_sent = true
			if _peer.get_available_bytes() > 0:
				_buffer += _peer.get_utf8_string(_peer.get_available_bytes())
			if "\n" in _buffer:
				var data: Variant = JSON.parse_string(_buffer.get_slice("\n", 0))
				if data is Dictionary and data.get("app") == "dragoon":
					info = data
					state = "online" if int(data.get("protocol", 0)) == PROTOCOL else "mismatch"
				else:
					state = "offline"
				_peer.disconnect_from_host()
				return true
		elif s == StreamPeerTCP.STATUS_ERROR or s == StreamPeerTCP.STATUS_NONE:
			state = "offline"
			return true
		if Time.get_ticks_msec() - _since > TIMEOUT_MSEC:
			state = "offline"
			_peer.disconnect_from_host()
			return true
		return false


## "ip:port" or "host" (default port) -> [host, port].
static func split_address(text: String, default_port := NetTable.DEFAULT_PORT) -> Array:
	var t := text.strip_edges()
	var colon := t.rfind(":")
	if colon > 0 and t.substr(colon + 1).is_valid_int():
		return [t.substr(0, colon), int(t.substr(colon + 1))]
	return [t, default_port]


# --- Saved servers ---------------------------------------------------------------------------------

## [{name, address, port}] from servers_file.
static func load_servers() -> Array:
	if not FileAccess.file_exists(servers_file):
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(servers_file))
	return (data as Array).filter(func(x: Variant) -> bool: return x is Dictionary) if data is Array else []


static func save_servers(list: Array) -> Error:
	var f := FileAccess.open(servers_file, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(list, " "))
	return OK
