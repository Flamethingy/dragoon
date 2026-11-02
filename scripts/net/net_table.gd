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
signal roll_shown(entry: Dictionary)  ## a new roll card with dice in my feed: the 3D dice throw it (TASK-61)
signal entry_imported(entry: Dictionary)
signal condition_menu_requested(ref: String)
signal concentration_confirm(ref: String, old_name: String, new_name: String, go: Callable)  ## a second concentration spell (TASK-59)
signal attack_requested(ref: String, query: String, multi: bool, kind: String)  ## a sheet's attack or save link: pick targets (TASK-54/55)  ## a token's right click, a sheet's or roll card's link (TASK-56)  ## DM: a core entry was copied into the world

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8
const PARTY := "party"  ## id of the group token on world maps
## What a sheet shows to someone who doesn't own it: the info page, no stats.
const INFO_FIELDS := ["name", "size", "type", "subtype", "race", "alignment", "description", "image", "tags"]
## Sheet fields nobody changes from the table.
const LOCKED_FIELDS := ["id", "player", "owners", "ref", "origin"]
## Layouts in an entity (TASK-47) -> the sheet key they are sent as.
const LAYOUT_FIELDS := {"hud": "hud", "sheet_pages": "pages"}

## Host: the timeline folder; empty = the example timeline data/worlds/westmarch/timelines/red-fang
## (the example world is copied there on first use).
@export var timeline_dir := ""
## Host: the event log; empty = the timeline's events.jsonl (with its fork's inherited events).
@export var log_path := ""
@export var auto_ui := true
var show_map_info := true  ## the help line at the top left of the map (off at the app's calm table)
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
var owners := {}  ## character ref -> [player ids] (its `owners`, plus picks of free PCs); the DM controls all
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
var hud_ref := ""  ## the active character (CharacterHud, TASK-44): its sheet stays open
var _show_sheet := {}  ## refs whose sheet should show in the sheet panel when it arrives
var _state := {}  ## the last table view from the host
var _status: ServerStatus.Responder  ## host: answers the start screens' heartbeat (TASK-38)
var _requested := {}  ## sha -> true while downloading
var _rules := {}  ## the world's rules settings as the host sent them (players)
var _combat := {}  ## the initiative order as the host sent it (players, TASK-58)
var _applied := {}  ## host: "<card id>:<target>" -> hp.changed id applied from a card (Assist, TASK-54)
var _pending_saves := {}  ## host: card id -> the save card waiting for players' saves (TASK-55)
var _pending_conc := {}  ## host: ref -> DC of the concentration save it still has to make (TASK-59)
var _catalog := {}  ## kind -> id -> entry of the packages (spells, items), read once (TASK-48)

var _ui: TableUI


func _ready() -> void:
	grid = TokenGrid.new()
	grid.name = "Grid"
	grid.can_drag = _may_drag
	add_child(grid)
	grid.move_requested.connect(_on_move_requested)
	grid.step_requested.connect(_on_step_requested)
	grid.token_clicked.connect(_on_token_clicked)
	grid.token_menu.connect(func(entity: String) -> void: condition_menu_requested.emit(entity))
	grid.budget = func(id: String) -> Dictionary:  # TASK-62: the trail's budget in a combat
		for c: Dictionary in combat_view().get("order", []):
			if c.get("usage") is Dictionary and (c.entity == id or (c.get("members", []) as Array).any(func(m: Dictionary) -> bool: return m.entity == id)):
				return c.usage
		return {}
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
	var facings := Replay.facings_on(map_id, event_log.effective())
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
		var owner := owner_of(id)
		var t := timeline.token_view(id, owner, player == "" or owns(player, id))
		if owners.has(id):
			t["owners"] = owners[id]
		if t.is_empty():
			continue
		_current_values(t)
		_conditions_on(t)
		if facings.has(id):
			t["facing"] = facings[id]
		if placed.has(id):
			t["cell"] = placed[id]
		elif on_map.has(id):
			t["cell"] = on_map[id]
		else:  # a PC new on this map: next to the party start
			t["cell"] = start + Vector2i(newcomers, 0)
			newcomers += 1
		tokens.append(t)
	return {"map": map, "tokens": tokens, "rules": rules_settings(), "combat": combat_view()}


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


## The conditions on a token as they are now (TASK-56): everyone sees them on the table.
func _conditions_on(t: Dictionary) -> void:
	var e := timeline.entry(str(t.id))
	var now := Replay.entity_state({"conditions": (e.get("conditions", []) as Array).duplicate() if e.get("conditions") is Array else [],
		"exhaustion": e.get("exhaustion", 0)}, event_log.effective(str(t.id)))
	var list: Array = now.get("conditions", [])
	if not list.is_empty():
		t["conditions"] = list
		if "exhaustion" in list:
			t["exhaustion"] = int(now.get("exhaustion", 1))


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
		players.append_array(owners[pc])
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
	e = import_to_world(e)
	var ref := timeline.token_entity(e)
	if ref == "":
		_set_status("Only creatures and characters go on the map")
		return ""
	var placed := Replay.tokens_on(map_id, event_log.effective())
	if grid.tokens.has(ref) or placed.has(ref):
		event_log.move_token(ref, map_id, grid.token_cell(ref) if grid.tokens.has(ref) else placed[ref], cell)
	else:
		event_log.place_token(ref, map_id, cell)
		join_combat(ref)  # TASK-58: a newcomer mid-combat is sorted in
	_apply_state(view_for(""))
	_send_tables()
	_set_status("%s placed at %s" % [timeline.name_of(ref), cell])
	return ref


## A token's look changed in a book (TASK-41): the map shows it again (players too).
func refresh_tokens() -> void:
	if not is_dm() or timeline == null:
		return
	timeline.reload_world()
	_apply_state(view_for(""))
	_send_tables()


## A core compendium entry is copied into the world before it is used (the world's book
## only shows what was imported); one already imported is reused. World and timeline
## entries come back as they are. {} if the world can't take it.
func import_to_world(e: Dictionary) -> Dictionary:
	if str(e.get("_layer", "core")) != "core":
		return e
	var kind := str(e.get("_kind", ""))
	var eid := str(e.get("id", ""))
	var store := timeline.world_store()
	var made := {}
	for w: Dictionary in store.list(kind):
		var origin: Variant = w.get("origin")
		if origin is Dictionary and str(origin.get("package", "")) == str(e.get("_package", "")) and str(origin.get("id", "")) == eid:
			made = w
			break
	if made.is_empty():
		made = store.copy_entry(EntryStore.open(str(e.get("_dir", ""))), kind, eid)
		if made.is_empty():
			return {}
		_set_status("%s imported into the world" % made.get("name", eid))
	made = made.duplicate(true)
	made["_kind"] = kind
	made["_layer"] = "world"
	made["_package"] = store.id
	made["_package_name"] = str(store.manifest.get("name", store.id))
	made["_dir"] = store.folder
	timeline.reload_world()
	entry_imported.emit(made)
	return made


# --- Combat (TASK-35) -----------------------------------------------------------------------

## True while a combat runs in this timeline.
func in_combat() -> bool:
	return event_log != null and bool(Replay.world_state(event_log.effective()).combat.active)


## DM: starts a combat on the current map with the creatures on it (`combat.started`).
## TASK-58: initiative per creature right away (decision 3): the DM's creatures are rolled,
## the players get a prompt in their chat (the DM can roll for an absent one). `surprised`:
## creatures caught unaware (2014: they lose their first turn, 2024: disadvantage on the
## roll). `groups`: [{name, members}] that share one roll and one turn.
func start_combat(surprised: Array = [], groups: Array = []) -> Dictionary:
	if not is_dm() or in_combat():
		return {}
	var order := []
	for id: String in grid.tokens:
		if id == PARTY:
			for m: Variant in (grid.tokens[id].get_meta("info", {}) as Dictionary).get("members", []):
				order.append({"entity": str(m), "initiative": 0, "rolled": false})
		elif "/" in id:
			order.append({"entity": id, "initiative": 0, "rolled": false})
	var e := event_log.append("combat.started", "", {"map": map_id, "order": order, "surprised": surprised})
	for g: Variant in groups:
		if g is Dictionary:
			_group(g.get("members", []), str(g.get("name", "")), false)
	for c: Dictionary in combat_state().order:
		_ask_initiative(str(c.entity))
	_set_status("Combat on %s" % timeline.name_of(map_id))
	_combat_changed()
	return e


## The combat as Replay.world_state has it (host), else as the host sent it.
func combat_state() -> Dictionary:
	if is_dm() and event_log != null:
		return Replay.world_state(event_log.effective()).combat
	return _combat if not _combat.is_empty() else {"active": false, "order": [], "round": 0, "turn": 0}


# --- Action economy (TASK-62) ---------------------------------------------------------------------

const ECONOMY := ["action", "bonus", "reaction", "object"]

## What `ref` used since its turn began (display only, never blocks): {action, bonus,
## reaction, object: bool, dash: bool, moved: metres, speed: metres (doubled by a Dash)}.
func turn_usage(ref: String) -> Dictionary:
	var out := {"action": false, "bonus": false, "reaction": false, "object": false, "dash": false, "moved": 0.0, "speed": 0.0}
	if event_log == null or timeline == null:
		return out
	var events := event_log.effective()
	var start := -1
	var group := ""
	for c: Dictionary in combat_state().order:
		if c.has("members") and ref in (c.members as Array):
			group = str(c.entity)
	for i in range(events.size() - 1, -1, -1):
		var e: Dictionary = events[i]
		if e.type == "combat.turn" and str(e.data.get("entity", "")) in [ref, group] and str(e.data.get("entity", "")) != "":
			start = i
			break
		if e.type == "combat.started":
			start = i
			break
	var cells := 0
	var legendary_spent := 0
	for i in range(maxi(start, 0), events.size()):
		var e: Dictionary = events[i]
		if str(e.entity) != ref:
			continue
		if str(e.data.get("kind", "")) in ["legendary", "legendary_resistance"]:
			if str(e.data.kind) == "legendary":
				legendary_spent += int(e.data.get("cost", 1)) * (1 if e.type == "action.used" else -1)
			continue
		match str(e.type):
			"action.used":
				out[str(e.data.get("kind", "action"))] = true
				if str(e.data.get("what", "")) == "dash":
					out["dash"] = true
			"action.unused":
				out[str(e.data.get("kind", "action"))] = false
				if str(e.data.get("what", "")) == "dash" or str(e.data.get("kind", "")) == "action":
					out["dash"] = false
			"token.moved":
				var f: Array = e.data.get("from", [0, 0])
				var t: Array = e.data.get("to", [0, 0])
				cells += maxi(absi(int(t[0]) - int(f[0])), absi(int(t[1]) - int(f[1])))
	out["moved"] = cells * TokenGrid.METRES_PER_CELL
	var s := sheet_for(Reveal.DM, ref)
	var la := Rules.legendary_count(s)  # TASK-63: legendary actions back at the start of its turn
	if la > 0:
		out["legendary"] = {"left": maxi(0, la - legendary_spent), "max": la}
	var lr := Rules.legendary_resistance(_feature_list(s))
	if lr > 0:
		out["legendary_resistance"] = {"left": maxi(0, lr - _since_rest(ref, "legendary_resistance")), "max": lr}
	var spent := _spent_recharges(ref, s)
	if not spent.is_empty():
		out["spent"] = spent
	out["speed"] = Rules.speed(s, Rules.edition_of(s, rules_settings())) * (2.0 if out.dash else 1.0)
	return out


## Marks (or unmarks) one of `ref`'s action / bonus / reaction / object pips this turn; "dash"
## is an action that doubles the movement.
func mark_action(ref: String, kind: String, on := true, what := "") -> void:
	if is_dm():
		_handle_mark(1, ref, kind, on, what)
	elif is_online():
		request_mark.rpc_id(1, ref, kind, on, what)


@rpc("any_peer", "call_remote", "reliable")
func request_mark(ref: String, kind: String, on: bool, what: String) -> void:
	if is_dm():
		_handle_mark(multiplayer.get_remote_sender_id(), ref, kind.left(20), on, what.left(60))


