extends RefCounted
## A falling spiked body. The first form hops twice on landing, then sinks through the ground.
## The second form breaks when it lands.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e40"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const GRAVITY := 1536
const MAX_FALL := 704 * 60
const MAX_SPEED := 512 * 60
const SINK_WINDOW := 60
const FIELDS := (
	Body.FIELDS
	+ [["colour", 0], ["sink_window", 0], ["hop_pending", 0], ["sinking", 0], ["thrown", 0]]
)
const BOX := [-12 * S, -12 * S, 12 * S, 12 * S]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 1, false)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.colour = values.variant
	values.vx = clampi(values.vx, -MAX_SPEED, MAX_SPEED)
	if int(source.get("source_index", 0)) == -1:
		values.can_respawn = 0
	return values


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if action == Body.RELEASED:
		# Mouth release replaces the generic spit bounce with a plain throw.
		var upward: bool = entity.vx == 0
		var direction: int = state.facing if upward else signi(entity.vx)
		entity.spat = 0
		entity.thrown = 1
		entity.facing = direction
		entity.vx = direction * (200 if upward else 320) * 60
		entity.vy = (-768 if upward else -256) * 60
	if Body.hazards(entity, state, world, BOX):
		return
	if entity.sink_window:
		entity.sink_window -= 1
	if entity.hop_pending:
		entity.hop_pending = 0
		entity.vy = -Motion.random_ticks(state, 384 * 60, 448 * 60)
	if entity.sinking:
		entity.vy = mini(entity.vy + GRAVITY, MAX_FALL)
		entity.x += entity.vx
		entity.y += entity.vy
	else:
		var distance: int = entity.vx
		if Motion.move(entity, world, BOX, distance, true) != distance:
			entity.vx = 0
		var grounded := Motion.gravity_box(entity, world, BOX, GRAVITY, MAX_FALL)
		if grounded:
			land(entity, state)
	if entity.thrown and entity.status == 1:
		Body.hit_others(entity, state, world, BOX, Hits.SPIT)


static func land(entity: Dictionary, state: Dictionary) -> void:
	if entity.colour == 1:
		Body.remove(entity, state)
		return
	if entity.sink_window == 0:
		entity.hop_pending = 1
		entity.sink_window = SINK_WINDOW
	else:
		entity.vy = -Motion.random_ticks(state, 256 * 60, 384 * 60)
		entity.sinking = 1


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if not entity.thrown and Body.player_overlap(entity, state, BOX):
		Body.hurt(entity, state)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	return Body.tongue(entity, state, 1)


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, _kind: int, _from_x: int
) -> void:
	Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var kind := Body.projectile_kind(projectile)
	if kind == Hits.EGG:
		projectile.fall_on_terrain = 1
	hit(entity, state, world, kind, projectile.x)
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.held == 0, "animation": "Yellow" if entity.colour else "Green"}


static func finished(entity: Dictionary) -> bool:
	return entity.status in [2, 3] and entity.held == 0


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant in [0, 1]
		and entity.colour in [0, 1]
		and entity.sink_window >= 0
		and entity.sink_window <= SINK_WINDOW
		and entity.hop_pending in [0, 1]
		and entity.sinking in [0, 1]
		and entity.thrown in [0, 1]
		and entity.vx >= -MAX_SPEED
		and entity.vx <= MAX_SPEED
	)
