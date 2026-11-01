class_name ImportJobs
extends RefCounted
## The VTT side of the import agent (TASK-28, import-agent.md "VTT <-> tool"): starts
## tools/import_agent.py as its own process for a PDF, image or link, follows its job folder
## (data/imports/<job>/: job.json, progress.log, the tool's raw draft package). A finished job
## is merged into its target package as drafts (TASK-30): hidden from the book and players
## until published, where same names are asked about.
## Settings (API key, python, agent script) live in user:// only, never in data/ or git.

static var settings_file := "user://import_settings.cfg"  ## tests point this elsewhere
const FILE_KINDS := {"pdf": "pdf", "png": "image", "jpg": "image", "jpeg": "image", "webp": "image"}

var packages_root := ""
var imports_root := ""  ## data/imports next to the packages
var pids := {}  ## job id -> process id (this run)


func _init(root := "") -> void:
	packages_root = root if root != "" else PackageDB.default_root()
	imports_root = packages_root.get_base_dir().path_join("imports")


# --- Settings -------------------------------------------------------------------------------

static func setting(key: String, default := "") -> String:
	var cfg := ConfigFile.new()
	cfg.load(settings_file)
	return str(cfg.get_value("import", key, default))


static func set_setting(key: String, value: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_file)
	cfg.set_value("import", key, value)
	cfg.save(settings_file)


static func python() -> String:
	return setting("python", "python")


## The agent script: the setting, else tools/import_agent.py of the project (or next to the exe).
static func agent_script() -> String:
	var s := setting("agent", "")
	if s != "":
		return s
	var dev := ProjectSettings.globalize_path("res://tools/import_agent.py")
	return dev if FileAccess.file_exists(dev) else OS.get_executable_path().get_base_dir().path_join("tools/import_agent.py")


## "pdf", "image" or "url" for an input ("" = not importable).
static func input_kind(input: String) -> String:
	if input.begins_with("http://") or input.begins_with("https://"):
		return "url"
	return FILE_KINDS.get(input.get_extension().to_lower(), "")


# --- Jobs ------------------------------------------------------------------------------------------

## Starts an import: creates data/imports/<job>/ with job.json and launches the agent
## (the API key goes in as the ANTHROPIC_API_KEY environment variable, never as an argument
## or into a file). `target` is a package id or "new:<name>". Returns the job ({} + error).
func start(input: String, target: String) -> Dictionary:
	var kind := input_kind(input)
	if kind == "":
		return {"error": "Can't import %s (PDF, PNG, JPG, WebP or a link)" % input.get_file()}
	if kind != "url" and not FileAccess.file_exists(input):
		return {"error": "No file %s" % input}
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	var base := "%s-%s" % [stamp, EntryStore.slug(input.get_file().get_basename() if kind != "url" else input.get_slice("//", 1).get_slice("/", 0))]
	var job_id := base
	var n := 2
	while DirAccess.dir_exists_absolute(imports_root.path_join(job_id)):
		job_id = "%s-%d" % [base, n]
		n += 1
	var dir := imports_root.path_join(job_id)
	DirAccess.make_dir_recursive_absolute(dir)
	var job := {"id": job_id, "input": input, "kind": kind, "target": target, "status": "starting",
		"started": Time.get_datetime_string_from_system()}
	EntryStore._write(dir.path_join("job.json"), job)
	var script := agent_script()
	if not FileAccess.file_exists(script):
		job.status = "failed"
		job["error"] = "The import tool is missing (%s)" % script
		EntryStore._write(dir.path_join("job.json"), job)
		return job
	var key := setting("api_key", "")
	if key != "":
		OS.set_environment("ANTHROPIC_API_KEY", key)
	var pid := OS.create_process(python(), [script, "--input", input, "--kind", kind, "--target", target,
		"--job", dir, "--packages", packages_root])
	if key != "":
		OS.unset_environment("ANTHROPIC_API_KEY")
	if pid <= 0:
		job.status = "failed"
		job["error"] = "Can't start %s (is Python installed? see Import settings)" % python()
		EntryStore._write(dir.path_join("job.json"), job)
		return job
	pids[job_id] = pid
	return job


func job_dir(job_id: String) -> String:
	return imports_root.path_join(job_id)


## A job as it is now: job.json, `log` (progress.log) and `running` (the process lives).
## A job whose process ended without saying done/failed counts as failed.
func status(job_id: String) -> Dictionary:
	var dir := job_dir(job_id)
	var job: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("job.json"))) \
		if FileAccess.file_exists(dir.path_join("job.json")) else null
	if not job is Dictionary:
		return {}
	job["log"] = FileAccess.get_file_as_string(dir.path_join("progress.log")) if FileAccess.file_exists(dir.path_join("progress.log")) else ""
	var pid: int = pids.get(job_id, 0)
	job["running"] = pid > 0 and OS.is_process_running(pid)
	if str(job.status) in ["starting", "running"] and pid > 0 and not job.running:
		job.status = "failed"
		job["error"] = str(job.get("error", "The import tool stopped without finishing"))
	return job


## Every job, newest first.
func jobs() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(imports_root):
		return out
	var ids := Array(DirAccess.get_directories_at(imports_root))
	ids.sort()
	ids.reverse()
	for id: String in ids:
		var s := status(id)
		if not s.is_empty():
			out.append(s)
	return out


