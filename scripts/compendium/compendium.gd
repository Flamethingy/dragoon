class_name Compendium
extends Control
## Browser for the core data packages (TASK-15), styled as a card collection book:
## bookmark tabs per kind on the left, a binder page of cards (picture, badge, name) in
## the middle that flips page by page, and the open card on the right with its key facts.
## The full text (stat block, Markdown) is folded away under "Full text".
## [[Wikilinks]] in it open the entry they name; Back returns.
## Document tabs (TASK-22) above the binder: "Browse" is the binder itself; double-click,
## middle-click, "Open" or Ctrl+click on a link opens an entry in its own full-view tab
## (EntryView). Tabs close (x, middle-click, Ctrl+W), switch (Ctrl+Tab), reorder by drag,
## keep their scroll position and come back on the next start (tabs_file).
## Editing (TASK-21): "Edit" in a full view turns the tab into the EntryEditor; "New..." in
## Browse creates an entry in a world package (or a new one). Source packages stay
## read-only unless unlocked; the editor offers "edit a copy" in a world package.
## Packages load on a worker thread (PackageDB), so the window stays responsive.

signal token_changed(entry: Dictionary)  ## a token style was saved (TASK-41)
signal tabs_restored  ## the saved tabs are open again (after loading)
signal close_requested  ## the Close button (when shown over the table)

const SEARCH_DELAY := 0.15
const GRID_GAP := 14
const SORTS := ["Name", "CR / Level", "Type", "Package"]
const DETAIL_WIDTH := 430
const KIND_ICONS := {"monsters": "icon_sword", "spells": "star", "items": "icon_chest",
	"features": "icon_dagger", "classes": "icon_helmet", "races": "icon_armor"}

var db := PackageDB.new()
## Where the open tabs are kept between runs ("" = don't keep them).
var tabs_file := "user://compendium_tabs.json"
## The packages folder ("" = PackageDB.default_root()).
var packages_root := ""
## What this book is (TASK-39). Neither set: the compendium, the core books and source
## packages only (new entries go into a package). `world_dir`: a world's book (its NPCs,
## places, maps, ... over the core; new entries go into the world). `timeline_dir`: a
## timeline's book (its own entries over its world and the core; new ones go into the
## timeline). There is no picker: the app opens the book it needs.
var timeline_dir := ""
var world_dir := ""
## Shown over the table: a Close button.
var closable := false
var _scope_label: Label

var _status: Label
var _progress: ProgressBar
var _tabs: VBoxContainer
var _tab_group := ButtonGroup.new()
var _packages_button: Button  ## the one Packages entry, below the bookmarks (TASK-36)
var _package_tools: HBoxContainer  ## Import... / Import from link..., over the package cards
var _search: LineEdit
var _in_text: Button
var _package: OptionButton
var _level: OptionButton
var _type: OptionButton
var _sort: OptionButton
var _page_area: Control
var _grid: GridContainer
var _prev: TextureButton
var _next: TextureButton
var _page_label: Label
var _search_timer: Timer

var _detail_scroll: ScrollContainer
var _detail_box: VBoxContainer
var _back: Button

var _kind := ""
var _level_values: Array = []  ## option index - 1 -> value
var _type_values: Array = []
var _package_values: Array = []
var _matches: Array = []
var _page := 0
var _per_page := 12
var _columns := 4
var _current: Dictionary = {}
var _history: Array[Dictionary] = []

var _browse_button: Button
var _tab_bar: TabBar
var _views: Control  ## holds _browse and the EntryViews, one shown at a time
var _browse: Control
var _open_views := {}  ## key -> EntryView
var _saved_tabs: Variant = null  ## {tabs: [{key, scroll}], current} to restore after a load
var _restoring := false
## Back closes the tab it leaves (TASK-24, Nico's try-out setting; kept in tabs_file).
var back_closes_tab := true
var _tab_history: Array[String] = []  ## previously shown tabs ("" = Browse), newest last
var _last_key := ""
var _navigating := false  ## don't record history while going back
var _bg_after := ""  ## key of the last background tab (they line up after the current one)
var _bg_from := ""  ## the tab that was current when background opening started
var highlighted := {}  ## key -> msec when a tab was last highlighted (tests)
var _tab_menu: PopupMenu
var _hovered_meta := ""
## The timeline's log, if any: editor saves during a session become events.
var event_log: EventLog
var _stores := {}  ## package id -> EntryStore
## Packages as cards (TASK-23): every installed package (on or off) as an entry of kind
## "packages", with _enabled, _count, _counts (entries loaded per kind).
const PACKAGES := "packages"
const DRAFTS := "drafts"  ## the Drafts page (TASK-30)
const PARTS := ["features", "tables"]  ## published along with their entries
var show_drafts := false  ## "Show drafts" in the binder
var _show_drafts: CheckBox
var manager: PackageManager
var package_cards: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UISkin.theme()
	StatBlock.db = db
	_build()
	db.loaded.connect(_on_loaded)
	get_window().files_dropped.connect(_on_files_dropped)
	if packages_root == "":  # the real data folder: old campaigns become timelines (TASK-32)
		for line in Worlds.migrate_data(PackageDB.default_root().get_base_dir()):
			print("Migrated: ", line)
	if scope() != "core":
		tabs_file = ""  # only the compendium keeps its tabs between runs
	db.timeline_dir = timeline_dir
	db.world_filter = scope_world_id()
	db.include_core = scope() == "core"
	_scope_label.text = scope_title()
	_open_timeline_log()
	for pkg in ImportJobs.new(packages_root).merge_finished():  # imports finished while the book was closed
		PackageManager.new(packages_root).set_enabled(pkg, true)
	db.load_async(packages_root)


# --- Layout --------------------------------------------------------------------------

