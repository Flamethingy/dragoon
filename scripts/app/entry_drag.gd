class_name EntryDrag
extends RefCounted
## Dragging a compendium entry somewhere (TASK-37): the drag data and the drop targets.
## Cards in any book start the drag; the map places a token (MapDrop), a sheet adds an item,
## spell or feature, a note gets a [[link]], a timeline's book makes it a timeline entry.

const TYPE := "dragoon_entry"
## Sheet list per dropped kind (a sheet.changed on that list).
const SHEET_LISTS := {"items": "inventory", "spells": "spells", "features": "features"}


static func data(e: Dictionary) -> Dictionary:
	return {"type": TYPE, "entry": e}


static func is_entry(d: Variant) -> bool:
	return d is Dictionary and d.get("type") == TYPE and d.get("entry") is Dictionary


static func entry_of(d: Variant) -> Dictionary:
	return d.entry if is_entry(d) else {}


## "kind/id" of a dragged entry.
static func ref_of(d: Variant) -> String:
	var e := entry_of(d)
	return "%s/%s" % [e.get("_kind", ""), e.get("id", "")] if not e.is_empty() else ""


## A label to show under the mouse while dragging.
static func preview(e: Dictionary) -> Control:
	var l := Label.new()
	l.text = str(e.get("name", "?"))
	l.add_theme_color_override("font_color", UISkin.INK)
	var bg := StyleBoxFlat.new()
	bg.bg_color = UISkin.CREAM
	bg.set_content_margin_all(6)
	bg.set_corner_radius_all(4)
	l.add_theme_stylebox_override("normal", bg)
	return l


## The [[link]] a note gets for an entry.
static func link(e: Dictionary) -> String:
	return "[[%s/%s|%s]]" % [e.get("_kind", ""), e.get("id", ""), e.get("name", "")]


## What a sheet gets: [list key, new list] for a dropped item/spell/feature, [] if it can't.
static func sheet_change(sheet: Dictionary, e: Dictionary) -> Array:
	var kind := str(e.get("_kind", ""))
	if not SHEET_LISTS.has(kind):
		return []
	var key: String = SHEET_LISTS[kind]
	var list: Array = (sheet.get(key, []) as Array).duplicate(true) if sheet.get(key) is Array else []
	var ref := "%s/%s" % [kind, e.get("id", "")]
	if kind == "items":
		for it: Variant in list:
			if it is Dictionary and str(it.get("item", "")) == ref:
				it["qty"] = int(it.get("qty", 1)) + 1
				return [key, list]
		list.append({"item": ref, "qty": 1})
	elif ref in list:
		return []
	else:
		list.append(ref)
	return [key, list]
