extends RefCounted
## Saved lamp pose. Element-hit consumers and light masks are not wired yet.

const Decor = preload("res://src/sim/types/decor.gd")
const CODES := ["d25", "d26"]
const FIELDS := [["lamp_style", 0], ["lamp_lit", 1], ["lamp_color", 0]]
const STEP_PHASE := -1


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Decor.prepare_options(source)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {
		"lamp_style": int(source.variant) % 2,
		"lamp_lit": int(source.variant < 2),
		"lamp_color": int(source.code == "d26")
	}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {
		"animation":
		"%s:%d:%d" % ["lit" if entity.lamp_lit else "dim", entity.lamp_color, entity.lamp_style]
	}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.code in CODES
		and entity.lamp_style in [0, 1]
		and entity.lamp_lit in [0, 1]
		and entity.lamp_color == int(entity.code == "d26")
	)
