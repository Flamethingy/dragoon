class_name Frontmatter
extends RefCounted
## Markdown files with YAML frontmatter -> {"frontmatter": Dictionary, "body": String}.
##
## Godot has no YAML parser, so this reads the subset our entity files use (decision in
## TASK-3, see backlog/docs/progress.md):
## - block maps (`key: value`, nesting by indentation) and block lists (`- item`,
##   including lists of maps: `- name: Bite`)
## - flow maps and lists: `{ str: 12, dex: 14 }`, `[a, "b", 3]` (nested too)
## - scalars: null/~, true/false, ints, floats, 'single' and "double" quoted strings
##   (with \" \\ \n \t escapes), plain strings; `# comments`
## - block strings `|` (keep lines) and `>` (fold into one line)
## Not supported (never written by us): anchors/aliases, tags, multi-document, complex keys.
## Unparseable lines are skipped with a warning instead of failing the whole file.


## Reads a file; {} if it can't be read.
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("File not found: %s" % path)
		return {}
	return parse(FileAccess.get_file_as_string(path))


## Splits off the frontmatter (between the first two `---` lines) and parses it.
## Without frontmatter: empty Dictionary and the whole text as body.
static func parse(text: String) -> Dictionary:
	text = text.replace("\r\n", "\n").trim_prefix("﻿")
	if not text.begins_with("---\n") and text.strip_edges() != "---":
		return {"frontmatter": {}, "body": text}
	var lines := text.split("\n")
	var end := -1
	for i in range(1, lines.size()):
		if lines[i].strip_edges() in ["---", "..."]:
			end = i
			break
	if end < 0:
		push_warning("Frontmatter is not closed with ---")
		return {"frontmatter": {}, "body": text}
	var yaml := "\n".join(lines.slice(1, end))
	var body := "\n".join(lines.slice(end + 1)).trim_prefix("\n")
	var data: Variant = parse_yaml(yaml)
	return {"frontmatter": data if data is Dictionary else {}, "body": body}


## Parses a YAML document of the supported subset.
static func parse_yaml(yaml: String) -> Variant:
	var lines: Array[Dictionary] = []  # {indent, text}, comments and blank lines removed
	var raw := yaml.replace("\r\n", "\n").replace("\t", "  ").split("\n")
	for line in raw:
		lines.append({"indent": line.length() - line.lstrip(" ").length(), "text": line.strip_edges(), "raw": line})
	var state := {"lines": lines, "i": 0}
	_skip_blank(state)
	if state.i >= lines.size():
		return {}
	return _block(state, int(lines[state.i].indent))


# --- Block structure --------------------------------------------------------------

static func _skip_blank(state: Dictionary) -> void:
	var lines: Array = state.lines
	while state.i < lines.size():
		var t: String = lines[state.i].text
		if t != "" and not t.begins_with("#"):
			return
		state.i += 1


## A map or list starting at the current line, with exactly this indentation.
static func _block(state: Dictionary, indent: int) -> Variant:
	var line: Dictionary = state.lines[state.i]
	if _is_item(line.text):
		return _list(state, indent)
	return _map(state, indent)


static func _is_item(text: String) -> bool:
	return text == "-" or text.begins_with("- ")


static func _map(state: Dictionary, indent: int) -> Dictionary:
	var result := {}
	var lines: Array = state.lines
	while true:
		_skip_blank(state)
		if state.i >= lines.size():
			break
		var line: Dictionary = lines[state.i]
		if line.indent < indent or line.indent == indent and _is_item(line.text):
			break
		if line.indent > indent:
			push_warning("Frontmatter: unexpected indentation: %s" % line.text)
			state.i += 1
			continue
		var colon := _key_colon(line.text)
		if colon < 0:
			push_warning("Frontmatter: not a 'key: value' line: %s" % line.text)
			state.i += 1
			continue
		var key := _unquote_key(line.text.substr(0, colon).strip_edges())
		var rest := _strip_comment(line.text.substr(colon + 1)).strip_edges()
		state.i += 1
		result[key] = _value_after_key(state, rest, indent)
	return result


