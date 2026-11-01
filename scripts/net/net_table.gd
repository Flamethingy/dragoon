class_name NetTable
extends Node
## The shared table (TASK-5 spike, grown for TASK-7/8/14/20). The DM hosts a timeline of a
## world (timelines.md) over ENet; players join by address with their player name from
## timeline.json and get their PC (its `player`), or pick a free one in the lobby.
##
## The DM instance owns all state. Players only ever receive a compact, whitelisted view
## of the current map and its tokens (Timeline.map_view / token_view, no bodies, no
## DM-only keys), and they only *request* changes: the host checks them (players may move
## only their own PC), writes events to the timeline's EventLog and broadcasts the result.
## Images go once per content hash and are cached on the clients (AssetCache).
## On world maps (`kind: world`) the PCs travel as one party token (TASK-13): moving it logs
## one token.moved per member (data.group = "party"); local maps show them one by one.
## The current map and picks of free PCs are kept in `table.json` in the timeline folder,
## so players can drop out and rejoin (by name) without restarting the host.
##
## Command line: `-- --host[=port] [--timeline=path]` or `-- --join=ip:port --name=Aria`.

signal status_changed(text: String)
signal notes_changed
signal table_changed  ## the map or tokens were (re)built
signal pcs_changed  ## lobby: the PC list or my PC changed
signal entry_received(ref: String)  ## player: an entry I asked for arrived or changed
signal accounts_changed  ## names or colors of the accounts changed
signal sheet_received(ref: String)  ## a sheet I opened arrived or changed (TASK-10)
signal rolls_changed  ## the roll log got a roll (TASK-12)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8
const PARTY := "party"  ## id of the group token on world maps
## What a sheet shows to someone who doesn't own it: the info page, no stats.
const INFO_FIELDS := ["name", "size", "type", "subtype", "race", "alignment", "description", "image", "tags"]
## Sheet fields nobody changes from the table.
const LOCKED_FIELDS := ["id", "player", "ref", "origin"]

## Host: the timeline folder; empty = the example timeline data/worlds/westmarch/timelines/red-fang
## (the example world is copied there on first use).
@export var timeline_dir := ""
## Host: the event log; empty = the timeline's events.jsonl (with its fork's inherited events).
@export var log_path := ""
@export var auto_ui := true
@export var calendar_path := "res://calendars/default.json"
## The login: a player's id or name from timeline.json (they are recognised by it when
## they rejoin).
@export var player_name := ""
@export var cache_dir := "user://cache/assets"

var grid: TokenGrid
var assets: AssetCache
var notes: SessionNotes
var status := "Offline"

# Host
var timeline: Timeline
var event_log: EventLog
var map_id := ""
var owners := {}  ## pc ref -> player id (pcs.json `player`, plus picks of free PCs)
var claims := {}  ## pc ref -> player id: free PCs picked in the lobby (table.json)
var peers := {}  ## peer id -> player id (connected and greeted)
var watching := {}  ## entity ref -> {peer id: true}: who has it open (gets reveal updates)

# Player
var pc_choices: Array = []  ## [{id, name, class, image, taken_by}]
var my_pc := ""
var my_player := ""  ## my player id, as the host knows me
var assets_received := 0  ## images downloaded this run (tests check the cache with it)
var entries := {}  ## ref -> the entry as the host let me see it (request_entry)
var accounts := {}  ## id -> {name, color "#rrggbb"}; "dm" = the DM (both sides)
var sheets := {}  ## ref -> the sheet as the host let me see it (open_sheet)
var rolls: Array = []  ## the roll log as I may see it (this session), oldest first
var rng := RandomNumberGenerator.new()  ## host: rolls the dice
var tables := {}  ## id -> rollable table (packages' tables.json, the timeline's win) (TASK-25)
const ROLL_LOG_SIZE := 100
var sheet_watchers := {}  ## host: ref -> {peer id: true} who has the sheet open
var _state := {}  ## the last table view from the host
var _status: ServerStatus.Responder  ## host: answers the start screens' heartbeat (TASK-38)
var _requested := {}  ## sha -> true while downloading

var _ui: TableUI


func _ready() -> void:
	grid = TokenGrid.new()
	grid.name = "Grid"
	grid.can_drag = _may_drag
	add_child(grid)
	grid.move_requested.connect(_on_move_requested)
	grid.token_clicked.connect(_on_token_clicked)
	assets = AssetCache.new(cache_dir)
	notes = SessionNotes.new()
	notes.calendar = WorldCalendar.load_file(calendar_path)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func() -> void:
		_set_status("Connected, saying hello...")
		hello.rpc_id(1, player_name))
	multiplayer.connection_failed.connect(func() -> void:
		_set_status("Could not connect")
		_go_offline.call_deferred())
	multiplayer.server_disconnected.connect(func() -> void:
		_set_status("The DM closed the table")
		_go_offline.call_deferred())
	if auto_ui:
		_ui = TableUI.new()
		_ui.table = self
		add_child(_ui)
	var join_to := ""
	var host_port := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--host"):
			host_port = int(arg.get_slice("=", 1)) if "=" in arg else DEFAULT_PORT
		elif arg.begins_with("--join="):
			join_to = arg.get_slice("=", 1)
		elif arg.begins_with("--name="):
			player_name = arg.get_slice("=", 1)
		elif arg.begins_with("--timeline="):
			timeline_dir = arg.get_slice("=", 1)
	if host_port > 0:
		host(host_port)
	elif join_to != "":
		join(join_to, player_name)


func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer 		and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func is_dm() -> bool:
	return is_online() and multiplayer.is_server()


# --- Hosting -------------------------------------------------------------------------