func _handle_mark(sender: int, ref: String, kind: String, on: bool, what: String) -> Dictionary:
	var sheet := _editable_sheet(sender, ref)
	if kind not in ECONOMY + ["legendary", "legendary_resistance"] or sheet.is_empty() or (kind != "legendary_resistance" and not in_combat()):
		return {}
	var data := {"kind": kind, "what": what}
	if kind == "legendary":  # TASK-63: "Costs 2 Actions"
		for f: Variant in _feature_list(sheet):
			if str((f as Dictionary).get("name", "")).to_lower() == what.to_lower():
				data["cost"] = Rules.legendary_cost(f)
	var e := event_log.append("action.used" if on else "action.unused", ref, data, _sender_player(sender))
	_combat_changed()
	return e


## A sheet's features (all its lists) as entries.
func _feature_list(sheet: Dictionary) -> Array:
	var features: Dictionary = timeline.entries("features")
	var out := []
	for key in ["features", "traits", "actions", "bonus_actions", "reactions", "legendary_actions"]:
		for fid: Variant in sheet.get(key, []):
			var f: Variant = features.get(str(fid))
			if f is Dictionary:
				out.append(f)
	return out


## How often `ref` used a `kind` since its last long rest (rest.taken, TASK-64).
func _since_rest(ref: String, kind: String) -> int:
	var n := 0
	for e: Dictionary in event_log.effective(ref):
		if e.type == "rest.taken" and str(e.data.get("kind", "long")) == "long":
			n = 0
		elif str(e.data.get("kind", "")) == kind:
			n += 1 if e.type == "action.used" else -1
	return maxi(n, 0)


## The recharge features `ref` used and that have not come back yet (in this combat).
func _spent_recharges(ref: String, sheet: Dictionary) -> Array:
	var names := {}
	for f: Variant in _feature_list(sheet):
		if Rules.recharge_of(f) > 0:
			names[str(f.name).to_lower()] = str(f.name)
	if names.is_empty():
		return []
	var spent := {}
	for e: Dictionary in event_log.effective(ref):
		var w := str(e.data.get("what", e.data.get("feature", ""))).to_lower()
		if e.type == "combat.started" or e.type == "rest.taken":
			spent.clear()
		elif e.type == "action.used" and names.has(w):
			spent[w] = true
		elif e.type == "feature.recharged" and names.has(w):
			spent.erase(w)
	return spent.keys().map(func(k: String) -> String: return names[k])


## Turn engine (TASK-63), host: the end of `before`'s turn and the start of `now`'s (after the
## combat.turn): durations run out (a log line, undoable), "save ends" saves, recharge rolls,
## regeneration and lair action reminders. Bookkeeping only: the DM decides the rest.
func _turn_engine(before: String, before_entry: Dictionary, now_entry: Dictionary, wrapped: bool) -> void:
	var ending := _members(before_entry) if before != "" else []
	var starting := _members(now_entry)
	for who: String in _combatants():
		var s := sheet_for(Reveal.DM, who)
		var durs: Dictionary = s.get("condition_durations", {}) if s.get("condition_durations") is Dictionary else {}
		for cond: String in durs.keys():
			var dur: Dictionary = durs[cond]
			var of := str(dur.get("of", who))
			if not dur.has("rounds"):
				pass
			elif str(dur.get("ends", "")) == "turn_end":
				if of in ending and _turns_of(of, int(dur.get("since", 0))) >= int(dur.rounds):
					_expire(who, cond, "end of %s's turn" % timeline.name_of(of))
					continue
			elif of in starting and _turns_of(of, int(dur.get("since", 0))) >= int(dur.rounds):
				_expire(who, cond, "start of %s's turn" % timeline.name_of(of))
				continue
			if dur.get("save_ends") is Dictionary and who in ending and automation("durations") != "off":
				_save_ends(who, cond, dur.save_ends)
	for who: String in starting:
		var s := sheet_for(Reveal.DM, who)
		var feats := _feature_list(s)
		for name: String in _spent_recharges(who, s):  # recharge: a d6 at the start of its turn
			var at := 6
			for f: Variant in feats:
				if str(f.name) == name:
					at = Rules.recharge_of(f)
			var r := int(Dice.roll("1d6", rng).total)
			if r >= at:
				event_log.append("feature.recharged", who, {"feature": name, "roll": r}, Reveal.DM)
			_dm_line(who, "%s: recharge %d (needs %d+) - %s" % [name, r, at, "ready again" if r >= at else "not yet"])
		var regen := Rules.regeneration(feats)
		if not regen.is_empty() and int(s.get("hp", 0)) > 0:
			_dm_line(who, "Regeneration: regains %d HP now%s" % [int(regen.amount), " (not if it took %s damage since its last turn)" % regen.stopped_by if str(regen.stopped_by) != "" else ""])
	if _lair_crossed(before_entry, now_entry, wrapped):
		for who: String in _combatants():
			var s := sheet_for(Reveal.DM, who)
			if not (s.get("lair_actions", []) as Array).is_empty() or _feature_list(s).any(func(f: Dictionary) -> bool: return "lair action" in str(f.get("name", "")).to_lower()):
				_dm_line(who, "Initiative 20: lair action (losing ties)")


func _members(entry: Dictionary) -> Array:
	return (entry.members as Array).map(func(m: Variant) -> String: return str(m)) if entry.has("members") else [str(entry.get("entity", ""))]


## Everyone in the combat (group members one by one).
func _combatants() -> Array:
	var out := []
	for c: Dictionary in combat_state().order:
		out.append_array(_members(c))
	return out


## How many of `ref`'s turns (or its group's) began after event `since`.
func _turns_of(ref: String, since: int) -> int:
	var group := ""
	for c: Dictionary in combat_state().order:
		if c.has("members") and ref in (c.members as Array):
			group = str(c.entity)
	var n := 0
	for e: Dictionary in event_log.effective():
		if int(e.get("id", 0)) > since and e.type == "combat.turn" and str(e.data.get("entity", "")) in [ref, group]:
			n += 1
	return n


func _lair_crossed(before_entry: Dictionary, now_entry: Dictionary, wrapped: bool) -> bool:
	var now_i := int(now_entry.get("initiative", 0))
	if wrapped:
		return now_i < 20
	return not before_entry.is_empty() and int(before_entry.get("initiative", 0)) >= 20 and now_i < 20


## A duration ran out: per the table's setting removed (a log line with undo), a reminder, or nothing.
func _expire(ref: String, cond: String, when: String) -> void:
	var cname := str(Rules.condition(cond).get("name", cond)).to_lower()
	match automation("durations"):
		"auto":
			var e := _handle_condition(1, ref, cond, false, 0, {})
			if not e.is_empty():
				var line := _log_entry(e)
				line["text"] = "%s ended (%s)" % [cname, when]
				_add_roll(line)
		"assist":
			_dm_line(ref, "%s has run out (%s): remove it?" % [cname, when])


## A "save ends" save at the end of its turn: the DM's creatures roll at once, players are asked.
func _save_ends(ref: String, cond: String, save: Dictionary) -> void:
	var cname := str(Rules.condition(cond).get("name", cond))
	var card := {"name": "%s (save ends)" % cname, "ability": str(save.get("ability", "con")), "dc": int(save.get("dc", 10)), "half": false,
		"damage": [], "conditions": [], "duration": {}, "cover": 0, "targets": [], "ends": cond}
	var waiting := not (owners.get(ref, []) as Array).is_empty()
	card.targets.append({"ref": ref, "name": timeline.name_of(ref), "waiting": true} if waiting else _save_row(ref, card))
	var data := {"roll": "%s: end %s? (DC %d %s save)" % [timeline.name_of(ref), cname.to_lower(), int(card.dc), str(card.ability).to_upper()],
		"results": [], "who": timeline.name_of(ref), "hidden": false, "save": card}
	var ev := event_log.append("dice.rolled", ref, data, Reveal.DM)
	_post_roll(_roll_entry(ev))
	if waiting:
		_pending_saves[int(ev.id)] = card.duplicate(true)
		_ask_save(int(ev.id), ref, _pending_saves[int(ev.id)])


## DM: the in-world clock moves on `minutes` (time.advanced); out of combat, durations in
## minutes (or rounds: 10 a minute) run out by it.
func advance_clock(minutes: int, reason := "") -> Dictionary:
	if not is_dm() or minutes <= 0:
		return {}
	var t := maxi(event_log.time, 0) + minutes
	var e := event_log.advance_time(event_log.day + t / 1440, t % 1440, reason)
	if not in_combat():
		var now := event_log.day * 1440 + event_log.time
		for ref: String in _clock_refs():
			var s := sheet_for(Reveal.DM, ref)
			var durs: Dictionary = s.get("condition_durations", {}) if s.get("condition_durations") is Dictionary else {}
			for cond: String in durs.keys():
				var dur: Dictionary = durs[cond]
				var length := int(dur.get("minutes", ceili(float(dur.get("rounds", 0)) / 10.0)))
				if length > 0 and int(dur.get("time", -1)) >= 0 and now - (int(dur.day) * 1440 + int(dur.time)) >= length:
					_expire(ref, cond, "after %d min" % length)
	table_changed.emit()
	return e


func _clock_refs() -> Array:
	var out := []
	for id: String in grid.tokens:
		if "/" in id:
			out.append(id)
	for id: String in timeline.entries("characters"):
		if not ("characters/" + id) in out:
			out.append("characters/" + id)
	return out


## Which pip an attack or feature takes: its place on the sheet (bonus_actions, reactions).
func _action_kind(sheet: Dictionary, name: String) -> String:
	var features: Dictionary = timeline.entries("features")
	for pair: Array in [["bonus_actions", "bonus"], ["reactions", "reaction"]]:
		for fid: Variant in sheet.get(pair[0], []):
			if str((features.get(str(fid), {}) as Dictionary).get("name", "")).to_lower() == name.to_lower():
				return pair[1]
	return "action"


## The initiative order for the tracker: [{entity, name, initiative, rolled, surprised,
## current, members: [{entity, name}]}] plus round and turn.
func combat_view() -> Dictionary:
	var c := combat_state()
	if not is_dm():
		return c
	var out := []
	var surprised: Array = c.get("surprised", [])
	for i in (c.order as Array).size():
		var o: Dictionary = c.order[i]
		var row := {"entity": o.entity, "initiative": o.initiative, "rolled": o.get("rolled", true), "current": i == int(c.turn),
			"name": str(o.get("name", "")) if o.has("members") else timeline.name_of(str(o.entity)),
			"surprised": str(o.entity) in surprised or (o.has("members") and (o.members as Array).any(func(m: Variant) -> bool: return m in surprised))}
		row["usage"] = turn_usage(str(o.members[0]) if o.has("members") and not (o.members as Array).is_empty() else str(o.entity))  # TASK-62
		if o.has("members"):
			row["members"] = (o.members as Array).map(func(m: Variant) -> Dictionary: return {"entity": str(m), "name": timeline.name_of(str(m))})
			if str(row.name) == "":
				row["name"] = "%s ×%d" % [timeline.name_of(str(o.members[0])), (o.members as Array).size()] if not (o.members as Array).is_empty() else "Group"
		out.append(row)
	return {"active": c.active, "round": c.round, "turn": c.turn, "order": out}


## The initiative prompt's link: a player rolls for their creature, the DM for an absent one.
func answer_initiative(ref: String) -> void:
	if is_dm():
		var entry := _waiting_entry(ref)
		if entry != "":
			_handle_roll(1, "initiative", ref, false)
	else:
		roll("initiative", ref)


## DM: rolls initiative for a creature or group (Rules: its bonus; surprised in 2024: with
## disadvantage). The roll is DM-only for the DM's creatures, public for the players'.
func roll_initiative(entity: String) -> Dictionary:
	if not is_dm() or not in_combat():
		return {}
	var ref := _initiative_ref(entity)
	if ref == "":
		return {}
	return _handle_roll(1, "initiative", ref, owner_of(ref) == "")


