extends RefCounted
## Configurable geometric types for synthetic collision checks.
const S := 3600


class FullBox:
	extends RefCounted
	const SOLID := 1

	static func solid_box(entity: Dictionary) -> Array:
		if entity.get("broken", 0):
			return []
		return [
			entity.x - 16 * 3600, entity.y - 8 * 3600, entity.x + 16 * 3600, entity.y + 8 * 3600
		]

	static func bump(entity: Dictionary, state: Dictionary, _world: Dictionary, side: int) -> void:
		entity.bump_count += 1
		entity.last_side = side
		state.y += int(entity.get("shift_player", 0))
		if side == 1 and entity.get("break_on_pound", 0):
			entity.broken = 1


class TopBox:
	extends RefCounted
	const SOLID := 2

	static func solid_box(entity: Dictionary) -> Array:
		return [entity.x - 16 * 3600, entity.y, entity.x + 16 * 3600, entity.y + 2 * 3600]


class Strips:
	extends RefCounted
	const SOLID := 2

	static func solid_boxes(entity: Dictionary) -> Array:
		return [
			[entity.x - 48 * 3600, entity.y, entity.x - 16 * 3600, entity.y + 2 * 3600],
			[entity.x + 16 * 3600, entity.y, entity.x + 48 * 3600, entity.y + 2 * 3600]
		]

	static func solid_box(entity: Dictionary) -> Array:
		# The plural provider takes precedence over this deliberately broad bound.
		return [entity.x - 48 * 3600, entity.y, entity.x + 48 * 3600, entity.y + 2 * 3600]


static func lookup(code: String) -> Script:
	match code:
		"unit-full":
			return FullBox
		"unit-top":
			return TopBox
		_:
			return Strips
