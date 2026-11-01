class_name DraftReview
extends VBoxContainer
## Reviewing an import job's drafts (TASK-28): the drafts on the left, the selected one in the
## entry editor (saves go into the draft package only) and its source page on the right with
## a crop editor for the picture. Accept merges into the target package (same name there:
## replace / keep both / skip), Discard drops the draft, Accept all takes the rest.

signal merged(entry: Dictionary)  ## an entry reached the target package
signal back_requested

var jobs: ImportJobs
var job_id := ""
var target: EntryStore
var ask: Callable  ## (title, text, buttons [[label, value]], on_choice) from the import panel

var current := {}  ## {kind, entry} being reviewed
var list: ItemList
var editor: EntryEditor
var crop: CropView
var page_label: Label
var status: Label
var _items: Array = []  ## [{kind, entry}] in list order


func setup(import_jobs: ImportJobs, id: String, target_store: EntryStore) -> void:
	jobs = import_jobs
	job_id = id
	target = target_store
	add_theme_constant_override("separation", 8)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	_button(bar, "Back", "Back to the import jobs", func() -> void: back_requested.emit())
	var title := Label.new()
	title.theme_type_variation = UISkin.V_HEADING
	title.text = "Review → %s" % (target.name if target else "?")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	bar.add_child(title)
	_button(bar, "Accept", "Merge this entry into %s" % (target.name if target else "the package"), accept_current).name = "Accept"
	_button(bar, "Discard", "Drop this draft", discard_current).name = "Discard"
	_button(bar, "Accept all", "Merge every remaining draft (asks about duplicates)", accept_all).name = "AcceptAll"
	status = Label.new()
	status.theme_type_variation = UISkin.V_MUTED
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	list = ItemList.new()
	list.name = "Drafts"
	list.custom_minimum_size = Vector2(220, 0)
	list.item_selected.connect(func(i: int) -> void: select(i))
	split.add_child(list)
	var inner := HSplitContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(inner)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)
	editor = EntryEditor.new()
	editor.name = "DraftEditor"
	editor.cancelled.connect(func() -> void: select(list.get_selected_items()[0] if list.is_anything_selected() else 0))
	editor.deleted.connect(func() -> void: refresh())
	scroll.add_child(editor)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	inner.add_child(side)
	page_label = Label.new()
	page_label.theme_type_variation = UISkin.V_MUTED
	side.add_child(page_label)
	crop = CropView.new()
	crop.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(crop)
	_button(side, "Use selection as picture", "Crop the dragged box from the page into this entry's picture", apply_crop).name = "UseCrop"
	refresh()


func refresh(select_index := 0) -> void:
	_items = jobs.draft_entries(job_id)
	list.clear()
	for d: Dictionary in _items:
		var dup := target != null and not ImportJobs.duplicate_of(target, d.kind, d.entry).is_empty()
		list.add_item("%s · %s%s" % [str(d.kind).capitalize().trim_suffix("s"), d.entry.get("name", d.entry.id), "  (in package)" if dup else ""])
	if _items.is_empty():
		current = {}
		editor.visible = false
		crop.show_page(null, Rect2i())
		page_label.text = ""
		status.text = "No drafts left. Everything is reviewed."
		return
	select(clampi(select_index, 0, _items.size() - 1))


func select(i: int) -> void:
	if i < 0 or i >= _items.size():
		return
	list.select(i)
	current = _items[i]
	var store := jobs.drafts(job_id)
	var e: Dictionary = store.find(current.kind, str(current.entry.id))
	current.entry = e
	editor.visible = true
	editor.setup(store, current.kind, e)
	var origin: Dictionary = e.get("origin", {}) if e.get("origin") is Dictionary else {}
	page_label.text = "Source: %s%s" % [str(origin.get("file", origin.get("url", "?"))).get_file(),
		"  · page %d" % int(origin.page) if origin.has("page") else ""]
	var tex: Texture2D = null
	if str(e.get("source_page", "")) != "":
		var img := ImageCache.decode(FileAccess.get_file_as_bytes(store.folder.path_join(str(e.source_page))))
		if img:
			tex = ImageTexture.create_from_image(img)
	var c: Array = e.get("crop", []) if e.get("crop") is Array else []
	crop.show_page(tex, Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3])) if c.size() == 4 else Rect2i())
	status.text = "%d draft(s) left." % _items.size()


func apply_crop() -> void:
	if current.is_empty():
		return
	var r := jobs.crop(job_id, current.kind, str(current.entry.id), crop.selection)
	status.text = "Picture cropped from the page." if not r.is_empty() else "Drag a box on the page first."
	if not r.is_empty():
		select(list.get_selected_items()[0])


## Merges the current draft (after saving pending edits); asks about a duplicate name.
func accept_current() -> void:
	if current.is_empty():
		return
	if editor.visible and editor.save().is_empty():
		return  # the editor shows what's wrong
	var at := list.get_selected_items()[0]
	_accept(current.kind, str(current.entry.id), ImportJobs.ASK, func(_r: Dictionary) -> void: refresh(at))


func discard_current() -> void:
	if current.is_empty():
		return
	var at := list.get_selected_items()[0]
	jobs.discard(job_id, current.kind, str(current.entry.id))
	refresh(at)


## Accepts every remaining draft in order; duplicates are asked one by one.
func accept_all() -> void:
	_accept_next(jobs.draft_entries(job_id), 0)


func _accept_next(todo: Array, i: int) -> void:
	if i >= todo.size():
		refresh()
		return
	_accept(todo[i].kind, str(todo[i].entry.id), ImportJobs.ASK, func(r: Dictionary) -> void:
		if not r.has("cancelled"):
			_accept_next(todo, i + 1)
		else:
			refresh())


func _accept(kind: String, id: String, mode: String, done: Callable) -> void:
	var r := jobs.accept(job_id, kind, id, target, mode)
	if r.has("duplicate"):
		var draft_name := str(jobs.drafts(job_id).find(kind, id).get("name", id))
		ask.call("Already in %s" % target.name,
			"\"%s\" is already in %s.\nReplace it, keep both, or skip this draft?" % [draft_name, target.name],
			[["Replace", ImportJobs.REPLACE], ["Keep both", ImportJobs.KEEP_BOTH], ["Skip", ImportJobs.SKIP]],
			func(choice: Variant) -> void:
				if choice == null:
					done.call({"cancelled": true})
				else:
					_accept(kind, id, str(choice), done))
		return
	if r.has("merged"):
		status.text = "Added %s to %s." % [r.merged.get("name", id), target.name]
		merged.emit(r.merged)
	elif r.has("skipped"):
		status.text = "Skipped."
	elif r.has("error"):
		status.text = str(r.error)
	done.call(r)


func _button(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(action)
	parent.add_child(b)
	return b
