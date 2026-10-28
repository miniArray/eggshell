extends RefCounted
## A helmeted walker. With its helmet on, any touch hurts the player. A thrown
## egg or body knocks the helmet off; it lands, looks around, blushes and runs
## faster. Without the helmet it can be stomped like an ordinary walker.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e29"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const WALK := 0
const HELMET_STOMP := 1
const FALL := 2
const LAND := 3
const LOOK := 4
const BLUSH := 5
const RUN := 6
## Phase lengths in ticks: helmet stomp 4 frames at 16/s, land 4 at 24/s,
## look 3 at 24/s, blush 2 at 5/s.
const TICKS := {HELMET_STOMP: 15, LAND: 10, LOOK: 8, BLUSH: 24}
const FIELDS := (
	Body.FIELDS
	+ [["phase", WALK], ["timer", 0], ["speed", 48], ["helmet", 1], ["run_age", 0], ["contact", 0]]
)
const BOX := [-14 * S, -34 * S, 14 * S, 16 * S]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 1)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.speed = 144 if int(source.get("variant", 0)) == 1 else 48
	return values


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Body.spit_step(entity, state, world, BOX) or Body.hazards(entity, state, world, BOX):
		return
	var grounded := Collision.floor_at(entity, world, BOX) != 0
	match entity.phase:
		WALK, RUN:
			var wet := int(
				World.water_overlaps(
					world,
					entity.x + BOX[0],
					entity.y + BOX[1],
					entity.x + BOX[2],
					entity.y + BOX[3]
				)
			)
			entity.vx = entity.facing * (entity.speed * 60 - entity.speed * 30 * wet)
			if grounded and Motion.edge(entity, world, BOX):
				entity.facing *= -1
				entity.vx = -entity.vx
			if entity.phase == RUN:
				entity.run_age = mini(1_000_000, entity.run_age + 1)
				if entity.run_age in [30, 60]:
					entity.facing *= -1  # It looks back over its shoulder twice.
		HELMET_STOMP, LAND, LOOK, BLUSH:
			entity.vx = 0
			entity.timer -= 1
			if entity.timer <= 0:
				match entity.phase:
					HELMET_STOMP:
						entity.phase = WALK
					LAND:
						set_phase(entity, LOOK)
					LOOK:
						set_phase(entity, BLUSH)
					BLUSH:
						entity.phase = RUN
						entity.facing *= -1
						entity.speed = 144
						entity.run_age = 0
		FALL:
			if grounded and entity.vy >= 0:
				set_phase(entity, LAND)
				entity.vx = 0
	var distance: int = entity.vx
	if distance and Motion.move(entity, world, BOX, distance, true) != distance:
		entity.facing *= -1
	Motion.gravity_box(entity, world, BOX)


static func set_phase(entity: Dictionary, phase: int) -> void:
	entity.phase = phase
	entity.timer = TICKS[phase]


## A strike knocks the helmet off; a second one defeats it.
static func strike(entity: Dictionary, state: Dictionary, from_x: int) -> void:
	if entity.helmet:
		entity.helmet = 0
		entity.phase = FALL
		entity.timer = 0
		entity.vy = -256 * 60
		entity.vx = (144 if entity.x > from_x else -144) * 60
	elif entity.phase != FALL:
		Body.remove(entity, state)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	var touching := Body.player_overlap(entity, state, BOX)
	if touching and entity.phase != FALL:
		var above: bool = entity.y > state.y - 8 * S
		if entity.helmet:
			Body.hurt(entity, state)
			if above and entity.phase == WALK:
				set_phase(entity, HELMET_STOMP)
				entity.vx = 0
		elif above and not entity.contact:
			if not Body.pounding(state):
				Moves.bounce(state, -absi(entity.vy / 2) - 320 * 60, input)
			Body.remove(entity, state)
		elif not above:
			Body.hurt(entity, state)
	entity.contact = int(touching)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	return Body.tongue(entity, state)


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, _kind: int, from_x: int
) -> void:
	strike(entity, state, from_x)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, _world: Dictionary
) -> int:
	if entity.phase == FALL:
		return 0
	var kind := Body.projectile_kind(projectile)
	strike(entity, state, projectile.x)
	return 1 if kind == Hits.EGG else 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var names := {
		WALK: "Move%d" % int(entity.speed == 144 and entity.helmet),
		HELMET_STOMP: "HelmetStomp",
		FALL: "LostHelmetFall",
		LAND: "LostHelmetLand",
		LOOK: "LookAround",
		BLUSH: "Blush",
		RUN: "BlushRun"
	}
	return {"visible": entity.held == 0, "animation": names[entity.phase]}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant <= 1
		and entity.phase >= WALK
		and entity.phase <= RUN
		and entity.timer >= 0
		and entity.timer <= 24
		and entity.speed in [48, 144]
		and entity.helmet in [0, 1]
		and entity.run_age >= 0
		and entity.run_age <= 1_000_000
		and entity.contact in [0, 1]
	)
