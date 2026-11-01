class_name NewTimelineForm
extends VBoxContainer
## The "New timeline" form (TASK-33): a fork of a timeline of the world at a point of its
## history (the latest event, any earlier event, or its start), then its name, its players
## with their colors, and the DM's name and color.

var world_dir := ""
var parent_dir := ""  ## preselected timeline to fork from
var name_edit: LineEdit
var parent_pick: OptionButton
var point_pick: OptionButton
var players_box: VBoxContainer
var dm_name: LineEdit
var dm_color: ColorPickerButton

var _parents: Array[Dictionary] = []
var _points: Array[int] = []  ## event id per point_pick item (-1 = latest, 0 = start)

const PLAYER_COLORS := ["#2e6e60", "#b8783c", "#3a5f9a", "#8f3b5a", "#5a7a2e", "#6b4a9a"]


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(520, 0)
	add_child(_muted("Name"))
	name_edit = LineEdit.new()
	name_edit.name = "TimelineName"
	add_child(name_edit)
	add_child(_muted("Fork from"))
	parent_pick = OptionButton.new()
	parent_pick.name = "Parent"
	_parents = Timeline.list(world_dir)
	for t in _parents:
		parent_pick.add_item(str(t.get("name", t.get("id", ""))))
	var at := _parents.find_custom(func(t: Dictionary) -> bool: return str(t._dir).simplify_path() == parent_dir.simplify_path())
	if not _parents.is_empty():
		parent_pick.select(maxi(at, 0))
	parent_pick.item_selected.connect(func(_i: int) -> void:
		_fill_points()
		_take_players())
	add_child(parent_pick)
	add_child(_muted("At"))
	point_pick = OptionButton.new()
	point_pick.name = "ForkPoint"
	point_pick.clip_text = true
	point_pick.custom_minimum_size = Vector2(500, 0)
	add_child(point_pick)
	add_child(_muted("Players"))
	players_box = VBoxContainer.new()
	players_box.name = "Players"
	add_child(players_box)
	var add := Button.new()
	add.text = "Add player"
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func() -> void: add_player("", PLAYER_COLORS[players_box.get_child_count() % PLAYER_COLORS.size()]))
	add_child(add)
	add_child(_muted("DM"))
	var dm_row := HBoxContainer.new()
	add_child(dm_row)
	dm_name = LineEdit.new()
	dm_name.name = "DMName"
	dm_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dm_row.add_child(dm_name)
	dm_color = ColorPickerButton.new()
	dm_color.name = "DMColor"
	dm_color.custom_minimum_size = Vector2(40, 0)
	dm_color.edit_alpha = false
	dm_row.add_child(dm_color)
	_fill_points()
	_take_players()


func parent() -> Dictionary:
	var i := parent_pick.selected
	return _parents[i] if i >= 0 and i < _parents.size() else {}


## The fork points of the picked timeline: its latest event, then its events newest first,
## then its start.
func _fill_points() -> void:
	point_pick.clear()
	_points = []
	var p := parent()
	if p.is_empty():
		return
	var tl := Timeline.new(str(p._dir))
	point_pick.add_item("Now (after its latest event)")
	_points.append(-1)
	var events := tl.events_log.events
	for i in range(events.size() - 1, maxi(-1, events.size() - 301), -1):
		var e: Dictionary = events[i]
		point_pick.add_item("After #%d · session %d · day %d · %s %s" % [e.id, e.session, e.day, e.type, e.entity])
		_points.append(int(e.id))
	point_pick.add_item("Its start (no events)")
	_points.append(0)
	point_pick.select(0)


## Players and DM from the picked timeline, to change as needed.
func _take_players() -> void:
	for c in players_box.get_children():
		players_box.remove_child(c)
		c.queue_free()
	var p := parent()
	for pl: Variant in p.get("players", []):
		if pl is Dictionary:
			add_player(str(pl.get("name", "")), str(pl.get("color", PLAYER_COLORS[0])))
	var dm: Dictionary = p.get("dm", {}) if p.get("dm") is Dictionary else {}
	dm_name.text = str(dm.get("name", "DM"))
	var c := str(dm.get("color", "#7a3b8f"))
	dm_color.color = Color.html(c) if Color.html_is_valid(c) else Color.html("#7a3b8f")


func add_player(player_name: String, color: String) -> void:
	var row := HBoxContainer.new()
	players_box.add_child(row)
	var n := LineEdit.new()
	n.text = player_name
	n.placeholder_text = "Player name"
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	var c := ColorPickerButton.new()
	c.custom_minimum_size = Vector2(40, 0)
	c.edit_alpha = false
	c.color = Color.html(color) if Color.html_is_valid(color) else Color.html(PLAYER_COLORS[0])
	row.add_child(c)
	var x := Button.new()
	x.text = "×"
	x.tooltip_text = "Remove this player"
	x.pressed.connect(func() -> void:
		players_box.remove_child(row)
		row.queue_free())
	row.add_child(x)


## [{id, name, color}] from the rows (rows without a name are left out).
func players() -> Array:
	var out := []
	var ids := {}
	for row in players_box.get_children():
		var n := (row.get_child(0) as LineEdit).text.strip_edges()
		if n == "":
			continue
		var id := EntryStore.slug(n)
		while ids.has(id):
			id += "-2"
		ids[id] = true
		out.append({"id": id, "name": n, "color": "#" + (row.get_child(1) as ColorPickerButton).color.to_html(false)})
	return out


## Creates the timeline; returns its folder ("" without a name or parent).
func create() -> String:
	var p := parent()
	if name_edit.text.strip_edges() == "" or p.is_empty():
		return ""
	var point: int = _points[point_pick.selected] if point_pick.selected >= 0 else -1
	var dm := {"name": dm_name.text.strip_edges() if dm_name.text.strip_edges() != "" else "DM", "color": "#" + dm_color.color.to_html(false)}
	var tl := Timeline.new(str(p._dir))
	var pl := players()
	if pl.is_empty():
		pl = [{"id": "player", "name": "Player", "color": PLAYER_COLORS[0]}]
	return tl.fork(name_edit.text.strip_edges(), point, pl, dm)


func _muted(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = UISkin.V_MUTED
	return l
