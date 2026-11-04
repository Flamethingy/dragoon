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


const PREVIEW_ALPHA := 0.55

static var _preview: WeakRef  ## the card following the mouse (TASK-93)


## TASK-93 (Nico 2026-11-04): a transparent copy of the card follows the mouse while dragging,
## the mouse at its middle. Over the map a creature's card makes way for the token ghost
## (MapDrop calls show_preview).
static func preview(e: Dictionary) -> Control:
	var holder := Control.new()
	holder.name = "EntryPreview"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := EntryCard.new()
	card.setup(e)
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW
	card.tooltip_text = ""
	card.size = EntryCard.SIZE
	card.position = -EntryCard.SIZE * 0.5
	holder.add_child(card)
	holder.modulate.a = PREVIEW_ALPHA
	_preview = weakref(holder)
	return holder


## The card following the mouse, null if none.
static func preview_node() -> Control:
	return _preview.get_ref() as Control if _preview != null else null


## Shows or hides the card following the mouse (hidden while the token ghost shows).
static func show_preview(on: bool) -> void:
	var p := preview_node()
	if p != null and p.visible != on:
		p.visible = on


## The [[link]] a note gets for an entry.
static func link(e: Dictionary) -> String:
	return "[[%s/%s|%s]]" % [e.get("_kind", ""), e.get("id", ""), e.get("name", "")]


## TASK-94: every Control under `root` (now and later) takes dropped items, spells and
## features for the character `ref_of` names (the HUD, the sheet pages): the table adds them.
## Controls with drops of their own keep them.
static func accept_on(root: Control, table: NetTable, ref_of: Callable) -> void:
	var hook := func(n: Node) -> void:
		var c := n as Control
		if c == null or (c.get_script() != null and (c.get_script() as Script).get_script_method_list().any(func(m: Dictionary) -> bool: return m.name == "_can_drop_data")):
			return
		c.set_drag_forwarding(Callable(),
			func(_at: Vector2, d: Variant) -> bool: return is_entry(d) and table.can_take_entry(str(ref_of.call()), entry_of(d)),
			func(_at: Vector2, d: Variant) -> void: table.add_entry_to(str(ref_of.call()), entry_of(d)))
	hook.call(root)
	for n: Node in root.find_children("*", "Control", true, false):
		hook.call(n)
	root.get_tree().node_added.connect(func(n: Node) -> void:
		if is_instance_valid(root) and root.is_ancestor_of(n):
			hook.call(n))


## What a sheet gets: [list key, new list] for a dropped item/spell/feature, [] if it can't.
static func sheet_change(sheet: Dictionary, e: Dictionary) -> Array:
	var kind := str(e.get("_kind", ""))
	if not SHEET_LISTS.has(kind):
		return []
	var key: String = SHEET_LISTS[kind]
	var list: Array = (sheet.get(key, []) as Array).duplicate(true) if sheet.get(key) is Array else []
	if key == "features" and sheet.get("_class_features") is Array:  # TASK-69: given by the classes, not stored
		list = list.filter(func(v: Variant) -> bool: return not (str(v) in (sheet._class_features as Array)))
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
