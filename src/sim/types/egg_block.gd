extends RefCounted
## A full-solid block that, struck from below, stops being solid, rises 64 px and
## drops back, then turns into a floating coloured egg.

const S := preload("res://src/sim/units.gd").SCALE
const Hits = preload("res://src/sim/hits.gd")
const Near = preload("res://src/sim/types/near_query.gd")
const CODES := ["o27"]
const SOLID := 1
const CONTACT_PHASE := -1
const FIELDS := [["colour", 0], ["home_y", 0], ["busy", 0]]
const HALF_TICKS := 15  # 0.25 s up, then 0.25 s back down.
const RISE := 64 * S
## Egg inventory colours: the plain form gives yellow, F=1 red.
const EGG_COLOURS := [1, 2]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var value: Variant = source.properties.get("F", 0)
	if not (value is int or value is float) or not is_finite(value) or value != floor(value):
		return {"ok": false, "error": "Invalid egg block colour"}
	if value < 0:
		return {"ok": false, "error": "Invalid egg block colour"}
	if value > 1:
		return {"ok": false, "degrade": true, "error": "egg block colour F=%d" % value}
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"colour": int(source.get("variant", 0)), "home_y": int(source.y)}


static func bounds(_entity: Dictionary) -> Array:
	return [-16 * S, -16 * S, 16 * S, 16 * S]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1 or entity.busy:
		return []
	return [entity.x - 16 * S, entity.y - 16 * S, entity.x + 16 * S, entity.y + 16 * S]


static func bump(entity: Dictionary, state: Dictionary, world: Dictionary, side: int) -> void:
	if side != 0 or entity.busy or entity.status != 1:
		return
	entity.busy = 2 * HALF_TICKS
	var probe := [entity.x - 16 * S, entity.y - 24 * S, entity.x + 16 * S, entity.y + 8 * S]
	Near.strike(state, world, probe, Hits.BUMP, entity.x, entity.token)


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if not entity.busy:
		return
	entity.busy -= 1
	var elapsed: int = 2 * HALF_TICKS - entity.busy
	var offset := mini(elapsed, 2 * HALF_TICKS - elapsed)
	entity.y = entity.home_y - RISE * offset / HALF_TICKS
	if entity.busy == 0:
		entity.status = 3
		var registry: Script = load("res://src/sim/registry.gd")
		registry.spawn_dynamic(
			state,
			world,
			"o7",
			entity.x,
			entity.home_y,
			{"F": EGG_COLOURS[entity.colour], "floating": 1}
		)


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {
		"visible": entity.status == 1,
		"animation": "Red" if entity.colour == 1 else "Yellow",
		"frame": int(entity.busy > 0)
	}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.colour in [0, 1]
		and entity.busy >= 0
		and entity.busy <= 2 * HALF_TICKS
		and entity.y <= entity.home_y
		and entity.y >= entity.home_y - RISE
	)
