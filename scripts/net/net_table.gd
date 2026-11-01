class_name NetTable
extends Node
## The shared table (TASK-5 spike, grown for TASK-7/8/14/20). The DM hosts a campaign folder
## (JSON, data-layout.md) over ENet; players join by address with their player name from
## campaign.json and get their PC (pcs.json `player`), or pick a free one in the lobby.
##
## The DM instance owns all state. Players only ever receive a compact, whitelisted view
## of the current map and its tokens (Campaign.map_view / token_view, no bodies, no
## DM-only keys), and they only *request* changes: the host checks them (players may move
## only their own PC), writes events to the campaign's EventLog and broadcasts the result.
## Images go once per content hash and are cached on the clients (AssetCache).
## On world maps (`kind: world`) the PCs travel as one party token (TASK-13): moving it logs
## one token.moved per member (data.group = "party"); local maps show them one by one.
## The current map and picks of free PCs are kept in `table.json` in the campaign folder,
## so players can drop out and rejoin (by name) without restarting the host.
##
## Command line: `-- --host[=port] [--campaign=path]` or `-- --join=ip:port --name=Aria`.

signal status_changed(text: String)
signal notes_changed
signal table_changed  ## the map or tokens were (re)built
signal pcs_changed  ## lobby: the PC list or my PC changed
signal entry_received(ref: String)  ## player: an entry I asked for arrived or changed

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8
const PARTY := "party"  ## id of the group token on world maps

## Host: the campaign folder; empty = data/campaigns/red-fang (the example is copied
## there on first use).
@export var campaign_dir := ""
## Host: the campaign's event log; empty = events.jsonl in the campaign folder.
@export var log_path := ""
@export var auto_ui := true
@export var calendar_path := "res://calendars/default.json"
## The login: a player's id or name from campaign.json (they are recognised by it when
## they rejoin).
@export var player_name := ""
@export var cache_dir := "user://cache/assets"

var grid: TokenGrid
var assets: AssetCache
var notes: SessionNotes
var status := "Offline"

# Host
var campaign: Campaign
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
var _state := {}  ## the last table view from the host
var _requested := {}  ## sha -> true while downloading

var _ui: TableUI


func _ready() -> void:
	grid = TokenGrid.new()
	grid.name = "Grid"
	grid.can_drag = _may_drag
	add_child(grid)
	grid.move_requested.connect(_on_move_requested)
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
		elif arg.begins_with("--campaign="):
			campaign_dir = arg.get_slice("=", 1)
	if host_port > 0:
		host(host_port)
	elif join_to != "":
		join(join_to, player_name)


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func is_dm() -> bool:
	return is_online() and multiplayer.is_server()


# --- Hosting -------------------------------------------------------------------------