func _build() -> void:
	var cover := PanelContainer.new()
	cover.theme_type_variation = UISkin.V_COVER
	if scope() != "core":
		cover.add_theme_stylebox_override("panel", UISkin.cover_box(UISkin.FOREST))  # the world's book
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cover)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	cover.add_child(row)

	# Left: title and bookmark tabs on the cover.
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(190, 0)
	side.add_theme_constant_override("separation", 6)
	row.add_child(side)
	var title := Label.new()
	title.text = "Compendium" if scope() == "core" else "Book"  # the world's book (Nico, 2026-11-01)
	title.theme_type_variation = UISkin.V_PLATE_LABEL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scope_label = Label.new()
	_scope_label.name = "Scope"
	_scope_label.add_theme_color_override("font_color", UISkin.CREAM)
	_scope_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(title)
	side.add_child(_scope_label)
	_status = Label.new()
	_status.text = "Opening the book..."
	_status.add_theme_color_override("font_color", UISkin.TAN)
	_status.add_theme_font_size_override("font_size", 12)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_status)
	_progress = ProgressBar.new()
	_progress.indeterminate = true
	_progress.show_percentage = false
	side.add_child(_progress)
	var tabs_scroll := ScrollContainer.new()
	tabs_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(tabs_scroll)
	_tabs = VBoxContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_constant_override("separation", 6)
	tabs_scroll.add_child(_tabs)
	if closable:
		var close := Button.new()
		close.text = "Back to the table"
		close.pressed.connect(func() -> void: close_requested.emit())
		side.add_child(close)
	_packages_button = Button.new()
	_packages_button.name = "Packages"
	_packages_button.theme_type_variation = UISkin.V_TAB
	_packages_button.toggle_mode = true
	_packages_button.button_group = _tab_group
	_packages_button.text = "Packages"
	_packages_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_packages_button.icon = UISkin.tex("icon_chest")
	_packages_button.tooltip_text = "All packages as cards: import, export, switch on/off, unlock or remove them"
	_packages_button.pressed.connect(open_packages)
	side.add_child(_packages_button)

	# Right of the cover: the document tabs over the binder (Browse) or a full view.
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)
	row.add_child(main)
	main.add_child(_build_tab_row())
	_views = Control.new()
	_views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_views)
	_browse = HBoxContainer.new()
	_browse.add_theme_constant_override("separation", 12)
	_browse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_views.add_child(_browse)

	# Browse, middle: the binder page.
	var page := PanelContainer.new()
	page.theme_type_variation = UISkin.V_PAGE
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browse.add_child(page)
	var page_box := VBoxContainer.new()
	page_box.add_theme_constant_override("separation", 10)
	page.add_child(page_box)
	page_box.add_child(_build_filters())
	_page_area = Control.new()
	_page_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_area.clip_contents = true
	_page_area.resized.connect(_on_page_resized)
	page_box.add_child(_page_area)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_grid.add_theme_constant_override("v_separation", GRID_GAP)
	_page_area.add_child(_grid)
	page_box.add_child(_build_pager())

	# Right: the open card.
	var detail := PanelContainer.new()
	detail.theme_type_variation = UISkin.V_PAGE
	detail.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	_browse.add_child(detail)
	var detail_col := VBoxContainer.new()
	detail.add_child(detail_col)
	var detail_bar := HBoxContainer.new()
	detail_col.add_child(detail_bar)
	_back = Button.new()
	_back.text = "Back"
	_back.icon = _flipped(UISkin.tex("arrow_right"))
	_back.disabled = true
	_back.tooltip_text = "Back to the previous card (Alt+Left)"
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back.pressed.connect(_go_back)
	detail_bar.add_child(_back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_bar.add_child(spacer)
	var open := Button.new()
	open.text = "Open"
	open.tooltip_text = "Open this card in its own tab (double-click a card)"
	open.pressed.connect(func() -> void: open_tab(_current))
	detail_bar.add_child(open)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_col.add_child(_detail_scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 10)
	_detail_scroll.add_child(_detail_box)
	_placeholder()

	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DELAY
	_search_timer.timeout.connect(_refresh_list)
	add_child(_search_timer)


func _build_tab_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_browse_button = Button.new()
	_browse_button.text = "Browse"
	_browse_button.icon = UISkin.tex("icon_chest")
	_browse_button.add_theme_constant_override("icon_max_width", 18)
	_browse_button.toggle_mode = true
	_browse_button.button_pressed = true
	_browse_button.tooltip_text = "The card binder (Ctrl+Tab switches tabs)"
	_browse_button.pressed.connect(show_browse)
	row.add_child(_browse_button)
	_tab_bar = TabBar.new()
	_tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tab_bar.deselect_enabled = true
	_tab_bar.drag_to_rearrange_enabled = true
	_tab_bar.clip_tabs = true
	_tab_bar.max_tab_width = 240
	_tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	_tab_bar.add_theme_constant_override("icon_max_width", 18)
	_tab_bar.tab_changed.connect(_on_tab_changed)
	_tab_bar.tab_close_pressed.connect(close_tab)
	_tab_bar.active_tab_rearranged.connect(func(_to: int) -> void: _save_tabs())
	_tab_bar.gui_input.connect(_on_tab_bar_input)
	row.add_child(_tab_bar)
	return row


func _build_filters() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "Search... (Ctrl+F)"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _search_timer.start())
	_search.text_submitted.connect(func(_t: String) -> void: _open_first())
	row.add_child(_search)
	_in_text = Button.new()
	_in_text.text = "Text too"
	_in_text.toggle_mode = true
	_in_text.tooltip_text = "Also search descriptions and actions"
	_in_text.toggled.connect(func(_on: bool) -> void: _refresh_list())
	row.add_child(_in_text)
	_sort = _filter_button("Sort")
	for s in SORTS:
		_sort.add_item("Sort: " + s)
	_sort.size_flags_horizontal = Control.SIZE_SHRINK_END
	_sort.custom_minimum_size = Vector2(170, 0)
	row.add_child(_sort)
	_show_drafts = CheckBox.new()
	_show_drafts.name = "ShowDrafts"
	_show_drafts.text = "Show drafts"
	_show_drafts.tooltip_text = "Also show unfinished entries (marked Draft)"
	_show_drafts.toggled.connect(set_show_drafts)
	row.add_child(_show_drafts)
	var new := Button.new()
	new.text = "New..."
	new.tooltip_text = "Create an entry of the kind shown here (asks for the kind on the package and draft pages)"
	new.name = "NewEntry"
	new.pressed.connect(func() -> void: new_entry(_kind))
	row.add_child(new)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	box.add_child(filters)
	_package = _filter_button("Package")
	_level = _filter_button("CR / level")
	_type = _filter_button("Type")
	for b in [_package, _level, _type]:
		filters.add_child(b)
	_package_tools = HBoxContainer.new()
	_package_tools.name = "PackageTools"
	_package_tools.add_theme_constant_override("separation", 8)
	_package_tools.visible = false
	filters.add_child(_package_tools)
	var imp := Button.new()
	imp.name = "ImportPackage"
	imp.text = "Import..."
	imp.tooltip_text = "Install a package file (.%s)" % PackageManager.EXTENSION
	imp.pressed.connect(import_package_dialog)
	_package_tools.add_child(imp)
	var link := Button.new()
	link.name = "ImportLink"
	link.text = "Import from link..."
	link.tooltip_text = "Turn a PDF, image or web page into entries with the import agent"
	link.pressed.connect(func() -> void: open_import(""))
	_package_tools.add_child(link)
	return box


func _filter_button(tooltip: String) -> OptionButton:
	var b := OptionButton.new()
	b.tooltip_text = tooltip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.fit_to_longest_item = false
	b.clip_text = true
	b.item_selected.connect(func(_i: int) -> void: _refresh_list())
	return b


func _build_pager() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_prev = _arrow(true)
	_prev.pressed.connect(func() -> void: _flip(-1))
	row.add_child(_prev)
	_page_label = Label.new()
	_page_label.custom_minimum_size = Vector2(220, 0)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_page_label)
	_next = _arrow(false)
	_next.pressed.connect(func() -> void: _flip(1))
	row.add_child(_next)
	return row


func _arrow(back: bool) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = _flipped(UISkin.tex("arrow_right")) if back else UISkin.tex("arrow_right")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(32, 32)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "Previous page (Page Up)" if back else "Next page (Page Down)"
	return b


## A horizontally mirrored copy of a sprite (for the back arrows).
func _flipped(t: Texture2D) -> Texture2D:
	return flipped(t)


static func flipped(t: Texture2D) -> Texture2D:
	var img := t.get_image()
	img.flip_x()
	return ImageTexture.create_from_image(img)


# --- Loading and kinds -----------------------------------------------------------------

func _on_loaded() -> void:
	_progress.hide()
	_hook_tables()
	if _saved_tabs == null and tabs_file != "" and FileAccess.file_exists(tabs_file):
		_saved_tabs = JSON.parse_string(FileAccess.get_file_as_string(tabs_file))
	_stores.clear()
	_status.text = "%d cards from %d packages" % [db.count(), db.packages.size()]
	if not db.errors.is_empty():
		_status.text += "\n%d problems (see Output)" % db.errors.size()
		for e in db.errors:
			push_warning(e)
	_build_package_cards()
	_build_bookmarks()
	if _kind == PACKAGES:  # after switching a package on/off: stay on the packages
		_packages_button.button_pressed = true
		_select_kind(PACKAGES)
	elif _tabs.get_child_count() > 2:
		var kinds := db.kinds_with(show_drafts)
		var keep := kinds.find(_kind)  # after a reload, stay on the same kind
		var i := keep if keep >= 0 else 0
		(_tabs.get_child(i) as Button).button_pressed = true
		_select_kind(kinds[i])
	else:
		_matches = []
		_render_page()
	var saved: Variant = _saved_tabs
	_saved_tabs = {}
	_restore_tabs(saved)


## The bookmark tabs on the cover, one per kind (with counts).
func _build_bookmarks() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	for k in db.kinds_with(show_drafts):
		var tab := Button.new()
		tab.theme_type_variation = UISkin.V_TAB
		tab.toggle_mode = true
		tab.button_group = _tab_group
		tab.text = "%s  %d" % [k.capitalize(), db.list(k, show_drafts).size()]
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.pressed.connect(_select_kind.bind(k))
		tab.button_pressed = k == _kind
		_tabs.add_child(tab)
	_packages_button.text = "Packages  %d" % package_cards.size()
	_packages_button.set_pressed_no_signal(_kind == PACKAGES)
	var dr := Button.new()
	dr.name = "Bookmark_drafts"
	dr.theme_type_variation = UISkin.V_TAB
	dr.text = "Drafts  %d" % db.draft_count()
	dr.alignment = HORIZONTAL_ALIGNMENT_LEFT
	dr.tooltip_text = "Every unfinished entry, grouped by package"
	dr.pressed.connect(open_drafts)
	_tabs.add_child(dr)


## The package cards (TASK-23/36): everything about packages happens there; a card's full
## view has on/off, Export, Unlock and Remove.
func open_packages() -> void:
	_packages_button.button_pressed = true  # the bookmarks of the kinds let go (one group)
	_select_kind(PACKAGES)


