extends RefCounted
## A folder of level-code files for the in-game level list. It only reads names,
## authors and file names; the game loads a chosen file through its usual path.
##
## Entry: {"path", "file", "name", "author", "ok", "error"}. `name` falls back to
## the file name. An unreadable file stays in the list with `ok = false`.

const Reader = preload("res://src/level/level_code.gd")
## File name extensions read as level codes, in lower case.
const EXTENSIONS := ["json", "txt"]
## More files than this in one folder are not listed.
const MAX_FILES := 4096


## Read every level-code file directly in `directory`, sorted by file name.
## Returns {"ok": true, "levels": Array} or {"ok": false, "error": String}.
static func scan(directory: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(directory):
		return {"ok": false, "error": "Level folder not found: " + directory}
	var names := []
	for file: String in DirAccess.get_files_at(directory):
		if file.get_extension().to_lower() in EXTENSIONS and not file.begins_with("."):
			names.append(file)
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	var levels := []
	for file: String in names.slice(0, MAX_FILES):
		var path := directory.path_join(file)
		var size := FileAccess.get_size(path) if FileAccess.file_exists(path) else -1
		if size > Reader.MAX_CODE_BYTES:
			levels.append(_failed(path, "Larger than 16 MiB"))
			continue
		levels.append(entry(path, FileAccess.get_file_as_string(path)))
	return {"ok": true, "levels": levels, "truncated": names.size() > MAX_FILES}


## The list entry for one file. `code` is the file's text.
static func entry(path: String, code: String) -> Dictionary:
	if code.is_empty():
		return _failed(path, "Empty or unreadable")
	# A JSON instance reports a bad file through its result, not the error log.
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(code) == OK else null
	if not parsed is Dictionary or not parsed.get("maps") is Dictionary:
		return _failed(path, "Not a level code")
	var result := _failed(path, "")
	result.ok = true
	result.name = _text(parsed.get("name"))
	if result.name.is_empty():
		result.name = path.get_file()
	# An absent author can be exported as numeric zero; show no author then.
	var author: Variant = parsed.get("author")
	result.author = "" if (author is float or author is int) and author == 0 else _text(author)
	return result


## The index of the next readable level after `current`, or -1 at the end.
static func next_index(levels: Array, current: int) -> int:
	if current < 0:
		return -1
	for index in range(current + 1, levels.size()):
		if levels[index].ok:
			return index
	return -1


## The index of the entry whose file is `path`, or -1.
static func find(levels: Array, path: String) -> int:
	var wanted := ProjectSettings.globalize_path(path).simplify_path()
	for index in levels.size():
		if ProjectSettings.globalize_path(levels[index].path).simplify_path() == wanted:
			return index
	return -1


static func _failed(path: String, error: String) -> Dictionary:
	return {
		"path": path, "file": path.get_file(), "name": path.get_file(), "author": "",
		"ok": false, "error": error
	}


## Display text for a name or author. A number (an absent author can be exported
## as zero) prints without a fraction. Line breaks become spaces.
static func _text(value: Variant) -> String:
	var text := ""
	if value is String:
		text = value
	elif (value is float or value is int) and is_finite(float(value)):
		text = String.num(float(value)).trim_suffix(".0")
	for separator: String in ["\r\n", "\n", "\r", "\t"]:
		text = text.replace(separator, " ")
	return text.strip_edges()
