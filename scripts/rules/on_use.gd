class_name OnUse
extends RefCounted
## "On Use" (TASK-108): an entry's `effects` (TASK-65, package-format.md) in plain words, a short
## sentence per step with coloured chips: "Targets [all creatures] in a [6 m sphere] within
## [45 m]. Each makes a [DEX save] against [your spell DC]. Failure: [8d6 fire]; success: [half]."
## Chip colours by what they are (Nico 2026-11-04): target blue, roll purple, damage red, heal
## green, condition orange, modifier gold, duration / scaling grey. The same colours are the
## nodes of the editor's flow (OnUseFlow). The text stays the source of truth: an entry without
## effects shows "No automation".
##
## New in the effects (TASK-108): `target` {kind: self|creature|creatures|area, count, range_m,
## self (you or ...)}, `roll: "check"` {skill | ability, dc, by: self|target, on_fail, on_success},
## a step without a roll that deals `damage`, and `then` (follow-up steps, `when`: hit, miss,
## fail, success, always).

const BLUE := Color8(70, 112, 165)
const PURPLE := Color8(124, 84, 152)
const GREY := Color8(128, 112, 112)
const KINDS := ["target", "roll", "damage", "heal", "condition", "modifier", "time"]
const ICONS := {"target": "🎯", "roll": "🎲", "damage": "💥", "heal": "💚", "condition": "⚠", "modifier": "✨", "time": "⏱"}
const WHEN := {"hit": "On a hit", "miss": "On a miss", "fail": "On a failure", "success": "On a success", "always": "Then"}
const ABILITY_NAMES := {"str": "STR", "dex": "DEX", "con": "CON", "int": "INT", "wis": "WIS", "cha": "CHA"}


static func color(kind: String) -> Color:
	match kind:
		"target":
			return BLUE
		"roll":
			return PURPLE
		"damage":
			return UISkin.RED
		"heal":
			return UISkin.GREEN
		"condition":
			return UISkin.ORANGE
		"modifier":
			return UISkin.GOLD
	return GREY


## The sentences of an entry: [[part, ...], ...]; a part is plain text (String) or a chip
## [text, kind]. [] without effects.
static func sentences(entry: Dictionary) -> Array:
	var out := []
	var list: Array = entry.get("effects", []) if entry.get("effects") is Array else []
	for fx: Variant in list:
		if fx is Dictionary:
			_step(fx, entry, out, "")
	return out


## The sentences as plain text (chips in [brackets]): for tests and tooltips.
static func plain(entry: Dictionary) -> String:
	var lines := PackedStringArray()
	for s: Array in sentences(entry):
		lines.append(sentence_text(s))
	return "\n".join(lines)


static func sentence_text(s: Array) -> String:
	var t := ""
	for p: Variant in s:
		t += "[%s]" % str(p[0]) if p is Array else str(p)
	return t