## Import...: a .dragoonpkg file; shows what is in it, then installs it.
func import_package_dialog() -> FileDialog:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.title = "Import package"
	d.filters = PackedStringArray(["*.%s ; Dragoon package" % PackageManager.EXTENSION])
	d.file_selected.connect(func(path: String) -> void:
		confirm_import_package(path)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered_ratio(0.6)
	return d


## Asks how to install a package file (Install, or Replace / Keep both if it is there).
func confirm_import_package(path: String) -> ConfirmationDialog:
	var info := manager.inspect(path)
	if not info.ok:
		_status.text = "Can't import: %s" % info.error
		return null
	var m: Dictionary = info.manifest
	var d := ConfirmationDialog.new()
	d.name = "ImportPackageDialog"
	d.title = "Import package"
	d.dialog_text = "%s  v%s\n%s" % [m.get("name", m.id), m.get("version", "?"), PackageManager.counts_text(m.get("counts", {}))]
	var install := func(choice: int) -> void:
		var r := manager.install(path, choice)
		_status.text = "Installed %s" % r.id if r.ok else "Not installed: %s" % r.error
		d.queue_free()
		if r.ok:
			_reload()
	if info.exists:
		d.dialog_text += "\n\nA package with the id \"%s\" is already installed." % m.id
		d.ok_button_text = "Replace"
		d.add_button("Keep both", false, "keep")
		d.custom_action.connect(func(_a: StringName) -> void: install.call(PackageManager.Conflict.KEEP_BOTH))
		d.confirmed.connect(func() -> void: install.call(PackageManager.Conflict.REPLACE))
	else:
		d.ok_button_text = "Install"
		d.confirmed.connect(func() -> void: install.call(PackageManager.Conflict.CANCEL))
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()
	return d


## Remove...: asks, then moves the package to data/removed.
func remove_package_dialog(package_id: String) -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.name = "RemovePackageDialog"
	d.title = "Remove package"
	d.dialog_text = "Remove \"%s\"?\nIt is moved to data/removed, so it can be put back by hand." % db.package_name(package_id)
	d.ok_button_text = "Remove"
	d.confirmed.connect(func() -> void:
		remove_package(package_id)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()
	return d


func remove_package(package_id: String) -> Error:
	var err := manager.remove(package_id)
	_status.text = "Removed %s" % package_id if err == OK else "Can't remove: %s" % error_string(err)
	if err == OK:
		for k: String in _open_views.keys():
			if str(_open_views[k].entry.get("_package", _open_views[k].entry.get("id", ""))) == package_id:
				close_tab(_tab_index(k))
		_reload()
	return err


## Unlock: a source package becomes editable (its entries can be changed in place).
func unlock_package(package_id: String) -> void:
	var store := EntryStore.open(manager.folder_of(package_id))
	store.unlock()
	_status.text = "%s can be edited now" % db.package_name(package_id)
	_reload()


## The import window (TASK-28), with a dropped file or a link filled in.
func open_import(input := "") -> ImportPanel:
	var panel := ImportPanel.new(db.root)
	panel.name = "ImportPanel"
	panel.drafts_requested.connect(func() -> void: open_drafts.call_deferred())
	panel.changed.connect(_reload)
	add_child(panel)
	panel.set_input(input)
	var current_package := str(_current.get("_package", ""))
	if current_package != "":
		panel.select_target(current_package)
	return panel


## A PDF or image dropped on the window goes to the import window.
func _on_files_dropped(files: PackedStringArray) -> void:
	if not is_visible_in_tree():
		return
	for f in files:
		if ImportJobs.input_kind(f) in ["pdf", "image"]:
			var open := find_child("ImportPanel", false, false) as ImportPanel
			if open:
				open.set_input(f)
			else:
				open_import(f)
			return


## Reads the packages again (an entry was imported from outside, e.g. dropped on the map).
func reload() -> void:
	_stores.clear()
	_reload()


func _reload() -> void:
	_progress.show()
	_status.text = "Re-reading packages..."
	_current = {}
	_history.clear()
	_saved_tabs = _tabs_state()
	_restoring = true
	_close_all_tabs()
	_restoring = false
	db.load_async(db.root)


func _select_kind(kind: String) -> void:
	show_browse()
	_kind = kind
	var list: Array = list_of(kind)
	_package.visible = kind != PACKAGES
	_package_tools.visible = kind == PACKAGES
	var pkgs := {}
	for e: Dictionary in list:
		pkgs[e["_package"]] = pkgs.get(e["_package"], 0) + 1
	_package_values = pkgs.keys()
	_package_values.sort_custom(func(a: String, b: String) -> bool: return db.package_name(a).to_lower() < db.package_name(b).to_lower())
	_package.clear()
	_package.add_item("All packages")
	for p: String in _package_values:
		_package.add_item("%s (%d)" % [db.package_name(p), pkgs[p]])

	_level_values = _distinct(list, _level_of)
	_level_values.sort()
	_level.clear()
	_level.add_item("Any CR" if kind == "monsters" else "Any level")
	for v: Variant in _level_values:
		_level.add_item(("CR " + StatBlock.cr_text(v)) if kind == "monsters" else StatBlock.level_text(v))
	_level.visible = not _level_values.is_empty()

	_type_values = _distinct(list, _types_of)
	_type_values.sort_custom(func(a: String, b: String) -> bool: return a.to_lower() < b.to_lower())
	_type.clear()
	_type.add_item("Any school" if kind == "spells" else "Anything" if kind == PACKAGES else "Any type")
	for v: String in _type_values:
		_type.add_item(v)
	_type.visible = not _type_values.is_empty()
	_page = 0
	_refresh_list()


func _distinct(list: Array, getter: Callable) -> Array:
	var seen := {}
	for e: Dictionary in list:
		for v: Variant in getter.call(e):
			seen[v] = true
	return seen.keys()


func _level_of(e: Dictionary) -> Array:
	var v: Variant = e.get("cr") if e["_kind"] == "monsters" else e.get("level") if e["_kind"] == "spells" else null
	return [] if v == null else [float(v)]


func _types_of(e: Dictionary) -> Array:
	if e["_kind"] == PACKAGES:  # one filter for kind, on/off and PDFs
		var out := ["World" if str(e.get("kind", "")) == "world" else "Source", "On" if e._enabled else "Off"]
		if e.get("documents") is Array and not e.documents.is_empty():
			out.append("Has PDFs")
		return out
	var v: Variant = e.get("school") if e["_kind"] == "spells" else e.get("type")
	if v is Array:
		return v.map(func(x: Variant) -> String: return str(x).strip_edges()).filter(func(s: String) -> bool: return s != "")
	var s := str(v).strip_edges() if v != null else ""
	return [s] if s != "" else []


# --- Matching and pages ----------------------------------------------------------------

func _refresh_list() -> void:
	if not db.is_loaded:
		return
	var query := _search.text.strip_edges().to_lower()
	var in_text := _in_text.button_pressed
	var pkg: String = _package_values[_package.selected - 1] if _package.selected > 0 else ""
	var level: Variant = _level_values[_level.selected - 1] if _level.visible and _level.selected > 0 else null
	var type: String = _type_values[_type.selected - 1] if _type.visible and _type.selected > 0 else ""
	_matches = []
	for e: Dictionary in list_of(_kind):
		if pkg != "" and e["_package"] != pkg:
			continue
		if level != null and _level_of(e) != [level]:
			continue
		if type != "" and type not in _types_of(e):
			continue
		if query != "" and not e["_key"].contains(query):
			if not (in_text or _kind == PACKAGES) or not _text_of(e).contains(query):
				continue
		_matches.append(e)
	_sort_matches()
	_page = 0
	_render_page()


func _text_of(e: Dictionary) -> String:
	if not e.has("_text"):
		var parts := PackedStringArray([str(e.get("description", ""))])
		parts.append(str(e.get("text", "")))
		for k in PackageDB.FEATURE_LISTS:
			for f: Dictionary in db.features_of(e, k):
				parts.append(str(f.get("name", "")) + " " + str(f.get("text", "")))
		e["_text"] = "\n".join(parts).to_lower()
	return e["_text"]


func _sort_matches() -> void:
	var col := _sort.selected
	var key := func(e: Dictionary) -> Variant:
		match col:
			1:
				var lv := _level_of(e)
				return -1.0 if lv.is_empty() else lv[0]
			2:
				return ", ".join(PackedStringArray(_types_of(e))).to_lower()
			3:
				return str(e["_package_name"]).to_lower()
		return e["_key"]
	_matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka: Variant = key.call(a)
		var kb: Variant = key.call(b)
		return a["_key"] < b["_key"] if ka == kb else ka < kb)


## How many cards fit: recompute the grid when the page area changes size.
func _on_page_resized() -> void:
	var area := _page_area.size
	var cols := maxi(1, int((area.x + GRID_GAP) / (EntryCard.SIZE.x + GRID_GAP)))
	var rows := maxi(1, int((area.y + GRID_GAP) / (EntryCard.SIZE.y + GRID_GAP)))
	if cols * rows == _per_page and cols == _columns:
		_center_grid()
		return
	var first := _page * _per_page
	_columns = cols
	_per_page = cols * rows
	_page = first / _per_page
	_render_page()


func _center_grid() -> void:
	var w := _columns * EntryCard.SIZE.x + (_columns - 1) * GRID_GAP
	_grid.position = Vector2(maxf(0.0, (_page_area.size.x - w) * 0.5), 0)


func _pages() -> int:
	return maxi(1, ceili(float(_matches.size()) / _per_page))


func _flip(by: int) -> void:
	var to := clampi(_page + by, 0, _pages() - 1)
	if to != _page:
		_page = to
		_render_page()


func _render_page() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_grid.columns = _columns
	var from := _page * _per_page
	for i in range(from, mini(from + _per_page, _matches.size())):
		var card := EntryCard.new()
		card.setup(_matches[i])
		card.selected = _matches[i] == _current
		card.pressed.connect(_show)
		card.open_requested.connect(open_tab)
		card.background_requested.connect(func(entry: Dictionary) -> void: open_tab(entry, true))
		card.package_toggled.connect(func(entry: Dictionary, on: bool) -> void: set_package_enabled(str(entry.id), on))
		_grid.add_child(card)
	_center_grid()
	_prev.disabled = _page == 0
	_next.disabled = _page >= _pages() - 1
	_prev.modulate.a = 0.3 if _prev.disabled else 1.0
	_next.modulate.a = 0.3 if _next.disabled else 1.0
	var total: int = list_of(_kind).size()
	if _matches.is_empty():
		_page_label.text = "No cards match" if total > 0 else ""
	else:
		_page_label.text = "Page %d / %d  ·  %d cards" % [_page + 1, _pages(), _matches.size()]


func _open_first() -> void:
	if not _matches.is_empty():
		_show(_matches[_page * _per_page] if _page * _per_page < _matches.size() else _matches[0])


# --- The open card ---------------------------------------------------------------------

func _placeholder() -> void:
	var hint := Label.new()
	hint.text = "Pick a card to open it."
	hint.theme_type_variation = UISkin.V_MUTED
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_box.add_child(hint)


func _show(e: Dictionary, remember := true) -> void:
	if e.is_empty() or e == _current:
		return
	if remember and not _current.is_empty():
		_history.append(_current)
	_current = e
	_back.disabled = _history.is_empty()
	for card: EntryCard in _grid.get_children():
		card.selected = card.entry == e
	_build_detail(e)
	_detail_scroll.scroll_vertical = 0


func _build_detail(e: Dictionary) -> void:
	for c in _detail_box.get_children():
		_detail_box.remove_child(c)
		c.queue_free()

	# Title plate with the name and subtitle.
	var plate := PanelContainer.new()
	plate.theme_type_variation = UISkin.V_PLATE
	_detail_box.add_child(plate)
	var plate_box := VBoxContainer.new()
	plate_box.add_theme_constant_override("separation", 0)
	plate.add_child(plate_box)
	var name := Label.new()
	name.theme_type_variation = UISkin.V_PLATE_LABEL
	name.text = str(e.get("name", "?"))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plate_box.add_child(name)
	var sub := Label.new()
	sub.text = CardData.subtitle(e)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", UISkin.TAN)
	sub.add_theme_font_size_override("font_size", 13)
	plate_box.add_child(sub)

	# The picture in a framed card.
	var frame := PanelContainer.new()
	frame.theme_type_variation = UISkin.V_CARD
	_detail_box.add_child(frame)
	var art := CardArt.new()
	art.custom_minimum_size = Vector2(0, 250)
	art.show_entry(e)
	frame.add_child(art)
	var b := CardData.badge(e)
	if not b.is_empty():
		var hex := UISkin.hex_badge(b[0], b[1], 15)
		hex.tooltip_text = CardData.badge_label(e)
		hex.position = Vector2(-2, -2)
		hex.scale = Vector2(1.3, 1.3)
		art.add_child(hex)

	# Tags (concentration, ritual).
	var tags := CardData.tags(e)
	if not tags.is_empty():
		var tag_row := HFlowContainer.new()
		tag_row.add_theme_constant_override("h_separation", 6)
		for t in tags:
			tag_row.add_child(_chip("", "", t))
		_detail_box.add_child(tag_row)

	# Stat chips.
	var chips := CardData.chips(e)
	if not chips.is_empty():
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for c: Array in chips:
			var chip := _chip(c[0], c[1], c[2])
			chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(chip)
		_detail_box.add_child(grid)

	# Ability scores as hexes.
	if e.get("_kind") == "monsters" and e.get("stats") is Dictionary:
		var abilities := HBoxContainer.new()
		abilities.alignment = BoxContainer.ALIGNMENT_CENTER
		abilities.add_theme_constant_override("separation", 4)
		for a in StatBlock.ABILITIES:
			var score := int(e.stats.get(a, 10))
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 0)
			var label := Label.new()
			label.text = a.to_upper()
			label.theme_type_variation = UISkin.V_MUTED
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(label)
			var hex := UISkin.hex_badge(str(score), "cream", 15)
			hex.tooltip_text = "%s %d (%s)" % [a.to_upper(), score, StatBlock._signed(floori((score - 10) / 2.0))]
			col.add_child(hex)
			var mod := Label.new()
			mod.text = StatBlock._signed(floori((score - 10) / 2.0))
			mod.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mod.add_theme_font_size_override("font_size", 13)
			col.add_child(mod)
			abilities.add_child(col)
		_detail_box.add_child(abilities)

	var source := Label.new()
	source.theme_type_variation = UISkin.V_MUTED
	source.text = "From " + str(e.get("_package_name", ""))
	source.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_box.add_child(source)

	# The full text, always shown (TASK-24); the column scrolls.
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.selection_enabled = true
	text.meta_underlined = false
	text.add_theme_constant_override("paragraph_separation", 4)
	text.meta_clicked.connect(_on_meta)
	text.meta_hover_started.connect(func(meta: Variant) -> void: _hovered_meta = str(meta))
	text.meta_hover_ended.connect(func(_meta: Variant) -> void: _hovered_meta = "")
	text.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE and _hovered_meta != "":
			_follow(_hovered_meta, _current, true, true)
			text.accept_event())
	text.text = StatBlock.to_bbcode(e)
	_detail_box.add_child(text)


