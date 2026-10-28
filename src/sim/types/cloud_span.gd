extends RefCounted
## A fixed-width, top-only span.
const CODES := ["p3"]
const SOLID := 2
const POST_SUPPORT := true
const S := preload("res://src/sim/units.gd").SCALE
const FIELDS := [["width", 128 * S]]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var registry: Script = load("res://src/sim/registry.gd")
	var width: Dictionary = registry.numeric_option(source.properties.get("E1", "128"))
	if not width.ok or width.value < 0:
		return {"ok": false, "error": "Invalid span width"}
	source.width = int(width.value) * S
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"width": int(source.width)}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func bounds(entity: Dictionary) -> Array:
	return [-entity.width / 2, -24 * S, entity.width / 2, 24 * S]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1 or entity.width == 0:
		return []
	return [
		entity.x - entity.width / 2,
		entity.y - 16 * S,
		entity.x + entity.width / 2,
		entity.y - 14 * S
	]


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1, "size_x": entity.width / S, "size_y": 48}


static func valid(entity: Dictionary) -> bool:
	return entity.width >= 0
