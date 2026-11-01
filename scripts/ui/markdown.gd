class_name Markdown
## Markdown -> RichTextLabel BBCode (from the Tamago desktop app, adapted to the dark
## editor theme and Obsidian [[wikilinks]]).
## Supports headings, **bold**, *italic*, ~~strike~~, `code`, fenced code blocks,
## lists (nested, ordered, task boxes), > quotes, links, tables, --- rules and images.
## [[Target]], [[Target|Label]] and [[Target#Section|Label]] (the pipe may be escaped
## as \| inside tables) become [url=wiki:Target#Section] links for the compendium.
## Everything else is shown as plain text: BBCode in the input is escaped.

const MUTED := Color(0.65, 0.65, 0.7)
const LINK := Color(0.55, 0.75, 1.0)
const CODE_BG := Color(1, 1, 1, 0.07)
const TABLE_HEAD := Color(1, 1, 1, 0.12)
const TABLE_ODD := Color(1, 1, 1, 0.0)
const TABLE_EVEN := Color(1, 1, 1, 0.04)
const TABLE_BORDER := Color(1, 1, 1, 0.2)
## Meta prefix of wikilinks: meta_clicked gets "wiki:Target#Section".
const WIKI := "wiki:"
## Groups: 1 target, 2 section, 3 label.
const WIKILINK := "\\G\\[\\[([^\\]|#\\\\]*)(?:#([^\\]|\\\\]*))?(?:\\\\?\\|([^\\]]*))?\\]\\]"
const HEADING_SIZES := [22, 19, 17, 15, 15, 15]
## `(url "optional title")` after a link or image; group 2 of IMAGE is the url.
const TARGET := "\\(\\s*<?([^)\\s>]+)>?(?:\\s+\"[^\"]*\")?\\s*\\)"
const IMAGE := "!\\[([^\\]]*)\\]" + TARGET

static var _regexes := {}


## The document as BBCode strings and images ({"image": src, "alt": alt}), in order.
## Images are only split out where they stand in a paragraph; elsewhere (tables,
## lists, headings) they become links, since BBCode can't hold loaded textures.
static func to_segments(md: String) -> Array:
	var out := []
	var lines := md.replace("\r\n", "\n").replace("\t", "    ").split("\n")
	var i := 0
	while i < lines.size():
		var line: String = lines[i]
		var stripped := line.strip_edges()
		if stripped == "":
			i += 1
			continue
		if not out.is_empty():
			out.append("\n")

		if stripped.begins_with("```") or stripped.begins_with("~~~"):
			var fence := stripped.substr(0, 3)
			var code := PackedStringArray()
			i += 1
			while i < lines.size() and not lines[i].strip_edges().begins_with(fence):
				code.append(lines[i])
				i += 1
			i += 1  # the closing fence
			out.append(_code_block("\n".join(code)))
			continue

		var m := _re("^(#{1,6})\\s+(.*?)(?:\\s+#+)?\\s*$").search(stripped)
		if m:
			var level := m.get_string(1).length()
			out.append("[font_size=%d][b]%s[/b][/font_size]" % [HEADING_SIZES[level - 1], inline(m.get_string(2))])
			i += 1
			continue

		if _re("^([-*_])(\\s*\\1){2,}$").search(stripped):
			out.append("[hr color=#%s height=1 width=100%%]" % TABLE_BORDER.to_html())
			i += 1
			continue

		if i + 1 < lines.size() and "|" in line and _is_table_separator(lines[i + 1]):
			var rows := [_cells(line)]
			i += 2
			while i < lines.size() and "|" in lines[i] and lines[i].strip_edges() != "":
				rows.append(_cells(lines[i]))
				i += 1
			out.append(_table(rows))
			continue

		if stripped.begins_with(">"):
			var quote := PackedStringArray()
			while i < lines.size() and lines[i].strip_edges().begins_with(">"):
				var q := lines[i].strip_edges().substr(1)
				quote.append(q.substr(1) if q.begins_with(" ") else q)
				i += 1
			out.append("[indent][color=#%s][i]%s[/i][/color][/indent]" % [MUTED.to_html(), to_bbcode("\n".join(quote))])
			continue

		if _list_item(line):
			var items := []  # [indent, marker, text]
			while i < lines.size():
				var item := _list_item(lines[i])
				if item:
					items.append([item.get_string(1).length(), item.get_string(2), item.get_string(3)])
				elif lines[i].strip_edges() == "":
					# A blank line inside a list only continues it if another item follows.
					var next := i + 1
					while next < lines.size() and lines[next].strip_edges() == "":
						next += 1
					if next >= lines.size() or not _list_item(lines[next]):
						break
				elif lines[i].begins_with("  ") or not _starts_block(lines[i]):
					items[-1][2] += "\n" + lines[i].strip_edges()  # continuation of the item
				else:
					break
				i += 1
			out.append(_list(items))
			continue

		# A paragraph: lines up to the next blank line or block.
		var para := PackedStringArray([line.strip_edges()])
		i += 1
		while i < lines.size() and lines[i].strip_edges() != "" and not _starts_block(lines[i]) \
				and not (i + 1 < lines.size() and "|" in lines[i] and _is_table_separator(lines[i + 1])):
			para.append(lines[i].strip_edges())
			i += 1
		out.append_array(_paragraph("\n".join(para)))

	# Merge neighbouring strings.
	var merged := []
	for seg in out:
		if seg is String and not merged.is_empty() and merged[-1] is String:
			merged[-1] += seg
		else:
			merged.append(seg)
	return merged


