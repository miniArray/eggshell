extends RefCounted
## The pack audio map: music tracks with optional loop and volume settings, effects,
## and neutral game events and music roles mapped to pack keys. Streams load lazily.
## This holder never plays audio; `audio_player.gd` owns playback.
const Pack = preload("res://src/level/asset_pack.gd")
## Track key -> absolute stream path.
var music: Dictionary = {}
## Effect key -> absolute stream path.
var effects: Dictionary = {}
## Track key -> {"loop_start": seconds, "volume_db": decibels}.
var music_settings: Dictionary = {}
## Neutral event name -> effect key, or a list of keys that take turns by frame.
var events: Dictionary = {}
## Neutral music role ("goal", "death") -> track key.
var tracks: Dictionary = {}
var _streams: Dictionary = {}


func setup(manifest: Dictionary, pack: String) -> void:
	music.clear()
	effects.clear()
	music_settings.clear()
	events.clear()
	tracks.clear()
	_streams.clear()
	var audio: Variant = manifest.get("audio", {})
	if not audio is Dictionary:
		return
	var entries: Variant = audio.get("music", {})
	if entries is Dictionary:
		for key: Variant in entries:
			var entry: Variant = entries[key]
			var file: Variant = entry.get("file") if entry is Dictionary else entry
			if not _ogg(file):
				continue
			music[str(key)] = pack.path_join(file)
			music_settings[str(key)] = _track_settings(entry)
	entries = audio.get("effects", {})
	if entries is Dictionary:
		for key: Variant in entries:
			if _ogg(entries[key]):
				effects[str(key)] = pack.path_join(entries[key])
	entries = audio.get("events", {})
	if entries is Dictionary:
		for key: Variant in entries:
			var keys := _key_list(entries[key])
			if not keys.is_empty():
				events[str(key)] = keys
	entries = audio.get("tracks", {})
	if entries is Dictionary:
		for key: Variant in entries:
			if entries[key] is String and not entries[key].is_empty():
				tracks[str(key)] = entries[key]


func is_empty() -> bool:
	return music.is_empty() and effects.is_empty()


## The effect key for a neutral event. Without a mapping, the event name is the key.
## A list mapping selects one key by the pick value, for example the saved frame.
func effect_key(event: String, pick := 0) -> String:
	var keys: Array = events.get(event, [event])
	return keys[posmod(pick, keys.size())]


## The track key for a music role. Without a mapping, the role name is the key.
func track_key(role: String) -> String:
	return tracks.get(role, role)


func settings_for(track: String) -> Dictionary:
	return music_settings.get(track, {"loop_start": 0.0, "volume_db": 0.0})


func stream(section: String, key: String) -> AudioStream:
	if section not in ["music", "effects"]:
		return null
	var entries := music if section == "music" else effects
	var path: String = entries.get(key, "")
	if path.is_empty():
		return null
	if not _streams.has(path):
		var loaded: AudioStream = null
		if path.begins_with("res://"):
			loaded = ResourceLoader.load(path, "AudioStream") as AudioStream
		elif FileAccess.file_exists(path):
			loaded = AudioStreamOggVorbis.load_from_file(path)
		if loaded == null:
			printerr("Audio file unreadable: " + path)
		_streams[path] = loaded
	return _streams[path]


static func _ogg(file: Variant) -> bool:
	return Pack.safe_file(file) and file.get_extension().to_lower() == "ogg"


static func _key_list(value: Variant) -> Array:
	var values: Array = value if value is Array else [value]
	var keys := []
	for item: Variant in values:
		if not item is String or item.is_empty():
			return []
		keys.append(item)
	return keys


static func _track_settings(entry: Variant) -> Dictionary:
	var result := {"loop_start": 0.0, "volume_db": 0.0}
	if not entry is Dictionary:
		return result
	var loop: Variant = entry.get("loop_start", 0.0)
	if Pack.number_ok(loop) and loop >= 0:
		result.loop_start = float(loop)
	var volume: Variant = entry.get("volume_db", 0.0)
	if Pack.number_ok(volume):
		result.volume_db = clampf(float(volume), -60.0, 24.0)
	return result