## One effect: its target, roll and results (one or two sentences), then its follow-ups.
static func _step(fx: Dictionary, entry: Dictionary, out: Array, when: String) -> void:
	var lead: Array = [WHEN[when] + ": "] if when != "" else []
	var many := _many(fx, entry)
	var tgt := target_parts(fx, entry)
	if not tgt.is_empty() and not fx.has("resource"):
		out.append(lead + tgt)
		lead = []
	var s: Array = lead.duplicate()
	var roll := str(fx.get("roll", ""))
	if roll == "attack":
		var to_hit: Variant = fx.get("to_hit", "spell")
		var range_word := str(fx.get("range", "ranged"))
		var what := "%s %sattack" % [range_word, "spell " if str(to_hit) == "spell" else ""]
		s.append_array(["Make a ", [what + ("" if str(to_hit) == "spell" else " " + _signed(int(to_hit))), "roll"], "."])
		var hit := results(fx)
		if not hit.is_empty():
			s.append_array([" Hit: "] + hit + ["."])
	elif roll == "save":
		s.append_array(["Each makes a " if many else "It makes a ", [_ability(fx.get("ability", "dex")) + " save", "roll"], " against ", [_dc(fx.get("dc", "spell")), "roll"], "."])
		var fail := results(fx.get("on_fail", {}) if fx.get("on_fail") is Dictionary else {})
		var success := _success(fx.get("on_success", "none"))
		if not fail.is_empty():
			s.append_array([" Failure: "] + fail)
			s.append_array(["; success: "] + success + ["."] if not success.is_empty() else ["."])
	elif roll == "check":
		var who := "You make a " if str(fx.get("by", "self")) == "self" else ("Each makes a " if many else "It makes a ")
		s.append_array([who, [check_name(fx), "roll"], " against ", [_dc(fx.get("dc", 10)), "roll"], "."])
		var ok := results(fx.get("on_success", {}) if fx.get("on_success") is Dictionary else {})
		var fail := results(fx.get("on_fail", {}) if fx.get("on_fail") is Dictionary else {})
		if not ok.is_empty():
			s.append_array([" Success: "] + ok + ["."])
		if not fail.is_empty():
			s.append_array([" Failure: "] + fail + ["."])
	elif fx.has("heal"):
		s.append_array(["Roll ", [_formula(str(fx.heal)), "roll"], ": ", "they " if many else "it ", ["regains that many HP", "heal"], "."])
	elif fx.get("apply", "") == "condition" or fx.has("condition"):
		s.append_array(["They are " if many else "It is ", [str(fx.get("condition", "?")), "condition"]])
		if fx.get("save_ends") is Dictionary:
			s.append_array([" (a ", [_ability(fx.save_ends.get("ability", "wis")) + " save", "roll"], " at the end of each of its turns ends it)"])
		s.append(".")
	elif fx.get("modifier") is Dictionary:
		s.append_array([[modifier_text(fx.modifier), "modifier"], " for " + ("them" if many else "it") + "."])
	elif fx.get("resource") is Dictionary:
		var r: Dictionary = fx.resource
		s.append_array([["%s use%s" % [str(r.get("max", 1)), "" if str(r.get("max", 1)) == "1" else "s"], "time"], ", back after a ", [_rest(str(r.get("reset", "long"))), "time"], "."])
	elif fx.get("damage") is Array:
		s.append_array(["They take " if many else "It takes "] + _damage_parts(fx.damage) + ["."])
	s.append_array(tags(fx))
	if s.size() > lead.size():
		out.append(s)
	for t: Variant in fx.get("then", []):
		if t is Dictionary:
			_step(t, entry, out, str(t.get("when", "always")) if WHEN.has(str(t.get("when", "always"))) else "always")


## "Targets [all creatures] in a [6 m sphere] within [45 m]." ([] for a resource).
static func target_parts(fx: Dictionary, entry: Dictionary) -> Array:
	var t := target_of(fx, entry)
	if t.is_empty():
		return []
	var out: Array = ["Targets "]
	var kind := str(t.get("kind", "creature"))
	var range_m: Variant = t.get("range_m")
	match kind:
		"self":
			return ["Targets ", ["yourself", "target"], "."]
		"area":
			var a: Dictionary = fx.get("area", {}) if fx.get("area") is Dictionary else {}
			out.append_array([["all creatures", "target"], " in a ", [area_text(a), "target"]])
		"creatures":
			var n := int(t.get("count", 0))
			out.append([("up to %d creatures" % n) if n > 0 else "any number of creatures", "target"])
		_:
			out.append(["you or a creature" if bool(t.get("self", false)) else "a creature", "target"])
	if range_m != null and kind != "self":
		if float(range_m) <= 0.0:
			out.append_array([" you ", ["touch", "target"]])
		else:
			out.append_array([" within ", [StatBlock._metres(range_m), "target"]])
	out.append(".")
	return out


