extends RefCounted
## A full barrier that opens while a body occupies its allowed entry side.
const CODES := ["o31"]
const SOLID := 1
const S := preload("res://src/sim/units.gd").SCALE
const Collision = preload("res://src/sim/collision.gd")
const Turn = preload("res://src/sim/oriented_box.gd")
const Moves = preload("res://src/sim/moves.gd")
const FIELDS := [["angle", 0], ["opened", 0]]
const BARRIER := [-64 * S, -16 * S, 64 * S, 16 * S]
const ENTRY := [-64 * S, 16 * S, 64 * S, 48 * S]
const AREA := [-64 * S, -16 * S, 64 * S, 48 * S]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var registry: Script = load("res://src/sim/registry.gd")
	var parsed: Dictionary = registry.numeric_option(source.properties.get("R", 0))
	if not parsed.ok:
		return {"ok": false, "error": "Invalid gate angle"}
	source.angle = Turn.angle_wrap(roundi(fposmod(parsed.value, 360.0) * 1000))
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"angle": int(source.angle), "layer": 9}


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var area := bounds(entity)
	var boxes := _body_boxes(
		state,
		world,
		[entity.x + area[0], entity.y + area[1], entity.x + area[2], entity.y + area[3]]
	)
	if entity.opened:
		for box: Array in boxes:
			if Turn.overlaps(entity.angle, AREA, box, entity.x, entity.y):
				return
		entity.opened = 0
	else:
		for box: Array in boxes:
			if Turn.overlaps(entity.angle, ENTRY, box, entity.x, entity.y):
				entity.opened = 1
				return


static func bounds(entity: Dictionary) -> Array:
	return Turn.bounds(entity.angle, AREA)


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1 or entity.opened:
		return []
	var box := Turn.bounds(entity.angle, BARRIER)
	return [entity.x + box[0], entity.y + box[1], entity.x + box[2], entity.y + box[3]]


static func solid_touches(entity: Dictionary, probe: Array) -> bool:
	return Turn.overlaps(entity.angle, BARRIER, probe, entity.x, entity.y)


static func touches(entity: Dictionary, probe: Array) -> bool:
	return Turn.overlaps(entity.angle, AREA, probe, entity.x, entity.y)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	if entity.status != 1 or entity.opened or projectile.mode != 1:
		return 0
	var box := [
		projectile.x - 12 * S, projectile.y - 12 * S, projectile.x + 12 * S, projectile.y + 12 * S
	]
	if not Turn.overlaps(entity.angle, ENTRY, box, entity.x, entity.y):
		return 0
	entity.opened = 1
	return 0


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	var probe := Moves.tongue_box(state)
	if entity.status != 1 or entity.opened or probe.is_empty():
		return 0
	return 2 if solid_touches(entity, probe) else 0


## Body boxes that may touch `area`, the gate's world bounds. The step only asks whether
## any box overlaps the turned area, and a box that does touches its bounds.
static func _body_boxes(state: Dictionary, world: Dictionary, area: Array) -> Array:
	var result := []
	if not state.get("captured_by", 0):
		var box := Moves.player_box(state)
		result.append([state.x + box[0], state.y + box[1], state.x + box[2], state.y + box[3]])
	var registry := Collision.registry_for(world)
	if registry == null:
		return result
	var indexed := registry.has_method("nearby") and registry.has_method("is_enemy")
	var candidates: Array = registry.nearby(state, world, area) if indexed else state.entities
	for entity: Dictionary in candidates:
		if entity.status != 1 or entity.collected or entity.get("held", 0):
			continue
		var type: Script = registry.lookup(entity.code)
		var enemy: bool = (
			registry.is_enemy(entity.code)
			if indexed
			else (
				entity.code in registry.Actor.CODES
				or type.get_script_constant_map().get("ENEMY", false)
			)
		)
		var actor: bool = enemy or entity.code in ["o4", "o7", "o14"] or entity.get("moving", 0)
		if not actor or not type.has_method("bounds"):
			continue
		var box: Array = type.bounds(entity)
		if box[0] >= box[2] or box[1] >= box[3]:
			continue
		result.append([entity.x + box[0], entity.y + box[1], entity.x + box[2], entity.y + box[3]])
	return result


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {
		"visible": entity.status == 1, "rotation": entity.angle / 1000.0, "frame": entity.opened
	}


static func valid(entity: Dictionary) -> bool:
	return entity.angle >= 0 and entity.angle < Turn.TURN and entity.opened in [0, 1]
