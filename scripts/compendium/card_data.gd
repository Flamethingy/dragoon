class_name CardData
## The few facts a compendium card and its detail panel show for an entry, per kind:
## a badge (CR, spell level ...), a subtitle, stat chips and fallback art colours.
## The full text stays in StatBlock.

const ART_COLORS := [Color8(102, 42, 58), Color8(190, 62, 59), Color8(90, 136, 100),
	Color8(201, 160, 95), Color8(138, 79, 94), Color8(180, 137, 120), Color8(124, 123, 155),
	Color8(96, 120, 150), Color8(150, 110, 70)]


## [text, hex colour] or [] for no badge.
static func badge(e: Dictionary) -> Array:
	match str(e.get("_kind", "")):
		"monsters":
			var cr: Variant = e.get("cr")
			if cr == null:
				return []
			var f := float(cr)
			return [StatBlock.cr_text(cr), "green" if f < 5 else "tan" if f < 11 else "red" if f < 17 else "wine"]
		"spells":
			var lv := int(e.get("level", 0)) if e.get("level") != null else 0
			return ["C" if lv == 0 else str(lv), "cream" if lv == 0 else "green" if lv < 4 else "red" if lv < 7 else "wine"]
		"items":
			var rarity := str(e.get("rarity", "")).to_lower()
			var colors := {"common": "cream", "uncommon": "green", "rare": "tan", "very rare": "red", "legendary": "wine", "artifact": "wine"}
			return [rarity.substr(0, 1).to_upper(), colors[rarity]] if colors.has(rarity) else []
		"classes":
			var hd: Variant = e.get("hit_dice", e.get("hit_die"))
			return ["d" + StatBlock._num(hd), "wine"] if hd != null else []
	return []


static func badge_label(e: Dictionary) -> String:
	match str(e.get("_kind", "")):
		"monsters": return "Challenge rating"
		"spells": return "Spell level (C = cantrip)"
		"items": return "Rarity: " + str(e.get("rarity", ""))
		"classes": return "Hit die"
	return ""


static func subtitle(e: Dictionary) -> String:
	match str(e.get("_kind", "")):
		"monsters":
			return " ".join(PackedStringArray([str(e.get("size", "")), str(e.get("type", ""))])).strip_edges()
		"spells":
			var lv := int(e.get("level", 0)) if e.get("level") != null else 0
			var school := str(e.get("school", ""))
			return ("%s cantrip" % school) if lv == 0 else ("Level %d %s" % [lv, school.to_lower()])
		"items":
			var parts := PackedStringArray()
			var t: Variant = e.get("type")
			if t is Array and not t.is_empty():
				parts.append(str(t[0]))
			elif t != null and str(t) != "":
				parts.append(str(t))
			if str(e.get("rarity", "")) != "":
				parts.append(str(e.rarity))
			return ", ".join(parts)
	return StatBlock.SINGULAR.get(str(e.get("_kind", "")), str(e.get("_kind", "")).capitalize())


## Stat chips: [icon sprite name or "", label, value].
static func chips(e: Dictionary) -> Array:
	var out := []
	match str(e.get("_kind", "")):
		"monsters":
			var ac := StatBlock._num(e.get("ac"))
			out.append(["icon_shield", "AC", ac])
			out.append(["icon_potion", "HP", StatBlock._num(e.get("hp"))])
			out.append(["icon_boot", "Speed", StatBlock._speed(e).replace("[lb]", "[")])
			if str(e.get("alignment", "")) != "":
				out.append(["", "Alignment", str(e.alignment)])
		"spells":
			out.append(["icon_dagger", "Casting", str(e.get("casting_time", "—"))])
			var r: Variant = e.get("range_m")
			out.append(["icon_boot", "Range", "Self / Touch" if r == null or float(r) == 0 else StatBlock._metres(r)])
			out.append(["icon_helmet", "Duration", str(e.get("duration", "—"))])
			out.append(["icon_chest", "Components", _components(e.get("components"))])
		"items":
			if e.get("gold") != null and float(e.gold) > 0:
				out.append(["coin_gold", "Cost", StatBlock._num(e.gold) + " gp"])
			if e.get("weight") != null:
				out.append(["", "Weight", StatBlock._num(e.weight) + " lb"])
			if e.get("attunement") != null and str(e.attunement) not in ["", "false", "False"]:
				out.append(["gem", "Attunement", "required" if e.attunement is bool else str(e.attunement)])
		_:
			for k: Variant in e:
				if out.size() >= 4:
					break
				var key := str(k)
				var v: Variant = e[k]
				if key in StatBlock.HIDDEN or key.begins_with("_") or v == null or v is Dictionary:
					continue
				var text: String = StatBlock._value(v) if not v is String else v
				if v is Array:
					text = ", ".join(PackedStringArray(v.map(func(x: Variant) -> String: return str(x))))
				text = str(text)
				if text == "" or text.length() > 60 or text.contains("\n") or text.contains("["):
					continue
				out.append(["", key.replace("_", " ").capitalize(), text])
	return out


static func _components(c: Variant) -> String:
	if not c is Dictionary:
		return str(c) if c != null else "—"
	var parts := PackedStringArray()
	for pair in [["verbal", "V"], ["somatic", "S"], ["material", "M"]]:
		if bool(c.get(pair[0], false)):
			parts.append(pair[1])
	return " ".join(parts) if not parts.is_empty() else "—"


## Spells: concentration / ritual tags.
static func tags(e: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if e.get("_kind") == "spells":
		if bool(e.get("concentration", false)):
			out.append("Concentration")
		if bool(e.get("ritual", false)):
			out.append("Ritual")
	return out


## Fallback art colour: picked from the type / school so similar entries match.
static func art_color(e: Dictionary) -> Color:
	var key := str(e.get("school", e.get("type", e.get("_kind", ""))))
	return ART_COLORS[posmod(hash(key.to_lower()), ART_COLORS.size())]


static func image_path(e: Dictionary) -> String:
	var rel := str(e.get("image", ""))
	return "" if rel == "" else str(e.get("_dir", "")).path_join(rel)
