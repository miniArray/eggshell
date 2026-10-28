class_name PlaySettings
extends RefCounted
## Player preferences in `settings.json`. Missing volume keys use their defaults.

const DEFAULT_VOLUME := 80
const VOLUME_KEYS := ["music_volume", "effects_volume"]


static func defaults() -> Dictionary:
	return {"resume": true, "music_volume": DEFAULT_VOLUME, "effects_volume": DEFAULT_VOLUME}


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
		if not invalid.is_empty():
			result.error = (
				"Invalid %s; using %d" % [", ".join(PackedStringArray(invalid)), DEFAULT_VOLUME]
			)
		return result
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		result.error = "Cannot create settings directory"
		return result
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		result.error = "Cannot create settings file"
		return result
	file.store_string(
		JSON.stringify(
			{
				"version": 1,
				"resume_where_i_left_off": true,
				"music_volume": DEFAULT_VOLUME,
				"effects_volume": DEFAULT_VOLUME
			},
			"\t"
		)
	)
	file.close()
	return result


## Returns a whole volume from 0 to 100, or -1 for any other value.
static func volume_value(value: Variant) -> int:
	if not (value is int or value is float):
		return -1
	if not is_finite(float(value)) or value != floor(value) or value < 0 or value > 100:
		return -1
	return int(value)
