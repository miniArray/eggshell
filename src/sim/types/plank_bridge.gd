extends RefCounted
## A fixed bridge whose top edge supports bodies from above only.

const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["p2"]
const SOLID := 2
const STEP_PHASE := -1
const CONTACT_PHASE := -1
const FIELDS := [["width", 96 * S]]
const MAX_WIDTH := 1_000_000


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var parsed := width_option(source.properties.get("E1", 96))
	if not parsed.ok:
		return {"ok": false, "error": "Invalid bridge width"}
	source.width = parsed.value
	return {"ok": true}


static func width_option(value: Variant) -> Dictionary:
	if value is String:
		var text: String = value.strip_edges()
		if not text.is_valid_float():
			return {"ok": false}
		value = text.to_float()
	if not (value is int or value is float) or not is_finite(value):
		return {"ok": false}
	if value < 0 or value > MAX_WIDTH:
		return {"ok": false}
	return {"ok": true, "value": roundi(value * S)}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"width": int(source.get("width", 96 * S))}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func bounds(entity: Dictionary) -> Array:
	return [-entity.width / 2, -16 * S, entity.width / 2, 16 * S]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1 or entity.width <= 0:
		return []
	# A 2 px strip at the body's top edge, as wide as the bridge.
	return [
		entity.x - entity.width / 2,
		entity.y - 16 * S,
		entity.x + entity.width / 2,
		entity.y - 14 * S
	]


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1, "size_x": float(entity.width) / S, "size_y": 32.0}


static func valid(entity: Dictionary) -> bool:
	return entity.width >= 0 and entity.width <= MAX_WIDTH * S
