extends RefCounted
## Fixed resizable spans. The drawn body is not solid; a 2 px top-only strip at a
## per-form offset below the body's top edge supports bodies from above.

const S := preload("res://src/sim/units.gd").SCALE
const CODES := [
	"p6", "p7", "p8", "p9", "p10", "p13", "p14", "p15", "p16", "p17", "p18", "p19", "p20", "p21"
]
const SOLID := 2
const POST_SUPPORT := true
const STEP_PHASE := -1
const CONTACT_PHASE := -1
const FIELDS := [["width", 96 * S]]
## Per form: default width, drawn height and support offset from the top, in pixels.
const FORMS := {
	"p6": [96, 32, 0],
	"p7": [96, 32, 0],
	"p8": [96, 32, 0],
	"p9": [96, 56, 12],
	"p10": [128, 32, 0],
	"p13": [80, 32, 0],
	"p14": [96, 32, 0],
	"p15": [96, 32, 0],
	"p16": [96, 32, 0],
	"p17": [96, 32, 0],
	"p18": [96, 32, 0],
	"p19": [64, 32, 0],
	"p20": [96, 32, 0],
	"p21": [96, 32, 0],
}
const MAX_WIDTH := 1_000_000


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var registry: Script = load("res://src/sim/registry.gd")
	var form: Array = FORMS[source.code]
	var width: Dictionary = registry.numeric_option(source.properties.get("E1", str(form[0])))
	if not width.ok or width.value < 0 or width.value > MAX_WIDTH:
		return {"ok": false, "error": "Invalid span width"}
	source.width = int(width.value) * S
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"width": int(source.width)}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func height(entity: Dictionary) -> int:
	return int(FORMS[entity.code][1]) * S


static func bounds(entity: Dictionary) -> Array:
	return [-entity.width / 2, -height(entity) / 2, entity.width / 2, height(entity) / 2]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1 or entity.width == 0:
		return []
	var top: int = entity.y - height(entity) / 2 + int(FORMS[entity.code][2]) * S
	return [entity.x - entity.width / 2, top, entity.x + entity.width / 2, top + 2 * S]


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {
		"visible": entity.status == 1,
		"size_x": float(entity.width) / S,
		"size_y": float(height(entity)) / S
	}


static func valid(entity: Dictionary) -> bool:
	return entity.width >= 0 and entity.width <= MAX_WIDTH * S