## The creature whose sheet rolls for `entity` (a group: its first member).
func _initiative_ref(entity: String) -> String:
	for c: Dictionary in combat_state().order:
		if c.entity == entity and c.has("members"):
			return str(c.members[0]) if not (c.members as Array).is_empty() else ""
	return entity


## The order entry a roll of `ref` belongs to, if it still waits for its initiative.
func _waiting_entry(ref: String) -> String:
	for c: Dictionary in combat_state().order:
		if bool(c.get("rolled", true)):
			continue
		if c.entity == ref or (c.has("members") and ref in (c.members as Array)):
			return str(c.entity)
	return ""


## A creature that joins the order: the DM's are rolled, the players' get a prompt.
func _ask_initiative(entity: String) -> void:
	var ref := _initiative_ref(entity)
	var players: Array = owners.get(ref, [])
	if players.is_empty():
		roll_initiative(entity)
		return
	var prompt := {"id": 0, "by": Reveal.DM, "who": timeline.name_of(ref), "ref": ref, "results": [], "hidden": false,
		"action": "prompt", "text": "Roll initiative"}
	for peer_id: int in peers:
		if str(peers[peer_id]) in players:
			roll_added.rpc_id(peer_id, prompt)
	var mine := prompt.duplicate()
	mine["action"] = "prompt_dm"
	mine["hidden"] = true
	_add_roll(mine)


## DM: creatures share one roll and one turn slot (e.g. all goblins), listed under it.
func group_creatures(members: Array, name := "") -> String:
	if not is_dm() or not in_combat() or members.size() < 2:
		return ""
	var id := _group(members, name, true)
	_combat_changed()
	return id


func _group(members: Array, name: String, roll: bool) -> String:
	var id := "group:%d" % (event_log.events.size() + 1)
	event_log.append("combat.grouped", "", {"group": id, "name": name, "members": members.map(func(m: Variant) -> String: return str(m))})
	if roll:
		_ask_initiative(id)
	return id


## DM: the group's creatures take their own turns again (each rolls).
func ungroup(group: String) -> void:
	if not is_dm() or not in_combat():
		return
	var members: Array = []
	for c: Dictionary in combat_state().order:
		if c.entity == group:
			members = c.get("members", [])
	if members.is_empty():
		return
	event_log.append("combat.ungrouped", "", {"group": group})
	for m: Variant in members:
		_ask_initiative(str(m))
	_combat_changed()


## DM: marks a creature surprised or not (round 1 only matters).
func set_surprised(ref: String, on: bool) -> void:
	if not is_dm() or not in_combat():
		return
	event_log.append("combat.surprise", ref, {"surprised": on})
	_combat_changed()


## DM: the order as dragged in the tracker (ties, or the DM's call): `combat.order_set`.
func set_order(entities: Array) -> void:
	if not is_dm() or not in_combat():
		return
	event_log.append("combat.order_set", "", {"order": entities.map(func(x: Variant) -> String: return str(x))})
	_combat_changed()


## DM: a creature put on the map mid-combat joins the order (rolled and sorted in).
func join_combat(ref: String) -> void:
	if not is_dm() or not in_combat() or ref == "":
		return
	var c := combat_state()
	if (c.order as Array).any(func(o: Dictionary) -> bool: return o.entity == ref or ref in (o.get("members", []) as Array)):
		return
	event_log.append("combat.joined", ref, {})  # waits for its roll, then is sorted in
	_ask_initiative(ref)
	_combat_changed()


func _combat_changed() -> void:
	_apply_state(view_for(""))
	_send_tables()
	table_changed.emit()


## DM: the next turn (and round, after the last in the order): `combat.turn`. 2014: a
## surprised creature's first turn passes (it can't act in round 1).
func next_turn() -> Dictionary:
	if not is_dm() or not in_combat():
		return {}
	var c: Dictionary = combat_state()
	var order: Array = c.order
	var turn := int(c.turn)
	var round_now := int(c.round)
	var skipped := PackedStringArray()
	for guard in order.size() + 1:
		turn += 1
		if turn >= maxi(order.size(), 1):
			turn = 0
			round_now += 1
		if order.is_empty():
			break
		if _defeated(order[turn]):  # TASK-57: out of the fight
			skipped.append(timeline.name_of(str(order[turn].entity)))
			continue
		if round_now != 1 or str(rules_settings().edition) == "2024" or not _surprised(c, order[turn]):
			break
		skipped.append(timeline.name_of(str(order[turn].entity)))
	var before := str(c.order[int(c.turn)].entity) if int(c.turn) >= 0 and int(c.turn) < order.size() else ""
	var e := event_log.append("combat.turn", "", {"round": round_now, "turn": turn, "entity": str(order[turn].entity) if not order.is_empty() else ""})
	if not order.is_empty():
		_turn_engine(before, order[int(c.turn)] if before != "" else {}, order[turn], round_now != int(c.round) or turn < int(c.turn))
	_set_status("Round %d, turn %d%s" % [round_now, turn + 1, " (no turn: %s)" % ", ".join(skipped) if not skipped.is_empty() else ""])
	if not order.is_empty():  # a character at 0 HP: its death save prompt
		var who := str(order[turn].entity)
		var s := sheet_for(Reveal.DM, who) if who.begins_with("characters/") else {}
		if not s.is_empty() and int(s.get("hp", 1)) == 0 and "dead" not in (s.get("conditions", []) as Array) and not _stable(s):
			var prompt := {"id": 0, "by": Reveal.DM, "who": timeline.name_of(who), "ref": who, "results": [], "hidden": false, "action": "death_prompt", "text": "Death save"}
			for peer_id: int in peers:
				if str(peers[peer_id]) in (owners.get(who, []) as Array):
					roll_added.rpc_id(peer_id, prompt)
			var mine := prompt.duplicate()
			mine["hidden"] = true
			_add_roll(mine)
	_combat_changed()
	return e


static func _surprised(c: Dictionary, o: Dictionary) -> bool:
	var s: Array = c.get("surprised", [])
	return str(o.entity) in s or (o.has("members") and not (o.members as Array).is_empty() and (o.members as Array).all(func(m: Variant) -> bool: return m in s))


## DM: ends the combat (`combat.ended`); it is saved as an encounter of the timeline.
## Returns the encounter ({} if none was made).
func end_combat(reason := "") -> Dictionary:
	if not is_dm() or not in_combat():
		return {}
	event_log.append("combat.ended", "", {"reason": reason} if reason != "" else {})
	_combat_changed()
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
		if player in owners[pc]:
			return pc
	return ""


## PCs with a `player` in pcs.json belong to them; free ones to whoever picked them.
func _update_owners() -> void:
	owners = timeline.owners()
	for pc: String in claims:
		if not owners.has(pc) and pc in timeline.pcs():
			owners[pc] = [claims[pc]]


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
	var taken_by := owner_of(pc)
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
	if view.has("rules"):
		_rules = Rules.settings_of(view.rules)
	if view.has("combat") and not is_dm():
		_combat = view.combat
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
		var info: Dictionary = token.get_meta("info", {}) if token else {}
		if token and info.get("image", "") == t.get("image", "") and info.get("token_style") == t.get("token_style"):
			token.set_meta("info", t)
			grid.set_token_cell(id, cell, token.get_meta("cell") != cell)
			grid.set_token_conditions(id, t.get("conditions", []), int(t.get("exhaustion", 0)))
		else:
			var pic := assets.texture(t.get("image", "")) if str(t.get("image", "")) != "" else null
			if pic != null or str(t.get("image", "")) == "":
				grid.add_token_view(t, TokenArt.compose(pic, t.get("token_style"), str(t.get("kind", ""))), cell)
				grid.set_token_conditions(id, t.get("conditions", []), int(t.get("exhaustion", 0)))
	for id: String in grid.tokens.keys():
		if not keep.has(id):
			grid.tokens[id].queue_free()
			grid.tokens.erase(id)
	var count := grid.tokens.size()
	grid.info_visible = show_map_info
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
	return my_player in (info.get("owners", [info.get("owner", "")]) as Array)


## True if `player` is one of the owners of `ref` (TASK-43). The DM controls everything.
func owns(player: String, ref: String) -> bool:
	return player != "" and player in (owners.get(ref, []) as Array)


## The first owner of a character ("" = none).
func owner_of(ref: String) -> String:
	var o: Array = owners.get(ref, [])
	return str(o[0]) if not o.is_empty() else ""


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
		if player == "" or not owns(player, entity):
			_deny(sender, entity, "that's not your token")
			return
	if not grid.can_place(entity, cell):
		_deny(sender, entity, "that square is blocked")
		return
	var from := grid.token_cell(entity)
	var by := "dm" if sender == 1 else str(peers[sender])
	var facing := TokenGrid.facing_of(cell - from)  # moving turns the token that way (TASK-42)
	var e := event_log.move_token(entity, grid.map_id, from, cell, by, "", facing)
	grid.set_token_cell(entity, cell)
	if facing != "":
		grid.set_token_facing(entity, facing)
	for peer_id: int in peers:
		token_moved.rpc_id(peer_id, entity, cell, int(e.get("id", 0)))
		if facing != "":
			token_turned.rpc_id(peer_id, entity, facing)
	_set_status("%s moved to %s (event %d)" % [_name_of(entity), cell, int(e.get("id", 0))])
	if in_combat():  # TASK-62: the movement budget on the tracker and the HUD
		_combat_changed()


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


## WASD / arrows (TASK-42): a step or a turn; the DM decides, players ask the DM.
func _on_step_requested(entity: String, dir: Vector2i, turn_only: bool) -> void:
	if not is_online():
		return
	if is_dm():
		_handle_step(1, entity, dir, turn_only)
	else:
		request_step.rpc_id(1, entity, dir, turn_only)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_step(entity: String, dir: Vector2i, turn_only: bool) -> void:
	if is_dm():
		_handle_step(multiplayer.get_remote_sender_id(), entity, dir, turn_only)


func _handle_step(sender: int, entity: String, dir: Vector2i, turn_only: bool) -> void:
	var facing := TokenGrid.facing_of(dir)
	if facing == "" or not grid.tokens.has(entity):
		return
	if not turn_only:
		_handle_move(sender, entity, grid.token_cell(entity) + TokenGrid.FACINGS[facing])
		if grid.token_facing(entity) == facing or entity == PARTY:
			return
	if sender != 1 and entity != PARTY and not owns(str(peers.get(sender, "")), entity):
		_deny(sender, entity, "that's not your token")
		return
	if entity != PARTY:  # the party token's members turn with it on the map only
		var by := "dm" if sender == 1 else str(peers[sender])
		event_log.turn_token(entity, grid.map_id, facing, by)
	grid.set_token_facing(entity, facing)
	for peer_id: int in peers:
		token_turned.rpc_id(peer_id, entity, facing)


## DM -> players: a token turned.
@rpc("authority", "call_remote", "reliable")
func token_turned(entity: String, facing: String) -> void:
	grid.set_token_facing(entity, facing)


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
## A click on a token only selects it (Nico, 2026-11-01: no sheet popping up; the
## character / creature sheet comes back in its own form later). open_sheet still works.
func _on_token_clicked(_entity: String) -> void:
	pass