## The step's target: its own `target`, else what the effect and the entry say (an area: all
## creatures in it; a self-range spell without an area: yourself; else a creature in range).
static func target_of(fx: Dictionary, entry: Dictionary) -> Dictionary:
	if fx.get("target") is Dictionary:
		return fx.target
	if fx.has("resource") or fx.has("when"):
		return {}
	var r: Variant = entry.get("range_m")
	if fx.get("area") is Dictionary and not (fx.area as Dictionary).is_empty():
		return {"kind": "area", "range_m": r} if r != null and float(r) > 0 else {"kind": "area"}
	if str(fx.get("roll", "")) == "check" and str(fx.get("by", "self")) == "self":
		return {}
	if fx.get("modifier") is Dictionary and r != null and float(r) == 0 and str(entry.get("_kind", "")) == "spells":
		return {"kind": "self"}
	if str(entry.get("_kind", "")) == "items" and r == null:
		return {"kind": "creature", "self": true, "range_m": 0}
	return {"kind": "creature", "range_m": r} if r != null else {"kind": "creature"}


## Is it more than one creature (for "each" and "they")?
static func _many(fx: Dictionary, entry: Dictionary) -> bool:
	var t := target_of(fx, entry)
	return str(t.get("kind", "")) in ["area", "creatures"]


## What happens: damage, healing, conditions, a modifier, a note ([] for nothing).
static func results(r: Dictionary) -> Array:
	var out := []
	if r.get("damage") is Array and not (r.damage as Array).is_empty():
		out.append_array(_damage_parts(r.damage))
	if r.has("heal"):
		if not out.is_empty():
			out.append(", ")
		out.append([_formula(str(r.heal)) + " healing", "heal"])
	for c: Variant in r.get("conditions", []):
		if not out.is_empty():
			out.append(", ")
		out.append([str(c), "condition"])
	if r.get("modifier") is Dictionary:
		if not out.is_empty():
			out.append(", ")
		out.append([modifier_text(r.modifier), "modifier"])
	if str(r.get("note", "")) != "":
		if not out.is_empty():
			out.append(", ")
		out.append(str(r.note))
	return out


static func _damage_parts(list: Array) -> Array:
	var out := []
	for d: Variant in list:
		if d is Dictionary:
			if not out.is_empty():
				out.append(" + ")
			out.append([("%s %s" % [_formula(str(d.get("dice", "?"))), str(d.get("type", ""))]).strip_edges(), "damage"])
	return out


static func _success(v: Variant) -> Array:
	if v is Dictionary:
		return results(v)
	match str(v):
		"half":
			return [["half", "damage"]]
		"none":
			return [["nothing", "time"]]
	return []


## Duration, concentration and scaling as grey chips after the sentence.
static func tags(fx: Dictionary) -> Array:
	var out := []
	var d: Variant = fx.get("duration")
	if d is Dictionary and not (d as Dictionary).is_empty():
		out.append_array([" ", [duration_text(d), "time"]])
	if bool(fx.get("concentration", false)):
		out.append_array([" ", ["concentration", "time"]])
	var sc: Variant = fx.get("scaling")
	if sc is Dictionary and not (sc as Dictionary).is_empty():
		out.append_array([" ", [scaling_text(sc), "time"]])
	return out


static func duration_text(d: Dictionary) -> String:
	var bits := PackedStringArray()
	if d.has("rounds"):
		var r := int(d.rounds)
		bits.append("1 minute" if r == 10 else ("%d minutes" % (r / 10) if r % 10 == 0 and r > 10 else "%d round%s" % [r, "" if r == 1 else "s"]))
	if str(d.get("until", d.get("ends", ""))) != "":
		bits.append("until " + str(d.get("until", d.get("ends", ""))).replace("_", " "))
	if bool(d.get("save_ends", false)):
		bits.append("save ends")
	return ", ".join(bits) if not bits.is_empty() else "a while"


static func scaling_text(sc: Dictionary) -> String:
	if sc.has("per_slot"):
		return "+%s per slot above %s" % [str(sc.per_slot), _ordinal(int(sc.get("above", 1)))]
	if sc.has("cantrip"):
		return "+%s at levels 5, 11, 17" % str(sc.cantrip) if str(sc.cantrip) != "true" else "grows at levels 5, 11, 17"
	if sc.has("targets_per_slot"):
		return "+%d target per slot above %s" % [int(sc.targets_per_slot), _ordinal(int(sc.get("above", 1)))]
	return "scales"


