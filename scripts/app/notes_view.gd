class_name NotesView
extends PanelContainer
## The Notes view in a session (TASK-33): every session note of the timeline (the DM; read
## from its notes.json) or the notes this player got (players), grouped by session, newest
## session last. Writing a note stays in the table's notes panel.

var table: NetTable
var text: RichTextLabel
var heading: Label


func _ready() -> void:
	theme_type_variation = UISkin.V_PAGE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	heading = Label.new()
	heading.theme_type_variation = UISkin.V_HEADING
	col.add_child(heading)
	text = RichTextLabel.new()
	text.name = "Notes"
	text.bbcode_enabled = true
	text.selection_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.meta_clicked.connect(func(meta: Variant) -> void: RollTables.handle_meta(str(meta)))
	col.add_child(text)
	table.notes_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())
	refresh()


func refresh() -> void:
	if text == null:
		return
	var all: Array[Dictionary] = []
	if table.is_dm() and table.timeline != null:
		all = SessionNotes.read_all(table.timeline.folder.path_join(SessionNotes.FILE))
		heading.text = "Notes · %s" % table.timeline.info.get("name", "")
	else:
		all = table.notes.entries.duplicate()
		heading.text = "Notes"
	var muted := Markdown.MUTED.to_html(false)
	var parts := PackedStringArray()
	var session := -999
	for e in all:
		if int(e.session) != session:
			session = int(e.session)
			parts.append("[font_size=18][b]%s[/b][/font_size]" % ("Between sessions" if session <= 0 else "Session %d" % session))
		parts.append("[color=#%s][font_size=12]%s[/font_size][/color]\n%s" % [muted, Markdown.escape(table.notes.heading(e)), Markdown.to_bbcode(str(e.text))])
	text.text = "\n\n".join(parts) if not parts.is_empty() else "[color=#%s]No notes yet.[/color]" % muted
