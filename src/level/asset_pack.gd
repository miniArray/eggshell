extends RefCounted
## Pack metadata is presentation input only. Version 2 remains readable.
const VERSION := 3
const DEFAULT_PATH := "res://packs/pantry"


static func read(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path.path_join("manifest.json")):
		return {}
	var manifest: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path.path_join("manifest.json"))
	)
	if not manifest is Dictionary:
		printerr("Invalid asset pack manifest; using placeholders")
		return {}
	var version: Variant = manifest.get("version")
	if not number_ok(version) or version != 2 and version != VERSION:
		printerr("Unsupported asset pack version; expected 2 or 3; using placeholders")
		return {}
	if (
		not manifest.get("tiles") is Dictionary
		or not manifest.get("player") is Dictionary
		or manifest.get("drawing_facts") != "drawing_facts.json"
	):
		printerr("Invalid asset pack metadata; using placeholders")
		return {}
	var drawing: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path.path_join(manifest.drawing_facts))
	)
	if not drawing is Dictionary or not drawing.get("tilemaps") is Dictionary:
		printerr("Invalid asset pack drawing facts; using placeholders")
		return {}
	for name: Variant in drawing.tilemaps.keys():
		if not slots_ok(drawing.tilemaps[name]):
			drawing.tilemaps.erase(name)
	for name: Variant in manifest.tiles.keys():
		if (
			not safe_file(manifest.tiles[name])
			or not drawing.tilemaps.get(name) is Dictionary
			or not drawing.tilemaps[name].get("instances") is Array
		):
			manifest.tiles.erase(name)
	for name: Variant in manifest.player.keys():
		if not animation_ok(manifest.player[name]):
			manifest.player.erase(name)
	for section: String in [
		"objects", "backgrounds", "gradients", "hud", "fonts", "audio", "terrain"
	]:
		if not manifest.get(section, {}) is Dictionary:
			printerr("Invalid optional pack section: " + section)
			manifest[section] = {}
	var objects: Dictionary = manifest.get("objects", {})
	for code: Variant in objects.keys():
		if not visual_ok(objects[code]):
			objects.erase(code)
	var hud: Dictionary = manifest.get("hud", {})
	if hud.has("backing") and not hud_backing_ok(hud.backing):
		printerr("Invalid HUD backing ignored")
		hud.erase("backing")
	var terrain: Dictionary = manifest.get("terrain", {})
	for name: Variant in terrain.keys():
		if not terrain[name] is Dictionary:
			terrain.erase(name)
			continue
		for part: Variant in terrain[name].keys():
			if not part in ["surface", "underside", "side"] or not strip_ok(terrain[name][part]):
				printerr("Invalid terrain strip ignored: %s %s" % [name, part])
				terrain[name].erase(part)
		if terrain[name].is_empty():
			terrain.erase(name)
	for section: String in ["background", "supports"]:
		if not manifest.has(section):
			continue
		var value: Variant = manifest[section]
		var keys := (
			["wall", "counter", "cabinet"] if section == "background" else ["shelf", "bracket"]
		)
		if not value is Dictionary:
			manifest.erase(section)
			continue
		for key: String in keys:
			if not safe_file(value.get(key)):
				manifest.erase(section)
				break
	var density: Variant = manifest.get("density", 1)
	if not number_ok(density) or density < 1 or density > 4 or density != floorf(density):
		printerr("Invalid asset pack density; using 1")
		density = 1
	manifest["density"] = int(density)
	manifest["drawing"] = drawing
	return manifest


static func slots_ok(value: Variant) -> bool:
	if not value is Dictionary or not value.get("instances") is Array:
		return false
	for slot: Variant in value.instances:
		if (
			not slot is Dictionary
			or not slot.get("layer") is String
			or not number_ok(slot.get("layer_index"))
			or not number_ok(slot.get("z_order"))
		):
			return false
	return true


static func safe_file(value: Variant) -> bool:
	return (
		value is String
		and not value.is_empty()
		and not value.is_absolute_path()
		and not ":" in value
		and not "\\" in value
		and not ".." in value.split("/")
	)


static func point_ok(value: Variant) -> bool:
	return value is Array and value.size() == 2 and number_ok(value[0]) and number_ok(value[1])


static func number_ok(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func animation_ok(value: Variant) -> bool:
	if not value is Dictionary or not value.get("frames") is Array or value.frames.is_empty():
		return false
	var fps: Variant = value.get("fps", value.get("speed", 0))
	if not number_ok(fps) or fps < 0 or not value.get("loop", true) is bool:
		return false
	for frame: Variant in value.frames:
		if (
			not frame is Dictionary
			or not safe_file(frame.get("file"))
			or not point_ok(frame.get("origin", value.get("origin", [0, 0])))
			or not number_ok(frame.get("duration", 1))
			or frame.get("duration", 1) <= 0
		):
			return false
	return true


static func strip_ok(value: Variant) -> bool:
	if not value is Dictionary or not safe_file(value.get("file")):
		return false
	var edge: Variant = value.get("edge", 0)
	return number_ok(edge) and edge >= 0 and edge == floorf(edge)


static func visual_ok(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if not value.has("animations"):
		return safe_file(value.get("file")) and point_ok(value.get("origin", [0, 0]))
	if not value.get("animations") is Dictionary or value.animations.is_empty():
		return false
	for animation: Variant in value.animations.values():
		if not animation_ok(animation):
			return false
	return true


static func hud_backing_ok(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var color: Variant = value.get("color")
	if not color is Array or color.size() != 3:
		return false
	for channel: Variant in color:
		if not number_ok(channel) or channel < 0 or channel > 255 or channel != floorf(channel):
			return false
	var padding: Variant = value.get("padding", 2)
	return number_ok(padding) and padding >= 0 and padding <= 16 and padding == floorf(padding)