static func modifier_text(m: Dictionary) -> String:
	var v: Variant = m.get("value", 0)
	var target := str(m.get("target", "")).replace("_", " ")
	target = target.to_upper() if target.length() <= 3 else target
	var op := str(m.get("op", "add"))
	if op == "set":
		return "%s becomes %s" % [target, str(v)]
	var val := str(v)
	if v is float or v is int:
		val = _signed(int(v))
	elif not val.begins_with("+") and not val.begins_with("-"):
		val = "+" + val
	return "%s %s" % [val, target]


static func area_text(a: Dictionary) -> String:
	var size := StatBlock._metres(a.get("size_m", 0))
	if str(a.get("shape", "")) == "line" and a.has("width_m"):
		return "%s × %s line" % [size, StatBlock._metres(a.width_m)]
	return "%s %s" % [size, str(a.get("shape", "area"))]


static func check_name(fx: Dictionary) -> String:
	var skill := str(fx.get("skill", ""))
	var ab := str(fx.get("ability", ""))
	if skill != "":
		return "%s(%s) check" % [_ability(ab) + " " if ab != "" else "", skill.replace("_", " ").capitalize()]
	return _ability(ab if ab != "" else "str") + " check"


static func _ability(a: Variant) -> String:
	return str(ABILITY_NAMES.get(str(a).to_lower(), str(a).to_upper()))


static func _dc(dc: Variant) -> String:
	return "your spell DC" if str(dc) == "spell" else "DC %s" % str(dc)


## "2d4+2" -> "2d4 + 2", "+mod" -> "+ your modifier".
static func _formula(f: String) -> String:
	return f.replace("+mod", " + your modifier").replace("+", " + ").replace("  ", " ").replace("+ your", "+ your").strip_edges()


static func _signed(n: int) -> String:
	return "+%d" % n if n >= 0 else str(n)


static func _ordinal(n: int) -> String:
	return str(n) + ("st" if n == 1 else "nd" if n == 2 else "rd" if n == 3 else "th")


static func _rest(r: String) -> String:
	return "short rest" if r == "short" else "long rest" if r == "long" else r.replace("_", " ")


# --- The view ------------------------------------------------------------------------------------

## The "On Use" section: a heading and the sentences as words with chips; without effects the
## fallback note.
static func view(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.name = "OnUse"
	box.add_theme_constant_override("separation", 6)
	var head := Label.new()
	head.text = "On Use"
	head.theme_type_variation = UISkin.V_HEADING
	box.add_child(head)
	var list := sentences(entry)
	if list.is_empty():
		var none := Label.new()
		none.name = "NoAutomation"
		none.text = "No automation: the text below is what counts."
		none.theme_type_variation = UISkin.V_MUTED
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(none)
		return box
	for s: Array in list:
		box.add_child(sentence_view(s))
	return box


## A sentence: its words and chips in a flow, so it wraps like text.
static func sentence_view(s: Array) -> Control:
	var flow := HFlowContainer.new()
	flow.name = "Sentence"
	flow.add_theme_constant_override("h_separation", 0)
	flow.add_theme_constant_override("v_separation", 3)
	flow.tooltip_text = sentence_text(s)
	for p: Variant in s:
		if p is Array:
			flow.add_child(chip(str(p[0]), str(p[1])))
			continue
		# plain words: one label each so the line can break between them
		var words := str(p).split(" ")
		for i in words.size():
			var w := words[i] + (" " if i < words.size() - 1 else "")
			if w == "":
				continue
			var l := Label.new()
			l.text = w
			l.add_theme_color_override("font_color", UISkin.INK)
			l.add_theme_font_size_override("font_size", 15)
			flow.add_child(l)
	return flow


static func chip(text: String, kind: String) -> Control:
	var l := Label.new()
	l.name = "Chip_" + kind
	l.text = text
	l.tooltip_text = kind.capitalize() if kind != "time" else "Duration / scaling"
	var c := color(kind)
	var sb := StyleBoxFlat.new()
	sb.bg_color = c.lerp(UISkin.CREAM, 0.78)
	sb.border_color = c
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 0
	sb.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", sb)
	l.add_theme_color_override("font_color", c.darkened(0.35))
	l.add_theme_font_size_override("font_size", 14)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.set_meta("kind", kind)
	return l