## The DM sees every sheet, a player the sheet of their own PC; everyone else only gets
## the info page (INFO_FIELDS, with reveals applied).
func may_see_sheet(player: String, ref: String) -> bool:
	return player == Reveal.DM or owns(player, ref)


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
		sheet["_multiattack"] = not Dice.multiattack(sheet, features).is_empty()  # TASK-54
		sheet["_save_actions"] = _save_features(sheet)  # TASK-55
		var refs := {}  # spells and items: name (and level) for the HUD's quick buttons (TASK-48)
		for v: Variant in sheet.get("spells", []):
			var e := catalog_entry(str(v))
			refs[str(v)] = {"name": str(e.get("name", HudWidgets._name_of(v))), "level": int(e.get("level", 0))}
		for it: Variant in sheet.get("inventory", []):
			var r := str(it.get("item", "")) if it is Dictionary else str(it)
			refs[r] = {"name": str(catalog_entry(r).get("name", HudWidgets._name_of(r)))}
		sheet["_refs"] = refs
		# the HUD and the sheet pages (TASK-47): its own, a creature copy its template's
		var tpl := layout_template(ref)
		var source: Dictionary = timeline.world_entries(tpl.get_slice("/", 0)).get(tpl.get_slice("/", 1), {}) if tpl != "" else sheet
		for key: String in LAYOUT_FIELDS:
			sheet["_" + LAYOUT_FIELDS[key]] = source.get(key, []) if source.get(key) is Array else []
	else:
		for key: String in INFO_FIELDS:
			if view.has(key):
				sheet[key] = view[key]
	sheet["ref"] = ref
	sheet["_kind"] = ref.get_slice("/", 0)
	sheet["_full"] = full
	sheet["_editable"] = full
	sheet["_owner"] = ", ".join((owners.get(ref, []) as Array).map(func(o: Variant) -> String: return timeline.player_name(str(o))))
	return sheet


## Opens a sheet: the DM builds it, players ask the host (and get updates while it is open).
## show = false: only fetch it (the HUD), don't open the sheet panel.
func open_sheet(ref: String, show := true) -> void:
	if show:
		_show_sheet[ref] = true
	if is_dm():
		var sheet := sheet_for(Reveal.DM, ref)
		if not sheet.is_empty():
			sheets[ref] = sheet
			sheet_received.emit(ref)
	elif is_online():
		request_sheet.rpc_id(1, ref)


## True once if the sheet panel asked for this sheet (open_sheet with show).
func sheet_wanted(ref: String) -> bool:
	return _show_sheet.erase(ref)


func close_sheet(ref: String) -> void:
	_show_sheet.erase(ref)
	if ref == hud_ref and ref != "":
		return  # the HUD still shows it
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


## Spends (`amount` > 0) or gets back (< 0) a resource: resource.used / resource.restored
## (spell slots: "spell_slots.<level>", features by id, "ki", ...) (TASK-51).
func use_resource(ref: String, resource: String, amount: int) -> void:
	if is_dm():
		_handle_resource(1, ref, resource, amount)
	elif is_online():
		request_resource.rpc_id(1, ref, resource, amount)


## Gives (`qty` > 0) or takes (< 0) items: item.gained / item.lost (TASK-51).
func change_item(ref: String, item: String, qty: int) -> void:
	if is_dm():
		_handle_item(1, ref, item, qty)
	elif is_online():
		request_item.rpc_id(1, ref, item, qty)


## Puts a condition on (`on`) or takes it off (TASK-56): condition.applied / condition.removed.
## Exhaustion has a level (1-6; 0 takes it off). A creature immune to it still gets it, but
## the DM is warned (warn, never block). `duration` (optional): {rounds | minutes, ends}.
func set_condition(ref: String, condition: String, on := true, level := 0, duration := {}) -> void:
	if is_dm():
		_handle_condition(1, ref, condition, on, level, duration)
	elif is_online():
		request_condition.rpc_id(1, ref, condition, on, level, duration)


@rpc("any_peer", "call_remote", "reliable")
func request_condition(ref: String, condition: String, on: bool, level: int, duration: Dictionary) -> void:
	if is_dm():
		_handle_condition(multiplayer.get_remote_sender_id(), ref, condition.left(60), on, level, duration)


## Who may change `ref`'s conditions: the DM, and the players whose sheet it is.
func may_change(ref: String) -> bool:
	return is_dm() or ref == my_pc or (grid != null and grid.tokens.has(ref) and ref != PARTY and _may_drag(ref))


## The conditions on `ref` as I know them: {conditions: [...], exhaustion: n}.
func conditions_of(ref: String) -> Dictionary:
	var src: Dictionary = {}
	if grid != null and grid.tokens.has(ref):
		src = grid.tokens[ref].get_meta("info", {})
	if src.is_empty() and sheets.has(ref):
		src = sheets[ref]
	if is_dm() and timeline != null and src.is_empty():
		src = sheet_for(Reveal.DM, ref)
	return {"conditions": (src.get("conditions", []) as Array).duplicate() if src.get("conditions") is Array else [],
		"exhaustion": int(src.get("exhaustion", 0))}


func _handle_condition(sender: int, ref: String, condition: String, on: bool, level: int, duration: Dictionary, extra := {}) -> Dictionary:
	var sheet := _editable_sheet(sender, ref)
	var id := condition.to_lower().strip_edges()
	if sheet.is_empty() or Rules.conditions().get(id) == null:
		return {}
	var has: bool = id in (sheet.get("conditions", []) as Array)
	if id == "exhaustion":
		on = level > 0
		if on and has and int(sheet.get("exhaustion", 1)) == clampi(level, 1, 6):
			return {}
	elif on == has:
		return {}
	if not on and not has:
		return {}
	var data := {"condition": id}
	if on and id == "exhaustion":
		data["level"] = clampi(level, 1, 6)
	if on and not duration.is_empty():
		data["duration"] = duration.duplicate()
		if not data.duration.has("of"):  # TASK-63: whose turns it counts (default: its own)
			data.duration["of"] = ref
	if on:
		data.merge(extra)
	var immune := on and Rules.immune_to(sheet, id)
	if immune:
		data["immune"] = true
	var e := event_log.append("condition.applied" if on else "condition.removed", ref, data, _sender_player(sender))
	_after_change(ref, e)
	if on and id != "concentrating" and sheet.get("concentration") is Dictionary and _breaks_concentration(id):
		end_concentration(ref, "%s" % str(Rules.condition(id).name).to_lower())  # TASK-59
	if immune:  # warn, never block: the DM sees it
		var warn := _log_entry(e)
		warn["text"] = "is immune to %s (applied anyway, undo if that was a mistake)" % str(Rules.condition(id).name).to_lower()
		_add_roll(warn)
		_set_status("%s is immune to %s" % [timeline.name_of(ref), Rules.condition(id).name])
	return e


## A class reaches `level` (level.gained): the class in `classes` changes (TASK-51).
func gain_level(ref: String, cls: String, level: int) -> void:
	if is_dm():
		_handle_level(1, ref, cls, level)
	elif is_online():
		request_level.rpc_id(1, ref, cls, level)


@rpc("any_peer", "call_remote", "reliable")
func request_resource(ref: String, resource: String, amount: int) -> void:
	if is_dm():
		_handle_resource(multiplayer.get_remote_sender_id(), ref, resource.left(100), amount)


@rpc("any_peer", "call_remote", "reliable")
func request_item(ref: String, item: String, qty: int) -> void:
	if is_dm():
		_handle_item(multiplayer.get_remote_sender_id(), ref, item.left(200), qty)


@rpc("any_peer", "call_remote", "reliable")
func request_level(ref: String, cls: String, level: int) -> void:
	if is_dm():
		_handle_level(multiplayer.get_remote_sender_id(), ref, cls.left(100), level)


## The sheet `ref` if `sender` may change it ({} and a denial if not).
func _editable_sheet(sender: int, ref: String) -> Dictionary:
	if not may_see_sheet(_sender_player(sender), ref):
		_deny_sheet(sender, "that's not your sheet")
		return {}
	return sheet_for(Reveal.DM, ref)


func _handle_resource(sender: int, ref: String, resource: String, amount: int) -> Dictionary:
	var sheet := _editable_sheet(sender, ref)
	if sheet.is_empty() or resource == "" or amount == 0:
		return {}
	var used := int((sheet.get("resources_used", {}) as Dictionary).get(resource, 0)) if sheet.get("resources_used") is Dictionary else 0
	var e: Dictionary
	if amount > 0:
		e = event_log.append("resource.used", ref, {"resource": resource, "amount": amount}, _sender_player(sender))
	else:
		var back := mini(-amount, used)
		if back <= 0:
			return {}
		e = event_log.append("resource.restored", ref, {"resource": resource, "amount": back}, _sender_player(sender))
	_after_change(ref, e)
	return e


func _handle_item(sender: int, ref: String, item: String, qty: int) -> Dictionary:
	var sheet := _editable_sheet(sender, ref)
	if sheet.is_empty() or item == "" or qty == 0:
		return {}
	var e := event_log.append("item.gained" if qty > 0 else "item.lost", ref, {"item": item, "qty": absi(qty)}, _sender_player(sender))
	_after_change(ref, e)
	return e


func _handle_level(sender: int, ref: String, cls: String, level: int) -> Dictionary:
	var sheet := _editable_sheet(sender, ref)
	if sheet.is_empty() or cls == "" or level < 1 or level > 20:
		return {}
	var e := event_log.append("level.gained", ref, {"class": cls, "level": level}, _sender_player(sender))
	_after_change(ref, e)
	return e


## After a sheet event: everyone who has it open gets it again; a player's change shows
## as a log line for the DM (TASK-51: trust, but visible).
func _after_change(ref: String, e: Dictionary) -> void:
	_sheet_changed(ref)
	_set_status("%s: %s (event %d)" % [timeline.name_of(ref), log_text(e), int(e.get("id", 0))])
	if str(e.get("by", Reveal.DM)) != Reveal.DM:
		_add_roll(_log_entry(e))


## Event types a player's own change can be: shown to the DM as log lines.
const LOGGED := ["sheet.changed", "hp.changed", "item.gained", "item.lost", "resource.used", "resource.restored", "level.gained",
	"condition.applied", "condition.removed"]


## A player's change as a line in the DM's feed (hidden from the players).
func _log_entry(e: Dictionary) -> Dictionary:
	return {"id": e.get("id", 0), "by": e.get("by", ""), "who": timeline.name_of(str(e.get("entity", ""))) if timeline != null else str(e.get("entity", "")),
		"text": log_text(e), "action": "log", "results": [], "hidden": true, "real": e.get("real", "")}


## What a sheet event did, in words ("HP -5 → 19", "gained 2× Torch").
static func log_text(e: Dictionary) -> String:
	var d: Dictionary = e.get("data", {})
	match str(e.get("type", "")):
		"sheet.changed":
			return "changed %s: %s → %s" % [d.get("path", "?"), _short(d.get("from")), _short(d.get("to"))]
		"hp.changed":
			return "HP %+d → %d" % [int(d.get("delta", 0)), int(d.get("hp", 0))]
		"item.gained", "item.lost":
			var qty := int(d.get("qty", 1))
			return "%s %s%s" % ["gained" if e.type == "item.gained" else "lost", "%d× " % qty if qty != 1 else "", HudWidgets._name_of(d.get("item", "?"))]
		"resource.used", "resource.restored":
			return "%s %d %s" % ["used" if e.type == "resource.used" else "got back", int(d.get("amount", 1)), _resource_name(str(d.get("resource", "")))]
		"level.gained":
			return "reached level %d %s" % [int(d.get("level", 1)), HudWidgets._name_of(d.get("class", ""))]
		"condition.applied":
			if str(d.get("condition", "")) == "exhaustion":
				return "exhaustion level %d" % int(d.get("level", 1))
			return "is %s" % str(d.get("condition", "")).replace("_", " ")
		"condition.removed":
			return "is no longer %s" % str(d.get("condition", "")).replace("_", " ")
	return str(e.get("type", ""))


## "spell_slots.2" -> "level 2 spell slot(s)", "second_wind" -> "Second Wind".
static func _resource_name(r: String) -> String:
	if r.begins_with("spell_slots."):
		return "level %s spell slot" % r.get_slice(".", 1)
	return r.get_file().replace("_", " ").replace("-", " ").capitalize()


static func _short(v: Variant) -> String:
	var t := JSON.stringify(v) if v is Array or v is Dictionary else str(v)
	return t if t.length() <= 40 else t.left(37) + "..."


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


func _handle_hp(sender: int, ref: String, delta: int, reason: String, crit := false) -> Dictionary:
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
	_after_hp(ref, sheet, hp, after, delta, crit)
	_after_change(ref, e)
	return e


# --- 0 HP, death saves, defeated creatures (TASK-57) ---------------------------------------------

