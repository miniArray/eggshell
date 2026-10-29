extends RefCounted
## A runtime petal. It orbits its stem's face, flies straight out, or drops and slides.

const Body = preload("res://src/sim/enemy_body.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const Stem = preload("res://src/sim/types/petal_stem.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["enemy_petal"]
const ENEMY := true
const ELEMENT_REACTIONS := Elements.BURNS
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const ORBIT := 0
const FLY := 1
const FALL := 2
const THROWN := 3
const RADIUS := 32
const RADIUS_TICKS := 18
const MAX_FALL := 704 * 60
const BOX := [-16 * S, -16 * S, 16 * S, 16 * S]
const HULL := [[-12, -12], [0, -16], [12, -12], [16, 0], [12, 12], [0, 16], [-12, 12], [-16, 0]]
const FIELDS := Body.FIELDS + [["mode", ORBIT], ["stem_token", 0], ["slot", 0], ["age", 0]]


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.can_respawn = 0
	return values


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func hull(entity: Dictionary) -> Array:
	var result := []
	for point: Array in HULL:
		result.append([entity.x + point[0] * S, entity.y + point[1] * S])
	return result


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	if action == Body.RELEASED:
		# Mouth release is the same plain throw as the spiked hopper.
		var upward: bool = entity.vx == 0
		var direction: int = state.facing if upward else signi(entity.vx)
		entity.spat = 0
		entity.mode = THROWN
		entity.facing = direction
		entity.vx = direction * (200 if upward else 320) * 60
		entity.vy = (-768 if upward else -256) * 60
	entity.age = mini(entity.age + 1, RADIUS_TICKS)
	match entity.mode:
		ORBIT:
			var stem: Dictionary = Body.registry_for().find_token(state, entity.stem_token)
			if stem.is_empty() or stem.status != 1 or stem.code != "e18":
				entity.mode = FALL
				entity.vy = -128 * 60
				return
			var center := Stem.face_center(stem)
			var angle := Stem.petal_angle(stem, entity.slot)
			var radius: int = RADIUS * S * entity.age / RADIUS_TICKS
			entity.x = center[0] + Motion.turn_cosine(angle, radius)
			entity.y = center[1] + Motion.turn_sine(angle, radius)
		FLY:
			entity.x += entity.vx
			entity.y += entity.vy
		FALL, THROWN:
			var distance: int = entity.vx
			if Motion.move(entity, world, BOX, distance, true) != distance:
				entity.vx = 0
			Motion.gravity_box(entity, world, BOX, 2048, MAX_FALL)
			if entity.mode == THROWN and entity.status == 1:
				Body.hit_others(entity, state, world, BOX, Hits.SPIT)
	Body.hazards(entity, state, world, BOX)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	if entity.mode == THROWN or entity.hidden or entity.held or entity.status != 1:
		return
	if state.get("captured_by", 0):
		return
	if Body.polygon_overlap(hull(entity), Body.world_box(state, Moves.player_box(state))):
		Body.hurt(entity, state)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	# A dropped petal has no collisions; only its damage helper remains.
	if entity.mode == FALL:
		return 0
	return Body.tongue(entity, state, 1)


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, _from_x: int
) -> void:
	if Reactions.hit(entity, state, world, kind, ELEMENT_REACTIONS, bounds(entity)):
		return
	if entity.mode != FALL:
		Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if entity.mode == FALL:
		return 0
	hit(entity, state, world, Body.projectile_kind(projectile), projectile.get("x", entity.x))
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.held == 0, "animation": "Petal"}


static func finished(entity: Dictionary) -> bool:
	return entity.status in [2, 3] and entity.held == 0


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.mode >= ORBIT
		and entity.mode <= THROWN
		and entity.stem_token >= 0
		and entity.slot >= 0
		and entity.slot < Stem.PETALS
		and entity.age >= 0
		and entity.age <= RADIUS_TICKS
	)
