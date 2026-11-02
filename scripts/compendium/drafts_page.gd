class_name DraftsPage
extends VBoxContainer
## The Drafts page (TASK-30): every draft of every package and the campaign as cards, grouped
## by package, then kind. Cards show the kind, the last edit and which required fields are
## still empty. "Publish all" per package and per import job (asks about same-name entries).

signal open_requested(entry: Dictionary)
signal background_requested(entry: Dictionary)
signal publish_all_requested(package_id: String, job: String)  ## job "" = the whole package
signal publish_requested(entry: Dictionary)  ## one draft (an effects proposal, TASK-66)
signal discard_requested(entry: Dictionary)

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
				if str(e.get("draft_of", "")) != "":  # TASK-66: proposed effects, old vs new
					_body.add_child(_proposal(db, e))
					continue
				var card := EntryCard.new()
				card.draft_info = true
				card.setup(e)
				card.pressed.connect(func(x: Dictionary) -> void: open_requested.emit(x))
				card.open_requested.connect(func(x: Dictionary) -> void: open_requested.emit(x))
				card.background_requested.connect(func(x: Dictionary) -> void: background_requested.emit(x))
				flow.add_child(card)


## An effects proposal (TASK-66): the entry, its effects now and the proposed ones, Publish /
## Discard / Open.
func _proposal(db: PackageDB, e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = "Proposal_%s" % str(e.id).validate_node_name()
	row.add_theme_constant_override("separation", 12)
	var now := db.get_entry(str(e["_package"]), str(e["_kind"]), str(e.draft_of))
	var text := RichTextLabel.new()
	text.name = "Diff"
	text.bbcode_enabled = true
	text.fit_content = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var muted := Markdown.MUTED.to_html(false)
	var notes := str(e.get("ai_notes", ""))
	text.text = "[b]%s[/b]  [color=#%s]effects[/color]\n[color=#%s]now:[/color] %s\n[color=#%s]proposed:[/color] [color=#%s]%s[/color]%s" % [
		Markdown.escape(str(e.get("name", ""))), muted, muted, Markdown.escape(summary(now.get("effects", []))), muted,
		UISkin.GREEN.to_html(false), Markdown.escape(summary(e.get("effects", []))),
		"\n[color=#%s][i]%s[/i][/color]" % [muted, Markdown.escape(notes)] if notes != "" else ""]
	text.tooltip_text = JSON.stringify(e.get("effects", []), "  ")
	row.add_child(text)
	var publish := Button.new()
	publish.name = "Publish"
	publish.text = "Publish"
	publish.tooltip_text = "Write the proposed effects into the entry"
	publish.pressed.connect(func() -> void: publish_requested.emit(e))
	row.add_child(publish)
	var discard := Button.new()
	discard.name = "Discard"
	discard.text = "Discard"
	discard.tooltip_text = "Throw this proposal away"
	discard.pressed.connect(func() -> void: discard_requested.emit(e))
	row.add_child(discard)
	var open := Button.new()
	open.name = "Open"
	open.text = "Open"
	open.pressed.connect(func() -> void: open_requested.emit(now if not now.is_empty() else e))
	row.add_child(open)
	return row


## Effects in one line: "save DEX (DC spell): 8d6 fire · half · sphere 6.1 m · +1d6/slot".
static func summary(effects: Variant) -> String:
	if not effects is Array or (effects as Array).is_empty():
		return "none (text only)"
	var parts := PackedStringArray()
	for v: Variant in effects:
		if not v is Dictionary:
			continue
		var fx: Dictionary = v
		var bits := PackedStringArray()
		if fx.has("roll"):
			var fail: Dictionary = fx.get("on_fail", {}) if fx.get("on_fail") is Dictionary else {}
			var dmg: Array = fx.get("damage", fail.get("damage", []))
			var conds: Array = fail.get("conditions", [])
			var head := "attack %s" % str(fx.get("to_hit", "")) if str(fx.roll) == "attack" else "%s %s (DC %s)" % [str(fx.roll), str(fx.get("ability", "")).to_upper(), str(fx.get("dc", ""))]
			var dice := PackedStringArray()
			for d: Variant in dmg:
				if d is Dictionary:
					dice.append("%s %s" % [str(d.get("dice", "")), str(d.get("type", ""))])
			bits.append(head + (": " + ", ".join(dice) if not dice.is_empty() else ""))
			if str(fx.get("on_success", "")) == "half":
				bits.append("half")
			for c: Variant in conds:
				bits.append(str(c))
		elif fx.has("apply"):
			bits.append("%s %s" % [str(fx.apply), str(fx.get("condition", ""))])
		elif fx.has("heal"):
			bits.append("heal %s" % str(fx.heal))
		elif fx.get("modifier") is Dictionary:
			bits.append("%s %s %s" % [str(fx.modifier.get("target", "")), str(fx.modifier.get("op", "add")), str(fx.modifier.get("value", ""))])
		elif fx.get("resource") is Dictionary:
			bits.append("resource %s" % str(fx.resource.get("id", "")))
		if fx.get("area") is Dictionary:
			bits.append("%s %s m" % [str(fx.area.get("shape", "")), str(fx.area.get("size_m", ""))])
		if fx.get("duration") is Dictionary and (fx.duration as Dictionary).has("rounds"):
			bits.append("%d rounds%s" % [int(fx.duration.rounds), ", save ends" if fx.duration.get("save_ends") else ""])
		if fx.get("scaling") is Dictionary:
			var sc: Dictionary = fx.scaling
			if sc.has("per_slot"):
				bits.append("+%s/slot" % str(sc.per_slot))
			elif sc.has("cantrip"):
				bits.append("cantrip +%s" % str(sc.cantrip))
			elif sc.has("targets_per_slot"):
				bits.append("+1 target/slot")
		parts.append(" · ".join(bits))
	return " | ".join(parts)


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
