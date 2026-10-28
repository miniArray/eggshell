extends RefCounted
## A candle lamp (d25 burns with fire, d26 with ice). Its own element lights it
## and the other element puts it out. Light masks are not drawn yet.

const Decor = preload("res://src/sim/types/decor.gd")
const Elements = preload("res://src/sim/elements.gd")
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


## Fire breath and burning bubbles count as fire, ice breath as ice. Everything
## else passes the lamp untouched (reaction 0).
static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	var striking: int = {"fire_shot": Elements.FIRE, "e16": Elements.FIRE, "ice_shot": Elements.ICE}.get(
		projectile.get("code", ""), Elements.NONE
	)
	if striking != Elements.NONE:
		entity.lamp_lit = int(striking == element(entity))
	return 0


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
