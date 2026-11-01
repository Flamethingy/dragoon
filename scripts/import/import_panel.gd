class_name ImportPanel
extends Control
## The Import window over the compendium (TASK-28): pick a PDF, image or link (or it comes from
## drag & drop), the target package (or a new world package) and start the import agent; the
## jobs with their progress log; Review opens the drafts (DraftReview). The API key and Python
## path are set here and kept in user:// only. Emits `changed` when entries were merged.

signal changed

const NEW_PACKAGE := "__new__"

var jobs: ImportJobs
var db: PackageDB  ## the book, for the editor's value tokens (optional)
var manager: PackageManager
var input_edit: LineEdit
var target_pick: OptionButton
var new_name: LineEdit
var key_edit: LineEdit
var python_edit: LineEdit
var job_list: ItemList
var log_view: TextEdit
var note: Label
var review: DraftReview

var _page: VBoxContainer
var _main: VBoxContainer
var _targets: Array = []  ## package ids in picker order (+ NEW_PACKAGE)
var _job_ids: Array = []
var _dirty := false
var _poll: Timer


func _init(packages_root := "") -> void:
	jobs = ImportJobs.new(packages_root)
	manager = PackageManager.new(jobs.packages_root)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UISkin.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(UISkin.WINE.darkened(0.5), 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var page := PanelContainer.new()
	page.theme_type_variation = UISkin.V_PAGE
	margin.add_child(page)
	_page = VBoxContainer.new()
	page.add_child(_page)
	_build_main()
	_poll = Timer.new()
	_poll.wait_time = 0.5
	_poll.timeout.connect(refresh_jobs)
	add_child(_poll)
	_poll.start()
	refresh_jobs()


func _build_main() -> void:
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 10)
	_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_child(_main)
	var head := HBoxContainer.new()
	_main.add_child(head)
	var title := Label.new()
	title.text = "Import (PDF, image or link)"
	title.theme_type_variation = UISkin.V_HEADING
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_button(head, "Close", "Close the import window", close)
	note = Label.new()
	note.theme_type_variation = UISkin.V_MUTED
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Drop a PDF or image on the window, or paste a link. The import agent turns it into drafts; nothing goes into a package until you accept it."
	_main.add_child(note)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	_main.add_child(grid)
	grid.add_child(_label("File or link"))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(row)
	input_edit = LineEdit.new()
	input_edit.name = "Input"
	input_edit.placeholder_text = "C:/Books/Bestiary.pdf or https://..."
	input_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input_edit)
	_button(row, "Browse...", "Pick a PDF or image", _browse)
	grid.add_child(_label("Into package"))
	var trow := HBoxContainer.new()
	grid.add_child(trow)
	target_pick = OptionButton.new()
	target_pick.name = "Target"
	target_pick.item_selected.connect(func(_i: int) -> void: new_name.visible = target_id() == NEW_PACKAGE)
	trow.add_child(target_pick)
	new_name = LineEdit.new()
	new_name.name = "NewName"
	new_name.placeholder_text = "Name of the new package"
	new_name.custom_minimum_size = Vector2(260, 0)
	trow.add_child(new_name)
	_fill_targets()
	grid.add_child(_label(""))
	_button(grid, "Start import", "Run the import agent on it", start).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var settings := HBoxContainer.new()
	settings.add_theme_constant_override("separation", 8)
	_main.add_child(settings)
	settings.add_child(_label("Anthropic API key"))
	key_edit = LineEdit.new()
	key_edit.name = "ApiKey"
	key_edit.secret = true
	key_edit.placeholder_text = "sk-ant-... (kept on this computer only)"
	key_edit.text = ImportJobs.setting("api_key")
	key_edit.custom_minimum_size = Vector2(300, 0)
	settings.add_child(key_edit)
	settings.add_child(_label("Python"))
	python_edit = LineEdit.new()
	python_edit.name = "Python"
	python_edit.text = ImportJobs.python()
	python_edit.custom_minimum_size = Vector2(180, 0)
	settings.add_child(python_edit)
	_button(settings, "Save settings", "Saved in this computer's user folder, never in packages or git", save_settings)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	split.add_child(left)
	left.add_child(_label("Import jobs"))
	job_list = ItemList.new()
	job_list.name = "Jobs"
	job_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	job_list.item_selected.connect(func(_i: int) -> void: _show_log())
	left.add_child(job_list)
	var jrow := HBoxContainer.new()
	left.add_child(jrow)
	_button(jrow, "Review drafts", "Check the results and merge them", func() -> void: open_review(selected_job())).name = "Review"
	_button(jrow, "Cancel job", "Stop the import agent", func() -> void:
		jobs.cancel(selected_job())
		refresh_jobs())
	log_view = TextEdit.new()
	log_view.name = "Log"
	log_view.editable = false
	log_view.add_theme_color_override("font_readonly_color", Color(0.24, 0.12, 0.13))
	log_view.add_theme_color_override("background_color", Color(1, 1, 1, 0.35))
	log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(log_view)


func _fill_targets() -> void:
	target_pick.clear()
	_targets = []
	for m: Dictionary in manager.list():
		target_pick.add_item("%s (%s)" % [m.get("name", m.id), m.get("kind", "source")])
		_targets.append(str(m.id))
	target_pick.add_item("New world package...")
	_targets.append(NEW_PACKAGE)
	target_pick.select(0)
	new_name.visible = _targets.size() == 1