## What follows `key:`: an inline value, a block string, or a nested block below.
static func _value_after_key(state: Dictionary, rest: String, indent: int) -> Variant:
	if rest == "|" or rest == ">" or rest in ["|-", ">-", "|+", ">+"]:
		return _block_string(state, indent, rest.begins_with(">"), rest.ends_with("-"))
	if rest != "":
		return _scalar_or_flow(rest)
	_skip_blank(state)
	var lines: Array = state.lines
	if state.i >= lines.size():
		return null
	var next: Dictionary = lines[state.i]
	if next.indent > indent or next.indent == indent and _is_item(next.text):
		return _block(state, next.indent)
	return null


static func _list(state: Dictionary, indent: int) -> Array:
	var result := []
	var lines: Array = state.lines
	while true:
		_skip_blank(state)
		if state.i >= lines.size():
			break
		var line: Dictionary = lines[state.i]
		if line.indent != indent or not _is_item(line.text):
			break
		var rest := _strip_comment(line.text.substr(1)).strip_edges()
		if rest == "":
			state.i += 1
			_skip_blank(state)
			if state.i < lines.size() and lines[state.i].indent > indent:
				result.append(_block(state, lines[state.i].indent))
			else:
				result.append(null)
		elif _key_colon(rest) >= 0 and not rest.begins_with("{") and not rest.begins_with("[") and not _is_quoted(rest):
			# "- key: value": a map whose first key sits on the item line. Rewrite the line
			# as that key, indented like the following keys, and parse the map from there.
			var item_indent: int = indent + (line.text.length() - line.text.substr(1).lstrip(" ").length())
			lines[state.i] = {"indent": item_indent, "text": line.text.substr(1).strip_edges(), "raw": line.raw}
			result.append(_map(state, item_indent))
		else:
			state.i += 1
			result.append(_scalar_or_flow(rest))
	return result


static func _block_string(state: Dictionary, indent: int, folded: bool, chomp: bool) -> String:
	var lines: Array = state.lines
	var parts := PackedStringArray()
	var block_indent := -1
	while state.i < lines.size():
		var line: Dictionary = lines[state.i]
		if line.text != "" and line.indent <= indent:
			break
		if block_indent < 0 and line.text != "":
			block_indent = line.indent
		var raw: String = line.raw
		parts.append(raw.substr(block_indent) if block_indent >= 0 and raw.length() >= block_indent else "")
		state.i += 1
	while not parts.is_empty() and parts[parts.size() - 1].strip_edges() == "":
		parts.remove_at(parts.size() - 1)
	var text := ""
	if folded:
		var paragraphs := PackedStringArray()
		var current := PackedStringArray()
		for p in parts:
			if p.strip_edges() == "":
				paragraphs.append(" ".join(current))
				current.clear()
			else:
				current.append(p.strip_edges())
		paragraphs.append(" ".join(current))
		text = "\n".join(paragraphs)
	else:
		text = "\n".join(parts)
	return text if chomp else text + "\n"


# --- Lines and scalars -----------------------------------------------------------

## Index of the `:` that ends the key (followed by a space or the end), outside quotes.
static func _key_colon(text: String) -> int:
	var quote := ""
	var depth := 0
	for i in text.length():
		var c := text[i]
		if quote != "":
			if c == quote:
				quote = ""
			elif c == "\\" and quote == "\"":
				pass
			continue
		if c == "\"" or c == "'":
			if i == 0:
				quote = c
			continue
		if c == "{" or c == "[":
			depth += 1
		elif c == "}" or c == "]":
			depth -= 1
		elif c == ":" and depth == 0 and (i == text.length() - 1 or text[i + 1] == " "):
			return i
	return -1


static func _unquote_key(key: String) -> String:
	if _is_quoted(key):
		return str(_scalar(key))
	return key


static func _is_quoted(text: String) -> bool:
	return text.length() >= 2 and (text[0] == "\"" or text[0] == "'")


