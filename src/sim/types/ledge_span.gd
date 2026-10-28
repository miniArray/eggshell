extends RefCounted
## Fixed resizable ledges whose top edge supports bodies from above only.
## The second form also stands on a decorative stalk of the given height.

const Plank = preload("res://src/sim/types/plank_bridge.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["p4", "p5"]
const SOLID := 2
const STEP_PHASE := -1
const CONTACT_PHASE := -1
const FIELDS := Plank.FIELDS + [["stalk", 0]]


static func prepare(source: Dictionary, world: Dictionary) -> Dictionary:
	var result := Plank.prepare(source, world)
	if not result.ok or source.code != "p5":
		return result
	# The stalk height uses the leading integer of E2; text without digits is zero.
	var raw: Variant = source.properties.get("E2", "0")
	if raw is String:
		var text: String = raw.strip_edges()
		var digits := ""
		for index in text.length():
			if text[index].is_valid_int():
				digits += text[index]
			else:
				break
		source.stalk = mini(digits.to_int(), Plank.MAX_WIDTH) * S if not digits.is_empty() else 0
	elif (raw is int or raw is float) and is_finite(raw) and raw >= 0:
		source.stalk = mini(int(raw), Plank.MAX_WIDTH) * S
	else:
		return {"ok": false, "error": "Invalid ledge stalk height"}
	return result


static func create(source: Dictionary, world: Dictionary) -> Dictionary:
	var values := Plank.create(source, world)
	values.stalk = int(source.get("stalk", 0))
	return values


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func bounds(entity: Dictionary) -> Array:
	return Plank.bounds(entity)


static func solid_box(entity: Dictionary) -> Array:
	return Plank.solid_box(entity)


static func view_state(entity: Dictionary, state: Dictionary) -> Dictionary:
	return Plank.view_state(entity, state)


static func valid(entity: Dictionary) -> bool:
	return Plank.valid(entity) and entity.stalk >= 0 and entity.stalk <= Plank.MAX_WIDTH * S