func target_id() -> String:
	var i := target_pick.selected
	return _targets[i] if i >= 0 and i < _targets.size() else ""


func select_target(package_id: String) -> void:
	var i := _targets.find(package_id)
	if i >= 0:
		target_pick.select(i)
		new_name.visible = package_id == NEW_PACKAGE


func set_input(text: String) -> void:
	input_edit.text = text


func save_settings() -> void:
	ImportJobs.set_setting("api_key", key_edit.text.strip_edges())
	ImportJobs.set_setting("python", python_edit.text.strip_edges() if python_edit.text.strip_edges() != "" else "python")
	note.text = "Settings saved (on this computer only)."


## Starts the agent for the input and target; returns the job (or {error}).
func start() -> Dictionary:
	var input := input_edit.text.strip_edges()
	var target := target_id()
	if target == NEW_PACKAGE:
		if new_name.text.strip_edges() == "":
			note.text = "Give the new package a name."
			return {"error": "no name"}
		target = "new:" + new_name.text.strip_edges()
	if key_edit.text.strip_edges() != ImportJobs.setting("api_key"):
		save_settings()
	var job := jobs.start(input, target)
	if job.has("error") and not job.has("id"):
		note.text = str(job.error)
		return job
	note.text = "Import started: %s" % input.get_file() if str(job.get("status")) != "failed" else "Import failed: %s" % job.get("error", "")
	refresh_jobs()
	_select_job(str(job.id))
	return job


func refresh_jobs() -> void:
	if job_list == null or not _main.visible:
		return
	var keep := selected_job()
	var all := jobs.jobs()
	_job_ids = []
	job_list.clear()
	for j: Dictionary in all:
		var drafts := jobs.draft_entries(str(j.id)).size()
		job_list.add_item("%s  ·  %s%s" % [str(j.input).get_file() if str(j.kind) != "url" else str(j.input),
			j.status, "  ·  %d draft(s)" % drafts if drafts > 0 else ""])
		_job_ids.append(str(j.id))
	if keep != "":
		_select_job(keep)
	elif not _job_ids.is_empty():
		_select_job(_job_ids[0])


func _select_job(id: String) -> void:
	var i := _job_ids.find(id)
	if i >= 0:
		job_list.select(i)
		_show_log()


func selected_job() -> String:
	if job_list == null or not job_list.is_anything_selected():
		return ""
	var i: int = job_list.get_selected_items()[0]
	return _job_ids[i] if i < _job_ids.size() else ""


func _show_log() -> void:
	var s := jobs.status(selected_job())
	if s.is_empty():
		log_view.text = ""
		return
	var text := str(s.log)
	if s.has("error") and str(s.error) != "":
		text += "\n[%s] %s" % [s.status, s.error]
	if log_view.text != text:
		log_view.text = text
		log_view.scroll_vertical = log_view.get_line_count()


## The drafts of a job side by side with their source pages.
func open_review(job_id: String) -> DraftReview:
	var s := jobs.status(job_id)
	if s.is_empty():
		return null
	var target := jobs.target_store(str(s.target))
	if str(s.target).begins_with("new:") and target != null:
		# the new package exists now: later merges of this job go into it
		s.target = target.id
		s.erase("log")
		s.erase("running")
		EntryStore._write(jobs.job_dir(job_id).path_join("job.json"), s)
		manager.set_enabled(target.id, true)
		_dirty = true
	if jobs.drafts(job_id) == null:
		note.text = "This job has no drafts yet."
		return null
	_main.visible = false
	review = DraftReview.new()
	review.ask = ask
	review.db = db
	review.merged.connect(func(_e: Dictionary) -> void: _dirty = true)
	review.back_requested.connect(close_review)
	_page.add_child(review)
	review.setup(jobs, job_id, target)
	return review


func close_review() -> void:
	if review:
		review.queue_free()
		review = null
	_main.visible = true
	refresh_jobs()


func close() -> void:
	if _dirty:
		changed.emit()
	queue_free()


func _browse() -> void:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.title = "Import a PDF or image"
	d.filters = PackedStringArray(["*.pdf ; PDF", "*.png, *.jpg, *.jpeg, *.webp ; Images"])
	d.file_selected.connect(set_input)
	d.visibility_changed.connect(func() -> void:
		if not d.visible:
			d.queue_free.call_deferred())
	add_child(d)
	d.popup_centered_ratio(0.6)


## A small question in the window: buttons [[label, value]] plus Cancel (on_choice(null)).
func ask(title: String, text: String, buttons: Array, on_choice: Callable) -> void:
	var cover := Control.new()
	cover.name = "Question"
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(cover)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(center)
	var page := PanelContainer.new()
	page.theme_type_variation = UISkin.V_PAGE
	page.custom_minimum_size = Vector2(440, 0)
	center.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	page.add_child(col)
	var t := Label.new()
	t.text = title
	t.theme_type_variation = UISkin.V_HEADING
	col.add_child(t)
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(400, 0)
	col.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var answer := func(value: Variant) -> void:
		remove_child(cover)  # gone at once, so the next question can take its place
		cover.queue_free()
		on_choice.call(value)
	for b: Array in buttons:
		_button(row, str(b[0]), "", answer.bind(b[1])).name = "Choice_" + str(b[0]).validate_node_name()
	_button(row, "Cancel", "", answer.bind(null))


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _button(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and event.keycode == KEY_ESCAPE:
		if review:
			close_review()
		else:
			close()
		get_viewport().set_input_as_handled()
