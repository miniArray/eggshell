extends RefCounted
## A slime blob that creeps along, turning at walls. Landing on it squashes it
## under the player before it bursts. The dripping form hangs hidden on a ceiling
## and drops when the player comes near, then stares at the player before it
## creeps on.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e15"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const WALK := 0
const SQUASH := 1
const HANG := 2
const DRIP := 3
const DROP := 4
const LAND := 5
const STARE := 6
## Ticks: squash 3 frames at 12/s, drip 3 at 16/s, land 7 at 24/s, stare 1 s.
const TICKS := {SQUASH: 15, DRIP: 12, LAND: 18, STARE: 60}
const FIELDS := (
	Body.FIELDS + [["phase", WALK], ["timer", 0], ["fall_from", 0], ["pin_dx", 0], ["contact", 0]]
)
const WALK_BOX := [-10 * S, -8 * S, 10 * S, 16 * S]
const HANG_BOX := [-10 * S, 0, 10 * S, 16 * S]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var result := Options.prepare(source, 1)
	if result.ok and source.variant == 1:
		source.y -= 16 * S  # The dripping form starts 16 px higher, against the ceiling.
	return result


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	if int(source.get("variant", 0)) == 1:
		values.phase = HANG
		values.hidden = 1
	return values


static func bounds(entity: Dictionary) -> Array:
	return HANG_BOX if entity.phase in [HANG, DRIP] else WALK_BOX


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	var box := bounds(entity)
	if Body.spit_step(entity, state, world, box) or Body.hazards(entity, state, world, box):
		return
	match entity.phase:
		HANG:
			if entity.timer == 0:
				attach(entity, world)
			if entity.phase == HANG and absi(state.x - entity.x) < 96 * S:
				entity.phase = DRIP
				entity.hidden = 0
				entity.timer = TICKS[DRIP]
				entity.facing = 1 if state.x > entity.x else -1
			return
		DRIP:
			entity.timer -= 1
			if entity.timer <= 0:
				entity.phase = DROP
				entity.y += 8 * S
				entity.fall_from = entity.y
				entity.vy = 0
			return
		SQUASH:
			entity.vx = 0
			pin(entity, state)
			entity.timer -= 1
			if entity.timer <= 0:
				Body.remove(entity, state)
			return
		LAND, STARE:
			entity.vx = 0
			entity.timer -= 1
			if entity.timer <= 0:
				if entity.phase == LAND:
					entity.phase = STARE
					entity.timer = TICKS[STARE]
					entity.facing = 1 if state.x > entity.x else -1
				else:
					entity.phase = WALK
		WALK:
			var wet := int(
				World.water_overlaps(
					world,
					entity.x + box[0],
					entity.y + box[1],
					entity.x + box[2],
					entity.y + box[3]
				)
			)
			entity.vx = entity.facing * 48 * 60 / (wet + 1)
		DROP:
			entity.vx = 0
	var distance: int = entity.vx
	if distance and Motion.move(entity, world, box, distance, true) != distance:
		entity.facing *= -1
	if Motion.gravity_box(entity, world, box) and entity.phase == DROP:
		var far: bool = entity.y > entity.fall_from + 112 * S
		entity.phase = LAND if far else WALK
		entity.timer = TICKS[LAND] if far else 0


## The hanging form needs a solid within 2 px above; without one it creeps instead.
static func attach(entity: Dictionary, world: Dictionary) -> void:
	entity.timer = 1
	if not Collision.overlaps(entity, world, WALK_BOX, 0, -2 * S):
		entity.phase = WALK
		entity.hidden = 0
		entity.timer = 0


static func pin(entity: Dictionary, state: Dictionary) -> void:
	state.x = entity.x + entity.pin_dx
	state.y = entity.y
	state.vx = 0
	state.vy = 0
	state.on_floor = 1


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if entity.phase in [HANG, SQUASH]:
		entity.contact = 0
		return
	var touching := Body.player_overlap(entity, state, bounds(entity))
	if touching and not entity.contact and entity.y > state.y - 8 * S:
		entity.phase = SQUASH
		entity.timer = TICKS[SQUASH]
		entity.vx = 0
		entity.pin_dx = clampi(state.x - entity.x, -64 * S, 64 * S)
		pin(entity, state)
	elif touching and entity.y < state.y - 8 * S:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	return Body.tongue(entity, state) if entity.phase in [WALK, LAND, STARE, DROP] else 0


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, _kind: int, _from_x: int
) -> void:
	if entity.phase not in [HANG, SQUASH]:
		Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if entity.phase in [HANG, SQUASH]:
		return 0
	hit(entity, state, world, Body.projectile_kind(projectile), projectile.x)
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var names := {
		WALK: "Walk",
		SQUASH: "Squash",
		HANG: "Drip",
		DRIP: "Drip",
		DROP: "Fall",
		LAND: "Land",
		STARE: "Stare"
	}
	return {"visible": entity.held == 0 and entity.phase != HANG, "animation": names[entity.phase]}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant <= 1
		and entity.phase >= WALK
		and entity.phase <= STARE
		and entity.timer >= 0
		and entity.timer <= 60
		and absi(entity.pin_dx) <= 64 * S
		and entity.contact in [0, 1]
	)