## The document as one BBCode string, images as links.
static func to_bbcode(md: String) -> String:
	var bbcode := ""
	for seg in to_segments(md):
		bbcode += seg if seg is String else _image_link(seg["image"], seg["alt"])
	return bbcode


## Plain text, safe inside BBCode.
static func escape(text: String) -> String:
	return text.replace("[", "[lb]")


## Inline formatting of one block of text (images become links).
static func inline(text: String) -> String:
	var out := ""
	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		var m: RegExMatch

		if c == "\\" and i + 1 < n and text[i + 1] in "\\`*_{}[]()#+-.!|~<>":
			out += escape(text[i + 1])
			i += 2
			continue

		if c == "`":
			var ticks := _re("\\G`+").search(text, i).get_string()
			var end := text.find(ticks, i + ticks.length())
			if end != -1:
				var code := text.substr(i + ticks.length(), end - i - ticks.length())
				if code.length() > 2 and code.begins_with(" ") and code.ends_with(" "):
					code = code.substr(1, code.length() - 2)
				out += "[bgcolor=#%s][code]%s[/code][/bgcolor]" % [CODE_BG.to_html(), escape(code)]
				i = end + ticks.length()
				continue
			out += ticks
			i += ticks.length()
			continue

		if c == "!":
			m = _re("\\G" + IMAGE).search(text, i)
			if m:
				out += _image_link(m.get_string(2), m.get_string(1))
				i = m.get_end()
				continue

		if c == "[" and i + 1 < n and text[i + 1] == "[":
			m = _re(WIKILINK).search(text, i)
			if m:
				var target := m.get_string(1).strip_edges()
				var section := m.get_string(2).strip_edges()
				var label := m.get_string(3).strip_edges()
				if label == "":
					label = target if section == "" else section
				out += _link(WIKI + target + ("#" + section if section != "" else ""), escape(label))
				i = m.get_end()
				continue

		if c == "[":
			m = _re("\\G\\[((?:[^\\[\\]]|\\[[^\\]]*\\])+)\\]" + TARGET).search(text, i)
			if m:
				out += _link(m.get_string(2), inline(m.get_string(1)))
				i = m.get_end()
				continue

		if c == "<":
			m = _re("\\G<((?:https?://|mailto:)[^>\\s]+)>").search(text, i)
			if m:
				out += _link(m.get_string(1), escape(m.get_string(1)))
				i = m.get_end()
				continue

		if c == "h" and (i == 0 or not _is_word(text[i - 1])):
			m = _re("\\Ghttps?://[^\\s<>()\\[\\]]*[^\\s<>()\\[\\].,;:!?'\"]").search(text, i)
			if m:
				out += _link(m.get_string(), escape(m.get_string()))
				i = m.get_end()
				continue

		if c in "*_~":
			var emphasis := _emphasis(text, i)
			if not emphasis.is_empty():
				out += emphasis[0]
				i = emphasis[1]
				continue

		out += escape(c)
		i += 1
	return out


# --- Blocks ---------------------------------------------------------------------

static func _paragraph(text: String) -> Array:
	var segs := []
	var from := 0
	for m in _re(IMAGE).search_all(text):
		if m.get_start() > from:
			segs.append(inline(text.substr(from, m.get_start() - from)))
		segs.append({"image": m.get_string(2), "alt": m.get_string(1)})
		from = m.get_end()
	if from < text.length():
		segs.append(inline(text.substr(from)))
	return segs


static func _code_block(code: String) -> String:
	return "[table=1][cell bg=#%s padding=8,6,8,6][code]%s[/code][/cell][/table]" % [CODE_BG.to_html(), escape(code)]


## `items` are [indent, marker, text]. Each item is its own [ul] (so it keeps its own
## marker: numbers, task boxes); nested items go inside their parent's [ul].
static func _list(items: Array) -> String:
	return _list_items(items, 0)[0]


