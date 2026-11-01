class_name EntryDrag
extends RefCounted
## Dragging a compendium entry somewhere (TASK-37): the drag data and the drop targets.
## Cards in any book start the drag; the map places a token (MapDrop), a sheet adds an item,
## spell or feature, a note gets a [[link]], a timeline's book makes it a timeline entry.

const TYPE := "dragoon_entry"

## Between OS windows Godot ends a drag as "not dropped" when the mouse is let go over
## another window (Nico tried it, 2026-11-01). The card being dragged is remembered here;
## when its drag ends without a drop, `hub.dropped_outside` tells the app the entry and
## the mouse position on the screen, and the app hands it to the window under the mouse.
class Hub:
	extends RefCounted
	signal dropped_outside(entry: Dictionary, screen_position: Vector2i, from: Viewport)

static var hub := Hub.new()
static var carrying := {}  ## the entry of the card being dragged
static var source: Viewport  ## the window it was dragged in


## A card started a drag.
static func start(e: Dictionary, from: Viewport) -> void:
	carrying = e
	source = from


## The drag of a card in `from` ended (`dropped`: something in that window took it).
static func end(from: Viewport, dropped: bool) -> void:
	if carrying.is_empty() or from != source:
		return
	var e := carrying
	carrying = {}
	source = null
	if not dropped:
		hub.dropped_outside.emit(e, DisplayServer.mouse_get_position(), from)
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