## Drops a ` # comment` outside quotes.
static func _strip_comment(text: String) -> String:
	var quote := ""
	for i in text.length():
		var c := text[i]
		if quote != "":
			if c == "\\" and quote == "\"":
				continue
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#" and (i == 0 or text[i - 1] == " "):
			return text.substr(0, i)
	return text


static func _scalar_or_flow(text: String) -> Variant:
	if text.begins_with("{") or text.begins_with("["):
		var state := {"s": text, "i": 0}
		var value: Variant = _flow(state)
		return value
	return _scalar(text)


## A plain or quoted scalar to its type.
static func _scalar(text: String) -> Variant:
	text = text.strip_edges()
	if text.length() >= 2 and text[0] == "\"" and text.ends_with("\""):
		return _unescape(text.substr(1, text.length() - 2))
	if text.length() >= 2 and text[0] == "'" and text.ends_with("'"):
		return text.substr(1, text.length() - 2).replace("''", "'")
	match text:
		"", "~", "null", "Null", "NULL":
			return null
		"true", "True", "TRUE", "yes", "Yes":
			return true
		"false", "False", "FALSE", "no", "No":
			return false
	if text.is_valid_int():
		return text.to_int()
	if text.is_valid_float() and not text.contains(" "):
		return text.to_float()
	return text


static func _unescape(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		var c := s[i]
		if c == "\\" and i + 1 < s.length():
			i += 1
			match s[i]:
				"n": out += "\n"
				"t": out += "\t"
				"\"": out += "\""
				"\\": out += "\\"
				"/": out += "/"
				_: out += "\\" + s[i]
		else:
			out += c
		i += 1
	return out


# --- Flow collections ({...}, [...]) ----------------------------------------------

static func _flow(state: Dictionary) -> Variant:
	_flow_space(state)
	var s: String = state.s
	if state.i >= s.length():
		return null
	var c := s[state.i]
	if c == "{":
		state.i += 1
		var map := {}
		while true:
			_flow_space(state)
			if state.i >= s.length():
				push_warning("Frontmatter: unclosed {")
				break
			if s[state.i] == "}":
				state.i += 1
				break
			var key := str(_flow_token(state, true))
			_flow_space(state)
			var value: Variant = null
			if state.i < s.length() and s[state.i] == ":":
				state.i += 1
				value = _flow(state)
			map[key] = value
			_flow_space(state)
			if state.i < s.length() and s[state.i] == ",":
				state.i += 1
		return map
	if c == "[":
		state.i += 1
		var list := []
		while true:
			_flow_space(state)
			if state.i >= s.length():
				push_warning("Frontmatter: unclosed [")
				break
			if s[state.i] == "]":
				state.i += 1
				break
			list.append(_flow(state))
			_flow_space(state)
			if state.i < s.length() and s[state.i] == ",":
				state.i += 1
		return list
	return _flow_token(state, false)


static func _flow_space(state: Dictionary) -> void:
	var s: String = state.s
	while state.i < s.length() and s[state.i] == " ":
		state.i += 1


## A scalar inside a flow collection: quoted, or up to , ] } (or : for keys).
static func _flow_token(state: Dictionary, is_key: bool) -> Variant:
	var s: String = state.s
	var start: int = state.i
	if state.i < s.length() and (s[state.i] == "\"" or s[state.i] == "'"):
		var quote := s[state.i]
		state.i += 1
		while state.i < s.length():
			if s[state.i] == "\\" and quote == "\"":
				state.i += 2
				continue
			if s[state.i] == quote:
				if quote == "'" and state.i + 1 < s.length() and s[state.i + 1] == "'":
					state.i += 2
					continue
				break
			state.i += 1
		state.i += 1
		return _scalar(s.substr(start, state.i - start))
	while state.i < s.length():
		var c := s[state.i]
		if c == "," or c == "]" or c == "}":
			break
		if is_key and c == ":" and (state.i + 1 >= s.length() or s[state.i + 1] in [" ", ",", "}"]):
			break
		state.i += 1
	return _scalar(s.substr(start, state.i - start))