## A character drops to 0: Unconscious, death saves; damage at 0 is a failed save (two on a
## crit), massive damage only warns; healing gets them up (no longer Unconscious, the saves
## start over). A creature at 0 is defeated: marked dead (the DM can make it Unconscious
## instead), skipped in the turn order.
func _after_hp(ref: String, sheet: Dictionary, before: int, after: int, delta: int, crit: bool) -> void:
	if delta < 0 and after > 0 and sheet.get("concentration") is Dictionary and automation("concentration") != "off":
		_concentration_check(ref, -delta)  # TASK-59
	elif delta < 0 and after == 0 and sheet.get("concentration") is Dictionary:
		end_concentration(ref, "0 HP")
	if automation("death_saves") == "off":
		return
	var conds: Array = sheet.get("conditions", [])
	var pc := ref.begins_with("characters/")
	if delta < 0 and after == 0:
		var hp_max := int(sheet.get("_hp_max", 0))
		var left := -delta - before  # what is left after reaching 0
		if pc and hp_max > 0 and left >= hp_max and "dead" not in conds:
			_dm_line(ref, "massive damage: %d left after 0 HP is at least the HP maximum (%d), instant death by the rules · your call" % [left, hp_max])
		if before > 0:
			if pc:
				_handle_condition(1, ref, "unconscious", true, 0, {})
			elif "dead" not in conds and "unconscious" not in conds:
				_handle_condition(1, ref, "dead", true, 0, {})
		elif pc and "dead" not in conds and not _stable(sheet):
			_death_save_event(ref, false, 2 if crit else 1, {"damage": true})
	elif delta > 0 and before == 0 and after > 0:
		if "unconscious" in conds:
			_handle_condition(1, ref, "unconscious", false, 0, {})
		if "dead" in conds:
			_dm_line(ref, "healed while marked dead · take Dead off if that's right")


static func _stable(sheet: Dictionary) -> bool:
	return sheet.get("death_saves") is Dictionary and int(sheet.death_saves.get("successes", 0)) >= 3


## A hidden line in the DM's feed about `ref`.
func _dm_line(ref: String, text: String) -> void:
	_add_roll({"id": 0, "by": Reveal.DM, "who": timeline.name_of(ref), "ref": ref, "results": [], "hidden": true, "action": "log", "text": text})


func _death_save_event(ref: String, success: bool, count: int, extra := {}, by := Reveal.DM) -> Dictionary:
	var data := {"success": success, "count": count}
	data.merge(extra)
	var e := event_log.append("death_save.rolled", ref, data, by)
	var s := sheet_for(Reveal.DM, ref)
	if s.get("death_saves") is Dictionary and int(s.death_saves.get("failures", 0)) >= 3 and "dead" not in (s.get("conditions", []) as Array):
		_handle_condition(1, ref, "dead", true, 0, {})
		_dm_line(ref, "three failed death saves: dead (undo if that's not how it went)")
	return e


## Rolls a death save for a character at 0 HP (its player or the DM): 10+ a success, a
## natural 1 two failures, a natural 20 back up with 1 HP.
func roll_death_save(ref: String) -> void:
	if is_dm():
		_handle_death_save(1, ref)
	elif is_online():
		request_death_save.rpc_id(1, ref)


@rpc("any_peer", "call_remote", "reliable")
func request_death_save(ref: String) -> void:
	if is_dm():
		_handle_death_save(multiplayer.get_remote_sender_id(), ref)


func _handle_death_save(sender: int, ref: String) -> Dictionary:
	var player := _sender_player(sender)
	if player == "" or not may_see_sheet(player, ref):
		_deny_roll(sender, "that's not your sheet")
		return {}
	var s := sheet_for(Reveal.DM, ref)
	if s.is_empty() or int(s.get("hp", 0)) > 0 or "dead" in (s.get("conditions", []) as Array) or _stable(s):
		_deny_roll(sender, "no death save needed")
		return {}
	var r := Dice.roll("1d20", rng)
	r["label"] = "Death save"
	var natural := int(r.total)
	var outcome := ""
	var data := {"roll": "Death save", "formula": "1d20", "result": natural, "dice": r.dice, "results": [r], "who": str(s.get("name", "")), "hidden": false}
	var ev := event_log.append("dice.rolled", ref, data, player)
	if natural == 20:
		_death_save_event(ref, true, 1, {"hp": 1, "natural": 20}, player)
		_handle_condition(1, ref, "unconscious", false, 0, {})
		outcome = "natural 20: back up with 1 HP!"
	elif natural == 1:
		_death_save_event(ref, false, 2, {"natural": 1}, player)
		outcome = "natural 1: two failures"
	else:
		_death_save_event(ref, natural >= 10, 1, {}, player)
		outcome = "success" if natural >= 10 else "failure"
	var after := sheet_for(Reveal.DM, ref)
	var ds: Dictionary = after.get("death_saves", {}) if after.get("death_saves") is Dictionary else {}
	if _stable(after):
		outcome += " · stable"
	elif "dead" in (after.get("conditions", []) as Array):
		outcome += " · dead"
	var entry := _roll_entry(ev)
	entry["text"] = "%s (%d successes, %d failures)" % [outcome, int(ds.get("successes", 0)), int(ds.get("failures", 0))] if natural != 20 else outcome
	entry["action"] = "death_save"
	_sheet_changed(ref)
	return _post_roll(entry)


## True if the order entry is out of the fight: dead, or a creature (not a character) at 0 HP.
## A group: all its members.
func _defeated(o: Dictionary) -> bool:
	var refs: Array = o.get("members", [o.entity])
	if refs.is_empty():
		return false
	for r: Variant in refs:
		var s := sheet_for(Reveal.DM, str(r))
		if s.is_empty():
			return false
		var conds: Array = s.get("conditions", [])
		if not ("dead" in conds or (not str(r).begins_with("characters/") and int(s.get("hp", 1)) <= 0)):
			return false
	return true


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
	_after_change(ref, e)
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
		open_sheet(ref, false)
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
	var waiting := ""  # TASK-58: an initiative roll in a combat that waits for it
	if in_combat() and ref != "" and query.to_lower().strip_edges().begins_with("init"):
		waiting = _waiting_entry(ref)
		if waiting != "" and str(rules_settings().edition) == "2024" and ref in (combat_state().get("surprised", []) as Array) \
				and not (" advantage" in query or " disadvantage" in query or " normal" in query):
			query += " with disadvantage"  # 2024: surprised
	if player == "":
		return {}
	if ref == "" and player != Reveal.DM:
		ref = _pc_of(player)
	if ref != "" and not may_see_sheet(player, ref):
		_deny_roll(sender, "that's not your sheet")
		return {}
	var sheet := sheet_for(Reveal.DM, ref) if ref != "" else {}
	var asked := Dice.resolve(sheet, query, timeline.entries("features"), rules_settings()) if not sheet.is_empty() else []
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
	if waiting != "" and str(asked[0].label).begins_with("Initiative"):
		event_log.append("initiative.rolled", waiting, {"total": int(results[0].total), "dex": Rules.score(sheet, "dex"),
			"formula": str(results[0].formula)}, player)
		_combat_changed()
	var entry := _roll_entry(e)
	_add_roll(entry)
	if not entry.hidden:
		for peer_id: int in peers:
			roll_added.rpc_id(peer_id, entry)
	return entry


# --- Attacks (TASK-54) -------------------------------------------------------------------------

## An attack of `ref` ("Longsword") at `targets` (refs on the map): per target a to-hit roll
## against its AC (+ cover), natural 20 = crit (the world's crit rule), natural 1 = miss, then
## damage after resistance / immunity / vulnerability. With damage on Auto (decision 1) it
## is taken off at once (hp.changed per target, undo on the card); Assist leaves an Apply on
## the card. `opts`: {advantage: -1/0/1 (else the conditions suggest it), cover: "half" /
## "three_quarters", multi: true (the creature's Multiattack: its listed attacks in a row)}.
func attack(ref: String, query: String, targets: Array, opts := {}) -> void:
	if is_dm():
		_handle_attack(1, ref, query, targets, opts)
	elif is_online():
		request_attack.rpc_id(1, ref, query, targets, opts)


@rpc("any_peer", "call_remote", "reliable")
func request_attack(ref: String, query: String, targets: Array, opts: Dictionary) -> void:
	if is_dm():
		_handle_attack(multiplayer.get_remote_sender_id(), ref, query.left(100), targets.slice(0, 12), opts)


## Asks the table's UI to pick targets for an attack (a sheet's or the HUD's attack link).
func begin_attack(ref: String, query: String, multi := false, kind := "attack") -> void:
	attack_requested.emit(ref, query, multi, kind)


func _handle_attack(sender: int, ref: String, query: String, targets: Array, opts: Dictionary) -> Array:
	var player := _sender_player(sender)
	if player == "" or not may_see_sheet(player, ref):
		_deny_roll(sender, "that's not your sheet")
		return []
	var sheet := sheet_for(Reveal.DM, ref)
	var features: Dictionary = timeline.entries("features")
	var names: Array = Dice.multiattack(sheet, features) if bool(opts.get("multi", false)) else [query]
	var cards := []
	if in_combat() and not names.is_empty():  # TASK-62: the action (once for a Multiattack)
		var kind := "action" if bool(opts.get("multi", false)) else _action_kind(sheet, str(names[0]).trim_prefix("attack with "))
		event_log.append("action.used", ref, {"kind": kind, "what": "Multiattack" if bool(opts.get("multi", false)) else str(names[0])}, player)
	for n: Variant in names:
		var atk := Dice.attack_of(sheet, str(n), features)
		if atk.is_empty():
			_deny_roll(sender, "%s has no attack \"%s\"" % [sheet.get("name", ref), n])
			continue
		cards.append(_attack_card(player, ref, sheet, atk, targets, opts))
	return cards


func _attack_card(player: String, ref: String, sheet: Dictionary, atk: Dictionary, targets: Array, opts: Dictionary) -> Dictionary:
	var settings := rules_settings()
	var edition := Rules.edition_of(sheet, settings)
	var cover := Rules.cover_bonus(str(opts.get("cover", "")))
	var mode := automation("damage")
	var rows := []
	var results := []
	for t: Variant in targets:
		var tref := str(t)
		var ts := sheet_for(Reveal.DM, tref)
		if ts.is_empty() or tref == ref:
			continue
		var adv := int(opts.advantage) if opts.has("advantage") else signi(Rules.suggested_advantage(sheet, "attack", edition) + Rules.suggested_advantage(ts, "attacked", edition))
		var hit_roll := Dice.roll(Dice.d20(int(atk.to_hit) + Rules.d20_penalty(sheet, edition), adv), rng)
		var ac := Rules.ac(ts) + cover
		var crit := str(hit_roll.get("crit", "")) == "20"
		var hit := crit or (str(hit_roll.get("crit", "")) != "1" and int(hit_roll.total) >= ac)
		hit_roll["label"] = "%s to hit %s" % [atk.name, timeline.name_of(tref)]
		results.append(hit_roll)
		var row := {"ref": tref, "name": timeline.name_of(tref), "ac": ac, "total": int(hit_roll.total), "formula": str(hit_roll.formula),
			"hit": hit, "crit": crit, "fumble": str(hit_roll.get("crit", "")) == "1", "advantage": adv, "damage": [], "amount": 0}
		if hit:
			for d: Dictionary in atk.damage:
				var f := Rules.crit_formula(str(d.dice), settings) if crit else str(d.dice)
				var dr := Dice.roll(f, rng)
				var after := Rules.damage_after(ts, int(dr.total), str(d.type))
				row.damage.append({"formula": f, "rolled": int(dr.total), "type": str(d.type), "amount": int(after.amount), "note": str(after.note)})
				row.amount = int(row.amount) + int(after.amount)
			if mode == "auto" and int(row.amount) > 0:
				var e := _handle_hp(1, tref, -int(row.amount), atk.name, crit)
				row["applied"] = int(e.get("id", 0))
			elif mode == "assist" and int(row.amount) > 0:
				row["pending"] = true
		rows.append(row)
	var data := {"roll": "%s attack" % atk.name, "formula": results[0].formula if not results.is_empty() else "", "result": results[0].total if not results.is_empty() else 0,
		"dice": results[0].dice if not results.is_empty() else [], "results": results, "who": str(sheet.get("name", "")),
		"hidden": false, "attack": {"name": atk.name, "targets": rows, "cover": cover}}
	var ev := event_log.append("dice.rolled", ref, data, player)
	return _post_roll(_roll_entry(ev))


