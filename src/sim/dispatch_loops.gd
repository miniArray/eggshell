extends RefCounted
## The registry's per-step entity loops: lifecycle and step, contact, and request
## consumption. Each visits entities in table order, including entities appended while it
## runs, and keeps the solid index and entity grid informed of every dispatch.

const Collision = preload("res://src/sim/collision.gd")
const EntityGrid = preload("res://src/sim/entity_grid.gd")
const EntityLifecycle = preload("res://src/sim/entity_lifecycle.gd")
const ACTIVE := 1
static var _registry: Script = null
## Per code: the registry's dispatch facts (Registry.facts), read once.
static var _facts := {}


## The registry, resolved at first use to avoid a registry/loops import cycle.
static func registry() -> Script:
	if _registry == null:
		_registry = load("res://src/sim/registry.gd")
	return _registry


static func facts(code: String) -> Dictionary:
	var known: Variant = _facts.get(code)
	if known == null:
		known = registry().facts(code)
		_facts[code] = known
	return known


static func advance(state: Dictionary, world: Dictionary, pressed: int) -> void:
	state.pressed_input = pressed
	# Preserve actor movement before pad gravity, including capture's early exit.
	var grid := EntityGrid.attach(state, world)
	# The grid keeps these two arrays; appending inline keeps dispatch overhead low.
	var dispatching: Array = grid.dispatching
	var dirty: Array = grid.dirty
	for phase in [0, 1]:
		if phase == 1 and state.captured_by:
			break
		var solids := Collision.solid_rows(world)
		var entities: Array = state.entities
		var members := _members(world, entities, "step_phase", phase)
		var next := 0
		var tail := entities.size()
		# Table order: the cached members, then entities appended during this loop.
		while next < members.size() or tail < entities.size():
			var entity: Dictionary
			if next < members.size():
				entity = entities[members[next]]
				next += 1
			else:
				entity = entities[tail]
				tail += 1
			var known := facts(entity.code)
			if known.step_phase != phase:
				continue
			var row: Variant = solids.get(entity.token)
			if row != null and is_same(row.entity, entity):
				Collision.dispatch_begin(world, row)
			else:
				row = null
			dispatching.append(entity)
			# The lifecycle returns at once for an active entity that cannot despawn.
			if entity.status != ACTIVE or entity.can_despawn:
				EntityLifecycle.run(entity, state, world)
			if entity.status == ACTIVE:
				known.type.step(entity, state, world)
			dispatching.pop_back()
			dirty.append(entity)
			if row != null:
				Collision.dispatch_end(world, row)


static func contact(state: Dictionary, input: int, world: Dictionary) -> void:
	var grid: Variant = EntityGrid.current(world)
	var dispatching: Array = grid.dispatching if grid != null else []
	var dirty: Array = grid.dirty if grid != null else []
	# The step's solid rows only change at the next Collision.begin_step.
	var solids := Collision.solid_rows(world)
	for phase in [0, 1, 2]:
		var entities: Array = state.entities
		var members := _members(world, entities, "contact_phase", phase)
		var next := 0
		var tail := entities.size()
		# Table order: the cached members, then entities appended during this loop.
		while next < members.size() or tail < entities.size():
			var entity: Dictionary
			if next < members.size():
				entity = entities[members[next]]
				next += 1
			else:
				entity = entities[tail]
				tail += 1
			var known := facts(entity.code)
			if (
				known.contact_phase == phase
				and entity.status == ACTIVE
				and entity.get("held", 0) != 1
				and entity.get("hidden", 0) != 1
			):
				var row: Variant = solids.get(entity.token)
				if row != null and is_same(row.entity, entity):
					Collision.dispatch_begin(world, row)
				else:
					row = null
				dispatching.append(entity)
				known.type.contact(entity, state, world, input)
				dispatching.pop_back()
				dirty.append(entity)
				if row != null:
					Collision.dispatch_end(world, row)


## Entity request consumers, after the registry ran the level-wide consumers.
static func consume_requests(state: Dictionary, world: Dictionary) -> void:
	var solids := Collision.solid_rows(world)
	var grid: Variant = EntityGrid.current(world)
	var entities: Array = state.entities
	var members := _members(world, entities, "consume", true)
	var next := 0
	var tail := entities.size()
	# Table order: the cached consumers, then entities appended during this loop.
	while next < members.size() or tail < entities.size():
		var entity: Dictionary
		if next < members.size():
			entity = entities[members[next]]
			next += 1
		else:
			entity = entities[tail]
			tail += 1
		var known := facts(entity.code)
		if not known.consume:
			continue
		var row: Variant = solids.get(entity.token)
		if row != null and is_same(row.entity, entity):
			Collision.dispatch_begin(world, row)
		else:
			row = null
		EntityGrid.begin(grid, entity)
		known.type.consume_requests(entity, state, world)
		EntityGrid.end(grid, entity)
		if row != null:
			Collision.dispatch_end(world, row)


## Indices of the table entities whose code has `key` == `value` in its facts, in table
## order. Codes never change and tables change only by replacement or appending, so the
## list holds while the table array and its size are unchanged.
static func _members(world: Dictionary, entities: Array, key: String, value: Variant) -> Array:
	var cache: Variant = world.get("dispatch_members")
	if cache == null or not is_same(cache.entities, entities) or cache.count != entities.size():
		cache = {"entities": entities, "count": entities.size(), "lists": {}}
		world.dispatch_members = cache
	var name := "%s:%s" % [key, value]
	var list: Variant = cache.lists.get(name)
	if list == null:
		list = []
		for index in entities.size():
			if facts(entities[index].code)[key] == value:
				list.append(index)
		cache.lists[name] = list
	return list
