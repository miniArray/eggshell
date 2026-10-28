extends RefCounted
## Resizable full-solid spans that turn over when a matching switch block is struck.
## While turning they have no solid body; afterwards they are flipped.

const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["p11", "p12"]
const SOLID := 1
const CONTACT_PHASE := -1
const FIELDS := [["width", 112 * S], ["flipped", 0], ["spin", 0]]
const EXTRA_WIDTH := 8
const MAX_WIDTH := 1_000_000
const SPIN_TICKS := 38  # 0.625 s, rounded up to whole ticks.
const TURN_RATE := 1440  # Degrees per second while turning.


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var registry: Script = load("res://src/sim/registry.gd")
	var width: Dictionary = registry.numeric_option(source.properties.get("E1", "96"))
	if not width.ok or width.value < 0 or width.value > MAX_WIDTH:
		return {"ok": false, "error": "Invalid turning span width"}
	source.width = (int(width.value) + EXTRA_WIDTH) * S
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"width": int(source.width)}


## The switch colour that turns this form.
static func colour(entity: Dictionary) -> int:
	return 0 if entity.code == "p11" else 1


static func turning(entity: Dictionary) -> bool:
	return entity.spin > 0


static func start_turn(entity: Dictionary) -> void:
	if entity.status == 1 and entity.spin == 0:
		entity.spin = SPIN_TICKS


static func step(entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	if entity.spin > 0:
		entity.spin -= 1
		if entity.spin == 0:
			entity.flipped = 1 - entity.flipped


static func bounds(entity: Dictionary) -> Array:
	return [-entity.width / 2, -16 * S, entity.width / 2, 8 * S]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1 or entity.width == 0 or entity.spin > 0:
		return []
	# The support body is 24 px tall, centred 4 px above the drawn span.
	return [
		entity.x - entity.width / 2,
		entity.y - 16 * S,
		entity.x + entity.width / 2,
		entity.y + 8 * S
	]


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var direction := 1 if entity.code == "p11" else -1
	var turned: int = TURN_RATE * (SPIN_TICKS - entity.spin) / 60 if entity.spin else 0
	return {
		"visible": entity.status == 1,
		"size_x": float(entity.width) / S,
		"size_y": 16.0,
		"rotation": float(posmod(180 * entity.flipped + direction * turned, 360))
	}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.width >= 0
		and entity.width <= (MAX_WIDTH + EXTRA_WIDTH) * S
		and entity.flipped in [0, 1]
		and entity.spin >= 0
		and entity.spin <= SPIN_TICKS
	)