## A rounded paper chip: optional icon, small label, value.
func _chip(icon_name: String, label: String, value: String) -> Control:
	return chip(icon_name, label, value)


static func chip(icon_name: String, label: String, value: String) -> Control:
	var chip := PanelContainer.new()
	chip.theme_type_variation = UISkin.V_CHIP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	chip.add_child(row)
	if icon_name != "":
		row.add_child(UISkin.icon(icon_name, Color.WHITE if icon_name in ["coin_gold", "gem"] else Color(0.55, 0.3, 0.35), 20))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	if label != "":
		var l := Label.new()
		l.text = label
		l.theme_type_variation = UISkin.V_MUTED
		l.add_theme_font_size_override("font_size", 11)
		col.add_child(l)
	var v := Label.new()
	v.text = value
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_theme_font_size_override("font_size", 15)
	col.add_child(v)
	return chip


func _go_back() -> void:
	if _history.is_empty():
		return
	_show(_history.pop_back(), false)
	_back.disabled = _history.is_empty()


## A link in the quick card: opens there, or in a new tab with Ctrl.
func _on_meta(meta: Variant) -> void:
	_follow(str(meta), _current, Input.is_key_pressed(KEY_CTRL))


## Follows a link from `from`: entry:/wiki: links open the entry (quick card or new tab),
## web links the browser.
func _follow(link: String, from: Dictionary, in_tab: bool, background := false) -> void:
	if RollTables.handle_meta(link):
		return
	if link.begins_with("pdf:"):
		var rest := link.substr(4)
		open_document(rest.get_slice("/", 0), rest.substr(rest.find("/") + 1).uri_decode())
		return
	if link.begins_with("pkgkind:"):
		var rest := link.substr(8)
		browse_package(rest.get_slice("/", 0), rest.get_slice("/", 1))
		return
	var e := {}
	if link.begins_with("entry:"):
		var parts := link.substr(6).split("/")
		if parts.size() == 3:
			e = db.get_entry(parts[0], parts[1], parts[2])
	elif link.begins_with(Markdown.WIKI):
		var target := link.substr(Markdown.WIKI.length()).get_slice("#", 0)
		if target == "":
			return
		e = db.resolve(target, str(from.get("_package", "")))
		if e.is_empty():
			_status.text = "No card named \"%s\"" % target
			return
	elif link.begins_with("https://") or link.begins_with("http://"):
		OS.shell_open(link)
		return
	if e.is_empty():
		return
	if background:
		open_tab(e, true)
	elif in_tab:
		open_tab(e)
	else:
		_show(e)


# --- Document tabs (TASK-22) ------------------------------------------------------------

## Opens an entry in its own full-view tab, or focuses the tab it already has.
## `background` (middle-click): the tab opens right after the current one (several in a row
## line up in order) and is only highlighted, the current tab stays (TASK-24).
func open_tab(e: Dictionary, background := false) -> EntryView:
	if e.is_empty():
		return null
	var key := EntryView.key_of(e)
	if _open_views.has(key):
		if background:
			_highlight(key)
		else:
			_tab_bar.current_tab = _tab_index(key)
			_on_tab_changed(_tab_bar.current_tab)
		return _open_views[key]
	var view := EntryView.new()
	view.book = self
	view.setup(e)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.hide()
	view.link_clicked.connect(func(link: String) -> void: _follow(link, view.entry, true))
	view.link_background.connect(func(link: String) -> void: _follow(link, view.entry, true, true))
	view.back_requested.connect(go_back_tab)
	view.send_requested.connect(func(entry: Dictionary) -> void: promote_to_world(entry))
	view.edit_requested.connect(func(_e: Dictionary) -> void: start_edit(view))
	view.token_requested.connect(func(_e: Dictionary) -> void: open_token_editor(view))
	_views.add_child(view)
	_open_views[key] = view
	_tab_bar.add_tab(str(e.get("name", "?")), UISkin.tex(KIND_ICONS.get(e.get("_kind"), "dot_wine")))
	var i := _tab_bar.tab_count - 1
	_tab_bar.set_tab_metadata(i, key)
	_tab_bar.set_tab_tooltip(i, "%s\n%s · %s" % [e.get("name", "?"), CardData.subtitle(e), e.get("_package_name", "")])
	if background:
		var cur := current_tab_key()
		if _bg_from != cur or _tab_index(_bg_after) < 0:
			_bg_from = cur
			_bg_after = cur
		var to := _tab_index(_bg_after) + 1  # Browse ("" -> -1): to the front
		var keep := _tab_bar.current_tab
		_navigating = true
		_tab_bar.move_tab(i, to)
		_tab_bar.current_tab = _tab_index(cur) if cur != "" else -1
		_navigating = false
		if keep != _tab_bar.current_tab or cur == "":
			_on_tab_changed(_tab_bar.current_tab)
		_bg_after = key
		_highlight(key)
		_save_tabs()
		return view
	_tab_bar.current_tab = i
	_on_tab_changed(i)  # tab_changed isn't sent when the first tab is selected on its own
	return view


