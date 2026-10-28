extends RefCounted
## An overhead actor drops, chooses a direction on landing, then rolls.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const World = preload("res://src/sim/world.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e28"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := true
const HIT_KIND := Hits.SHELL
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const HANG := 0
const LAUGH := 1
const ROLL := 2
const FIELDS := Body.FIELDS + [["mode", HANG], ["timer", 0], ["landed", 0], ["contact", 0]]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0, false)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(_entity: Dictionary) -> Array:
	return [-24 * S, -24 * S, 24 * S, 24 * S]


static func drop(entity: Dictionary) -> void:
	entity.mode = ROLL
	entity.timer = 0


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var fresh: bool = entity.started == 0
	if Body.process(entity, state) in [Body.HELD, Body.GONE]:
		return
	if fresh:
		entity.facing = 1 if entity.x < state.x else -1
	if entity.mode != ROLL:
		if entity.y < state.y and absi(entity.x - state.x) < 180 * S:
			drop(entity)
		elif entity.mode == LAUGH:
			entity.timer -= 1
			if entity.timer == 0:
				drop(entity)
	if entity.mode != ROLL:
		return
	var box := bounds(entity)
	if Body.hazards(entity, state, world, box):
		return
	entity.vx = entity.facing * 320 * 60 if entity.landed else 0
	var distance: int = entity.vx
	if (
		Motion.move(entity, world, box, distance, true) != distance
		or (entity.landed and _wall_point(entity, state, world))
	):
		Body.strike_wall(entity, state, world, box, signi(distance), Hits.SHELL)
		if entity.source_index >= 0:
			entity.status = 2
			entity.vx = 0
			entity.vy = 0
		else:
			Body.remove(entity, state)
		return
	if Motion.gravity_box(entity, world, box) and not entity.landed:
		entity.landed = 1
		entity.facing = 1 if entity.x < state.x else -1
	Body.hit_others(entity, state, world, box, Hits.SHELL)


static func _wall_point(entity: Dictionary, state: Dictionary, world: Dictionary) -> bool:
	var x: int = entity.x + entity.facing * 29 * S
	var y: int = entity.y
	if World.overlaps_box(world, x, y, x, y):
		return true
	var registry: Script = Body.registry_for(world)
	for other: Dictionary in state.entities:
		if (
			other.id == entity.id
			or other.status != 1
			or other.get("held", 0)
			or other.get("hidden", 0)
		):
			continue
		var type: Script = registry.lookup(other.code)
		if type.get_script_constant_map().get("SOLID", 0) != 1:
			continue
		var boxes := []
		if type.has_method("solid_boxes"):
			boxes = type.solid_boxes(other)
		elif type.has_method("solid_box"):
			boxes = [type.solid_box(other)]
		for box: Array in boxes:
			if box.size() == 4 and x >= box[0] and x <= box[2] and y >= box[1] and y <= box[3]:
				return true
	return false


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	var touching := Body.player_overlap(entity, state, bounds(entity))
	if touching:
		if entity.y > state.y + 8 * S and not entity.contact:
			Body.bounce(entity, state, input)
			if entity.mode != ROLL:
				drop(entity)
		elif entity.y < state.y + 8 * S:
			Body.hurt(entity, state)
	entity.contact = int(touching)


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, kind: int, _from_x: int
) -> void:
	if kind == Hits.CLEAR:
		Body.remove(entity, state)
	elif entity.mode != ROLL and kind in [Hits.EGG, Hits.SPIT, Hits.SHELL]:
		entity.mode = LAUGH
		entity.timer = 81


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if entity.mode == ROLL:
		return 0
	var kind := Body.projectile_kind(projectile)
	if projectile.code in ["e6", "e8", "e11", "e28"] and not projectile.get("spat", 0):
		if not Body.begin_overlap(projectile, entity, state, world):
			return 0
	hit(entity, state, world, kind, projectile.x)
	return 1 if kind == Hits.EGG or projectile.get("spat", 0) or projectile.get("roll", 0) else 3


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.mirror == 0
		and entity.mode >= HANG
		and entity.mode <= ROLL
		and entity.timer >= 0
		and entity.timer <= 81
		and entity.landed in [0, 1]
		and entity.contact in [0, 1]
		and entity.held == 0
		and entity.spat == 0
	)
