extends RefCounted
## Static scenery has no step or contact work. Placement values stay immutable.

const CODES := [
	"d1",
	"d2",
	"d3",
	"d4",
	"d9",
	"d10",
	"d11",
	"d12",
	"d13",
	"d14",
	"d15",
	"d16",
	"d17",
	"d18",
	"d19",
	"d20",
	"d21",
	"d24",
	"d27",
	"d28",
	"d29",
	"d30",
	"d31",
	"d32",
	"d33",
	"d34",
	"d35",
	"d36",
	"d37",
	"d38",
	"d39",
	"d40",
	"d41",
	"d42",
	"d43",
	"d44",
	"d45",
	"d46",
	"d47",
	"d48",
	"d49",
	"d50",
	"d51",
	"d52",
	"d53",
	"d54",
	"d55",
	"d56",
	"d57",
	"d58",
	"d59",
	"d60",
	"d61",
	"d62",
	"d63",
	"d64",
	"d65",
	"d66",
	"d67",
	"d68",
	"d69",
	"d70",
	"d71",
	"d72",
	"d73",
	"d74",
	"d75",
	"d76"
]
const FIELDS := []
const STEP_PHASE := -1
const S := preload("res://src/sim/units.gd").SCALE
const MAX_COORD := 0x7fffffffffffffff / 16384
const MAX_PIXELS := MAX_COORD / S - 1024
const MAX_POSITION := MAX_PIXELS * S


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return prepare_options(source)


static func prepare_options(source: Dictionary) -> Dictionary:
	var raw: Dictionary = source.properties
	var code: String = source.code
	for key: String in ["F", "M", "R"]:
		var value: Variant = raw.get(key, 0)
		if not number_ok(value) or absf(value) > MAX_PIXELS:
			return {"ok": false, "error": "Invalid scenery option: " + key}
		if key != "R" and value != floor(value):
			return {"ok": false, "error": "Scenery frame and mirror must be integers"}
	var variant := int(raw.get("F", 0))
	var mirror := int(raw.get("M", 0))
	if variant < 0 or mirror < 0:
		return {"ok": false, "error": "Invalid scenery frame or mirror"}
	if variant >= frame_count(code) or mirror > 1:
		return {
			"ok": false,
			"degrade": true,
			"error": "scenery frame F=%d or mirror M=%d" % [variant, mirror]
		}
	if (
		source.x < -MAX_POSITION
		or source.x > MAX_POSITION
		or source.y < -MAX_POSITION
		or source.y > MAX_POSITION
	):
		return {"ok": false, "error": "Scenery position exceeds integer headroom"}
	var rotation := fposmod(float(raw.get("R", 0)), 360.0)
	if resized(code) and (mirror != 0 or rotation != 0):
		return {"ok": false, "degrade": true, "error": "transformed extendable scenery"}
	var height := 0.0
	if resized(code):
		var parsed := size_option(raw.get("E1", 0))
		if not parsed.ok:
			return {"ok": false, "error": "Invalid scenery height"}
		height = float(int(parsed.value))
	source.variant = variant
	source.mirror = mirror
	source.layer = layer_for(code)
	source.decor = {
		"variant": variant,
		"mirror": mirror,
		"rotation": rotation,
		"height": height,
		"layer": source.layer
	}
	return {"ok": true}


static func number_ok(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value)


static func size_option(value: Variant) -> Dictionary:
	if value is String:
		var text: String = value.strip_edges()
		if not text.is_valid_float():
			return {"ok": false}
		value = text.to_float()
	if not number_ok(value) or value < 0 or value > MAX_PIXELS:
		return {"ok": false}
	return {"ok": true, "value": float(value)}


static func resized(code: String) -> bool:
	var index := code.substr(1).to_int()
	return (
		(index >= 14 and index <= 23)
		or index in [27, 28, 75]
		or (index >= 31 and index <= 54)
		or (index >= 56 and index <= 67)
	)


static func frame_count(code: String) -> int:
	var index := code.substr(1).to_int()
	if index in [1, 2, 22, 23]:
		return 2
	if index in [3, 4]:
		return 5
	if (index >= 5 and index <= 13) or index in [25, 26]:
		return 4
	if index >= 68 and index <= 72:
		return 7
	return 6 if index in [75, 76] else 1


static func layer_for(code: String) -> int:
	var index := code.substr(1).to_int()
	if (index >= 14 and index <= 21) or (index >= 31 and index <= 54):
		return 5
	if index >= 9 and index <= 13:
		return 12
	return 6 if index == 23 else 7


static func create(_source: Dictionary, _world: Dictionary) -> Dictionary:
	return {}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func valid(entity: Dictionary) -> bool:
	return entity.code in CODES
