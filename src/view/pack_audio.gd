extends RefCounted
## Audio lookup only. This holder creates no player and never starts playback.
const Pack = preload("res://src/level/asset_pack.gd")
var music: Dictionary = {}
var effects: Dictionary = {}
var _streams: Dictionary = {}


func setup(manifest: Dictionary, pack: String) -> void:
	music.clear()
	effects.clear()
	_streams.clear()
	var audio: Dictionary = manifest.get("audio", {})
	for section: String in ["music", "effects"]:
		var entries: Variant = audio.get(section, {})
		if not entries is Dictionary:
			continue
		var target: Dictionary = music if section == "music" else effects
		for key: Variant in entries:
			var file: Variant = entries[key]
			if Pack.safe_file(file) and file.get_extension().to_lower() == "ogg":
				target[str(key)] = pack.path_join(file)


func stream(section: String, key: String) -> AudioStream:
	if section not in ["music", "effects"]:
		return null
	var entries := music if section == "music" else effects
	var path: String = entries.get(key, "")
	if path.is_empty():
		return null
	if not _streams.has(path):
		_streams[path] = (
			ResourceLoader.load(path, "AudioStream") as AudioStream
			if path.begins_with("res://")
			else AudioStreamOggVorbis.load_from_file(path)
		)
	return _streams[path]
