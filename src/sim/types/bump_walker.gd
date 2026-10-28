extends RefCounted
## A round bumper that never hurts: touching it shoves the player aside, and
## landing on it bounces the player. The plain form idles, looks around and
## waddles a few steps; F=1 hops toward the player and belly-slides; F=2 flies
## back and forth with a gentle bob.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e19"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
## Walk-form phases.
const IDLE := 0
const STEP := 1
## Slide-form phases.
const HOP := 2
const SLIDE := 3
const GET_UP := 4
const RISE := 5
const LOOK := 6
const AIM := 7
## Fly form.
const FLY := 8
const STEP_TICKS := 9  # Six walk frames at 40 per second.
const SLIDE_TICKS := 150  # 2.5 s easing out from full slide speed.
const FLY_SWEEP := 150  # 2.5 s per horizontal sweep.
const FLY_BOB := 75  # 1.25 s per vertical bob.
const FIELDS := (
	Body.FIELDS
	+ [["phase", IDLE], ["timer", 0], ["flip_timer", 30], ["cycles", 0], ["age", 0], ["contact", 0]]
)
const BOX := [-14 * S, -10 * S, 14 * S, 16 * S]
const MAX_AGE := 1_000_000


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 2)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	var form := int(source.get("variant", 0))
	values.phase = [IDLE, AIM, FLY][form]
	return values


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Body.spit_step(entity, state, world, BOX) or Body.hazards(entity, state, world, BOX):
		return
	entity.age = mini(MAX_AGE, entity.age + 1)
	if entity.phase == FLY:
		fly(entity, world)
		return
	var grounded := Collision.floor_at(entity, world, BOX) != 0
	match entity.phase:
		IDLE:
			entity.vx = 0
			if entity.timer == 0:
				entity.timer = Motion.random_ticks(state, 60, 150)
				entity.cycles = Motion.random_cycles(state) + 2  # round(random(3, 6))
				entity.flip_timer = 30
			else:
				entity.flip_timer -= 1
				if entity.flip_timer == 0:
					entity.facing *= -1
					entity.flip_timer = 30
				entity.timer -= 1
				if entity.timer == 0:
					entity.phase = STEP
					entity.timer = STEP_TICKS
		STEP:
			entity.vx = entity.facing * 64 * 60
			if grounded and Motion.edge(entity, world, BOX):
				entity.facing *= -1
				entity.vx = -entity.vx
			entity.timer -= 1
			if entity.timer == 0:
				if entity.cycles > 0:
					entity.cycles -= 1
					entity.timer = STEP_TICKS
				else:
					entity.phase = IDLE
					entity.vx = 0
		AIM:
			entity.facing = 1 if state.x > entity.x else -1
			entity.phase = HOP
			entity.vy = -192 * 60
		HOP:
			entity.vx = entity.facing * 256 * 60
			if grounded and entity.vy >= 0:
				entity.phase = SLIDE
				entity.timer = SLIDE_TICKS
		SLIDE:
			entity.timer -= 1
			var eased: int = 290 * entity.timer * entity.timer / (SLIDE_TICKS * SLIDE_TICKS)
			var snow: bool = World.named_overlaps(
				world,
				"snow64",
				entity.x + BOX[0],
				entity.y + BOX[3],
				entity.x + BOX[2],
				entity.y + BOX[3] + 4 * S
			)
			entity.vx = entity.facing * eased * 60 / (1 if snow else 2)
			if entity.timer <= 0:
				entity.phase = GET_UP
				entity.timer = 12
				entity.vx = 0
		GET_UP:
			entity.timer -= 1
			if entity.timer <= 0:
				entity.phase = RISE
				entity.vy = -192 * 60
		RISE:
			entity.vx = 0
			if grounded and entity.vy >= 0:
				entity.phase = LOOK
				entity.cycles = 3
				entity.timer = 12
		LOOK:
			entity.vx = 0
			entity.timer -= 1
			if entity.timer <= 0:
				entity.cycles = maxi(0, entity.cycles - 1)
				entity.facing *= -1
				entity.timer = 3
				var toward: bool = (state.x > entity.x) == (entity.facing > 0)
				if entity.cycles <= 0 and toward:
					entity.phase = AIM
	var distance: int = entity.vx
	if distance and Motion.move(entity, world, BOX, distance, true) != distance:
		entity.facing *= -1
	Motion.gravity_box(entity, world, BOX)


## Ping-pong sweeps with an in-out ease: ±144 px/s across, ±48 px/s up and down.
static func fly(entity: Dictionary, world: Dictionary) -> void:
	var sweep: int = entity.age % (2 * FLY_SWEEP)
	var start := -144 if entity.mirror == 0 else 144
	var across := sweep_speed(sweep, FLY_SWEEP, start, -start)
	var bob := sweep_speed(entity.age % (2 * FLY_BOB), FLY_BOB, -48, 48)
	entity.vx = across * 60
	entity.vy = bob * 60
	entity.facing = 1 if entity.vx > 0 else -1
	var dx: int = entity.vx
	Motion.move(entity, world, BOX, dx, true)
	if Collision.prepare(entity, world, BOX):
		Collision.vertical(entity, world, BOX, entity.vy, Collision.floor_at(entity, world, BOX))


static func sweep_speed(tick: int, span: int, from: int, to: int) -> int:
	var t := tick if tick < span else 2 * span - tick
	# Smoothstep in integers: 3t² − 2t³ over the span.
	var eased := (3 * t * t * span - 2 * t * t * t) * 1000 / (span * span * span)
	return from + (to - from) * eased / 1000


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	var touching := Body.player_overlap(entity, state, BOX)
	if touching:
		var away := -1 if state.x < entity.x else 1
		var centred: bool = absi(state.x - entity.x) < 16 * S
		if not state.on_floor:
			if state.y < entity.y:
				Moves.bounce(state, -absi(entity.vy / 2) - 256 * 60, input)
			else:
				state.vy = absi(state.vy)
		elif centred:
			Moves.bounce(state, -absi(entity.vy / 2) - 256 * 60, input)
			state.vx = away * 224 * 60
			entity.vx = -away * 96 * 60
		else:
			if entity.phase == SLIDE:
				entity.timer = 0
			state.vx = away * 224 * 60
			entity.vx = -away * 96 * 60
	entity.contact = int(touching)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	return Body.tongue(entity, state, 0)


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, _kind: int, _from_x: int
) -> void:
	Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if projectile.has("fall_on_terrain"):
		projectile.fall_on_terrain = 1
	hit(entity, state, world, Body.projectile_kind(projectile), projectile.x)
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var names := {
		IDLE: "Idle",
		STEP: "Walk",
		HOP: "Jump",
		SLIDE: "Slide",
		GET_UP: "Slide",
		RISE: "Jump",
		LOOK: "Idle",
		AIM: "Idle",
		FLY: "Fly1"
	}
	return {"visible": entity.held == 0, "animation": names[entity.phase]}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant <= 2
		and entity.phase >= IDLE
		and entity.phase <= FLY
		and entity.timer >= 0
		and entity.timer <= SLIDE_TICKS
		and entity.flip_timer >= 0
		and entity.flip_timer <= 30
		and entity.cycles >= 0
		and entity.cycles <= 8
		and entity.age >= 0
		and entity.age <= MAX_AGE
		and entity.contact in [0, 1]
	)