## A short highlight on a tab: a star before its title for a moment.
func _highlight(key: String) -> void:
	highlighted[key] = Time.get_ticks_msec()
	var i := _tab_index(key)
	if i < 0:
		return
	var title := _tab_bar.get_tab_title(i).trim_prefix("✦ ")
	_tab_bar.set_tab_title(i, "✦ " + title)
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		var j := _tab_index(key)
		if j >= 0:
			_tab_bar.set_tab_title(j, _tab_bar.get_tab_title(j).trim_prefix("✦ ")))


func close_tab(index: int) -> void:
	if index < 0 or index >= _tab_bar.tab_count:
		return
	var key: String = _tab_bar.get_tab_metadata(index)
	var view: EntryView = _open_views.get(key)
	_open_views.erase(key)
	if view:
		_views.remove_child(view)
		view.queue_free()
	_tab_bar.remove_tab(index)
	_on_tab_changed(_tab_bar.current_tab)


func show_browse() -> void:
	if _tab_bar == null:
		return
	if _tab_bar.current_tab != -1:
		_tab_bar.current_tab = -1
	_on_tab_changed(-1)


## Key of the shown tab ("" = Browse).
func current_tab_key() -> String:
	var i := _tab_bar.current_tab
	return str(_tab_bar.get_tab_metadata(i)) if i >= 0 and i < _tab_bar.tab_count else ""


## Keys of the open tabs in tab order.
func tab_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for i in _tab_bar.tab_count:
		out.append(str(_tab_bar.get_tab_metadata(i)))
	return out


func open_view(key: String) -> EntryView:
	return _open_views.get(key)


func _tab_index(key: String) -> int:
	for i in _tab_bar.tab_count:
		if _tab_bar.get_tab_metadata(i) == key:
			return i
	return -1


func _on_tab_changed(_index: int) -> void:
	var key := current_tab_key()
	if key != _last_key:
		if not _navigating and not _restoring:
			_tab_history.append(_last_key)
			if _tab_history.size() > 100:
				_tab_history.pop_front()
		_last_key = key
	for k: String in _open_views:
		_open_views[k].back_button.disabled = _back_target(k) == null
		_open_views[k].send_button.visible = timeline_dir != "" and _open_views[k].entry.get("_layer") == "timeline" \
			and _open_views[k].entry.get("_kind") not in [PACKAGES, DRAFTS]
	_browse.visible = key == ""
	_browse_button.set_pressed_no_signal(key == "")
	for k: String in _open_views:
		_open_views[k].visible = k == key
	_save_tabs()


## The tab Back goes to from `from`: the newest earlier tab that is still open (or Browse);
## null if there is none.
func _back_target(from: String) -> Variant:
	for i in range(_tab_history.size() - 1, -1, -1):
		var k: String = _tab_history[i]
		if k != from and (k == "" or _open_views.has(k)):
			return k
	return null


## Back (arrow, Alt+Left, mouse back button): to the previously shown tab, closing the one
## left if back_closes_tab. Nothing on Browse.
func go_back_tab() -> void:
	var from := current_tab_key()
	if from == "":
		return
	var target: Variant = _back_target(from)
	if target == null:
		return
	while not _tab_history.is_empty():  # drop the history up to the target
		if _tab_history.pop_back() == target:
			break
	_navigating = true
	if back_closes_tab:
		close_tab(_tab_index(from))
	if target == "":
		show_browse()
	else:
		_tab_bar.current_tab = _tab_index(target)
		_on_tab_changed(_tab_bar.current_tab)
	_navigating = false


## Right-click on a tab: Close / Close all / to the left / to the right, and the setting.
func open_tab_menu(index: int, at := Vector2.ZERO) -> PopupMenu:
	if _tab_menu == null:
		_tab_menu = PopupMenu.new()
		_tab_menu.id_pressed.connect(func(id: int) -> void: _on_tab_menu(id, int(_tab_menu.get_meta("tab", -1))))
		add_child(_tab_menu)
	_tab_menu.clear()
	_tab_menu.add_item("Close", 0)
	_tab_menu.add_item("Close all tabs", 1)
	_tab_menu.add_item("Close tabs to the left", 2)
	_tab_menu.add_item("Close tabs to the right", 3)
	_tab_menu.add_separator()
	_tab_menu.add_check_item("Back closes the tab", 4)
	_tab_menu.set_item_checked(_tab_menu.get_item_index(4), back_closes_tab)
	_tab_menu.set_item_disabled(_tab_menu.get_item_index(2), index <= 0)
	_tab_menu.set_item_disabled(_tab_menu.get_item_index(3), index >= _tab_bar.tab_count - 1)
	_tab_menu.set_meta("tab", index)
	_tab_menu.reset_size()
	_tab_menu.popup(Rect2i(Vector2i(at if at != Vector2.ZERO else get_global_mouse_position()), Vector2i.ZERO))
	return _tab_menu


func _on_tab_menu(id: int, index: int) -> void:
	var key := str(_tab_bar.get_tab_metadata(index)) if index >= 0 and index < _tab_bar.tab_count else ""
	match id:
		0:
			close_tab(index)
		1:
			_close_all_tabs()
		2:
			for i in range(index - 1, -1, -1):
				close_tab(i)
		3:
			for i in range(_tab_bar.tab_count - 1, index, -1):
				close_tab(i)
		4:
			back_closes_tab = not back_closes_tab
			_save_tabs()
	if id in [2, 3] and key != "" and current_tab_key() == "":
		_tab_bar.current_tab = _tab_index(key)
		_on_tab_changed(_tab_bar.current_tab)


## Ctrl+Tab / Ctrl+Shift+Tab: Browse, then the tabs in order, round.
func _cycle_tab(by: int) -> void:
	var count := _tab_bar.tab_count + 1  # + Browse
	var to := posmod(_tab_bar.current_tab + 1 + by, count) - 1
	if to < 0:
		show_browse()
	else:
		_tab_bar.current_tab = to
		_on_tab_changed(to)


func _on_tab_bar_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var i := _tab_bar.get_tab_idx_at_point(event.position)
	if i < 0:
		return
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		close_tab(i)
		_tab_bar.accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		open_tab_menu(i)
		_tab_bar.accept_event()


func _tabs_state() -> Dictionary:
	var list := []
	for key in tab_keys():
		list.append({"key": key, "scroll": _open_views[key].scroll_vertical})
	return {"tabs": list, "current": current_tab_key(), "back_closes_tab": back_closes_tab}


func _save_tabs() -> void:
	if tabs_file == "" or _restoring or _tab_bar == null:
		return
	var f := FileAccess.open(tabs_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_tabs_state(), "  "))


## Reopens saved tabs (after a start or a reload); entries that are gone are skipped.
func _restore_tabs(state: Variant) -> void:
	if not state is Dictionary or state.is_empty():
		return
	_restoring = true
	back_closes_tab = bool(state.get("back_closes_tab", true))
	var scrolls := {}
	for t: Variant in state.get("tabs", []):
		if not t is Dictionary:
			continue
		var parts := str(t.get("key", "")).split("/")
		if parts.size() != 3:
			continue
		var view := open_tab(entry_for(parts[0], parts[1], parts[2]))
		if view:
			scrolls[view] = int(t.get("scroll", 0))
	var current := str(state.get("current", ""))
	if _open_views.has(current):
		_tab_bar.current_tab = _tab_index(current)
		_on_tab_changed(_tab_bar.current_tab)
	else:
		show_browse()
	# Scroll once the views have their size (texts lay out over a frame or two).
	for i in 3:
		if not is_inside_tree():  # the book was put away meanwhile (its window closed)
			_restoring = false
			return
		await get_tree().process_frame
	for view: Variant in scrolls:  # a quick second reload may have closed them already
		if is_instance_valid(view):
			(view as EntryView).scroll_vertical = scrolls[view]
	_restoring = false
	_save_tabs()
	tabs_restored.emit()


# --- Timeline (TASK-6, TASK-32) ---------------------------------------------------------------

## Dropping an entry from another book (TASK-37): it is imported after a dialog that lists
## what comes along (the entry and the features it needs). Into the world's book: copied
## into the world; into a timeline's book: the timeline's own (entity.created); into the
## compendium (core): a world's or timeline's own entry goes into a homebrew package.
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not EntryDrag.is_entry(data):
		return false
	var e := EntryDrag.entry_of(data)
	if str(e.get("_kind", "")) in [PACKAGES, DRAFTS, ""]:
		return false
	if scope() == "core":
		return str(e.get("_layer", "core")) != "core"
	return str(e.get("_layer", "")) != scope()


func _drop_data(_at: Vector2, data: Variant) -> void:
	confirm_import(EntryDrag.entry_of(data))


## Where an import goes: the world / timeline, or in the compendium the first homebrew
## package (null: a new "Homebrew" package is made on import).
func import_target() -> EntryStore:
	var stores := writable_stores()
	return stores[0] if not stores.is_empty() else null