## The DM: opens the campaign and its event log (so the table continues where it
## stopped) and listens on `port`.
func host(port := DEFAULT_PORT) -> Error:
	if campaign_dir == "":
		campaign_dir = Campaign.install_example(Campaign.default_root().path_join("red-fang"))
	if not Campaign.is_campaign(campaign_dir):
		_set_status("No campaign (campaign.json) in %s" % campaign_dir)
		return ERR_FILE_NOT_FOUND
	campaign = Campaign.new(campaign_dir, assets)
	if log_path == "":
		log_path = campaign.events_path()
	event_log = EventLog.open(log_path)
	_load_table_file()
	_update_owners()
	var maps := campaign.maps()
	if map_id not in maps:
		map_id = maps[0] if not maps.is_empty() else ""
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		_set_status("Can't host on port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	player_name = "DM"
	_open_notes()
	_apply_state(view_for(""))
	_set_status("Hosting %s on port %d (%d events in the log)" % [campaign.info.get("name", campaign.id()), port, event_log.events.size()])
	return OK


## What one player sees of the table: {map: map_view, tokens: [token_view + cell]}.
## `player` "" = the DM (sees the private fields of every token).
func view_for(player: String) -> Dictionary:
	var map := campaign.map_view(map_id)
	if map.is_empty():
		return {}
	var on_map: Dictionary = map.tokens
	map.erase("tokens")
	var placed := Replay.tokens_on(map_id, event_log.effective())
	var ids: Array = on_map.keys()
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
		var t := campaign.token_view(id, owner, player == "" or (owner != "" and owner == player))
		if t.is_empty():
			continue
		if placed.has(id):
			t["cell"] = placed[id]
		elif on_map.has(id):
			t["cell"] = on_map[id]
		else:  # a PC new on this map: next to the party start
			t["cell"] = start + Vector2i(newcomers, 0)
			newcomers += 1
		tokens.append(t)
	return {"map": map, "tokens": tokens}


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
		names.append(campaign.name_of(pc))
		players.append(owners[pc])
	if image == "":
		image = campaign.token_view(members[0]).get("image", "")
	return {"id": PARTY, "image": image, "name": "Party: %s" % ", ".join(names), "size": "medium",
		"kind": "party", "members": members, "players": players, "cell": cell}


## DM: shows another map to everyone.
func show_map_to_all(id: String) -> void:
	if not is_dm() or id not in campaign.maps():
		return
	map_id = id
	_save_table_file()
	_apply_state(view_for(""))
	_send_tables()
	_set_status("Showing %s" % campaign.name_of(id))


func _send_tables() -> void:
	for peer_id: int in peers:
		receive_table.rpc_id(peer_id, view_for(peers[peer_id]))


func _send_pc_lists() -> void:
	var choices := campaign.pc_choices(owners)
	for peer_id: int in peers:
		pc_list.rpc_id(peer_id, choices, _pc_of(peers[peer_id]), peers[peer_id])


func _pc_of(player: String) -> String:
	for pc: String in owners:
		if owners[pc] == player:
			return pc
	return ""


## PCs with a `player` in pcs.json belong to them; free ones to whoever picked them.
func _update_owners() -> void:
	owners = campaign.owners()
	for pc: String in claims:
		if not owners.has(pc) and pc in campaign.pcs():
			owners[pc] = claims[pc]


func _table_file() -> String:
	return campaign_dir.path_join("table.json")


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
		_set_status("%s left (their PC stays at the table)" % campaign.player_name(peers[id]))
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
	_set_status("Joining %s:%d..." % [ip, port])
	return OK


## Player -> DM, right after connecting.
@rpc("any_peer", "call_remote", "reliable")
func hello(name_given: String) -> void:
	if not is_dm():
		return
	var sender := multiplayer.get_remote_sender_id()
	var player := campaign.player_id(name_given.left(64))
	if player == "":
		join_denied.rpc_id(sender, "\"%s\" isn't a player in this campaign" % name_given.strip_edges().left(64))
		return
	if player in peers.values():
		join_denied.rpc_id(sender, "%s is already at the table" % campaign.player_name(player))
		return
	peers[sender] = player
	pc_list.rpc_id(sender, campaign.pc_choices(owners), _pc_of(player), player)
	sync_notes.rpc_id(sender, notes.session, _notes_for(player), notes.names)
	receive_table.rpc_id(sender, view_for(player))
	var who := campaign.player_name(player)
	_set_status("%s joined as %s" % [who, campaign.name_of(_pc_of(player))] if _pc_of(player) != "" \
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
	if player == "" or pc not in campaign.pcs():
		return
	var taken_by: String = owners.get(pc, "")
	if taken_by != "" and taken_by != player:
		pc_denied.rpc_id(sender, "%s already plays %s" % [campaign.player_name(taken_by), campaign.name_of(pc)])
		return
	for other: String in claims.keys():  # one picked PC per player
		if claims[other] == player:
			claims.erase(other)
	if not campaign.owners().has(pc):
		claims[pc] = player
	_update_owners()
	_save_table_file()
	_send_pc_lists()
	_apply_state(view_for(""))
	_send_tables()
	_set_status("%s plays %s" % [campaign.player_name(player), campaign.name_of(pc)])


@rpc("authority", "call_remote", "reliable")
func pc_denied(reason: String) -> void:
	_set_status(reason)
	pcs_changed.emit()


## Back to the start screen (call deferred, not from inside the network poll).
func _go_offline() -> void:
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
	for c: Dictionary in campaign.pc_choices(owners):
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
			var tex := assets.texture(t.get("image", ""))
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
	for peer_id: int in peers:
		sync_notes.rpc_id(peer_id, notes.session, _notes_for(peers[peer_id]), notes.names)
	_set_status("Session %d started" % event_log.session)


func _open_notes() -> void:
	notes = SessionNotes.open(campaign_dir, event_log.session, notes.calendar)
	notes.names = {"dm": str(campaign.info.get("dm", {}).get("name", "DM"))}
	for p: Dictionary in campaign.players():
		notes.names[str(p.id)] = str(p.get("name", p.id))
	_show_notes()


func _show_notes() -> void:
	notes_changed.emit()


# --- Entries and reveals (TASK-18) -------------------------------------------------------

## Opens an entry: the DM reads it whole, players ask the host, which cuts out what they
## may not see (Campaign.entry_view) and keeps them updated when a reveal changes.
func open_entry(ref: String) -> void:
	if is_dm():
		entries[ref] = campaign.entry_view(ref, "dm")
		entry_received.emit(ref)
	elif is_online():
		request_entry.rpc_id(1, ref)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_entry(ref: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not is_dm() or not peers.has(sender) or campaign.entry(ref).is_empty():
		return
	if not watching.has(ref):
		watching[ref] = {}
	watching[ref][sender] = true
	receive_entry.rpc_id(sender, ref, entry_for(peers[sender], ref))


## Host: an entry as `player` may see it now (the event log's clock).
func entry_for(player: String, ref: String) -> Dictionary:
	return campaign.entry_view(ref, player, event_log.effective(ref, event_log.day, event_log.time))


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


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)
