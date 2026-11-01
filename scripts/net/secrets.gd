class_name Secrets
extends RefCounted
## DM-only content (TASK-8, concept "Secrets"). The marking is a PROPOSAL for TASK-1 until
## the schema decides it:
## - frontmatter: keys `dm`, `secret`, `secrets` and any key starting with `dm_`
##   (e.g. `dm_notes: ...`), at any depth
## - body: Obsidian comments `%% ... %%`, callouts `> [!dm]` / `> [!secret]`, and sections
##   whose heading is or starts with "DM" or "Secret" (until the next heading of the same
##   or a higher level)
## The host strips these before anything leaves it. Players get whitelisted fields anyway
## (see Campaign), so stripping is a second line of defence for when bodies are sent.

const SECRET_KEYS := ["dm", "secret", "secrets"]


static func is_secret_key(key: String) -> bool:
	var k := key.to_lower()
	return k in SECRET_KEYS or k.begins_with("dm_")


## A copy of the frontmatter without DM-only keys.
static func strip_frontmatter(data: Variant) -> Variant:
	if data is Dictionary:
		var out := {}
		for key: Variant in data:
			if not is_secret_key(str(key)):
				out[key] = strip_frontmatter(data[key])
		return out
	if data is Array:
		var out := []
		for item: Variant in data:
			out.append(strip_frontmatter(item))
		return out
	return data


## The body without DM-only parts.
static func strip_body(md: String) -> String:
	# %% comments %% (also across lines)
	var re := RegEx.create_from_string("(?s)%%.*?%%")
	md = re.sub(md, "", true)
	var out := PackedStringArray()
	var skip_level := 0  # > 0: inside a secret section of this heading level
	var in_callout := false
	for line in md.replace("\r\n", "\n").split("\n"):
		var heading := _heading_level(line)
		if skip_level > 0:
			if heading > 0 and heading <= skip_level:
				skip_level = 0
			else:
				continue
		if heading > 0 and _is_secret_title(line.substr(heading).strip_edges()):
			skip_level = heading
			continue
		var stripped := line.strip_edges()
		if in_callout:
			if stripped.begins_with(">"):
				continue
			in_callout = false
		var callout := stripped.to_lower().replace(" ", "")
		if callout.begins_with(">[!dm]") or callout.begins_with(">[!secret]") \
				or callout.begins_with(">[!dm]-") or callout.begins_with(">[!secret]-"):
			in_callout = true
			continue
		out.append(line)
	return "\n".join(out).strip_edges()


## {"frontmatter", "body"} -> the same without secrets.
static func strip_entity(entity: Dictionary) -> Dictionary:
	return {"frontmatter": strip_frontmatter(entity.get("frontmatter", {})),
		"body": strip_body(str(entity.get("body", "")))}


static func _heading_level(line: String) -> int:
	var n := 0
	while n < line.length() and line[n] == "#":
		n += 1
	return n if n > 0 and n <= 6 and line.length() > n and line[n] == " " else 0


static func _is_secret_title(title: String) -> bool:
	var t := title.to_lower()
	return t == "dm" or t.begins_with("dm ") or t.begins_with("dm:") or t.begins_with("dm-") \
		or t.begins_with("secret")