## What importing `e` brings along: [{kind, id, name, there}], the entry first, then the
## features its lists use; `there` = the target has it already.
func import_list(e: Dictionary) -> Array:
	var kind := str(e.get("_kind", ""))
	var target := import_target()
	var out := [{"kind": kind, "id": str(e.get("id", "")), "name": str(e.get("name", "?")),
		"there": target != null and _has_import(target, kind, e)}]
	if kind == "monsters":
		var from := EntryStore.open(str(e.get("_dir", "")))
		for key: String in PackageDB.FEATURE_LISTS:
			var ids: Array = e.get(key, []) if e.get(key) is Array else []
			for fid: Variant in ids:
				var f := from.find("features", str(fid))
				if f.is_empty() or out.any(func(o: Dictionary) -> bool: return o.kind == "features" and o.id == str(fid)):
					continue
				out.append({"kind": "features", "id": str(fid), "name": str(f.get("name", fid)),
					"there": target != null and target.has("features", str(fid))})
	return out


## The target has this entry already: a copy of it (origin) or the same entry.
static func _has_import(target: EntryStore, kind: String, e: Dictionary) -> bool:
	for m: Dictionary in target.list(kind):
		var o: Variant = m.get("origin")
		if o is Dictionary and str(o.get("id", "")) == str(e.get("id", "")) and str(o.get("package", "")) == str(e.get("_package", "")):
			return true
	return false


## The import dialog: the list of what comes along, Import / Cancel.
func confirm_import(e: Dictionary) -> ConfirmationDialog:
	var target := import_target()
	var where := 'a new package "Homebrew"'
	if target != null:
		where = str(target.manifest.get("name", target.id))
	var d := ConfirmationDialog.new()
	d.name = "ImportDialog"
	d.theme = UISkin.theme()
	d.title = "Import"
	d.ok_button_text = "Import"
	var col := VBoxContainer.new()
	d.add_child(col)
	var head := Label.new()
	head.text = "Import into %s:" % where
	col.add_child(head)
	var list := ItemList.new()
	list.name = "ImportList"
	list.custom_minimum_size = Vector2(440, 220)
	for item: Dictionary in import_list(e):
		var line := "%s  (%s)" % [item.name, str(item.kind).capitalize().trim_suffix("s")]
		if item.there:
			line += "  - already there" if item.kind == "features" else "  - already there, imported again as a copy"
		list.add_item(line)
	col.add_child(list)
	d.confirmed.connect(func() -> void:
		import_entry(e)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()
	return d


## Imports an entry with its features (see confirm_import). Returns the new entry.
func import_entry(e: Dictionary) -> Dictionary:
	if scope() != "core":
		return take_entry(e)
	var target := import_target()
	if target == null:
		target = new_package("Homebrew")
	var made := target.copy_entry(EntryStore.open(str(e.get("_dir", ""))), str(e.get("_kind", "")), str(e.get("id", "")))
	if not made.is_empty():
		_status.text = "%s is in %s now" % [made.get("name", "?"), target.manifest.get("name", target.id)]
		_stores.clear()
		_reload()
	return made


## While an entry this book can take is dragged, a drop zone covers the book (its cards
## would otherwise catch the drop); it goes away when the drag ends.
func _drop_zone(on: bool) -> void:
	var zone := get_node_or_null("DropZone") as Label
	if not on:
		if zone != null:
			zone.queue_free()
		return
	if zone == null:
		zone = Label.new()
		zone.name = "DropZone"
		zone.text = "Drop here to import it into the %s" % ("compendium" if scope() == "core" else scope())
		zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		zone.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		zone.add_theme_color_override("font_color", UISkin.CREAM)
		zone.add_theme_font_size_override("font_size", 22)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(UISkin.WINE, 0.55)
		zone.add_theme_stylebox_override("normal", bg)
		zone.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		zone.mouse_filter = Control.MOUSE_FILTER_STOP
		zone.set_drag_forwarding(Callable(), _can_drop_data, _drop_data)
		add_child(zone)


## Makes a dropped entry this book's own. Returns the new entry ({} if not).
func take_entry(e: Dictionary) -> Dictionary:
	var kind := str(e.get("_kind", ""))
	var made := {}
	if scope() == "timeline":
		var store := timeline_store()
		if store != null:
			if event_log != null:
				store.timeline.events_log = event_log  # in a session: the table's live log
			made = store.timeline.add_entry(kind, e, str(e.get("_dir", "")))
	elif scope() == "world":
		var target: EntryStore = writable_stores()[0]
		made = target.copy_entry(EntryStore.open(str(e.get("_dir", ""))), kind, str(e.get("id", "")))
	if not made.is_empty():
		_status.text = "%s is in the %s now" % [made.get("name", "?"), scope()]
		_stores.clear()
		_reload()
	return made


## "core", "world" or "timeline" (see timeline_dir / world_dir).
func scope() -> String:
	return "timeline" if timeline_dir != "" else "world" if world_dir != "" else "core"


## The world packages the book reads: none for the core book, else its world.
func scope_world_id() -> String:
	if timeline_dir != "" and Timeline.is_timeline(timeline_dir):
		return Timeline.new(timeline_dir).world_id()
	if world_dir != "":
		return str(EntryStore.open(world_dir).id)
	return ""


func scope_title() -> String:
	match scope():
		"timeline":
			var tl := Timeline.new(timeline_dir)
			return "Timeline: %s" % tl.info.get("name", tl.id())
		"world":
			return "World: %s" % EntryStore.open(world_dir).name
	return "Books and source packages"


func timeline_store() -> EntryStore:
	if timeline_dir == "":
		return null
	for p in db.packages:
		if p.get("_layer") == "timeline":
			return store_for({"_package": p.get("id", ""), "_dir": timeline_dir})
	return EntryStore.open(timeline_dir)


## Merges an entry made in the timeline into its world (timelines.md "Promote"): same ref
## and id, so every timeline can use it. Re-reads the book and opens the world entry.
func promote_to_world(e: Dictionary) -> Dictionary:
	var store := timeline_store()
	if store == null or str(e.get("_layer", "")) != "timeline":
		return {}
	var ref := "%s/%s" % [e.get("_kind", ""), e.get("id", "")]
	var r := store.timeline.promote(ref)
	if r.has("error"):
		_status.text = "Couldn't promote %s: %s" % [e.get("name", "?"), r.error]
		return r
	_status.text = "%s is in the world now" % e.get("name", "?")
	_stores.clear()
	_reload()
	return r


## Standalone, the timeline's own log, so edits during a running session become events.
func _open_timeline_log() -> void:
	if event_log == null and timeline_dir != "" and Timeline.is_timeline(timeline_dir):
		event_log = Timeline.new(timeline_dir).events_log


# --- Editing (TASK-21) -------------------------------------------------------------------

## Accounts for "Visible for" and the frame colors: the players of every timeline of every
## world (by id) and the DM. The book is the DM's view.
func accounts() -> Dictionary:
	if Markdown.reveal_accounts.is_empty():
		var out := {}
		for w in Worlds.list(PackageManager.new(packages_root).worlds_root):
			for t in Timeline.list(str(w._dir)):
				out.merge(Timeline.new(str(t._dir)).accounts())
		Markdown.reveal_accounts = out
		Markdown.reveal_viewer = Reveal.DM
	return Markdown.reveal_accounts


## The store (package folder) an entry lives in.
func store_for(e: Dictionary) -> EntryStore:
	var pkg := str(e.get("_package", ""))
	if not _stores.has(pkg):
		_stores[pkg] = EntryStore.open(str(e.get("_dir", "")))
	return _stores[pkg]


## Stores entries can be created or copied into (TASK-39): the core book only its unlocked
## (homebrew) packages, a world's book only the world, a timeline's book only the timeline.
func writable_stores() -> Array:
	match scope():
		"timeline":
			var t := timeline_store()
			return [t] if t != null else []
		"world":
			for p in db.packages:
				if str(p.get("_dir", "")).simplify_path() == world_dir.simplify_path():
					return [store_for({"_package": p.get("id", ""), "_dir": world_dir})]
			return [EntryStore.open(world_dir)]
	var out := []
	for p in db.packages:
		if str(p.get("_layer", "")) != "core":
			continue
		var s := store_for({"_package": p.get("id", ""), "_dir": p.get("_dir", "")})
		if s != null and not s.is_read_only():
			out.append(s)
	return out


## Turns a full-view tab into the editor for its entry.
func start_edit(view: EntryView, is_new := false) -> EntryEditor:
	var store := store_for(view.entry)
	if store == null:
		_status.text = "Can't find the package folder of %s" % view.entry.get("name", "?")
		return null
	var kind := str(view.entry.get("_kind", ""))
	var current := store.find(kind, str(view.entry.get("id", "")))
	var form := EntryEditor.new()
	form.event_log = event_log
	form.name_source = func(prefix: String) -> PackedStringArray: return db.suggest(prefix)
	form.copy_targets = writable_stores().filter(func(t: EntryStore) -> bool: return t != store)
	form.accounts = accounts()
	form.db = db
	form.is_new = is_new
	form.entry_open_requested.connect(func(e: Dictionary) -> void: open_tab(e))
	form.entries_changed.connect(func(s: EntryStore, changes: Array) -> void:
		_apply_changes(s, changes)
		_drafts_changed())
	form.setup(store, kind, current if not current.is_empty() else view.entry)
	var old_id := str(view.entry.get("id", ""))
	form.saved.connect(func(saved_entry: Dictionary) -> void: _on_saved(view, store, kind, saved_entry, old_id))
	form.cancelled.connect(view.end_edit)
	form.deleted.connect(func() -> void: _on_deleted(view, store, kind))
	form.open_requested.connect(edit_entry)
	view.begin_edit(form)
	return form


## The Token button (TASK-41): the token editor for the entry of `view`; Save writes
## `token_style` into the entry (read-only source packages: import it or edit a copy).
func open_token_editor(view: EntryView) -> TokenEditor:
	var e := view.entry
	var ed := TokenEditor.new()
	ed.setup(e)
	add_child(ed)
	var store := store_for(e)
	if store == null or store.is_read_only():
		ed.lock("This creature is in a read-only package. Drag it into your Book (or use Edit, then edit a copy) to give it its own token.")
	ed.saved.connect(func(style: Dictionary) -> void: save_token(view, style))
	ed.close_requested.connect(ed.queue_free)
	ed.canceled.connect(ed.queue_free)
	ed.popup_centered()
	return ed


## Writes a token style into the entry shown in `view` and shows it again.
func save_token(view: EntryView, style: Dictionary) -> Dictionary:
	var e := view.entry
	var store := store_for(e)
	if store == null or store.is_read_only():
		return {}
	var kind := str(e.get("_kind", ""))
	var after := e.duplicate(true)
	after["token_style"] = style
	var r := store.commit(kind, e, after, event_log)
	if r.error != OK:
		_status.text = "Couldn't save the token (%s)" % error_string(r.error)
		return {}
	var held := db.put_entry(store.find(kind, str(e.get("id", ""))), kind, store)
	view.setup(held)
	_status.text = "Token of %s saved" % held.get("name", "?")
	token_changed.emit(held)
	return held


## Opens an entry of a store in a tab and starts editing it (new entries, copies, features).
func edit_entry(store: EntryStore, kind: String, id: String, is_new := false) -> EntryEditor:
	var e := store.find(kind, id)
	if e.is_empty():
		return null
	_stores[store.id] = store
	var held := db.put_entry(e, kind, store)
	_after_db_change(kind)
	var view := open_tab(held)
	return start_edit(view, is_new) if view else null


func _on_saved(view: EntryView, store: EntryStore, kind: String, saved_entry: Dictionary, old_id: String) -> void:
	var held := db.put_entry(store.find(kind, str(saved_entry.get("id", ""))), kind, store, old_id)
	var old_key := view.key
	view.end_edit()
	view.setup(held)
	if old_key != view.key:
		_open_views.erase(old_key)
		_open_views[view.key] = view
		var i := _tab_index(old_key)
		if i >= 0:
			_tab_bar.set_tab_metadata(i, view.key)
	var t := _tab_index(view.key)
	if t >= 0:
		_tab_bar.set_tab_title(t, str(held.get("name", "?")))
	_after_db_change(kind)
	_drafts_changed()
	_status.text = "Saved %s" % held.get("name", "?")


func _on_deleted(view: EntryView, store: EntryStore, kind: String) -> void:
	db.remove_entry(store.id, kind, str(view.entry.get("id", "")))
	close_tab(_tab_index(view.key))
	_after_db_change(kind)
	_status.text = "Deleted %s" % view.entry.get("name", "?")


# --- Packages as cards (TASK-23) --------------------------------------------------------------

func _build_package_cards() -> void:
	manager = PackageManager.new(db.root)
	var loaded := {}  ## package id -> {kind: count} of what is in the book
	for kind: String in db.kinds():
		for e: Dictionary in db.entries[kind]:
			var c: Dictionary = loaded.get_or_add(e["_package"], {})
			c[kind] = int(c.get(kind, 0)) + 1
	package_cards = []
	for m: Dictionary in manager.list():
		var id := str(m._folder)
		var e := m.duplicate(true)
		e["id"] = id
		e["_kind"] = PACKAGES
		e["_package"] = id
		e["_package_name"] = str(m.get("name", id))
		e["_dir"] = manager.folder_of(id)
		e["_key"] = str(m.get("name", id)).to_lower()
		e["_text"] = (str(m.get("name", id)) + "\n" + str(m.get("description", ""))).to_lower()
		e["_layer"] = "world" if str(m.get("kind", "")) == "world" else "core"
		e["image"] = str(m.get("cover", m.get("image", "")))
		var counts: Dictionary = loaded.get(id, m.get("counts", {}) if m.get("counts") is Dictionary else {})
		e["_counts"] = counts
		var total := 0
		for k: Variant in counts:
			total += int(counts[k])
		e["_count"] = total
		package_cards.append(e)


## The entries of a kind in the binder (the package cards for "packages").
func list_of(kind: String) -> Array:
	return package_cards if kind == PACKAGES else db.list(kind, show_drafts)


## The "Show drafts" tickbox: drafts join the binder (marked) or leave it.
func set_show_drafts(on: bool) -> void:
	show_drafts = on
	_show_drafts.set_pressed_no_signal(on)
	if not db.is_loaded:
		return
	_build_bookmarks()
	if _kind != "":
		_select_kind(_kind)


## The Drafts page in its own tab.
func open_drafts() -> EntryView:
	return open_tab(entry_for("", DRAFTS, DRAFTS))


## Publishes every draft of a package (or of one import job in it); same-name entries are
## asked about one by one (replace / keep both / skip; Cancel stops).
func publish_all(package_id: String, job := "") -> void:
	var todo := db.all_drafts().filter(func(e: Dictionary) -> bool:
		return e["_package"] == package_id and (job == "" or DraftsPage.job_of(e) == job))
	# main entries first (they take their features and tables along), loose parts last
	todo.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["_kind"] in PARTS) < int(b["_kind"] in PARTS))
	var store := store_for(todo[0]) if not todo.is_empty() else null
	if store == null:
		return
	if store.is_read_only():
		store.unlock()  # publishing in a source package is the explicit choice
	_publish_next(store, todo, 0, 0)


