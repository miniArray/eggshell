extends RefCounted
## A solid block that sends out spinning discs while the player is within 336 px
## horizontally, and draws them back in when the player leaves.

const S := preload("res://src/sim/units.gd").SCALE
const Disc = preload("res://src/sim/types/orbit_disc.gd")
const CODES := ["e38"]
const SOLID := 1
const CONTACT_PHASE := -1
const FIELDS := [["count", 1], ["speed", 96], ["radius", 96], ["out", 0]]
const RANGE := 336 * S
const MAX_COUNT := 64
const MAX_OPTION := 100_000


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := []
	for pair: Array in [["E1", "1"], ["E2", "96"], ["E3", "96"]]:
		var raw: Variant = source.properties.get(pair[0], pair[1])
		var parsed: Dictionary = registry().numeric_option(
			pair[1] if raw is String and raw.strip_edges() == "" else raw
		)
		if not parsed.ok:
			return {"ok": false, "error": "Invalid disc block option: " + pair[0]}
		values.append(int(parsed.value))
	if values[0] < 0 or values[0] > MAX_COUNT or absi(values[1]) > MAX_OPTION:
		return {"ok": false, "degrade": true, "error": "disc block option out of range"}
	if absi(values[2]) > MAX_OPTION:
		return {"ok": false, "degrade": true, "error": "disc block radius out of range"}
	source.count = values[0]
	source.speed = values[1]
	source.radius = values[2]
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {
		"count": int(source.count),
		"speed": int(source.speed),
		"radius": int(source.radius),
		"spawn_mode": 1,
		"status": 0,
		"can_despawn": 1,
		"can_respawn": 1
	}


static func bounds(_entity: Dictionary) -> Array:
	return [-16 * S, -16 * S, 16 * S, 16 * S]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1:
		return []
	return [entity.x - 16 * S, entity.y - 16 * S, entity.x + 16 * S, entity.y + 16 * S]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var near: bool = absi(entity.x - state.x) < RANGE
	if near and not entity.out:
		entity.out = 1
		for slot in entity.count:
			registry().spawn_dynamic(
				state,
				world,
				Disc.CODES[0],
				entity.x,
				entity.y,
				{
					"owner": entity.token,
					"offset": 360000 * slot / maxi(1, entity.count),
					"speed": entity.speed,
					"radius": entity.radius
				}
			)
	elif not near and entity.out:
		entity.out = 0
		for other: Dictionary in state.entities:
			if other.code == Disc.CODES[0] and other.owner == entity.token:
				other.retracting = 1


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1, "frame": entity.out}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.count >= 0
		and entity.count <= MAX_COUNT
		and absi(entity.speed) <= MAX_OPTION
		and absi(entity.radius) <= MAX_OPTION
		and entity.out in [0, 1]
	)
