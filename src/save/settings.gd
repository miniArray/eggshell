class_name PlaySettings
extends RefCounted
## Player preferences in `settings.json`. Missing volume and zoom keys use defaults.

const DEFAULT_VOLUME := 80
const VOLUME_KEYS := ["music_volume", "effects_volume"]
## Saved zoom steps stay within this many steps of the container fit.
const ZOOM_LIMIT := 16


static func defaults() -> Dictionary:
	return {
		"resume": true, "music_volume": DEFAULT_VOLUME, "effects_volume": DEFAULT_VOLUME, "zoom": 0
	}


static func read_or_create(directory: String) -> Dictionary:
	var path := directory.path_join("settings.json")
	var result := defaults()
	result.error = ""
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if (
			not parsed is Dictionary
			or parsed.get("version") != 1
			or not parsed.get("resume_where_i_left_off") is bool
		):
			result.error = "Invalid settings; using defaults"
			return result
		result.resume = parsed.resume_where_i_left_off
		var invalid := []
		for key: String in VOLUME_KEYS:
			if not parsed.has(key):
				continue
			var volume := volume_value(parsed[key])
			if volume < 0:
				invalid.append(key)
			else:
				result[key] = volume
		var messages := []
		if not invalid.is_empty():
			messages.append(
				"Invalid %s; using %d" % [", ".join(PackedStringArray(invalid)), DEFAULT_VOLUME]
			)
		if parsed.has("zoom"):
			var zoom: Variant = zoom_value(parsed.zoom)
			if zoom == null:
				messages.append("Invalid zoom; using 0")
			else:
				result.zoom = zoom
		result.error = "; ".join(PackedStringArray(messages))
		return result
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		result.error = "Cannot create settings directory"
		return result
	result.error = _write(path, _stored(result))
	return result


## Store a new zoom step and keep every other saved preference. Returns an error
## message, or an empty string.
static func save_zoom(directory: String, zoom: int) -> String:
	var path := directory.path_join("settings.json")
	var current := read_or_create(directory)
	if current.error.begins_with("Cannot"):
		return current.error
	var stored: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	stored = parsed if parsed is Dictionary and current.error.is_empty() else _stored(current)
	stored.zoom = clampi(zoom, -ZOOM_LIMIT, ZOOM_LIMIT)
	return _write(path, stored)


## Returns a whole volume from 0 to 100, or -1 for any other value.
static func volume_value(value: Variant) -> int:
	if not (value is int or value is float):
		return -1
	if not is_finite(float(value)) or value != floor(value) or value < 0 or value > 100:
		return -1
	return int(value)


## Returns a whole zoom step within ZOOM_LIMIT, or null for any other value.
static func zoom_value(value: Variant) -> Variant:
	if value is bool or not (value is int or value is float):
		return null
	if not is_finite(float(value)) or value != floor(value) or absf(value) > ZOOM_LIMIT:
		return null
	return int(value)


static func _stored(values: Dictionary) -> Dictionary:
	return {
		"version": 1,
		"resume_where_i_left_off": values.resume,
		"music_volume": values.music_volume,
		"effects_volume": values.effects_volume,
		"zoom": values.zoom
	}


static func _write(path: String, values: Dictionary) -> String:
	# Write a sibling file, then rename it, so a failed write keeps the old settings.
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot create settings file"
	file.store_string(JSON.stringify(values, "\t"))
	file.close()
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return "Cannot replace settings file"
	return ""