# --- Concentration (TASK-59) ---------------------------------------------------------------------

## The spell `ref` concentrates on ({spell, name}, {} if none).
func concentration_of(ref: String) -> Dictionary:
	var s: Dictionary = sheet_for(Reveal.DM, ref) if is_dm() else sheets.get(ref, {})
	return s.get("concentration", {}) if s.get("concentration") is Dictionary else {}


## `ref` starts concentrating on `spell` (a ref or a name). Already on another one: that one
## ends first. `confirm`: on my screen, ask before ending the old one (concentration_confirm).
func concentrate(ref: String, spell: String, name := "", confirm := false) -> void:
	var old := concentration_of(ref)
	var label := name if name != "" else HudWidgets._name_of(spell)
	if confirm and not old.is_empty() and str(old.spell) != spell:
		concentration_confirm.emit(ref, str(old.get("name", old.spell)), label, func() -> void: concentrate(ref, spell, name, false))
		return
	if is_dm():
		_handle_concentrate(1, ref, spell, label)
	elif is_online():
		request_concentrate.rpc_id(1, ref, spell, label)


@rpc("any_peer", "call_remote", "reliable")
func request_concentrate(ref: String, spell: String, name: String) -> void:
	if is_dm():
		_handle_concentrate(multiplayer.get_remote_sender_id(), ref, spell.left(100), name.left(100))


func _handle_concentrate(sender: int, ref: String, spell: String, name: String) -> Dictionary:
	if automation("concentration") == "off" or _editable_sheet(sender, ref).is_empty():
		return {}
	var old := concentration_of(ref)
	if not old.is_empty():
		if str(old.spell) == spell:
			return {}
		end_concentration(ref, "concentrating on %s now" % name)
	return _handle_condition(1, ref, "concentrating", true, 0, {}, {"spell": spell, "name": name})


## Ends `ref`'s concentration: the marker comes off and so do the conditions its spell put
## on others (their condition.applied carries source {caster, spell}).
func end_concentration(ref: String, reason := "") -> void:
	if not is_dm():
		if is_online():
			request_end_concentration.rpc_id(1, ref)
		return
	var c := concentration_of(ref)
	if c.is_empty():
		return
	_handle_condition(1, ref, "concentrating", false, 0, {})
	var ended := PackedStringArray()
	for e: Dictionary in event_log.effective():
		var src: Variant = e.get("data", {}).get("source")
		if e.type != "condition.applied" or not src is Dictionary or str(src.get("caster", "")) != ref or str(src.get("spell", "")) != str(c.spell):
			continue
		var target := str(e.entity)
		var cond := str(e.data.get("condition", ""))
		if cond in (sheet_for(Reveal.DM, target).get("conditions", []) as Array):
			_handle_condition(1, target, cond, false, 0, {})
			ended.append("%s no longer %s" % [timeline.name_of(target), cond])
	_dm_line(ref, "concentration on %s ends%s%s" % [c.get("name", c.spell), " (%s)" % reason if reason != "" else "",
		" · " + ", ".join(ended) if not ended.is_empty() else ""])


@rpc("any_peer", "call_remote", "reliable")
func request_end_concentration(ref: String) -> void:
	if is_dm() and not _editable_sheet(multiplayer.get_remote_sender_id(), ref).is_empty():
		end_concentration(ref, "ended by its player")


## Conditions that end concentration: incapacitated (and what includes it), 0 HP's unconscious.
func _breaks_concentration(id: String) -> bool:
	var flags: Array = Rules.condition(id, str(rules_settings().edition)).get("flags", [])
	return "incapacitated" in flags or "breaks_concentration" in flags or id in ["incapacitated", "paralyzed", "petrified", "stunned", "unconscious", "dead"]


## Damage on a concentrating creature: a CON save, DC max(10, half the damage). The DM's
## creatures roll at once; a player's gets a prompt (the DM can roll for them).
func _concentration_check(ref: String, damage: int) -> void:
	var dc := maxi(10, damage / 2)
	if str(rules_settings().edition) == "2024":
		dc = mini(dc, 30)
	if (owners.get(ref, []) as Array).is_empty():
		_concentration_save(ref, dc, Reveal.DM)
		return
	_pending_conc[ref] = maxi(dc, int(_pending_conc.get(ref, 0)))
	var prompt := {"id": 0, "by": Reveal.DM, "who": timeline.name_of(ref), "ref": ref, "results": [], "hidden": false,
		"action": "conc_prompt", "text": "CON save DC %d to keep concentrating" % int(_pending_conc[ref])}
	for peer_id: int in peers:
		if str(peers[peer_id]) in (owners.get(ref, []) as Array):
			roll_added.rpc_id(peer_id, prompt)
	var mine := prompt.duplicate()
	mine["hidden"] = true
	_add_roll(mine)


## The concentration save prompt's link: the player (or the DM for them) rolls it.
func answer_concentration(ref: String) -> void:
	if is_dm():
		if _pending_conc.has(ref):
			_concentration_save(ref, int(_pending_conc[ref]), Reveal.DM)
	elif is_online():
		request_concentration_save.rpc_id(1, ref)


@rpc("any_peer", "call_remote", "reliable")
func request_concentration_save(ref: String) -> void:
	var player := _sender_player(multiplayer.get_remote_sender_id())
	if is_dm() and _pending_conc.has(ref) and owns(player, ref):
		_concentration_save(ref, int(_pending_conc[ref]), player)


func _concentration_save(ref: String, dc: int, by: String) -> Dictionary:
	_pending_conc.erase(ref)
	var s := sheet_for(Reveal.DM, ref)
	var c := concentration_of(ref)
	if c.is_empty():
		return {}
	var asked := Dice.resolve(s, "con save", {}, rules_settings())
	var r := Dice.roll(str(asked[0].formula) if not asked.is_empty() else "1d20", rng)
	r["label"] = "Concentration (DC %d)" % dc
	var kept := int(r.total) >= dc
	var data := {"roll": "Concentration save", "formula": r.formula, "result": r.total, "dice": r.dice, "results": [r], "who": str(s.get("name", "")),
		"hidden": false, "concentration": {"dc": dc, "kept": kept, "spell": c.get("name", "")}}
	var ev := event_log.append("dice.rolled", ref, data, by)
	var entry := _roll_entry(ev)
	entry["action"] = "concentration"
	if kept:
		entry["text"] = "keeps concentrating on %s" % c.get("name", "")
	elif automation("concentration") == "auto":
		end_concentration(ref, "failed the save")
		entry["text"] = "loses concentration on %s" % c.get("name", "")
	else:
		entry["text"] = "failed: [url=endconc:%s]end concentration on %s[/url]" % [ref, Markdown.escape(str(c.get("name", "")))]
	return _post_roll(entry)


# --- Save-based actions (TASK-55) -------------------------------------------------------------

## A save-based feature ("Acid Breath") or spell ("spells/burning-hands") of `ref` at
## `targets`: the damage is rolled once, each target rolls its save against the DC (the
## feature's, else the caster's spell DC). The DM's creatures save at once; a player's
## creature gets a "DEX save DC 15" prompt (the DM can roll for them). A fail takes the damage
## (and the conditions the text names), a success half if the text says so, none otherwise.
## `opts`: {cover} (+2 / +5 on Dex saves).
func save_action(ref: String, what: String, targets: Array, opts := {}) -> void:
	if is_dm():
		_handle_save_action(1, ref, what, targets, opts)
	elif is_online():
		request_save_action.rpc_id(1, ref, what, targets, opts)


@rpc("any_peer", "call_remote", "reliable")
func request_save_action(ref: String, what: String, targets: Array, opts: Dictionary) -> void:
	if is_dm():
		_handle_save_action(multiplayer.get_remote_sender_id(), ref, what.left(100), targets.slice(0, 20), opts)


## The save-based features of a sheet (names), for its links.
func _save_features(sheet: Dictionary) -> Array:
	var out := []
	var features: Dictionary = timeline.entries("features") if timeline != null else {}
	for key in ["features", "actions", "bonus_actions", "reactions", "legendary_actions"]:
		for fid: Variant in sheet.get(key, []):
			var f: Variant = features.get(str(fid), {})
			if f is Dictionary and not f.has("attack") and not Rules.save_effect(f).is_empty():
				out.append(str(f.get("name", fid)))
	return out


## The entry behind `what`: a spell / item ref, else one of the sheet's features by name.
func _effect_entry(sheet: Dictionary, what: String) -> Dictionary:
	if "/" in what:
		return catalog_entry(what)
	var features: Dictionary = timeline.entries("features")
	for key in ["features", "traits", "actions", "bonus_actions", "reactions", "legendary_actions"]:
		for fid: Variant in sheet.get(key, []):
			var f: Variant = features.get(str(fid), {})
			if f is Dictionary and str(f.get("name", "")).to_lower() == what.to_lower():
				return f
	return {}


func _handle_save_action(sender: int, ref: String, what: String, targets: Array, opts: Dictionary) -> Dictionary:
	var player := _sender_player(sender)
	if player == "" or not may_see_sheet(player, ref):
		_deny_roll(sender, "that's not your sheet")
		return {}
	var sheet := sheet_for(Reveal.DM, ref)
	var entry := _effect_entry(sheet, what)
	var fx := Rules.save_effect(entry, sheet)
	if fx.is_empty():
		_deny_roll(sender, "\"%s\" has no saving throw" % what)
		return {}
	if str(fx.name) == "":
		fx.name = HudWidgets._name_of(what)
	if in_combat():  # TASK-62
		event_log.append("action.used", ref, {"kind": "action" if "/" in what else _action_kind(sheet, what), "what": str(fx.name)}, player)
	var rolls := []
	for d: Dictionary in fx.damage:
		var r := Dice.roll(str(d.dice), rng)
		rolls.append({"formula": str(d.dice), "rolled": int(r.total), "type": str(d.type)})
	var cover := Rules.cover_bonus(str(opts.get("cover", ""))) if fx.ability == "dex" else 0
	var card := {"name": fx.name, "ability": fx.ability, "dc": fx.dc, "half": fx.half, "damage": rolls, "conditions": fx.conditions,
		"duration": fx.duration, "cover": cover, "targets": [], "from": ref}
	if bool(entry.get("concentration", false)):  # TASK-59: the caster concentrates, its conditions are linked
		_handle_concentrate(1, ref, what, str(fx.name))
		card["source"] = {"caster": ref, "spell": what}
	var waiting := []
	for t: Variant in targets:
		var tref := str(t)
		if tref == ref or sheet_for(Reveal.DM, tref).is_empty():
			continue
		if (owners.get(tref, []) as Array).is_empty():
			card.targets.append(_save_row(tref, card))
		else:
			waiting.append(tref)
			card.targets.append({"ref": tref, "name": timeline.name_of(tref), "waiting": true})
	var data := {"roll": "%s (DC %d %s save)" % [fx.name, fx.dc, str(fx.ability).to_upper()], "results": [], "who": str(sheet.get("name", "")),
		"hidden": false, "save": card}
	var ev := event_log.append("dice.rolled", ref, data, player)
	var posted := _post_roll(_roll_entry(ev))
	if not waiting.is_empty():
		_pending_saves[int(ev.id)] = card.duplicate(true)  # its own copy: the posted card stays as it was
		for tref: String in waiting:
			_ask_save(int(ev.id), tref, _pending_saves[int(ev.id)])
	return posted


