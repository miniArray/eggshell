class_name PlaySettings
extends RefCounted


static func read_or_create(directory: String) -> Dictionary:
	var path := directory.path_join("settings.json")
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if (
			parsed is Dictionary
			and parsed.get("version") == 1
			and parsed.get("resume_where_i_left_off") is bool
		):
			return {"resume": parsed.resume_where_i_left_off, "error": ""}
		return {"resume": true, "error": "Invalid settings; using resume enabled"}
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"resume": true, "error": "Cannot create settings directory"}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"resume": true, "error": "Cannot create settings file"}
	file.store_string(JSON.stringify({"version": 1, "resume_where_i_left_off": true}, "\t"))
	file.close()
	return {"resume": true, "error": ""}
