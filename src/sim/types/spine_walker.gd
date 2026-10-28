extends RefCounted
## A fast walker that raises a spiked shell when the player comes near.

const Body = preload("res://src/sim/enemy_body.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e25"]
const ENEMY := true
const ELEMENT_REACTIONS := Elements.BURNS | Elements.FREEZES
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const WALK := 0
const SPIKE := 1
const SHRINK := 2
const TWEEN := 20
const SPIKE_TICKS := 60
const COOLDOWN := 60
const REACH := 96 * S
const SMALL := [32, 28]
const LARGE := [64, 62]
# Spine hull at full size, relative to the bottom centre, facing left.
const HULL := [[-32, -18], [0, -62], [32, -46], [32, 0], [-32, 0]]
const BOX := [-14 * S, -10 * S, 14 * S, 16 * S]
const FIELDS := (
	Body.FIELDS
	+ [
		["mode", WALK],
		["timer", 0],
		["cooldown", 0],
		["colour", 0],
		["spine_w", 32],
		["spine_h", 28],
		["from_w", 64],
		["from_h", 62]
	]
)


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 1)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.colour = values.variant
	return values


static func bounds(entity: Dictionary) -> Array:
	if entity.mode == WALK:
		return BOX
	var half: int = entity.spine_w * S / 2
	return [-half, 16 * S - entity.spine_h * S, half, 16 * S]


static func spine_hull(entity: Dictionary) -> Array:
	var result := []
	for point: Array in HULL:
		var x: int = point[0] * entity.spine_w * S / 64
		if entity.facing > 0:
			x = -x
		result.append([entity.x + x, entity.y + 16 * S + point[1] * entity.spine_h * S / 62])
	return result


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	if action == Body.RELEASED:
		_reset(entity)
	if Body.spit_step(entity, state, world, BOX) or Body.hazards(entity, state, world, BOX):
		return
	entity.cooldown = maxi(0, entity.cooldown - 1)
	if entity.mode == WALK:
		_walk(entity, state, world)
	else:
		entity.vx = 0
		entity.timer += 1
		face_player(entity, state)
		if entity.mode == SPIKE:
			var tick := mini(entity.timer, TWEEN)
			var part := TWEEN * TWEEN * TWEEN * TWEEN - (TWEEN - tick) ** 4
			entity.spine_w = SMALL[0] + (LARGE[0] - SMALL[0]) * part / TWEEN ** 4
			entity.spine_h = SMALL[1] + (LARGE[1] - SMALL[1]) * part / TWEEN ** 4
			if entity.timer >= SPIKE_TICKS:
				shrink(entity)
		else:
			var part: int = entity.timer ** 4
			entity.spine_w = entity.from_w + (SMALL[0] - entity.from_w) * part / TWEEN ** 4
			entity.spine_h = entity.from_h + (SMALL[1] - entity.from_h) * part / TWEEN ** 4
			if entity.timer >= TWEEN:
				_reset(entity)
				entity.cooldown = COOLDOWN
	Motion.gravity_box(entity, world, BOX)


static func _walk(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var wet := int(
		World.water_overlaps(
			world, entity.x + BOX[0], entity.y + BOX[1], entity.x + BOX[2], entity.y + BOX[3]
		)
	)
	var speed := 128 if entity.colour else 192
	entity.vx = entity.facing * speed * 60 / (wet + 1)
	var distance: int = entity.vx
	if Motion.move(entity, world, BOX, distance, true) != distance:
		entity.facing *= -1
	elif Collision.floor_at(entity, world, BOX) != 0 and Motion.edge(entity, world, BOX):
		entity.facing *= -1
	if (
		entity.cooldown == 0
		and not state.get("captured_by", 0)
		and absi(entity.x - state.x) < REACH
		and absi(entity.y - state.y) < REACH
	):
		entity.mode = SPIKE
		entity.timer = 0
		entity.vx = 0
		entity.spine_w = SMALL[0]
		entity.spine_h = SMALL[1]
		face_player(entity, state)


static func face_player(entity: Dictionary, state: Dictionary) -> void:
	if entity.x != state.x:
		entity.facing = -1 if entity.x > state.x else 1


static func shrink(entity: Dictionary) -> void:
	if entity.mode != SPIKE:
		return
	entity.mode = SHRINK
	entity.timer = 0
	entity.from_w = entity.spine_w
	entity.from_h = entity.spine_h


static func _reset(entity: Dictionary) -> void:
	entity.mode = WALK
	entity.timer = 0
	entity.spine_w = SMALL[0]
	entity.spine_h = SMALL[1]


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	if Body.player_overlap(entity, state, BOX):
		Body.hurt(entity, state)
		return
	if entity.mode != WALK and not entity.held and entity.status == 1:
		var player := Body.world_box(state, Moves.player_box(state))
		if not state.get("captured_by", 0) and Body.polygon_overlap(spine_hull(entity), player):
			Body.hurt(entity, state)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	if entity.mode != WALK:
		return 0
	return Body.tongue(entity, state, 1)


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, _from_x: int
) -> void:
	if Reactions.hit(entity, state, world, kind, ELEMENT_REACTIONS, bounds(entity)):
		return
	if entity.mode == WALK:
		Body.remove(entity, state)
	else:
		shrink(entity)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var kind := Body.projectile_kind(projectile)
	if entity.mode == WALK:
		if kind == Hits.EGG:
			projectile.fall_on_terrain = 1
		hit(entity, state, world, kind, projectile.x)
		return 3
	if entity.mode == SHRINK:
		return 0
	# Raised spines destroy what strikes them and start folding.
	shrink(entity)
	return 1


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	# Raised spines are a separate source sprite; the pack only carries the walk loops.
	return {"visible": entity.held == 0, "animation": str(entity.colour) + "Walk"}


static func finished(entity: Dictionary) -> bool:
	return entity.status in [2, 3] and entity.held == 0


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant in [0, 1]
		and entity.colour in [0, 1]
		and entity.mode >= WALK
		and entity.mode <= SHRINK
		and entity.timer >= 0
		and entity.timer <= SPIKE_TICKS
		and entity.cooldown >= 0
		and entity.cooldown <= COOLDOWN
		and entity.spine_w >= SMALL[0]
		and entity.spine_w <= LARGE[0]
		and entity.spine_h >= SMALL[1]
		and entity.spine_h <= LARGE[1]
		and entity.from_w >= SMALL[0]
		and entity.from_w <= LARGE[0]
		and entity.from_h >= SMALL[1]
		and entity.from_h <= LARGE[1]
	)