## One target's save: rolled now (the DM's side), damage and conditions as the result says.
func _save_row(tref: String, card: Dictionary, by := Reveal.DM) -> Dictionary:
	var ts := sheet_for(Reveal.DM, tref)
	var asked := Dice.resolve(ts, "%s save" % card.ability, {}, rules_settings())
	var formula := str(asked[0].formula) if not asked.is_empty() else "1d20"
	if int(card.get("cover", 0)) > 0:
		formula += "+%d" % int(card.cover)
	var r := Dice.roll(formula, rng)
	var ok := int(r.total) >= int(card.dc)  # a natural 20 or 1 means nothing special on a save
	var row := {"ref": tref, "name": timeline.name_of(tref), "total": int(r.total), "formula": formula, "success": ok,
		"label": str(asked[0].label) if not asked.is_empty() else "", "damage": [], "amount": 0, "by": by}
	if card.has("ends"):  # TASK-63: a "save ends" save
		if ok and str(card.ends) in (ts.get("conditions", []) as Array):
			var gone := _handle_condition(1, tref, str(card.ends), false, 0, {})
			if not gone.is_empty():
				row["ended"] = str(card.ends)
				row["applied_conditions"] = [int(gone.id)]
		return row
	if not ok or bool(card.half):
		for d: Dictionary in card.damage:
			var amount := int(d.rolled) if not ok else int(d.rolled) / 2
			var after := Rules.damage_after(ts, amount, str(d.type))
			row.damage.append({"rolled": amount, "type": str(d.type), "amount": int(after.amount), "note": str(after.note)})
			row.amount = int(row.amount) + int(after.amount)
	if int(row.amount) > 0:
		match automation("damage"):
			"auto":
				row["applied"] = int(_handle_hp(1, tref, -int(row.amount), str(card.name)).get("id", 0))
			"assist":
				row["pending"] = true
	if not ok and not (card.conditions as Array).is_empty() and automation("conditions") != "off":
		var done := []
		for c: Variant in card.conditions:
			if automation("conditions") == "auto":
				var dur: Dictionary = (card.get("duration", {}) as Dictionary).duplicate()
				if not dur.is_empty():  # TASK-63: "for 1 minute" counts the actor's turns, "its next turn" the target's
					dur["of"] = tref if str(dur.get("ends", "")) == "turn_end" or str(card.get("from", "")) == "" else str(card.from)
				if bool(dur.get("save_ends", false)):
					dur["save_ends"] = {"ability": card.ability, "dc": card.dc}
				var e := _handle_condition(1, tref, str(c), true, 1, dur, {"source": card.source} if card.has("source") else {})
				if not e.is_empty():
					done.append(int(e.id))
		row["conditions"] = card.conditions
		if not done.is_empty():
			row["applied_conditions"] = done
	return row


## Asks the players of `tref` for their save (a prompt in their chat), the DM sees it wait.
func _ask_save(card_id: int, tref: String, card: Dictionary) -> void:
	var prompt := {"id": card_id, "by": Reveal.DM, "who": timeline.name_of(tref), "ref": tref, "results": [], "hidden": false,
		"action": "save_prompt", "text": "%s save DC %d" % [str(card.ability).to_upper(), int(card.dc)]}
	var players: Array = owners.get(tref, [])
	for peer_id: int in peers:
		if str(peers[peer_id]) in players:
			roll_added.rpc_id(peer_id, prompt)
	var mine := prompt.duplicate()
	mine["action"] = "save_prompt_dm"
	mine["hidden"] = true
	_add_roll(mine)


## A player answers their save prompt (or the DM rolls for an absent one): the result card.
func answer_save(card_id: int, tref: String) -> void:
	if is_dm():
		_handle_save_answer(1, card_id, tref)
	elif is_online():
		request_save_answer.rpc_id(1, card_id, tref)


@rpc("any_peer", "call_remote", "reliable")
func request_save_answer(card_id: int, tref: String) -> void:
	if is_dm():
		_handle_save_answer(multiplayer.get_remote_sender_id(), card_id, tref)


func _handle_save_answer(sender: int, card_id: int, tref: String) -> Dictionary:
	var player := _sender_player(sender)
	var card: Dictionary = _pending_saves.get(card_id, {})
	if card.is_empty() or not (card.targets as Array).any(func(r: Dictionary) -> bool: return r.ref == tref and r.get("waiting", false)):
		return {}
	if player != Reveal.DM and not owns(player, tref):
		_deny_roll(sender, "that's not your save")
		return {}
	for r: Dictionary in card.targets:
		if r.ref == tref:
			r.erase("waiting")
	if not (card.targets as Array).any(func(r: Dictionary) -> bool: return r.get("waiting", false)):
		_pending_saves.erase(card_id)
	var one := card.duplicate()
	one["targets"] = [_save_row(tref, card, player)]
	var data := {"roll": "%s: %s save" % [card.name, str(card.ability).to_upper()], "results": [], "who": timeline.name_of(tref), "hidden": false, "save": one}
	var ev := event_log.append("dice.rolled", tref, data, player)
	return _post_roll(_roll_entry(ev))


## A new roll card into the feed, to everyone who may see it.
func _post_roll(entry: Dictionary) -> Dictionary:
	_add_roll(entry)
	if not entry.hidden:
		for peer_id: int in peers:
			roll_added.rpc_id(peer_id, entry)
	return entry


## DM: takes back the damage an attack card applied (its hp.changed events are undone).
func undo_card(card_id: int) -> int:
	if not is_dm():
		return 0
	var card := event_log.get_event(card_id)
	var count := 0
	for row: Variant in _card_rows(card):
		var id := int((row as Dictionary).get("applied", 0))
		if _applied.has("%d:%s" % [card_id, row.ref]):
			id = int(_applied["%d:%s" % [card_id, row.ref]])
		var ids: Array = [id] + (row as Dictionary).get("applied_conditions", [])
		var any := false
		for x: Variant in ids:
			if int(x) > 0 and not event_log.is_undone(int(x)):
				event_log.undo(int(x))
				any = true
		if any:
			_applied.erase("%d:%s" % [card_id, row.ref])
			_sheet_changed(str(row.ref))
			count += 1
	if count > 0:
		_set_status("Undone: %s" % card.get("data", {}).get("roll", "the attack"))
		_post_roll({"id": 0, "by": Reveal.DM, "who": str(card.get("data", {}).get("who", "")), "results": [], "hidden": true,
			"action": "log", "text": "damage of %s undone" % card.get("data", {}).get("roll", "the attack")})
	return count


## The target rows of an attack or save card event.
static func _card_rows(card: Dictionary) -> Array:
	var d: Dictionary = card.get("data", {})
	for key in ["attack", "save"]:
		if d.get(key) is Dictionary:
			return (d[key] as Dictionary).get("targets", [])
	return []


## DM: applies the damage an attack card (Assist) left for one target.
func apply_card(card_id: int, target: String) -> Dictionary:
	if not is_dm() or _applied.has("%d:%s" % [card_id, target]):
		return {}
	var card := event_log.get_event(card_id)
	for row: Variant in _card_rows(card):
		if str(row.ref) == target and int(row.get("amount", 0)) > 0 and int(row.get("applied", 0)) == 0:
			var e := _handle_hp(1, target, -int(row.amount), str(card.data.get("roll", "")))
			_applied["%d:%s" % [card_id, target]] = int(e.get("id", 0))
			return e
	return {}


# --- Rules settings (TASK-53) -----------------------------------------------------------------

## The world's rules settings: edition, house rules (crits), automation (TASK-60).
func rules_settings() -> Dictionary:
	if is_dm() and timeline != null:
		return timeline.rules_settings()
	return _rules if not _rules.is_empty() else Rules.settings_of({})


## How much the table does by itself in `category` (TASK-60): "off", "assist" or "auto".
func automation(category: String) -> String:
	return Rules.automation(rules_settings(), category)


## DM: changes the world's rules settings; everyone gets them with the table.
func set_rules_settings(settings: Dictionary) -> void:
	if not is_dm() or timeline == null:
		return
	timeline.set_rules_settings(settings)
	_apply_state(view_for(""))
	_send_tables()


# --- Quick buttons (TASK-48) ------------------------------------------------------------------

## A spell or item from the timeline, the world, else the packages ("spells/fire-bolt").
func catalog_entry(ref: String) -> Dictionary:
	var kind := ref.get_slice("/", 0)
	var id := ref.get_slice("/", 1)
	if kind == "" or id == "":
		return {}
	if timeline != null:
		var own: Dictionary = timeline.entries(kind)
		if own.has(id):
			return own[id]
	if not _catalog.has(kind):
		var by_id := {}
		var root := PackageDB.default_root()
		if DirAccess.dir_exists_absolute(root):
			for d in DirAccess.get_directories_at(root):
				var file := root.path_join(d).path_join(kind + ".json")
				if FileAccess.file_exists(file):
					var list: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
					if list is Array:
						for e: Variant in list:
							if e is Dictionary and e.has("id") and not by_id.has(str(e.id)):
								by_id[str(e.id)] = e
		_catalog[kind] = by_id
	return (_catalog[kind] as Dictionary).get(id, {})


## Casts a spell / uses an item of `ref` (a quick button): for now it is posted in the chat
## with what it rolls (HudActions); nothing is spent yet (TASK-49).
func use_action(ref: String, what: String) -> void:
	if is_dm():
		_handle_use(1, ref, what)
	elif is_online():
		request_use.rpc_id(1, ref, what)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_use(ref: String, what: String) -> void:
	if is_dm():
		_handle_use(multiplayer.get_remote_sender_id(), ref.left(200), what.left(200))


func _handle_use(sender: int, ref: String, what: String) -> Dictionary:
	var player := _sender_player(sender)
	if player == "" or ref == "" or not may_see_sheet(player, ref):
		_deny_roll(sender, "that's not your sheet")
		return {}
	var sheet := sheet_for(Reveal.DM, ref)
	var kind := what.get_slice("/", 0)
	if sheet.is_empty() or kind not in ["spells", "items"]:
		return {}
	var use := HudActions.spell(sheet, catalog_entry(what), what) if kind == "spells" else HudActions.item(sheet, catalog_entry(what), what)
	var results := []
	for a: Dictionary in use.asked:
		var r := Dice.roll(str(a.formula), rng)
		r["label"] = a.label
		results.append(r)
	var data := {"text": use.text, "action": what, "who": str(sheet.get("name", "")), "results": results}
	var e: Dictionary
	if results.is_empty():
		e = event_log.append("chat.message", ref, data, player)
	else:
		data.merge({"roll": str(results[0].label), "formula": results[0].formula, "result": results[0].total,
			"dice": results[0].dice, "hidden": false})
		e = event_log.append("dice.rolled", ref, data, player)
	var entry := _roll_entry(e)
	_add_roll(entry)
	for peer_id: int in peers:
		roll_added.rpc_id(peer_id, entry)
	return entry


## A dice.rolled (or chat.message) event as the roll log / chat shows it.
static func _roll_entry(e: Dictionary) -> Dictionary:
	var d: Dictionary = e.get("data", {})
	var entry := {"id": e.get("id", 0), "by": e.get("by", ""), "who": d.get("who", ""), "results": d.get("results", []),
		"hidden": bool(d.get("hidden", false)), "real": e.get("real", "")}
	if str(e.get("entity", "")) != "":
		entry["ref"] = str(e.entity)
	if e.get("type") == "chat.message" or d.has("text"):
		entry["text"] = str(d.get("text", ""))
	if d.has("action"):  # a quick button: a spell cast, an item used (TASK-48)
		entry["action"] = str(d.action)
	if d.has("attack"):  # targets, hits, damage (TASK-54)
		entry["attack"] = d.attack
	if d.has("save"):  # DC, saves per target, damage (TASK-55)
		entry["save"] = d.save
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
	if not (entry.get("results", []) as Array).is_empty():
		roll_shown.emit(entry)
	if entry.has("table") and _ui != null:  # the table on my screen shows the row
		RollTables.set_result(str(entry.table), int(entry.value), int(entry.row))
	if rolls.size() > ROLL_LOG_SIZE:
		rolls = rolls.slice(rolls.size() - ROLL_LOG_SIZE)
	rolls_changed.emit()


