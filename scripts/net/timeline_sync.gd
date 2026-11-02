class_name TimelineSync
extends Node
## The timeline bar's data on every screen (TASK-82). Only the DM's host has the event log:
## it keeps the moments (TimelineMoments) up to date as events come in (a full rebuild after
## an undo) and sends each player their version. Players get only what they may know: world
## events, the player characters, and what happened on maps without fog of war (per-player
## sight is for later); DM-only rolls never say anything in a summary anyway.
## A child of the NetTable named "TimelineSync", so its RPCs meet on every peer.

signal changed

## What the bar shows: {moments: [...], sessions: [...], now_at, hours_per_day, map_names {id: name}}
var data := {}
var table: NetTable

var _dm: TimelineMoments
var _players: TimelineMoments
var _seen := 0  ## events of the log already in the moments
var _maps_of := {}  ## entity -> the map its token is on (for the players' filter)
var _dirty := false


func _ready() -> void:
	name = "TimelineSync"


## Host: starts following the log.
func follow(log: EventLog) -> void:
	if not log.appended.is_connected(_on_appended):
		log.appended.connect(_on_appended)
	rebuild()


func _on_appended(e: Dictionary) -> void:
	if e.has("undoes") or _dm == null:
		_dirty = true  # an undo changes the past: build anew
	else:
		_add(e)
	_send_soon()


## Host: the moments from the whole log again (after an undo, or at the start).
func rebuild() -> void:
	if table == null or table.event_log == null:
		return
	var hours := table.notes.calendar.hours_per_day if table.notes != null and table.notes.calendar != null else 24
	var names := func(ref: String) -> String: return table.timeline.name_of(ref) if table.timeline != null else ""
	_dm = TimelineMoments.new()
	_dm.hours_per_day = hours
	_dm.name_of = names
	_players = TimelineMoments.new()
	_players.hours_per_day = hours
	_players.name_of = names
	_maps_of.clear()
	for e in table.event_log.effective():
		_add(e)
	_dirty = false
	_send_soon()


func _add(e: Dictionary) -> void:
	_dm.add(e)
	if _players_may_see(e):
		_players.add(e)
	var map := str(e.data.get("map", ""))
	if map != "" and str(e.entity) != "":
		_maps_of[str(e.entity)] = map


## True if the players may know about this event (no hidden creatures on fogged maps).
func _players_may_see(e: Dictionary) -> bool:
	var who := str(e.entity)
	if who == "" or who.begins_with("characters/"):
		return true
	var map := str(e.data.get("map", _maps_of.get(who, "")))
	if map == "":
		return true
	return not bool(table.timeline.entry(map).get("fog", false)) if table.timeline != null else true


func _send_soon() -> void:
	if not is_queued_for_deletion() and not has_meta("sending"):
		set_meta("sending", true)
		_send.call_deferred()


func _send() -> void:
	remove_meta("sending")
	if _dirty:
		rebuild()
		return
	data = _pack(_dm)
	changed.emit()
	var mine := _pack(_players)
	for peer_id: int in table.peers:
		receive.rpc_id(peer_id, mine)


## Host: a player just joined.
func welcome(peer_id: int) -> void:
	if _players != null:
		receive.rpc_id(peer_id, _pack(_players))


func _pack(m: TimelineMoments) -> Dictionary:
	var moments: Array = []
	var map_names := {}
	for x: Dictionary in m.moments:
		var y := x.duplicate()
		y.erase("events")  # ids aren't needed on the bar
		y.erase("clock")
		moments.append(y)
		for map: String in x.maps:
			if not map_names.has(map):
				map_names[map] = table.timeline.name_of(map) if table.timeline != null else map
	var log := table.event_log
	return {"moments": moments, "sessions": m.sessions.duplicate(true), "hours_per_day": m.hours_per_day,
		"now_at": maxi(m.seconds_of(log.day, log.time) if log != null else 0, int(moments.back().at) if not moments.is_empty() else 0),
		"map_names": map_names}


@rpc("authority", "call_remote", "reliable")
func receive(view: Dictionary) -> void:
	data = view
	changed.emit()