func _publish_next(store: EntryStore, todo: Array, i: int, done: int) -> void:
	if i >= todo.size():
		_drafts_changed()
		_status.text = "Published %d draft(s)" % done
		return
	_publish_one(store, todo[i], EntryStore.ASK, func(r: Dictionary) -> void:
		if r.has("cancelled"):
			_drafts_changed()
			return
		_publish_next(store, todo, i + 1, done + (1 if r.has("published") else 0)))


func _publish_one(store: EntryStore, e: Dictionary, mode: String, done: Callable) -> void:
	var kind := str(e["_kind"])
	var now := store.find(kind, str(e.id))
	if now.is_empty() or not EntryStore.is_draft(now):
		done.call({})  # went along with its entry (or was thrown away with it)
		return
	if kind in PARTS and mode == EntryStore.ASK:
		mode = EntryStore.KEEP_BOTH  # "Claws" exists a hundred times; never ask for parts
	var r := store.publish(kind, str(e.id), mode)
	if r.has("duplicate"):
		var dialog := ConfirmationDialog.new()
		dialog.name = "DuplicateQuestion"
		dialog.title = "Already published"
		dialog.dialog_text = "\"%s\" is already in %s.\nReplace it, keep both, or throw this draft away?" % [e.get("name", "?"), store.name]
		dialog.ok_button_text = "Replace"
		dialog.add_button("Keep both", false, EntryStore.KEEP_BOTH)
		dialog.add_button("Skip (discard draft)", false, EntryStore.SKIP)
		dialog.confirmed.connect(func() -> void:
			_drop(dialog)
			_publish_one(store, e, EntryStore.REPLACE, done))
		dialog.custom_action.connect(func(action: StringName) -> void:
			_drop(dialog)
			_publish_one(store, e, str(action), done))
		dialog.canceled.connect(func() -> void:
			_drop(dialog)
			done.call({"cancelled": true}))
		add_child(dialog)
		dialog.popup_centered()
		return
	var changes: Array = [[kind, str(e.id)]] + r.get("removed", []) + r.get("parts", [])
	if r.has("published"):
		changes.append([kind, str(r.published.id)])
	_apply_changes(store, changes)
	done.call(r)


## Re-reads changed entries of a store into the book (gone ones are dropped).
func _apply_changes(store: EntryStore, changes: Array) -> void:
	for c: Array in changes:
		db.remove_entry(store.id, str(c[0]), str(c[1]))
		var e := store.find(str(c[0]), str(c[1]))
		if not e.is_empty():
			db.put_entry(e, str(c[0]), store)


## After drafts changed: bookmarks, the binder and an open Drafts page catch up.
func _drafts_changed() -> void:
	_build_bookmarks()
	if _kind != "" and db.is_loaded:
		var keep := _page
		_refresh_list()
		_page = mini(keep, _pages() - 1)
		_render_page()
	var page := open_view(EntryView.key_of(entry_for("", DRAFTS, DRAFTS)))
	if page and page.drafts_page:
		page.drafts_page.refresh(db)


## An entry by package, kind and id (package cards too).
func entry_for(package_id: String, kind: String, id: String) -> Dictionary:
	if kind == DRAFTS:
		return {"id": DRAFTS, "_kind": DRAFTS, "_package": "", "_package_name": "", "name": "Drafts", "_key": "drafts"}
	if kind == PACKAGES:
		for e: Dictionary in package_cards:
			if e.id == id:
				return e
		return {}
	return db.get_entry(package_id, kind, id)


