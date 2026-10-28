extends RefCounted
## A candle lamp (d25 burns with fire, d26 with ice). Its own element lights it
## and the other element puts it out. Light masks are not drawn yet.

const Decor = preload("res://src/sim/types/decor.gd")
const Elements = preload("res://src/sim/elements.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["d25", "d26"]
const FIELDS := [["lamp_style", 0], ["lamp_lit", 1], ["lamp_color", 0]]
const STEP_PHASE := -1
const ELEMENT_REACTIONS := Elements.LIGHTS
const BOX := [-8 * S, -16 * S, 8 * S, 16 * S]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Decor.prepare_options(source)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {
		"lamp_style": int(source.variant) % 2,
		"lamp_lit": int(source.variant < 2),
		"lamp_color": int(source.code == "d26")
	}


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


## The element that keeps this lamp burning.
static func element(entity: Dictionary) -> int:
	return Elements.ICE if entity.lamp_color == 1 else Elements.FIRE


static func hit(
	entity: Dictionary, _state: Dictionary, _world: Dictionary, kind: int, _from_x: int
) -> void:
	var striking := (
		Elements.FIRE if kind == Hits.FIRE else (Elements.ICE if kind == Hits.ICE else Elements.NONE)
	)
	if striking == Elements.NONE:
		return
	entity.lamp_lit = int(striking == element(entity))


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
