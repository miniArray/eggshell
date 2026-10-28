extends RefCounted
## Neighbour queries for object types. Uses the registry index when it exists;
## otherwise it scans every entity in table order, with the same result order.

const Collision = preload("res://src/sim/collision.gd")


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func nearby(state: Dictionary, world: Dictionary, box: Array) -> Array:
	var dispatch := registry()
	if dispatch.has_method("nearby"):
		return dispatch.nearby(state, world, box)
	var result := []
	for entity: Dictionary in state.get("entities", []):
		if dispatch.overlaps_box(entity, dispatch.lookup(entity.code), box):
			result.append(entity)
	return result


## Strike every active, visible entity with a hit hook inside a world-space box.
static func strike(
	state: Dictionary, world: Dictionary, box: Array, kind: int, from_x: int, skip_token: int
) -> void:
	var dispatch := registry()
	for other: Dictionary in nearby(state, world, box):
		var type: Script = dispatch.lookup(other.code)
		if (
			other.token == skip_token
			or other.status != 1
			or other.get("held", 0) == 1
			or other.get("hidden", 0) == 1
			or not type.has_method("hit")
		):
			continue
		if dispatch.overlaps_box(other, type, box):
			type.hit(other, state, world, kind, from_x)


## Refile another entity's solid boxes after this code moved or enlarged them.
## The solid index refiles the dispatched entity itself; without an index this
## does nothing.
static func refresh_solid(world: Dictionary, entity: Dictionary) -> void:
	var collision: Script = Collision
	if collision.has_method("refresh"):
		collision.call("refresh", world, entity)