## The DM: opens the timeline and its event log (so the table continues where it
## stopped) and listens on `port`.
func host(port := DEFAULT_PORT) -> Error:
	if timeline_dir == "":
		Worlds.migrate_data(PackageDB.default_root().get_base_dir())  # old campaigns (TASK-32)
		timeline_dir = Worlds.install_example()
	if not Timeline.is_timeline(timeline_dir):
		_set_status("No timeline (timeline.json) in %s" % timeline_dir)
		return ERR_FILE_NOT_FOUND
	timeline = Timeline.new(timeline_dir, assets)
	if log_path == "" or log_path == timeline.events_path():
		log_path = timeline.events_path()
		event_log = timeline.events_log
	else:
		event_log = EventLog.open(log_path)
	_load_table_file()
	_update_owners()
	var maps := timeline.maps()
	if map_id not in maps:
		map_id = maps[0] if not maps.is_empty() else ""
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		_set_status("Can't host on port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	_status = ServerStatus.Responder.new()
	_status.info = status_info
	if _status.start(port) != OK:
		push_warning("No heartbeat on TCP port %d" % port)
	player_name = "DM"
	_open_notes()
	accounts = timeline.accounts()
	_apply_accounts()
	rng.randomize()
	load_tables()
	_load_rolls()
	_apply_state(view_for(""))
	_set_status("Hosting %s on port %d (%d events in the log)" % [timeline.info.get("name", timeline.id()), port, event_log.events.size()])
	return OK


## What one player sees of the table: {map: map_view, tokens: [token_view + cell]}.
## `player` "" = the DM (sees the private fields of every token).
func view_for(player: String) -> Dictionary:
	var map := timeline.map_view(map_id)
	if map.is_empty():
		return {}
	var on_map: Dictionary = map.tokens
	map.erase("tokens")
	var placed := Replay.tokens_on(map_id, event_log.effective())
	var ids: Array = on_map.keys()
	for id: String in placed:  # tokens placed in this timeline (token.placed events)
		if id not in ids:
			ids.append(id)
	var start: Vector2i = map.party_start
	var newcomers := 0
	var members: Array = owners.keys()  # the party: every PC someone plays
	members.sort()
	var world: bool = map.kind == "world" and not members.is_empty()
	for pc: String in members:
		if world:
			ids.erase(pc)
		elif pc not in ids:
			ids.append(pc)
	var tokens := []
	if world:
		tokens.append(_party_token(members, placed, start, map.party_token))
	for id: String in ids:
		var owner: String = owners.get(id, "")
		var t := timeline.token_view(id, owner, player == "" or (owner != "" and owner == player))
		if t.is_empty():
			continue
		_current_values(t)
		if placed.has(id):
			t["cell"] = placed[id]
		elif on_map.has(id):
			t["cell"] = on_map[id]
		else:  # a PC new on this map: next to the party start
			t["cell"] = start + Vector2i(newcomers, 0)
			newcomers += 1
		tokens.append(t)
	return {"map": map, "tokens": tokens}


## HP and AC on a token as they are now (the events), not as in the file.
func _current_values(t: Dictionary) -> void:
	var base := {}
	for key: String in Timeline.OWNER_FIELDS:
		if t.has(key):
			base[key] = t[key]
	if base.is_empty():
		return
	var now := Replay.entity_state(base, event_log.effective(str(t.id)))
	for key: String in base:
		t[key] = now.get(key)


## The group token: where its members are (they always move together), named after them.
func _party_token(members: Array, placed: Dictionary, start: Vector2i, image: String) -> Dictionary:
	var cell := start
	for pc: String in members:
		if placed.has(pc):
			cell = placed[pc]
			break
	var names := PackedStringArray()
	var players := []
	for pc: String in members:
		names.append(timeline.name_of(pc))
		players.append(owners[pc])
	if image == "":
		image = timeline.token_view(members[0]).get("image", "")
	return {"id": PARTY, "image": image, "name": "Party: %s" % ", ".join(names), "size": "medium",
		"kind": "party", "members": members, "players": players, "cell": cell}


## DM: shows another map to everyone.
func show_map_to_all(id: String) -> void:
	if not is_dm() or id not in timeline.maps():
		return
	map_id = id
	_save_table_file()
	_apply_state(view_for(""))
	_send_tables()
	_set_status("Showing %s" % timeline.name_of(id))


## DM: a compendium entry dropped on the map at `cell` (TASK-34): its entity in this
## timeline (Timeline.token_entity: monsters get numbered copies) is placed there with a
## `token.placed` event, or moved there if it is on this map already. Returns the ref.
func drop_token(e: Dictionary, cell: Vector2i) -> String:
	if not is_dm() or map_id == "":
		return ""
	var ref := timeline.token_entity(e)
	if ref == "":
		_set_status("Only monsters, NPCs and PCs go on the map")
		return ""
	var placed := Replay.tokens_on(map_id, event_log.effective())
	if grid.tokens.has(ref) or placed.has(ref):
		event_log.move_token(ref, map_id, grid.token_cell(ref) if grid.tokens.has(ref) else placed[ref], cell)
	else:
		event_log.place_token(ref, map_id, cell)
	_apply_state(view_for(""))
	_send_tables()
	_set_status("%s placed at %s" % [timeline.name_of(ref), cell])
	return ref


# --- Combat (TASK-35) -----------------------------------------------------------------------

## True while a combat runs in this timeline.
func in_combat() -> bool:
	return event_log != null and bool(Replay.world_state(event_log.effective()).combat.active)


## DM: starts a combat on the current map with the creatures on it (`combat.started`).
func start_combat() -> Dictionary:
	if not is_dm() or in_combat():
		return {}
	var order := []
	for id: String in grid.tokens:
		if "/" in id:
			order.append({"entity": id, "initiative": 0})
	var e := event_log.append("combat.started", "", {"map": map_id, "order": order})
	_set_status("Combat on %s" % timeline.name_of(map_id))
	table_changed.emit()
	return e


## DM: the next turn (and round, after the last in the order): `combat.turn`.
func next_turn() -> Dictionary:
	if not is_dm() or not in_combat():
		return {}
	var c: Dictionary = Replay.world_state(event_log.effective()).combat
	var turn := int(c.turn) + 1
	var round_now := int(c.round)
	if turn >= maxi((c.order as Array).size(), 1):
		turn = 0
		round_now += 1
	var e := event_log.append("combat.turn", "", {"round": round_now, "turn": turn})
	_set_status("Round %d, turn %d" % [round_now, turn + 1])
	return e


## DM: ends the combat (`combat.ended`); it is saved as an encounter of the timeline.
## Returns the encounter ({} if none was made).
func end_combat(reason := "") -> Dictionary:
	if not is_dm() or not in_combat():
		return {}
	event_log.append("combat.ended", "", {"reason": reason} if reason != "" else {})
	var made := Encounters.open(timeline.folder).sync(event_log, timeline)
	_set_status("Combat over%s" % ("" if made.is_empty() else ": saved as \"%s\"" % made[0].name))
	table_changed.emit()
	return made[0] if not made.is_empty() else {}


## DM: the world's maps changed (added, grid aligned): reads them again and shows `id`.
func maps_changed(id := "") -> void:
	if not is_dm():
		return
	timeline.reload_world()
	grid.map_id = ""  # rebuild the map even if it is the same one
	show_map_to_all(id if id != "" else map_id)


func _send_tables() -> void:
	for peer_id: int in peers:
		receive_table.rpc_id(peer_id, view_for(peers[peer_id]))


func _send_pc_lists() -> void:
	var choices := timeline.pc_choices(owners)
	for peer_id: int in peers:
		pc_list.rpc_id(peer_id, choices, _pc_of(peers[peer_id]), peers[peer_id])


func _pc_of(player: String) -> String:
	for pc: String in owners:
		if owners[pc] == player:
			return pc
	return ""


## PCs with a `player` in pcs.json belong to them; free ones to whoever picked them.
func _update_owners() -> void:
	owners = timeline.owners()
	for pc: String in claims:
		if not owners.has(pc) and pc in timeline.pcs():
			owners[pc] = claims[pc]


func _table_file() -> String:
	return timeline_dir.path_join("table.json")


func _load_table_file() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_table_file())) \
		if FileAccess.file_exists(_table_file()) else null
	if data is Dictionary:
		map_id = str(data.get("map", ""))
		claims = data.get("claims", {}) if data.get("claims") is Dictionary else {}