func cancel(job_id: String) -> void:
	var pid: int = pids.get(job_id, 0)
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	var s := status(job_id)
	if not s.is_empty() and str(s.status) in ["starting", "running"]:
		s.status = "cancelled"
		s.erase("log")
		s.erase("running")
		EntryStore._write(job_dir(job_id).path_join("job.json"), s)


# --- Merging into the package as drafts (TASK-30) -----------------------------------------------------

## The tool's draft package of a job (null until it wrote package.json).
func drafts(job_id: String) -> EntryStore:
	return EntryStore.open(job_dir(job_id))


## The target package for a job: an existing package or a new world package ("new:<name>").
func target_store(target: String) -> EntryStore:
	if target.begins_with("new:"):
		return EntryStore.create_package(PackageManager.new(packages_root).root, target.substr(4).strip_edges())  # a new book (TASK-39)
	return EntryStore.open(PackageManager.new(packages_root).folder_of(target))


## Merges every finished job that is not merged yet; returns the ids of the packages that got drafts.
func merge_finished() -> PackedStringArray:
	var out := PackedStringArray()
	for j: Dictionary in jobs():
		if str(j.status) == "done" and not bool(j.get("merged", false)):
			var r := merge(str(j.id))
			if r.has("package") and str(r.package) not in out:
				out.append(str(r.package))
	return out


## Puts a finished job's entries into its target package as drafts: features, tables and
## pictures along (ids that are taken get new ones, references follow), the source pages
## under imports/<job>/, every entry with `draft: true` and `origin {import, file|url, page, job}`.
## Same names are not asked about here but when publishing. A read-only source package as
## target is unlocked (picking it was the choice). Returns {package, count} or {error}.
func merge(job_id: String) -> Dictionary:
	var s := status(job_id)
	if s.is_empty() or str(s.status) != "done":
		return {"error": "The job is not finished"}
	if bool(s.get("merged", false)):
		return {"package": str(s.get("merged_into", "")), "count": 0}
	var src := drafts(job_id)
	if src == null:
		return {"error": "The job left no entries"}
	var target := target_store(str(s.target))
	if target == null:
		return {"error": "No package %s" % s.target}
	if target.is_read_only():
		target.unlock()
	var ids := {}  ## "kind/old id" -> new id
	var kinds := []
	for file in DirAccess.get_files_at(src.folder):
		var kind := file.get_basename()
		if file.ends_with(".json") and kind not in ["package", "job"]:
			kinds.append(kind)
	# features first (monsters point at them), tables last (they point at their entry)
	kinds.sort_custom(func(a: String, b: String) -> bool: return _order(a) < _order(b))
	var count := 0
	for kind: String in kinds:
		for e: Variant in src.list(kind):
			if not e is Dictionary or not e.has("id"):
				continue
			var copy: Dictionary = EntryStore.strip(e).duplicate(true)
			var old_id := str(copy.id)
			copy["id"] = target.free_id(kind, str(copy.get("name", old_id))) if target.has(kind, old_id) else old_id
			ids["%s/%s" % [kind, old_id]] = str(copy.id)
			if kind == "creatures":
				for list_key in PackageDB.FEATURE_LISTS:
					if copy.get(list_key) is Array:
						copy[list_key] = copy[list_key].map(func(f: Variant) -> String: return str(ids.get("features/" + str(f), f)))
			if kind == "tables" and str(copy.get("parent", "")) != "":
				var parent := str(copy.parent)
				if ids.has(parent):
					copy["parent"] = "%s/%s" % [parent.get_slice("/", 0), ids[parent]]
			for key in ["image", "token", "source_page"]:
				if str(copy.get(key, "")) != "":
					copy[key] = _copy_file(src, target, str(copy[key]), "imports/%s/%s" % [job_id, copy[key]])
			var origin: Dictionary = copy.get("origin", {}) if copy.get("origin") is Dictionary else {}
			origin["import"] = str(origin.get("import", s.kind))
			if not origin.has("file") and not origin.has("url"):
				origin["url" if str(s.kind) == "url" else "file"] = str(s.input)
			origin["job"] = job_id
			copy["origin"] = origin
			copy["draft"] = true
			target.save(kind, copy)
			count += 1
	s.erase("log")
	s.erase("running")
	s["merged"] = true
	s["merged_into"] = target.id
	s["count"] = count
	s["target"] = target.id  # a new package exists now
	EntryStore._write(job_dir(job_id).path_join("job.json"), s)
	_append_log(job_id, "%d draft(s) put into %s" % [count, target.name])
	return {"package": target.id, "count": count}


static func _order(kind: String) -> int:
	return 0 if kind == "features" else 2 if kind == "tables" else 1


func _copy_file(src: EntryStore, target: EntryStore, rel: String, to_rel: String) -> String:
	var from := src.folder.path_join(rel)
	if not FileAccess.file_exists(from):
		return rel
	DirAccess.make_dir_recursive_absolute(target.folder.path_join(to_rel).get_base_dir())
	DirAccess.copy_absolute(from, target.folder.path_join(to_rel))
	return to_rel


func _append_log(job_id: String, line: String) -> void:
	var path := job_dir(job_id).path_join("progress.log")
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_string(line + "\n")
		f.close()