## [bbcode, next index] for the items from `start` on at its indentation or deeper.
static func _list_items(items: Array, start: int) -> Array:
	var level: int = items[start][0]
	var out := PackedStringArray()
	var i := start
	while i < items.size() and items[i][0] >= level:
		var marker: String = items[i][1]
		var text: String = items[i][2]
		if marker in ["-", "*", "+"]:
			marker = "•"
			var box := _re("^\\[([ xX])\\]\\s+").search(text)
			if box:
				marker = "☐" if box.get_string(1) == " " else "☑"
				text = text.substr(box.get_end())
		var bb := "[ul bullet=%s]%s" % [marker.replace(")", "."), inline(text)]
		i += 1
		if i < items.size() and items[i][0] > level:
			var children := _list_items(items, i)
			bb += "\n" + children[0]
			i = children[1]
		out.append(bb + "[/ul]")
	return ["\n".join(out), i]


static func _table(rows: Array) -> String:
	var columns: int = rows[0].size()
	var bb := "[table=%d]" % columns
	var pad := "padding=7,3,7,3 border=#%s" % TABLE_BORDER.to_html()
	for r in rows.size():
		for c in columns:
			var cell: String = rows[r][c] if c < rows[r].size() else ""
			if r == 0:
				bb += "[cell bg=#%s %s][b]%s[/b][/cell]" % [TABLE_HEAD.to_html(), pad, inline(cell)]
			else:
				bb += "[cell bg=#%s,#%s %s]%s[/cell]" % [TABLE_ODD.to_html(), TABLE_EVEN.to_html(), pad, inline(cell)]
	return bb + "[/table]"


static func _cells(line: String) -> PackedStringArray:
	var s := line.strip_edges()
	if s.begins_with("|"):
		s = s.substr(1)
	if s.ends_with("|") and not s.ends_with("\\|"):
		s = s.substr(0, s.length() - 1)
	var cells := PackedStringArray()
	for cell in s.replace("\\|", "\u0001").split("|"):
		cells.append(cell.replace("\u0001", "\\|").strip_edges())
	return cells


static func _is_table_separator(line: String) -> bool:
	return _re("^\\s*\\|?\\s*:?-+:?\\s*(\\|\\s*:?-+:?\\s*)*\\|?\\s*$").search(line) != null and "-" in line


static func _list_item(line: String) -> RegExMatch:
	return _re("^(\\s*)([-*+]|\\d{1,9}[.)])\\s+(.*)$").search(line)


static func _starts_block(line: String) -> bool:
	var s := line.strip_edges()
	return s.begins_with("```") or s.begins_with("~~~") or s.begins_with(">") \
			or _re("^#{1,6}\\s").search(s) != null or _re("^([-*_])(\\s*\\1){2,}$").search(s) != null \
			or _list_item(line) != null


# --- Inline ---------------------------------------------------------------------

## [bbcode, end index] for emphasis starting at `i`, or [] if it isn't one.
static func _emphasis(text: String, i: int) -> Array:
	for delim: String in ["***", "___", "**", "__", "~~", "*", "_"]:
		if not text.substr(i).begins_with(delim):
			continue
		var after := i + delim.length()
		if after >= text.length() or text[after] == " " or text[after] == delim[0]:
			continue
		# snake_case and 2*3*4 are not emphasis.
		if delim[0] != "~" and i > 0 and _is_word(text[i - 1]) and (delim[0] == "_" or text[i - 1].is_valid_int()):
			continue
		var end := after
		while true:
			end = text.find(delim, end + 1)
			if end == -1:
				break
			var closes := text[end - 1] != " " and (end + delim.length() >= text.length()
					or not (delim[0] == "_" and _is_word(text[end + delim.length()])))
			if closes and (end + delim.length() >= text.length() or text[end + delim.length()] != delim[0]):
				break
		if end == -1:
			continue
		var inner := inline(text.substr(after, end - after))
		var tags: Array = {"***": ["b", "i"], "___": ["b", "i"], "**": ["b"], "__": ["b"],
				"~~": ["s"], "*": ["i"], "_": ["i"]}[delim]
		var open := ""
		var close := ""
		for tag in tags:
			open += "[%s]" % tag
			close = "[/%s]" % tag + close
		return [open + inner + close, end + delim.length()]
	return []


static func _link(url: String, label_bbcode: String) -> String:
	var safe := url.replace("[", "%5B").replace("]", "%5D")
	return "[url=%s][color=#%s]%s[/color][/url]" % [safe, LINK.to_html(), label_bbcode]


static func _image_link(src: String, alt: String) -> String:
	var label := "[i]%s[/i]" % escape(alt if alt != "" else "image")
	return _link(src, label) if src.begins_with("https://") else label


static func _is_word(c: String) -> bool:
	return c.is_valid_identifier() or c.is_valid_int()


static func _re(pattern: String) -> RegEx:
	if not _regexes.has(pattern):
		_regexes[pattern] = RegEx.create_from_string(pattern)
	return _regexes[pattern]
