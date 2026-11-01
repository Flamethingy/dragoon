class_name TimelineView
extends PanelContainer
## The Timeline view in a session (TASK-33, DM): the timeline's history as a list of events,
## newest at the bottom, with the session, the in-world moment, who did it and what; events
## inherited from the parent before the fork are marked, undone ones struck through.
## Read only. A filter box narrows it by type, entity or writer.

var event_log: EventLog
var timeline: Timeline
var calendar: WorldCalendar
var tree: Tree
var filter_edit: LineEdit
var heading: Label


func _ready() -> void:
	theme_type_variation = UISkin.V_PAGE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	heading = Label.new()
	heading.theme_type_variation = UISkin.V_HEADING
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	filter_edit = LineEdit.new()
	filter_edit.name = "Filter"
	filter_edit.placeholder_text = "Filter: hp, characters/aria, ann ..."
	filter_edit.custom_minimum_size = Vector2(260, 0)
	filter_edit.text_changed.connect(func(_t: String) -> void: refresh())
	head.add_child(filter_edit)
	tree = Tree.new()
	tree.name = "Events"
	tree.columns = 6
	tree.hide_root = true
	tree.column_titles_visible = true
	for i in 6:
		tree.set_column_title(i, ["#", "Session", "When", "By", "What", "About"][i])
		tree.set_column_expand(i, i >= 4)
	tree.set_column_custom_minimum_width(0, 50)
	tree.set_column_custom_minimum_width(1, 70)
	tree.set_column_custom_minimum_width(2, 170)
	tree.set_column_custom_minimum_width(3, 80)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tree)
	if event_log != null:
		event_log.appended.connect(func(_e: Dictionary) -> void:
			if is_visible_in_tree():
				refresh())
	refresh()


func refresh() -> void:
	if tree == null:
		return
	tree.clear()
	var root := tree.create_item()
	if event_log == null:
		heading.text = "Timeline"
		return
	var info := timeline.info if timeline != null else {}
	var parent := str(info.get("parent", ""))
	heading.text = "Timeline · %s%s · %d events" % [info.get("name", ""), ("" if parent == "" else "  (fork of %s after #%d)" % [parent, int(info.get("fork_at", 0))]), event_log.events.size()]
	var f := filter_edit.text.strip_edges().to_lower()
	var own_from := event_log.inherited.size()
	for i in event_log.events.size():
		var e: Dictionary = event_log.events[i]
		var about := str(e.entity)
		if timeline != null and "/" in about:
			about = "%s (%s)" % [timeline.name_of(about), about]
		var when := calendar.format_moment(int(e.day), int(e.time)) if calendar != null else "day %d" % e.day
		var cells := [str(e.id), "prep" if int(e.session) <= 0 else str(e.session), when, str(e.get("by", "")), _what(e), about]
		if f != "" and not " ".join(cells).to_lower().contains(f):
			continue
		var item := tree.create_item(root)
		for c in cells.size():
			item.set_text(c, cells[c])
		var muted := i < own_from or e.has("undoes") or event_log.is_undone(int(e.id))
		if muted:
			for c in cells.size():
				item.set_custom_color(c, Markdown.MUTED)
		if i < own_from:
			item.set_tooltip_text(0, "From the parent timeline, before the fork")
		elif event_log.is_undone(int(e.id)):
			item.set_tooltip_text(4, "Undone")
	var last := root.get_child(root.get_child_count() - 1) if root.get_child_count() > 0 else null
	if last != null:
		tree.scroll_to_item(last)


## A short text for an event: its type and the data that matters.
static func _what(e: Dictionary) -> String:
	var d: Dictionary = e.get("data", {})
	match str(e.type):
		"hp.changed":
			return "HP %+d → %d" % [int(d.get("delta", 0)), int(d.get("hp", 0))]
		"token.moved":
			return "moved to %s on %s" % [d.get("to", []), d.get("map", "")]
		"token.placed":
			return "placed at %s on %s" % [d.get("at", []), d.get("map", "")]
		"token.turned":
			return "turned %s on %s" % [str(d.get("facing", "")).to_upper(), d.get("map", "")]
		"sheet.changed":
			return "%s: %s → %s" % [d.get("path", ""), d.get("from"), d.get("to")]
		"dice.rolled":
			return "rolled %s: %s" % [d.get("roll", d.get("formula", "")), d.get("result", "")]
		"entity.created":
			return "created"
	return str(e.type)