## Host: this session's rolls from the log (so a restart or a late joiner sees them).
func _load_rolls() -> void:
	rolls = []
	for e in event_log.events:
		if int(e.session) != event_log.session or event_log.is_undone(e.id):
			continue
		if e.type in ["dice.rolled", "chat.message"]:
			rolls.append(_roll_entry(e))
		elif e.type in LOGGED and str(e.get("by", Reveal.DM)) != Reveal.DM:
			rolls.append(_log_entry(e))
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


# --- HUD and sheet page layouts (TASK-47) -------------------------------------------------

## A creature copy's template in the Book ("kind/id" in the world), "" if it has none: its
## layouts live there, so the DM sets them up once for every goblin.
func layout_template(ref: String) -> String:
	var e := timeline.entry(ref)
	if ref.get_slice("/", 0) == "characters" or not e.has("copy_of"):
		return ""
	var src := str(e.copy_of).split("/")
	if src.size() == 3 and src[0] == timeline.world_id() and timeline.world_entries(src[1]).has(src[2]):
		return "%s/%s" % [src[1], src[2]]
	return ""


## Saves a layout (`hud` or `sheet_pages`) of `ref`: owners and the DM.
func save_layout(ref: String, field: String, value: Variant) -> void:
	if is_dm():
		_handle_layout(1, ref, field, value)
	elif is_online():
		request_layout.rpc_id(1, ref, field, value)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_layout(ref: String, field: String, value: Variant) -> void:
	if is_dm():
		_handle_layout(multiplayer.get_remote_sender_id(), ref, field, value)


## A character's layout is a sheet.changed event; a creature copy's goes into its template in
## the world package (DM only), and every open copy of it gets the new one.
func _handle_layout(sender: int, ref: String, field: String, value: Variant) -> bool:
	var player := _sender_player(sender)
	if not LAYOUT_FIELDS.has(field) or not value is Array or not may_see_sheet(player, ref):
		_deny_sheet(sender, "that's not your sheet")
		return false
	var tpl := layout_template(ref)
	if tpl == "":
		var from: Variant = timeline.entry(ref).get(field)
		var now: Variant = Replay.entity_state(timeline.entry(ref), event_log.effective(ref)).get(field, from)
		event_log.change_sheet(ref, field, now, value, "", player)
		_sheet_changed(ref)
		return true
	if player != Reveal.DM:
		_deny_sheet(sender, "only the DM changes a creature's HUD")
		return false
	var store := EntryStore.open(timeline.world_dir)
	var kind := tpl.get_slice("/", 0)
	var e := store.find(kind, tpl.get_slice("/", 1)).duplicate(true)
	if e.is_empty():
		return false
	e[field] = value
	store.save(kind, e)
	timeline.reload_world()
	var open_refs := sheets.keys()
	open_refs.append_array(sheet_watchers.keys())
	var done := {}
	for other: String in open_refs:
		if not done.has(other) and layout_template(other) == tpl:
			done[other] = true
			_sheet_changed(other)
	return true


# --- Chat (TASK-46) ----------------------------------------------------------------------------

## Says something in the chat (with the rolls, one feed). "/r 1d20+3" or "/roll perception"
## rolls instead (for `ref`, else one's own character, or a plain formula).
func say(text: String, ref := "") -> void:
	var t := text.strip_edges()
	if t == "":
		return
	for prefix in ["/roll ", "/r "]:
		if t.to_lower().begins_with(prefix):
			roll(t.substr(prefix.length()), ref)
			return
	if is_dm():
		_handle_chat(1, t)
	elif is_online():
		request_chat.rpc_id(1, t)


## Player -> DM.
@rpc("any_peer", "call_remote", "reliable")
func request_chat(text: String) -> void:
	if is_dm():
		_handle_chat(multiplayer.get_remote_sender_id(), text)


func _handle_chat(sender: int, text: String) -> Dictionary:
	var player := _sender_player(sender)
	if player == "" or text.strip_edges() == "":
		return {}
	var e := event_log.append("chat.message", "", {"text": text.strip_edges().left(2000)}, player)
	var entry := _roll_entry(e)
	_add_roll(entry)
	for peer_id: int in peers:
		roll_added.rpc_id(peer_id, entry)
	return entry


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
	if entry.has("text") and not entry.has("action"):  # a chat message
		var from := str(names.get(entry.get("by", ""), entry.get("by", "")))
		return "[font_size=12]%s[/font_size]\n%s" % [Markdown.escape(from), Markdown.escape(str(entry.text))]
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
	if entry.get("attack") is Dictionary:  # TASK-54: one line per target
		lines = _attack_lines(entry)
	elif entry.get("save") is Dictionary:  # TASK-55
		lines = _save_lines(entry)
	if str(entry.get("action", "")) == "conc_prompt":  # TASK-59
		lines.insert(0, "[b][url=conc:%s]%s · Roll[/url][/b]" % [entry.get("ref", ""), Markdown.escape(str(entry.get("text", "")))])
	elif str(entry.get("action", "")) == "concentration":
		lines.append("[i]%s[/i]" % str(entry.get("text", "")))
	if str(entry.get("action", "")) == "death_prompt":  # TASK-57
		lines.insert(0, "[b][url=death:%s]Death save · Roll[/url][/b]" % entry.get("ref", ""))
	elif str(entry.get("action", "")) == "death_save":
		lines.append("[i]%s[/i]" % Markdown.escape(str(entry.get("text", ""))))
	if str(entry.get("action", "")) == "save_prompt":
		lines.insert(0, "[b][url=save:%d:%s]%s · Roll[/url][/b]" % [int(entry.get("id", 0)), entry.get("ref", ""), Markdown.escape(str(entry.get("text", "")))])
	elif str(entry.get("action", "")) == "save_prompt_dm":
		lines.insert(0, "[i]waiting for the %s[/i] · [url=save:%d:%s]roll for them[/url]" % [Markdown.escape(str(entry.get("text", ""))), int(entry.get("id", 0)), entry.get("ref", "")])
	if str(entry.get("action", "")) == "prompt":  # TASK-58: the player's initiative prompt
		lines.insert(0, "[b][url=init:%s]Roll initiative[/url][/b]" % entry.get("ref", ""))
	elif str(entry.get("action", "")) == "prompt_dm":
		lines.insert(0, "[i]waiting for initiative[/i] · [url=init:%s]roll for them[/url]" % entry.get("ref", ""))
	elif entry.has("action"):  # "casts Fire Bolt (cantrip · 1 action · 36 m)", then its rolls
		lines.insert(0, "[i]%s[/i]" % Markdown.escape(str(entry.get("text", ""))))
	var who := str(entry.get("who", ""))
	var by := str(names.get(entry.get("by", ""), entry.get("by", "")))
	var head := Markdown.escape(who if who != "" else by)
	if who != "" and str(entry.get("ref", "")) != "":  # TASK-56: click for its conditions
		head = "[url=cond:%s]%s[/url]" % [entry.ref, head]
	if by != "" and who != "" and who != by:
		head += " [color=#%s](%s)[/color]" % [Markdown.MUTED.to_html(false), Markdown.escape(by)]
	if entry.get("hidden", false):
		head += " [color=#%s][i]hidden[/i][/color]" % Markdown.MUTED.to_html(false)
	return "[font_size=12]%s[/font_size]\n%s" % [head, "\n".join(lines)]


## A save card's lines: the damage rolled once, then "→ Goblin: DEX 9 failed · 14 fire".
static func _save_lines(entry: Dictionary) -> PackedStringArray:
	var s: Dictionary = entry.save
	var out := PackedStringArray()
	var muted := Markdown.MUTED.to_html(false)
	var dmg := PackedStringArray()
	for d: Dictionary in s.get("damage", []):
		dmg.append("%d %s [color=#%s](%s)[/color]" % [int(d.rolled), str(d.type), muted, Markdown.escape(str(d.formula))])
	out.append("DC %d %s save%s%s" % [int(s.dc), str(s.ability).to_upper(), " · " + ", ".join(dmg) if not dmg.is_empty() else "",
		" · half on a success" if bool(s.half) and not dmg.is_empty() else ""])
	var applied := false
	for row: Dictionary in s.get("targets", []):
		if row.get("waiting", false):
			out.append("→ %s: [i]waiting for the save[/i]" % Markdown.escape(str(row.name)))
			continue
		var verdict := "[color=#%s][b]saved[/b][/color]" % UISkin.GREEN.to_html(false) if bool(row.get("success", false)) else "[color=#%s][b]failed[/b][/color]" % UISkin.RED.to_html(false)
		var line := "→ %s: %s %d [color=#%s]%s[/color] %s" % [Markdown.escape(str(row.name)), str(s.ability).to_upper(), int(row.total), muted, Markdown.escape(str(row.formula)), verdict]
		var bits := PackedStringArray()
		for d: Dictionary in row.get("damage", []):
			var t := "%d %s" % [int(d.rolled), str(d.type)]
			if str(d.note) != "":
				t += " → %d (%s)" % [int(d.amount), d.note]
			bits.append(t.strip_edges())
		if not bits.is_empty():
			line += " · " + ", ".join(bits)
		if not (row.get("conditions", []) as Array).is_empty():
			line += " · " + ", ".join((row.conditions as Array).map(func(c: Variant) -> String: return str(c)))
		if row.has("ended"):  # TASK-63: a "save ends" save
			line += " · %s ends" % Markdown.escape(str(row.ended))
		if row.get("pending", false):
			line += " · [url=apply:%d:%s]apply %d[/url]" % [int(entry.get("id", 0)), row.ref, int(row.amount)]
		if int(row.get("applied", 0)) > 0 or not (row.get("applied_conditions", []) as Array).is_empty():
			applied = true
		out.append(line)
	if applied:
		out.append("[color=#%s]applied[/color] · [url=undo:%d]undo[/url]" % [muted, int(entry.get("id", 0))])
	return out


## An attack card's lines: "→ Goblin: 17 hits · 9 slashing → 4 (resistant)", undo / apply.
static func _attack_lines(entry: Dictionary) -> PackedStringArray:
	var a: Dictionary = entry.attack
	var out := PackedStringArray()
	var muted := Markdown.MUTED.to_html(false)
	var applied := false
	for row: Dictionary in a.get("targets", []):
		var verdict := "[color=#%s][b]miss[/b][/color]" % UISkin.RED.to_html(false)
		if bool(row.get("crit", false)):
			verdict = "[color=#%s][b]critical hit![/b][/color]" % UISkin.GREEN.to_html(false)
		elif bool(row.get("hit", false)):
			verdict = "[b]hit[/b]"
		elif bool(row.get("fumble", false)):
			verdict += " (nat 1)"
		var adv := " [color=#%s](%s)[/color]" % [muted, "adv" if int(row.advantage) > 0 else "dis"] if int(row.get("advantage", 0)) != 0 else ""
		var line := "→ %s: %d%s [color=#%s]%s[/color] %s" % [Markdown.escape(str(row.name)), int(row.total), adv, muted, Markdown.escape(str(row.formula)), verdict]
		var bits := PackedStringArray()
		for d: Dictionary in row.get("damage", []):
			var t := "%d %s" % [int(d.rolled), str(d.type)] if str(d.type) != "" else str(int(d.rolled))
			if str(d.note) != "":
				t += " → %d (%s)" % [int(d.amount), d.note]
			bits.append(t.strip_edges())
		if not bits.is_empty():
			line += " · " + ", ".join(bits)
		if row.get("pending", false):
			line += " · [url=apply:%d:%s]apply %d[/url]" % [int(entry.get("id", 0)), row.ref, int(row.amount)]
		if int(row.get("applied", 0)) > 0:
			applied = true
		out.append(line)
	if applied:
		out.append("[color=#%s]applied[/color] · [url=undo:%d]undo[/url]" % [muted, int(entry.get("id", 0))])
	if out.is_empty():
		out.append("[i]no target[/i]")
	return out


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)
