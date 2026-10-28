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
## Bytes read first from a large file to find its name and author.
const HEAD_BYTES := 4096


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
		# Most files name the level before their maps: read only the start first.
		var found := entry(path, _head(path))
		if not found.ok and size > HEAD_BYTES:
			found = entry(path, FileAccess.get_file_as_string(path))
		levels.append(found)
	return {"ok": true, "levels": levels, "truncated": names.size() > MAX_FILES}


## The list entry for one file. `code` is the file's text.
static func entry(path: String, code: String) -> Dictionary:
	if code.is_empty():
		return _failed(path, "Empty or unreadable")
	var parsed: Variant = header(code)
	if parsed == null:
		parsed = _json(code)
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


## The top-level fields before `"maps"` as a Dictionary, or null. It parses only
## that prefix, so a large level is not read in full to list its name. Any doubt
## (no such key, no name before it, other JSON errors) returns null.
static func header(code: String) -> Variant:
	var start := code.find("{")
	var cut := code.find("\"maps\"")
	if start < 0 or cut <= start:
		return null
	var prefix := code.substr(start, cut - start).strip_edges()
	if prefix.ends_with(","):
		prefix = prefix.left(-1)
	var parsed: Variant = _json(prefix + "}")
	if (
		not parsed is Dictionary
		or not parsed.has("name")
		or not code.substr(cut + 6, 64).strip_edges().begins_with(":")
	):
		return null
	return parsed


static func _json(text: String) -> Variant:
	# A JSON instance reports a bad file through its result, not the error log.
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


static func _head(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_buffer(HEAD_BYTES).get_string_from_utf8()


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
