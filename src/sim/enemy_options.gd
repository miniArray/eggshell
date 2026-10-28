extends RefCounted
## Validate placement options before they become integer simulation state.
const MAX_SPEED := 1000 * 60
const MIN_VERTICAL := -2000 * 60
const MAX_VERTICAL := 1408 * 60
const INTERNAL_LIMITS := {
	"facing": [-1, 1],
	"vx": [-MAX_SPEED, MAX_SPEED],
	"vy": [MIN_VERTICAL, MAX_VERTICAL],
	"colour": [0, 1],
	"slide": [0, 60],
	"origin_shell": [0, 0x7fffffffffffffff],
	"slide_direction": [-1, 1],
	"grace": [0, 1]
}


static func prepare(source: Dictionary, last_variant: int, allow_mirror: bool = true) -> Dictionary:
	var raw: Dictionary = source.get("properties", {})
	for key: String in ["F", "M", "R"]:
		var value: Variant = raw.get(key, 0)
		if not (value is int or value is float) or not is_finite(value):
			return {"ok": false, "error": "Invalid enemy option: " + key}
		if value < 0 or value != floor(value):
			return {"ok": false, "error": "Invalid enemy option: " + key}
		var limit := last_variant if key == "F" else (2 if key == "M" and allow_mirror else 0)
		if value > limit:
			return {"ok": false, "error": "Unsupported enemy option: " + key}
		source[{"F": "variant", "M": "mirror", "R": "rotation"}[key]] = int(value)
	if int(source.get("source_index", 0)) == -1:
		for key: String in INTERNAL_LIMITS:
			if not raw.has(key):
				continue
			var value: Variant = raw[key]
			var limits: Array = INTERNAL_LIMITS[key]
			if not value is int or value < limits[0] or value > limits[1]:
				return {"ok": false, "error": "Invalid runtime enemy option: " + key}
			if key in ["facing", "slide_direction"] and value == 0:
				return {"ok": false, "error": "Invalid runtime enemy direction"}
	source.layer = 8
	return {"ok": true}


static func option(source: Dictionary, key: String, fallback: int = 0) -> int:
	if int(source.get("source_index", 0)) != -1:
		return fallback
	var value: Variant = source.get("properties", {}).get(key, fallback)
	return int(value) if value is int else fallback
