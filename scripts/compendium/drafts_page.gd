class_name DraftsPage
extends VBoxContainer
## The Drafts page (TASK-30): every draft of every package and the campaign as cards, grouped
## by package, then kind. Cards show the kind, the last edit and which required fields are
## still empty. "Publish all" per package and per import job (asks about same-name entries).

signal open_requested(entry: Dictionary)
signal background_requested(entry: Dictionary)
signal publish_all_requested(package_id: String, job: String)  ## job "" = the whole package

var groups := {}  ## package id -> {kind -> [entries]}
var _body: VBoxContainer


func setup(db: PackageDB) -> void:
	add_theme_constant_override("separation", 8)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	refresh(db)


func refresh(db: PackageDB) -> void:
	groups = {}
	for e: Dictionary in db.all_drafts():
		var by_kind: Dictionary = groups.get_or_add(str(e["_package"]), {})
		by_kind.get_or_add(str(e["_kind"]), []).append(e)
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if groups.is_empty():
		var none := Label.new()
		none.name = "Empty"
		none.theme_type_variation = UISkin.V_MUTED
		none.text = "No drafts. New entries and imports show up here until they are published."
		_body.add_child(none)
		return
	var pkgs := groups.keys()
	pkgs.sort_custom(func(a: String, b: String) -> bool: return db.package_name(a).to_lower() < db.package_name(b).to_lower())
	for pkg: String in pkgs:
		var head := HBoxContainer.new()
		head.name = "Package_" + pkg.validate_node_name()
		_body.add_child(head)
		var title := Label.new()
		title.theme_type_variation = UISkin.V_HEADING
		title.text = "%s  %d" % [db.package_name(pkg), _count(groups[pkg])]
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		for job: String in _jobs(groups[pkg]):
			var b := Button.new()
			b.name = "PublishJob_" + job.validate_node_name()
			b.text = "Publish all from %s" % _job_label(groups[pkg], job)
			b.tooltip_text = "Publish every draft of this import"
			b.pressed.connect(func() -> void: publish_all_requested.emit(pkg, job))
			head.add_child(b)
		var all := Button.new()
		all.name = "PublishAll"
		all.text = "Publish all"
		all.tooltip_text = "Publish every draft of %s" % db.package_name(pkg)
		all.pressed.connect(func() -> void: publish_all_requested.emit(pkg, ""))
		head.add_child(all)
		var kinds: Array = groups[pkg].keys()
		kinds.sort()
		for kind: String in kinds:
			var sub := Label.new()
			sub.theme_type_variation = UISkin.V_MUTED
			sub.text = "%s  %d" % [kind.capitalize(), groups[pkg][kind].size()]
			_body.add_child(sub)
			var flow := HFlowContainer.new()
			flow.name = "Cards_%s_%s" % [pkg.validate_node_name(), kind]
			flow.add_theme_constant_override("h_separation", 12)
			flow.add_theme_constant_override("v_separation", 12)
			_body.add_child(flow)
			for e: Dictionary in groups[pkg][kind]:
				var card := EntryCard.new()
				card.draft_info = true
				card.setup(e)
				card.pressed.connect(func(x: Dictionary) -> void: open_requested.emit(x))
				card.open_requested.connect(func(x: Dictionary) -> void: open_requested.emit(x))
				card.background_requested.connect(func(x: Dictionary) -> void: background_requested.emit(x))
				flow.add_child(card)


## The import jobs whose drafts are in a package group.
static func _jobs(by_kind: Dictionary) -> Array:
	var out := []
	for kind: String in by_kind:
		for e: Dictionary in by_kind[kind]:
			var job := job_of(e)
			if job != "" and job not in out:
				out.append(job)
	out.sort()
	return out


static func job_of(e: Dictionary) -> String:
	return str(e.origin.get("job", "")) if e.get("origin") is Dictionary else ""


static func _job_label(by_kind: Dictionary, job: String) -> String:
	for kind: String in by_kind:
		for e: Dictionary in by_kind[kind]:
			if job_of(e) == job:
				return str(e.origin.get("file", e.origin.get("url", job))).get_file()
	return job


static func _count(by_kind: Dictionary) -> int:
	var n := 0
	for k: String in by_kind:
		n += by_kind[k].size()
	return n