## Switches a package on or off (card switch, full view) and re-reads the book.
func set_package_enabled(id: String, on: bool) -> void:
	if manager == null or manager.is_enabled(id) == on:
		return
	manager.set_enabled(id, on)
	_status.text = "%s switched %s" % [id, "on" if on else "off"]
	_reload()


## Browse, filtered to one package and kind (the counts in a package's full view).
func browse_package(package_id: String, kind: String) -> void:
	if not db.entries.has(kind):
		return
	var i := db.kinds().find(kind)
	if i >= 0 and i < _tabs.get_child_count():
		(_tabs.get_child(i) as Button).button_pressed = true
	_select_kind(kind)
	var p := _package_values.find(package_id)
	_package.selected = p + 1 if p >= 0 else 0
	_refresh_list()


func _doc_path(package_id: String, file: String) -> String:
	return PackageManager.new(db.root).folder_of(package_id).path_join(file)


## Opens a package's PDF in the system's viewer.
func open_document(package_id: String, file: String) -> void:
	var path := _doc_path(package_id, file)
	if not FileAccess.file_exists(path):
		_status.text = "Missing: %s" % file
		return
	OS.shell_open(path)


func show_document(package_id: String, file: String) -> void:
	OS.shell_show_in_file_manager(_doc_path(package_id, file))


func add_pdf_dialog(package_id: String) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.title = "Add a PDF to the package"
	dialog.filters = PackedStringArray(["*.pdf ; PDF documents", "* ; All files"])
	dialog.use_native_dialog = true
	dialog.file_selected.connect(func(path: String) -> void:
		add_pdf(package_id, path)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


## Copies a PDF into the package and shows it in the package's view.
func add_pdf(package_id: String, path: String) -> Dictionary:
	var doc := manager.add_document(package_id, path)
	if doc.has("error"):
		_status.text = str(doc.error)
		return doc
	var card := entry_for(package_id, PACKAGES, package_id)
	if not card.is_empty():
		card["documents"] = manager.manifest(package_id).get("documents", [])
		var view: EntryView = _open_views.get(EntryView.key_of(card))
		if view and view.documents_box:
			view._fill_documents(card)
	_status.text = "Added %s" % doc.title
	return doc


## Export with the size first (PDFs can be large).
func export_package_dialog(package_id: String) -> void:
	var docs := manager.documents(package_id).size()
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.title = "Export package (%s%s)" % [PackageManager.size_text(manager.package_size(package_id)), ", %d PDFs" % docs if docs > 0 else ""]
	dialog.filters = PackedStringArray(["*.%s ; Dragoon package" % PackageManager.EXTENSION])
	dialog.current_file = "%s.%s" % [package_id, PackageManager.EXTENSION]
	dialog.file_selected.connect(func(path: String) -> void:
		var err := manager.export_package(package_id, path)
		_status.text = "Exported to %s" % path if err == OK else "Export failed: %s" % error_string(err)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


# --- Rollable tables (TASK-25) -------------------------------------------------------------

## Tables resolve in this book (timeline > world > core). Standalone, rolls happen here and
## go into the timeline's event log; over the table the table rolls (TableUI sets the roller).
func _hook_tables() -> void:
	RollTables.resolver = func(id: String) -> Dictionary: return db.resolve_ref("tables/" + id)
	if not closable:
		RollTables.event_log = event_log
	if not RollTables.hub.changed.is_connected(_on_table_rolled):
		RollTables.hub.changed.connect(_on_table_rolled)
		RollTables.hub.rolled.connect(func(text: String) -> void: _status.text = text)


## A table got a result: the views that show it are drawn again.
func _on_table_rolled(id: String) -> void:
	for k: String in _open_views:
		var view: EntryView = _open_views[k]
		if not view.is_editing() and _shows_table(view.entry, id):
			view.setup(view.entry)
	if not _current.is_empty() and _shows_table(_current, id):
		_build_detail(_current)


static func _shows_table(e: Dictionary, id: String) -> bool:
	if e.get("_kind") == "tables" and str(e.get("id", "")) == id:
		return true
	for k: Variant in e:
		if e[k] is String and RollTables.embeds(e[k], id):
			return true
	return false


## Bookmarks and the binder page after entries were added, changed or removed.
func _after_db_change(kind: String) -> void:
	_build_bookmarks()
	if kind == _kind:
		var keep := _page
		_refresh_list()
		_page = mini(keep, _pages() - 1)
		_render_page()


## "New...": in a kind's overview a new entry of that kind right away (TASK-39), in the
## first writable store (a new "Homebrew" package if the core book has none). Elsewhere
## (packages, drafts) it asks for the kind and where to put it.
func new_entry(kind := "") -> EntryEditor:
	if kind != "" and kind not in [PACKAGES, DRAFTS]:
		var store := default_store()
		return create_entry(store, kind, "New " + kind.trim_suffix("s").replace("_", " "))
	_new_entry_dialog()
	return null


## Where new entries go when nobody asked: the timeline, the world, or the first unlocked
## package (a new Homebrew package if there is none).
func default_store() -> EntryStore:
	var stores := writable_stores()
	return stores[0] if not stores.is_empty() else new_package("Homebrew")


func _new_entry_dialog() -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.name = "NewEntryDialog"
	dialog.title = "New entry"
	dialog.ok_button_text = "Create"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	dialog.add_child(box)
	var kinds := PackedStringArray(Schema.KINDS.keys())
	kinds.remove_at(kinds.find("notes"))
	for k in db.kinds():
		if k not in kinds:
			kinds.append(k)
	kinds.sort()
	var kind_pick := OptionButton.new()
	kind_pick.name = "Kind"
	for k in kinds:
		kind_pick.add_item(k.capitalize())
	kind_pick.selected = maxi(0, kinds.find(_kind))
	box.add_child(kind_pick)
	var targets := writable_stores()
	var target_pick := OptionButton.new()
	for t: EntryStore in targets:
		target_pick.add_item("In %s" % t.name)
	var core := scope() == "core"
	if core:
		target_pick.add_item("In a new package...")
	box.add_child(target_pick)
	var package_name := LineEdit.new()
	package_name.placeholder_text = "Name of the new package"
	package_name.visible = core and targets.is_empty()
	box.add_child(package_name)
	target_pick.item_selected.connect(func(i: int) -> void: package_name.visible = core and i == targets.size())
	var entry_name := LineEdit.new()
	entry_name.placeholder_text = "Name"
	box.add_child(entry_name)
	dialog.confirmed.connect(func() -> void:
		var store: EntryStore = targets[target_pick.selected] if target_pick.selected >= 0 and target_pick.selected < targets.size() else null
		if store == null:
			store = new_package(package_name.text if package_name.text.strip_edges() != "" else "Homebrew")
		create_entry(store, kinds[kind_pick.selected], entry_name.text if entry_name.text.strip_edges() != "" else "New " + kinds[kind_pick.selected].trim_suffix("s"))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	entry_name.grab_focus()
	return dialog


## A new editable source package in the packages folder (shows up in the book right away).
func new_package(package_name: String) -> EntryStore:
	var store := EntryStore.create_package(db.root, package_name)
	var m := store.manifest.duplicate()
	m["_dir"] = store.folder
	m["_layer"] = "core"
	db.packages.append(m)
	_stores[store.id] = store
	return store


func create_entry(store: EntryStore, kind: String, entry_name: String) -> EntryEditor:
	var e := store.create(kind, entry_name)
	return edit_entry(store, kind, str(e.id), true)


func _close_all_tabs() -> void:
	while _tab_bar.tab_count > 0:
		close_tab(_tab_bar.tab_count - 1)


func _exit_tree() -> void:
	_save_tabs()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_tabs()
	elif what == NOTIFICATION_DRAG_BEGIN:
		_drop_zone(is_visible_in_tree() and _can_drop_data(Vector2.ZERO, get_viewport().gui_get_drag_data()))
	elif what == NOTIFICATION_DRAG_END:
		_drop_zone(false)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_XBUTTON1 and is_visible_in_tree():
		_back_everywhere()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and event.ctrl_pressed) or not is_visible_in_tree():
		return
	if event.keycode == KEY_TAB:
		_cycle_tab(-1 if event.shift_pressed else 1)
	elif event.keycode == KEY_W:
		if _tab_bar.current_tab >= 0:
			close_tab(_tab_bar.current_tab)
	else:
		return
	get_viewport().set_input_as_handled()


## Alt+Left / mouse back: in a full-view tab the tab history, on Browse the quick card's.
func _back_everywhere() -> void:
	if current_tab_key() != "":
		go_back_tab()
	else:
		_go_back()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed:
		return
	var handled := true
	if event.keycode == KEY_F and event.ctrl_pressed:
		_search.grab_focus()
		_search.select_all()
	elif event.keycode == KEY_LEFT and event.alt_pressed:
		_back_everywhere()
	elif event.keycode == KEY_PAGEDOWN and _browse.visible:
		_flip(1)
	elif event.keycode == KEY_PAGEUP and _browse.visible:
		_flip(-1)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


## Takes a finished question out of the tree at once (the next one may take its name).
func _drop(dialog: Node) -> void:
	if dialog.get_parent():
		dialog.get_parent().remove_child(dialog)
	dialog.queue_free()
