extends RefCounted
## A full-solid switch block. A strike from below or a thrown object turns over
## every span of its colour; the block then lifts briefly and pops bodies above it.

const S := preload("res://src/sim/units.gd").SCALE
const Hits = preload("res://src/sim/hits.gd")
const Near = preload("res://src/sim/types/near_query.gd")
const Span = preload("res://src/sim/types/spin_span.gd")
const CODES := ["o30"]
const SOLID := 1
const CONTACT_PHASE := -1
const FIELDS := [["colour", 0], ["home_y", 0], ["busy", 0]]
const BUMP_TICKS := 12  # 0.1 s up and 0.1 s back.
const LIFT := 32 * S


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var value: Variant = source.properties.get("F", 0)
	if not (value is int or value is float) or not is_finite(value) or value != floor(value):
		return {"ok": false, "error": "Invalid switch block colour"}
	if value < 0:
		return {"ok": false, "error": "Invalid switch block colour"}
	if value > 1:
		return {"ok": false, "degrade": true, "error": "switch block colour F=%d" % value}
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"colour": int(source.get("variant", 0)), "home_y": int(source.y)}


static func step(entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	if entity.busy:
		entity.busy -= 1
		var offset := mini(BUMP_TICKS - entity.busy, entity.busy)
		entity.y = entity.home_y - LIFT * offset / (BUMP_TICKS / 2)


static func bounds(_entity: Dictionary) -> Array:
	return [-16 * S, -16 * S, 16 * S, 16 * S]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1:
		return []
	return [entity.x - 16 * S, entity.y - 16 * S, entity.x + 16 * S, entity.y + 16 * S]


static func bump(entity: Dictionary, state: Dictionary, world: Dictionary, side: int) -> void:
	if side == 0:
		trigger(entity, state, world)


static func projectile_contact(
	entity: Dictionary, _projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if entity.status != 1:
		return 0
	if entity.busy:
		return 3  # A lifted block is an ordinary solid for the projectile.
	trigger(entity, state, world)
	return 1


## Turn every idle span of this colour. With none idle but some turning, nothing
## happens; with no span of this colour at all, the block still lifts.
static func trigger(entity: Dictionary, state: Dictionary, world: Dictionary) -> bool:
	if entity.busy or entity.status != 1:
		return false
	var matching := []
	var idle := false
	for other: Dictionary in state.entities:
		if other.code in Span.CODES and other.status == 1 and Span.colour(other) == entity.colour:
			matching.append(other)
			idle = idle or not Span.turning(other)
	if idle:
		for other: Dictionary in matching:
			Span.start_turn(other)
	elif not matching.is_empty():
		return false
	entity.busy = BUMP_TICKS
	var probe := [entity.x - 16 * S, entity.y - 24 * S, entity.x + 16 * S, entity.y + 8 * S]
	Near.strike(state, world, probe, Hits.BUMP, entity.x, entity.token)
	return true


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1, "frame": entity.colour}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.colour in [0, 1]
		and entity.busy >= 0
		and entity.busy <= BUMP_TICKS
		and entity.y <= entity.home_y
		and entity.y >= entity.home_y - LIFT
	)
