extends RefCounted
## Screen activation, despawn and respawn of table entities. The registry runs it before
## each entity's step (Registry.lifecycle) inside that entity's dispatch. Every distance
## is measured from the reference screen's centre (screen.gd), which stays inside the map.

const Screen = preload("res://src/sim/screen.gd")

const WAITING := 0
const ACTIVE := 1
const QUEUED := 2
const DEFEATED := 3
static var _registry: Script = null


## The registry, resolved at first use to avoid a registry/lifecycle import cycle.
static func registry() -> Script:
	if _registry == null:
		_registry = load("res://src/sim/registry.gd")
	return _registry


static func run(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.status == DEFEATED or entity.get("held", 0) == 1:
		return
	# An active entity that cannot despawn has no transition below; skip the box work.
	if entity.status == ACTIVE and not entity.can_despawn:
		return
	var dispatch := registry()
	var type: Script = dispatch.lookup(entity.code)
	var box := activation_box(entity, type)
	var screen_x := Screen.centre_x(state, world)
	var screen_y := Screen.centre_y(state, world)
	var far: bool = (
		box[0] > screen_x + entity.despawn_radius
		or box[2] < screen_x - entity.despawn_radius
		or box[1] > screen_y + entity.despawn_radius
		or box[3] < screen_y - entity.despawn_radius
	)
	if entity.source_index == -1:
		# A runtime entity has no immutable camera-respawn anchor.
		if entity.status == ACTIVE and entity.can_despawn and far:
			if type.has_method("deactivate"):
				type.deactivate(entity, state, world)
			entity.status = DEFEATED
		return
	var source: Dictionary = dispatch.source_for(entity, world)
	if entity.status == ACTIVE and entity.can_despawn and far:
		entity.status = QUEUED
		entity.offscreen = 0
	if entity.status == QUEUED and entity.can_respawn:
		if (
			absi(source.x - screen_x) > entity.activation_x
			or absi(source.y - screen_y) > entity.activation_y
		):
			entity.offscreen = 1
		if (
			entity.offscreen
			and absi(source.x - screen_x) < entity.respawn_radius
			and absi(source.y - screen_y) < entity.respawn_radius
		):
			var fresh: Dictionary = dispatch.create(source, world)
			fresh.collected = entity.collected
			fresh.checkpoint_collected = entity.checkpoint_collected
			for pair: Array in dispatch.fields(entity.code):
				entity[pair[0]] = fresh[pair[0]]
	if entity.status == WAITING:
		box = activation_box(entity, type)
		if (
			box[2] > screen_x - entity.activation_x
			and box[0] < screen_x + entity.activation_x
			and box[3] > screen_y - entity.activation_y
			and box[1] < screen_y + entity.activation_y
		):
			entity.status = ACTIVE
			if source.mirror == 2:
				entity.facing = -1 if state.x < entity.x else 1
			if type.has_method("activate"):
				type.activate(entity, state, world)


static func activation_box(entity: Dictionary, type: Script) -> Array:
	if type.has_method("activation_bounds"):
		return type.activation_bounds(entity)
	var box: Array = type.bounds(entity) if type.has_method("bounds") else [0, 0, 0, 0]
	return [entity.x + box[0], entity.y + box[1], entity.x + box[2], entity.y + box[3]]
