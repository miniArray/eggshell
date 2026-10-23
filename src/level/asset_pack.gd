extends RefCounted
## Built-in and optional external graphics packs share the v2 loader contract.
const VERSION := 2
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
	if manifest.get("version") != VERSION:
		printerr(
			(
				(
					"Unsupported asset pack version %s; expected %d. "
					+ "Provide a version 2 graphics pack; using placeholders"
				)
				% [str(manifest.get("version")), VERSION]
			)
		)
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
	for name: String in manifest.tiles:
		if not drawing.tilemaps.has(name) or not drawing.tilemaps[name].get("instances") is Array:
			printerr("Missing asset pack draw slots; using placeholders")
			return {}
	manifest["drawing"] = drawing
	return manifest