func _save_table_file() -> void:
	var f := FileAccess.open(_table_file(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"map": map_id, "claims": claims}, "  "))


func _on_peer_connected(id: int) -> void:
	if is_dm():
		_set_status("Someone is joining (peer %d)" % id)


func _on_peer_disconnected(id: int) -> void:
	if is_dm() and peers.has(id):
		_set_status("%s left (their PC stays at the table)" % timeline.player_name(peers[id]))
		peers.erase(id)
		for ref: String in watching:
			watching[ref].erase(id)


# --- Joining and the lobby -------------------------------------------------------------

## A player: "ip:port" or just "ip", with the name they play under.
func join(address: String, name_to_use := "") -> Error:
	if name_to_use.strip_edges() != "":
		player_name = name_to_use.strip_edges()
	if player_name == "":
		_set_status("Enter your name first")
		return ERR_INVALID_PARAMETER
	var ip := address.get_slice(":", 0).strip_edges()
	var port := int(address.get_slice(":", 1)) if ":" in address else DEFAULT_PORT
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip if ip != "" else "127.0.0.1", port)
	if err != OK:
		_set_status("Can't join %s: %s" % [address, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	load_tables()
	_set_status("Joining %s:%d..." % [ip, port])
	return OK


## Player -> DM, right after connecting.
@rpc("any_peer", "call_remote", "reliable")
func hello(name_given: String) -> void:
	if not is_dm():
		return
	var sender := multiplayer.get_remote_sender_id()
	var player := timeline.player_id(name_given.left(64))
	if player == "":
		join_denied.rpc_id(sender, "\"%s\" isn't a player in this timeline" % name_given.strip_edges().left(64))
		return
	if player in peers.values():
		join_denied.rpc_id(sender, "%s is already at the table" % timeline.player_name(player))
		return
	peers[sender] = player
	pc_list.rpc_id(sender, timeline.pc_choices(owners), _pc_of(player), player)
	receive_accounts.rpc_id(sender, accounts)
	sync_rolls.rpc_id(sender, _rolls_for(player))
	sync_notes.rpc_id(sender, notes.session, _notes_for(player), notes.names)
	receive_table.rpc_id(sender, view_for(player))
	var who := timeline.player_name(player)
	_set_status("%s joined as %s" % [who, timeline.name_of(_pc_of(player))] if _pc_of(player) != "" \
		else "%s joined, picking a character" % who)


## DM -> player: the name was refused; the player hangs up.
@rpc("authority", "call_remote", "reliable")
func join_denied(reason: String) -> void:
	_set_status("Can't join: %s" % reason)
	_go_offline.call_deferred()


## DM -> player: the PCs to pick from, which one is theirs ("" = none yet) and who they are.
@rpc("authority", "call_remote", "reliable")
func pc_list(choices: Array, mine: String, player: String) -> void:
	pc_choices = choices
	my_pc = mine
	my_player = player
	var need := []
	for c: Dictionary in choices:
		need.append(c.get("image", ""))
	_fetch(need)
	if mine == "":
		_set_status("Pick your character")
	else:
		for c: Dictionary in choices:
			if c.id == mine:
				_set_status("Playing %s" % c.name)
	pcs_changed.emit()


## Player: "I play this one".
func claim_pc(pc: String) -> void:
	if is_online() and not is_dm():
		request_pc.rpc_id(1, pc)


@rpc("any_peer", "call_remote", "reliable")
func request_pc(pc: String) -> void:
	if not is_dm():
		return
	var sender := multiplayer.get_remote_sender_id()
	var player: String = peers.get(sender, "")
	if player == "" or pc not in timeline.pcs():
		return
	var taken_by: String = owners.get(pc, "")
	if taken_by != "" and taken_by != player:
		pc_denied.rpc_id(sender, "%s already plays %s" % [timeline.player_name(taken_by), timeline.name_of(pc)])
		return
	for other: String in claims.keys():  # one picked PC per player
		if claims[other] == player:
			claims.erase(other)
	if not timeline.owners().has(pc):
		claims[pc] = player
	_update_owners()
	_save_table_file()
	_send_pc_lists()
	_apply_state(view_for(""))
	_send_tables()
	_set_status("%s plays %s" % [timeline.player_name(player), timeline.name_of(pc)])


@rpc("authority", "call_remote", "reliable")
func pc_denied(reason: String) -> void:
	_set_status(reason)
	pcs_changed.emit()


## Host: what the heartbeat tells start screens (ServerStatus): world, timeline, DM, players.
func status_info() -> Dictionary:
	var names := []
	for id: int in peers:
		names.append(timeline.player_name(peers[id]))
	return {"world": str(timeline.world_manifest().get("name", timeline.world_id())), "timeline": str(timeline.info.get("name", timeline.id())),
		"dm": str((timeline.info.get("dm", {}) as Dictionary).get("name", "DM")) if timeline.info.get("dm") is Dictionary else "DM",
		"players": names, "online": names.size(), "max": MAX_PLAYERS}


func _process(_delta: float) -> void:
	if _status != null:
		_status.poll()


## Back to the start screen (call deferred, not from inside the network poll).
func _go_offline() -> void:
	if _status != null:
		_status.stop()
		_status = null
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peers.clear()
	my_pc = ""
	my_player = ""
	pc_choices = []
	_state = {}
	grid.clear()
	pcs_changed.emit()
	table_changed.emit()


# --- The table view and images ----------------------------------------------------------

## DM -> player: the current map and tokens as this player may see them.
@rpc("authority", "call_remote", "reliable")
func receive_table(view: Dictionary) -> void:
	_state = view
	_fetch(_hashes(view))
	_try_show()


## Asks the host for the images that aren't in the cache yet.
func _fetch(hashes: Array) -> void:
	var need := []
	for sha: String in hashes:
		if sha != "" and not assets.has(sha) and not _requested.has(sha):
			_requested[sha] = true
			need.append(sha)
	if not need.is_empty():
		request_assets.rpc_id(1, need)


@rpc("any_peer", "call_remote", "reliable")
func request_assets(hashes: Array) -> void:
	if not is_dm():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not peers.has(sender):
		return
	# Only images this player may see: their table view and the PC portraits.
	var allowed := _hashes(view_for(peers[sender]))
	for c: Dictionary in timeline.pc_choices(owners):
		allowed.append(c.image)
	for sha: String in hashes:
		if sha not in allowed:
			continue
		var parts := assets.chunks(sha)
		for i in parts.size():
			asset_part.rpc_id(sender, sha, assets.extension(sha), i, parts.size(), parts[i])


@rpc("authority", "call_remote", "reliable")
func asset_part(sha: String, ext: String, index: int, count: int, data: PackedByteArray) -> void:
	if assets.receive(sha, ext, index, count, data):
		assets_received += 1
		_requested.erase(sha)
		_try_show()
		pcs_changed.emit()  # portraits in the picker


func _try_show() -> void:
	if _state.is_empty():
		return
	for sha: String in _hashes(_state):
		if not assets.has(sha):
			return
	_apply_state(_state)


static func _hashes(view: Dictionary) -> Array:
	var out := []
	if view.is_empty():
		return out
	out.append(view.map.get("image", ""))
	for t: Dictionary in view.tokens:
		if str(t.get("image", "")) != "":  # no picture: a placeholder token
			out.append(t.get("image", ""))
	return out


## Builds or updates the grid from a view (the map is only rebuilt when it changed).
func _apply_state(view: Dictionary) -> void:
	if view.is_empty():
		return
	var map: Dictionary = view.map
	var map_image: String = map.get("image", "")
	if grid.map_id != map.id or grid.get_meta("image", "") != map_image:
		var tex := assets.texture(map_image)
		if tex == null:
			return
		grid.show_map(map, tex)
		grid.set_meta("image", map_image)
	var keep := {}
	for t: Dictionary in view.tokens:
		var id: String = t.id
		keep[id] = true
		var cell: Vector2i = t.cell
		var token: Sprite2D = grid.tokens.get(id)
		if token and token.get_meta("info", {}).get("image", "") == t.get("image", ""):
			token.set_meta("info", t)
			grid.set_token_cell(id, cell, token.get_meta("cell") != cell)
		else:
			var tex := assets.texture(t.get("image", "")) if str(t.get("image", "")) != "" else TokenGrid.placeholder(str(t.get("kind", "")))
			if tex:
				grid.add_token_view(t, tex, cell)
	for id: String in grid.tokens.keys():
		if not keep.has(id):
			grid.tokens[id].queue_free()
			grid.tokens.erase(id)
	var count := grid.tokens.size()
	grid.set_info("%s · %d token%s · left drag: move, wheel: zoom, right drag: pan" % [map.get("name", map.id), count, "" if count == 1 else "s"])
	table_changed.emit()


# --- Moves -----------------------------------------------------------------------------

func _may_drag(entity: String) -> bool:
	if is_dm():
		return true
	var token: Sprite2D = grid.tokens.get(entity)
	if token == null or my_player == "":
		return false
	var info: Dictionary = token.get_meta("info", {})
	if info.has("players"):  # the party token: anyone in the party
		return my_player in info.players
	return str(info.get("owner", "")) == my_player


## Dropped a token here: the DM decides directly, players ask the DM.
func _on_move_requested(entity: String, cell: Vector2i) -> void:
	if not is_online():
		_set_status("Host or join a table first")
	elif is_dm():
		_handle_move(1, entity, cell)
	else:
		request_move.rpc_id(1, entity, cell)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_move(entity: String, cell: Vector2i) -> void:
	if not is_dm():
		return  # only the DM decides
	_handle_move(multiplayer.get_remote_sender_id(), entity, cell)


## The DM validates, logs and broadcasts (or tells the player no).
func _handle_move(sender: int, entity: String, cell: Vector2i) -> void:
	if not grid.tokens.has(entity):
		_deny(sender, entity, "unknown token")
		return
	if entity == PARTY:
		_handle_party_move(sender, cell)
		return
	if sender != 1:
		var player: String = peers.get(sender, "")
		if player == "" or owners.get(entity, "") != player:
			_deny(sender, entity, "that's not your token")
			return
	if not grid.can_place(entity, cell):
		_deny(sender, entity, "that square is blocked")
		return
	var from := grid.token_cell(entity)
	var by := "dm" if sender == 1 else str(peers[sender])
	var e := event_log.move_token(entity, grid.map_id, from, cell, by)
	grid.set_token_cell(entity, cell)
	for peer_id: int in peers:
		token_moved.rpc_id(peer_id, entity, cell, int(e.get("id", 0)))
	_set_status("%s moved to %s (event %d)" % [_name_of(entity), cell, int(e.get("id", 0))])


## The party token travels: one token.moved per member (data.group = "party"), so
## every character's own timeline stays complete.
func _handle_party_move(sender: int, cell: Vector2i) -> void:
	var info: Dictionary = grid.tokens[PARTY].get_meta("info")
	if sender != 1 and peers.get(sender, "") not in info.players:
		_deny(sender, PARTY, "you're not in this party")
		return
	if not grid.can_place(PARTY, cell):
		_deny(sender, PARTY, "that square is blocked")
		return
	var from := grid.token_cell(PARTY)
	var by := "dm" if sender == 1 else str(peers[sender])
	var last := {}
	for pc: String in info.members:
		last = event_log.move_token(pc, grid.map_id, from, cell, by, PARTY)
	grid.set_token_cell(PARTY, cell)
	for peer_id: int in peers:
		token_moved.rpc_id(peer_id, PARTY, cell, int(last.get("id", 0)))
	_set_status("The party travels to %s (%d events)" % [cell, info.members.size()])


## DM -> players: a move happened.
@rpc("authority", "call_remote", "reliable")
func token_moved(entity: String, cell: Vector2i, event_id: int) -> void:
	grid.set_token_cell(entity, cell)
	_set_status("%s moved to %s (event %d)" % [_name_of(entity), cell, event_id])


## DM -> one player: the move was refused.
@rpc("authority", "call_remote", "reliable")
func move_denied(entity: String, reason: String) -> void:
	_set_status("Can't move %s: %s" % [_name_of(entity), reason])


func _deny(sender: int, entity: String, reason: String) -> void:
	if sender == 1:
		move_denied(entity, reason)
	else:
		move_denied.rpc_id(sender, entity, reason)


func _name_of(entity: String) -> String:
	var token: Sprite2D = grid.tokens.get(entity)
	return str(token.get_meta("info", {}).get("name", entity)) if token else entity


# --- Session notes (TASK-14) -------------------------------------------------------------

## Writes a note: the DM directly, players through the DM.
func add_note(text: String) -> void:
	if text.strip_edges() == "":
		return
	if not is_online():
		_set_status("Host or join a table first")
	elif is_dm():
		_handle_note(1, text)
	else:
		request_note.rpc_id(1, text)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_note(text: String) -> void:
	if is_dm() and peers.has(multiplayer.get_remote_sender_id()):
		_handle_note(multiplayer.get_remote_sender_id(), text)


func _handle_note(sender: int, text: String) -> void:
	var by: String = "dm" if sender == 1 else peers.get(sender, "")
	var entry := notes.add(text.left(10000), by, event_log.day, event_log.time)
	_show_notes()
	for peer_id: int in peers:
		note_added.rpc_id(peer_id, _note_for(entry, peers[peer_id]))


## A note as a player may see it (<reveal> and %% work in notes too).
static func _note_for(entry: Dictionary, player: String) -> Dictionary:
	var out := entry.duplicate()
	out["text"] = Reveal.filter(str(entry.get("text", "")), player)
	return out


func _notes_for(player: String) -> Array:
	return notes.entries.map(func(e: Dictionary) -> Dictionary: return _note_for(e, player))


## DM -> players: a new note.
@rpc("authority", "call_remote", "reliable")
func note_added(entry: Dictionary) -> void:
	notes.entries.append(entry)
	_show_notes()


## DM -> players: all notes of the current session (on join and when a session starts)
## and the writers' display names.
@rpc("authority", "call_remote", "reliable")
func sync_notes(session: int, entries: Array, names: Dictionary) -> void:
	notes.session = session
	notes.names = names
	notes.entries.clear()
	for e: Dictionary in entries:
		notes.entries.append(e)
	_show_notes()


## DM: the next session starts (an event in the log; notes go to a new file).
func start_next_session() -> void:
	if not is_dm():
		return
	event_log.start_session(event_log.session + 1)
	_open_notes()
	_load_rolls()
	for peer_id: int in peers:
		sync_notes.rpc_id(peer_id, notes.session, _notes_for(peers[peer_id]), notes.names)
		sync_rolls.rpc_id(peer_id, _rolls_for(peers[peer_id]))
	_set_status("Session %d started" % event_log.session)


func _open_notes() -> void:
	notes = SessionNotes.open(timeline_dir, event_log.session, notes.calendar)
	notes.names = {"dm": str(timeline.info.get("dm", {}).get("name", "DM"))}
	for p: Dictionary in timeline.players():
		notes.names[str(p.id)] = str(p.get("name", p.id))
	_show_notes()


func _show_notes() -> void:
	notes_changed.emit()


# --- Account colors (TASK-19) -------------------------------------------------------------

## My account color: the DM saves it, players ask the DM. Everyone gets the new colors.
func set_my_color(color: Color) -> void:
	var hex := "#" + color.to_html(false)
	if is_dm():
		_handle_color(Reveal.DM, hex)
	elif is_online():
		request_color.rpc_id(1, hex)


func my_account() -> String:
	return Reveal.DM if is_dm() else my_player


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_color(hex: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if is_dm() and peers.has(sender):
		_handle_color(peers[sender], hex.left(9))


func _handle_color(account: String, hex: String) -> void:
	if not timeline.set_color(account, hex):
		return
	accounts = timeline.accounts()
	_apply_accounts()
	for peer_id: int in peers:
		receive_accounts.rpc_id(peer_id, accounts)


## DM -> players.
@rpc("authority", "call_remote", "reliable")
func receive_accounts(list: Dictionary) -> void:
	accounts = list
	_apply_accounts()


## Frames and hints in Markdown use these colors and "you" = this account.
func _apply_accounts() -> void:
	Markdown.reveal_accounts = accounts
	Markdown.reveal_viewer = my_account() if my_account() != "" else "?"
	accounts_changed.emit()
	_show_notes()


# --- Entries and reveals (TASK-18) -------------------------------------------------------

## Opens an entry: the DM reads it whole, players ask the host, which cuts out what they
## may not see (Timeline.entry_view) and keeps them updated when a reveal changes.
func open_entry(ref: String) -> void:
	if is_dm():
		entries[ref] = timeline.entry_view(ref, "dm")
		entry_received.emit(ref)
	elif is_online():
		request_entry.rpc_id(1, ref)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_entry(ref: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not is_dm() or not peers.has(sender) or timeline.entry(ref).is_empty():
		return
	if not watching.has(ref):
		watching[ref] = {}
	watching[ref][sender] = true
	receive_entry.rpc_id(sender, ref, entry_for(peers[sender], ref))


## Host: an entry as `player` may see it now (the event log's clock).
func entry_for(player: String, ref: String) -> Dictionary:
	return timeline.entry_view(ref, player, event_log.effective(ref, event_log.day, event_log.time))


## DM -> player.
@rpc("authority", "call_remote", "reliable")
func receive_entry(ref: String, entry: Dictionary) -> void:
	entries[ref] = entry
	entry_received.emit(ref)


## DM: shows (add) or hides (remove) a <reveal> passage for players during play. Logged as
## reveal.changed; players who have the entry open get the new view at once.
func change_reveal(ref: String, reveal: String, add: Array = [], remove: Array = [], field := "description") -> Dictionary:
	if not is_dm():
		return {}
	var e := event_log.change_reveal(ref, reveal, field, add, remove)
	for peer_id: int in watching.get(ref, {}):
		if peers.has(peer_id):
			receive_entry.rpc_id(peer_id, ref, entry_for(peers[peer_id], ref))
	if entries.has(ref):
		open_entry(ref)
	return e


# --- Sheets (TASK-10) ---------------------------------------------------------------------

## A click on a token opens its sheet (the party token: my own PC's).
func _on_token_clicked(entity: String) -> void:
	if entity == PARTY:
		if my_pc != "":
			open_sheet(my_pc)
		return
	open_sheet(entity)


## The DM sees every sheet, a player the sheet of their own PC; everyone else only gets
## the info page (INFO_FIELDS, with reveals applied).
func may_see_sheet(player: String, ref: String) -> bool:
	return player == Reveal.DM or (player != "" and owners.get(ref, "") == player)


## Host: a creature's sheet as `player` may see it now: its entry plus its events
## (Replay), never the file alone. Adds `_full`, `_editable`, `_hp_max` and `_class`.
func sheet_for(player: String, ref: String) -> Dictionary:
	if ref.get_slice("/", 0) not in Timeline.CREATURES:
		return {}
	var events := event_log.effective(ref, event_log.day, event_log.time)
	var view := timeline.entry_view(ref, player, events)
	if view.is_empty():
		return {}
	var full := may_see_sheet(player, ref)
	var sheet := {}
	if full:
		sheet = Replay.entity_state(view, events)
		sheet["_hp_max"] = int(timeline.entry(ref).get("hp", 0))
		if sheet.has("classes"):
			sheet["_class"] = timeline.class_text(sheet)
		var attacks := []
		var features := timeline.entries("features")
		for key in ["features", "actions", "bonus_actions", "reactions"]:
			for fid: Variant in sheet.get(key, []):
				var f: Variant = features.get(str(fid), {})
				if f is Dictionary and f.get("attack") is Dictionary:
					attacks.append(str(f.get("name", fid)))
		sheet["_attacks"] = attacks
	else:
		for key: String in INFO_FIELDS:
			if view.has(key):
				sheet[key] = view[key]
	sheet["ref"] = ref
	sheet["_kind"] = ref.get_slice("/", 0)
	sheet["_full"] = full
	sheet["_editable"] = full
	sheet["_owner"] = timeline.player_name(owners.get(ref, "")) if owners.get(ref, "") != "" else ""
	return sheet


## Opens a sheet: the DM builds it, players ask the host (and get updates while it is open).
func open_sheet(ref: String) -> void:
	if is_dm():
		var sheet := sheet_for(Reveal.DM, ref)
		if not sheet.is_empty():
			sheets[ref] = sheet
			sheet_received.emit(ref)
	elif is_online():
		request_sheet.rpc_id(1, ref)


func close_sheet(ref: String) -> void:
	sheets.erase(ref)
	if is_online() and not is_dm():
		forget_sheet.rpc_id(1, ref)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_sheet(ref: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not is_dm() or not peers.has(sender):
		return
	var sheet := sheet_for(peers[sender], ref)
	if sheet.is_empty():
		return
	sheet_watchers.get_or_add(ref, {})[sender] = true
	receive_sheet.rpc_id(sender, ref, sheet)


## Player -> DM: closed it, no more updates.
@rpc("any_peer", "call_remote", "reliable")
func forget_sheet(ref: String) -> void:
	if is_dm():
		sheet_watchers.get(ref, {}).erase(multiplayer.get_remote_sender_id())


## DM -> player.
@rpc("authority", "call_remote", "reliable")
func receive_sheet(ref: String, sheet: Dictionary) -> void:
	sheets[ref] = sheet
	sheet_received.emit(ref)


## Damage (negative) or healing (positive): an hp.changed event, the file stays as it is.
## Damage takes temporary HP first; HP stays between 0 and the maximum.
func change_hp(ref: String, delta: int, reason := "") -> void:
	if is_dm():
		_handle_hp(1, ref, delta, reason)
	elif is_online():
		request_hp.rpc_id(1, ref, delta, reason)


## Any other sheet field by dotted path (ac, temp_hp, stats.str, ...): a sheet.changed event.
func change_field(ref: String, path: String, value: Variant) -> void:
	if is_dm():
		_handle_field(1, ref, path, value)
	elif is_online():
		request_field.rpc_id(1, ref, path, value)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_hp(ref: String, delta: int, reason: String) -> void:
	if is_dm():
		_handle_hp(multiplayer.get_remote_sender_id(), ref, delta, reason)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_field(ref: String, path: String, value: Variant) -> void:
	if is_dm():
		_handle_field(multiplayer.get_remote_sender_id(), ref, path, value)


func _sender_player(sender: int) -> String:
	return Reveal.DM if sender == 1 else str(peers.get(sender, ""))


func _handle_hp(sender: int, ref: String, delta: int, reason: String) -> Dictionary:
	var player := _sender_player(sender)
	if not may_see_sheet(player, ref):
		_deny_sheet(sender, "that's not your sheet")
		return {}
	var sheet := sheet_for(Reveal.DM, ref)
	if sheet.is_empty() or delta == 0:
		return {}
	var hp := int(sheet.get("hp", 0))
	var temp := int(sheet.get("temp_hp", 0))
	var hp_max: int = sheet._hp_max if int(sheet._hp_max) > 0 else 1 << 30
	var data := {"reason": reason}
	if delta < 0 and temp > 0:
		var absorbed := mini(temp, -delta)
		temp -= absorbed
		data["temp"] = temp
		delta += absorbed
	var after := clampi(hp + delta, 0, maxi(hp_max, hp))
	data["delta"] = after - hp
	data["hp"] = after
	var e := event_log.append("hp.changed", ref, data, player)
	_sheet_changed(ref)
	_set_status("%s: HP %d -> %d (event %d)" % [timeline.name_of(ref), hp, after, int(e.get("id", 0))])
	return e


func _handle_field(sender: int, ref: String, path: String, value: Variant) -> Dictionary:
	var player := _sender_player(sender)
	if not may_see_sheet(player, ref):
		_deny_sheet(sender, "that's not your sheet")
		return {}
	if path == "" or path.get_slice(".", 0) in LOCKED_FIELDS or path.begins_with("_"):
		_deny_sheet(sender, "%s can't be changed here" % path)
		return {}
	var sheet := sheet_for(Reveal.DM, ref)
	if sheet.is_empty():
		return {}
	var from: Variant = value_at(sheet, path)
	if from == value or (from is float or from is int) and (value is float or value is int) and float(from) == float(value):
		return {}
	var e := event_log.change_sheet(ref, path, from, value, "", player)
	_sheet_changed(ref)
	_set_status("%s: %s -> %s (event %d)" % [timeline.name_of(ref), path, value, int(e.get("id", 0))])
	return e


## A dotted path's value in a dictionary (null if it isn't there).
static func value_at(d: Dictionary, path: String) -> Variant:
	var at: Variant = d
	for part in path.split("."):
		if not at is Dictionary or not at.has(part):
			return null
		at = at[part]
	return at


## Everyone who has the sheet open gets it again; tokens show the new HP/AC.
func _sheet_changed(ref: String) -> void:
	for peer_id: int in sheet_watchers.get(ref, {}).keys():
		if peers.has(peer_id):
			receive_sheet.rpc_id(peer_id, ref, sheet_for(peers[peer_id], ref))
		else:
			sheet_watchers[ref].erase(peer_id)
	if sheets.has(ref):
		open_sheet(ref)
	_apply_state(view_for(""))
	_send_tables()


func _deny_sheet(sender: int, reason: String) -> void:
	if sender == 1:
		_set_status("Can't change that: " + reason)
	else:
		sheet_denied.rpc_id(sender, reason)


## DM -> player.
@rpc("authority", "call_remote", "reliable")
func sheet_denied(reason: String) -> void:
	_set_status("Can't change that: " + reason)


# --- Dice (TASK-12) --------------------------------------------------------------------------

## Rolls by name for a creature ("Perception", "Dex save", "attack with Longsword", "initiative",
## "... with advantage") or a formula ("2d6+3"). `ref` "" = my PC (players) or a plain formula.
## The host rolls, logs dice.rolled and shows it to everyone; `hidden` (DM only) shows it
## to the DM alone.
func roll(query: String, ref := "", hidden := false) -> void:
	if is_dm():
		_handle_roll(1, query, ref, hidden)
	elif is_online():
		request_roll.rpc_id(1, query, ref)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_roll(query: String, ref: String) -> void:
	if is_dm():
		_handle_roll(multiplayer.get_remote_sender_id(), query.left(200), ref, false)


func _handle_roll(sender: int, query: String, ref: String, hidden: bool) -> Dictionary:
	var player := _sender_player(sender)
	if player == "":
		return {}
	if ref == "" and player != Reveal.DM:
		ref = _pc_of(player)
	if ref != "" and not may_see_sheet(player, ref):
		_deny_roll(sender, "that's not your sheet")
		return {}
	var sheet := sheet_for(Reveal.DM, ref) if ref != "" else {}
	var asked := Dice.resolve(sheet, query, timeline.entries("features")) if not sheet.is_empty() else []
	if asked.is_empty():
		if not Dice.is_formula(query):
			_deny_roll(sender, "I don't know how to roll \"%s\"" % query.strip_edges())
			return {}
		asked = [{"label": "", "formula": query.replace(" ", "")}]
	var results := []
	for a: Dictionary in asked:
		var r := Dice.roll(str(a.formula), rng)
		r["label"] = a.label
		results.append(r)
	var who := str(sheet.get("name", "")) if not sheet.is_empty() else timeline.player_name(player)
	var data := {"roll": str(asked[0].label) if str(asked[0].label) != "" else str(asked[0].formula),
		"formula": results[0].formula, "result": results[0].total, "dice": results[0].dice,
		"results": results, "who": who, "hidden": hidden and player == Reveal.DM}
	var e := event_log.append("dice.rolled", ref, data, player)
	var entry := _roll_entry(e)
	_add_roll(entry)
	if not entry.hidden:
		for peer_id: int in peers:
			roll_added.rpc_id(peer_id, entry)
	return entry


## A dice.rolled event as the roll log shows it.
static func _roll_entry(e: Dictionary) -> Dictionary:
	var d: Dictionary = e.get("data", {})
	var entry := {"id": e.get("id", 0), "by": e.get("by", ""), "who": d.get("who", ""), "results": d.get("results", []),
		"hidden": bool(d.get("hidden", false)), "real": e.get("real", "")}
	if d.has("table"):
		entry["table"] = str(d.table).trim_prefix("tables/")
		entry["value"] = int(d.get("value", 0))
		entry["row"] = int(d.get("row", -1))
	return entry


## The rollable tables everyone may roll: every package's tables.json, the world's and the timeline's own
## (host) on top. Players load them from their own packages folder.
func load_tables(packages_root := "") -> void:
	tables = {}
	var root := packages_root if packages_root != "" else PackageDB.default_root()
	var files := []
	for d in DirAccess.get_directories_at(root):
		files.append(root.path_join(d).path_join("tables.json"))
	if timeline != null:
		files.append(timeline.world_dir.path_join("tables.json"))
	for file: String in files:
		if not FileAccess.file_exists(file):
			continue
		var list: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if list is Array:
			for t: Variant in list:
				if t is Dictionary and t.has("id") and not EntryStore.is_draft(t):  # drafts stay out of play (TASK-30)
					tables[str(t.id)] = t
	if timeline != null:
		for t: Dictionary in timeline.created("tables").values():
			if not EntryStore.is_draft(t):
				tables[str(t.id)] = t


## Rolls a rollable table (TASK-25): the host rolls, logs dice.rolled with table, value and
## row, and everyone sees the row highlighted; `hidden` (DM) only for the DM.
func roll_table(id: String, hidden := false) -> void:
	if is_dm():
		_handle_table_roll(1, id, hidden)
	elif is_online():
		request_table_roll.rpc_id(1, id)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_table_roll(id: String) -> void:
	if is_dm():
		_handle_table_roll(multiplayer.get_remote_sender_id(), id.left(200), false)


func _handle_table_roll(sender: int, id: String, hidden: bool) -> Dictionary:
	var player := _sender_player(sender)
	var t: Dictionary = tables.get(id, {})
	if player == "" or t.is_empty():
		_deny_roll(sender, "there is no table \"%s\"" % id)
		return {}
	var r := Dice.roll(str(t.get("dice", "d20")), rng)
	if r.is_empty():
		_deny_roll(sender, "the table's die \"%s\" isn't a formula" % t.get("dice", ""))
		return {}
	var row := RollTables.row_for(t, int(r.total))
	var data := RollTables.event_data(id, t, r, row, hidden and player == Reveal.DM, timeline.player_name(player))
	var e := event_log.append("dice.rolled", "", data, player)
	var entry := _roll_entry(e)
	_add_roll(entry)
	if not entry.hidden:
		for peer_id: int in peers:
			roll_added.rpc_id(peer_id, entry)
	return entry


func _add_roll(entry: Dictionary) -> void:
	rolls.append(entry)
	if entry.has("table") and _ui != null:  # the table on my screen shows the row
		RollTables.set_result(str(entry.table), int(entry.value), int(entry.row))
	if rolls.size() > ROLL_LOG_SIZE:
		rolls = rolls.slice(rolls.size() - ROLL_LOG_SIZE)
	rolls_changed.emit()


## Host: this session's rolls from the log (so a restart or a late joiner sees them).
func _load_rolls() -> void:
	rolls = []
	for e in event_log.events:
		if e.type == "dice.rolled" and int(e.session) == event_log.session and not event_log.is_undone(e.id):
			rolls.append(_roll_entry(e))
	rolls = rolls.slice(maxi(0, rolls.size() - ROLL_LOG_SIZE))
	rolls_changed.emit()


func _rolls_for(_player: String) -> Array:
	return rolls.filter(func(r: Dictionary) -> bool: return not r.hidden)


## DM -> players: a new roll.
@rpc("authority", "call_remote", "reliable")
func roll_added(entry: Dictionary) -> void:
	_add_roll(entry)


## DM -> player: the session's rolls (on join, new session).
@rpc("authority", "call_remote", "reliable")
func sync_rolls(list: Array) -> void:
	rolls = list
	rolls_changed.emit()


func _deny_roll(sender: int, reason: String) -> void:
	if sender == 1:
		_set_status("Can't roll: " + reason)
	else:
		roll_denied.rpc_id(sender, reason)


## DM -> player.
@rpc("authority", "call_remote", "reliable")
func roll_denied(reason: String) -> void:
	_set_status("Can't roll: " + reason)


## One roll as BBCode for the log: "Aria · Perception: [14] + 4 = 18".
static func roll_bbcode(entry: Dictionary, names := {}) -> String:
	var lines := PackedStringArray()
	for r: Dictionary in entry.get("results", []):
		var total := "[b]%d[/b]" % int(r.get("total", 0))
		if r.get("crit") == "20":
			total = "[b][color=#%s]%d (nat 20)[/color][/b]" % [UISkin.GREEN.to_html(false), int(r.total)]
		elif r.get("crit") == "1":
			total = "[b][color=#%s]%d (nat 1)[/color][/b]" % [UISkin.RED.to_html(false), int(r.total)]
		var label := str(r.get("label", ""))
		var line := "%s%s  [color=#%s]%s[/color]  = %s" % [Markdown.escape(label) + ": " if label != "" else "",
			Markdown.escape(str(r.get("formula", ""))), Markdown.MUTED.to_html(false),
			Markdown.escape(str(r.get("text", "")).get_slice(" = ", 0)), total]
		if r.has("row_text"):
			line += " → " + (Markdown.inline(str(r.row_text)) if str(r.row_text) != "" else "no row")
		lines.append(line)
	var who := str(entry.get("who", ""))
	var by := str(names.get(entry.get("by", ""), entry.get("by", "")))
	var head := Markdown.escape(who if who != "" else by)
	if by != "" and who != "" and who != by:
		head += " [color=#%s](%s)[/color]" % [Markdown.MUTED.to_html(false), Markdown.escape(by)]
	if entry.get("hidden", false):
		head += " [color=#%s][i]hidden[/i][/color]" % Markdown.MUTED.to_html(false)
	return "[font_size=12]%s[/font_size]\n%s" % [head, "\n".join(lines)]


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)
