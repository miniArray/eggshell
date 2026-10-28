extends RefCounted
## A walker, two winged forms, empty shells and their released runners.

const Body = preload("res://src/sim/enemy_body.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e6", "e8", "enemy_runner"]
const ENEMY := true
const ELEMENT_REACTIONS := Elements.BURNS | Elements.FREEZES
const DYNAMIC := true
const GOAL_COIN := true
const HIT_KIND := Hits.SHELL
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const WALK := 0
const TURN := 1
const HOP := 2
const HOP_LAND := 3
const FLY := 4
const IDLE := 5
const SPIN := 6
const BARE := 7
const SLIDE := 8
const BARE_TURN := 9
const ENTER := 10
const SHAKE := 11
const RETURN_AIR := 12
const RETURN_LAND := 13
const UP_SPIT := 14
const FIELDS := (
	Body.FIELDS
	+ [
		["mode", WALK],
		["timer", 0],
		["colour", 0],
		["inside", 1],
		["contact", 0],
		["grace", 0],
		["flight_phase", 0],
		["flight_direction", -1],
		["runner_token", 0],
		["origin_shell", 0],
		["target_shell", 0],
		["enter_x", 0],
		["enter_y", 0],
		["target_x", 0],
		["target_y", 0],
		["slide_direction", 1]
	]
)


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 4)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.colour = 1 if source.code == "e8" else Options.option(source, "colour")
	values.mode = [WALK, HOP, FLY, IDLE, SPIN][values.variant]
	values.inside = int(values.variant <= 2)
	if source.code == "enemy_runner":
		values.mode = Options.option(source, "mode", BARE)
		values.timer = Options.option(source, "timer")
		values.origin_shell = Options.option(source, "origin_shell")
		values.slide_direction = Options.option(source, "slide_direction", 1)
		values.grace = Options.option(source, "grace")
		values.inside = 0
	return values


static func bounds(entity: Dictionary) -> Array:
	if entity.mode in [IDLE, SPIN, UP_SPIT, SHAKE]:
		return [-14 * S, -12 * S, 14 * S, 16 * S]
	if entity.mode in [SLIDE, ENTER]:
		return [-14 * S, -12 * S, 14 * S, 18 * S]
	if entity.mode == RETURN_AIR:
		return [-14 * S, -14 * S, 14 * S, 16 * S]
	return [-14 * S, -22 * S, 14 * S, 16 * S]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var registry: Script = Body.registry_for()
	if entity.runner_token:
		var runner: Dictionary = registry.find_token(state, entity.runner_token)
		if runner.is_empty() or runner.status != 1:
			entity.can_despawn = 1
			entity.runner_token = 0
	var fresh: bool = entity.started == 0
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	if fresh:
		entity.flight_direction = entity.facing
	if action == Body.RELEASED:
		if entity.mode not in [BARE, SLIDE, BARE_TURN, ENTER]:
			if entity.vx == 0:
				entity.mode = UP_SPIT
			else:
				spin(entity, signi(entity.vx))
				entity.spat = 0
	if Body.spit_step(entity, state, world, bounds(entity)):
		if not entity.spat and entity.mode == UP_SPIT:
			entity.mode = IDLE
		return
	if Body.hazards(entity, state, world, bounds(entity)):
		return
	if entity.mode == ENTER:
		_enter_step(entity, state)
		return
	if entity.mode == FLY:
		_fly_step(entity, world)
		return
	var box := bounds(entity)
	var grounded := Collision.floor_at(entity, world, box) != 0
	var wet := int(
		World.water_overlaps(
			world, entity.x + box[0], entity.y + box[1], entity.x + box[2], entity.y + box[3]
		)
	)
	match entity.mode:
		TURN, BARE_TURN:
			entity.vx = 0
			entity.timer -= 1
			if entity.timer == 13:
				entity.facing *= -1
			if entity.timer == 0:
				entity.mode = BARE if entity.mode == BARE_TURN else WALK
		HOP_LAND:
			entity.vx = 0
			entity.timer -= 1
			if entity.timer == 0:
				entity.mode = HOP
				entity.vy = (-448 if entity.colour else -280) * 60
		SHAKE:
			entity.vx = 0
			entity.timer -= 1
			if entity.timer == 0:
				entity.mode = RETURN_AIR
				entity.vy = -256 * 60
		RETURN_LAND:
			entity.vx = 0
			entity.timer -= 1
			if entity.timer == 0:
				entity.mode = WALK
		SLIDE:
			entity.vx = entity.slide_direction * 432 * 60 * entity.timer * entity.timer / 3600
			entity.timer -= 1
			if entity.timer == 0:
				entity.mode = BARE
		IDLE, UP_SPIT, RETURN_AIR:
			entity.vx = 0
		_:
			var speed := 432 if entity.mode == SPIN else (64 if entity.mode == HOP else 48)
			var liquid_divisor := wet + 1
			if entity.mode in [WALK, HOP, SPIN]:
				liquid_divisor *= liquid_divisor
			entity.vx = entity.facing * speed * 60 / liquid_divisor
			if (
				entity.colour == 1
				and entity.mode in [WALK, BARE]
				and grounded
				and Motion.edge(entity, world, box)
			):
				_turn(entity)
	var distance: int = entity.vx
	if Motion.move(entity, world, box, distance, true) != distance:
		if entity.mode in [SPIN, HOP]:
			if entity.mode == SPIN:
				Body.strike_wall(entity, state, world, box, signi(distance), Hits.SHELL)
			entity.facing *= -1
		elif entity.mode in [WALK, BARE]:
			_turn(entity)
	var hopped: bool = entity.mode in [HOP, HOP_LAND]
	var landed := Motion.gravity_box(
		entity, world, box, 512 if hopped else 2048, (176 if hopped else 704) * 60
	)
	if landed:
		if entity.mode == HOP:
			entity.mode = HOP_LAND
			entity.timer = 15
		elif entity.mode == RETURN_AIR:
			entity.mode = RETURN_LAND
			entity.timer = 15
		elif entity.mode == BARE:
			_find_shell(entity, state)
	if entity.mode == SPIN:
		Body.hit_others(entity, state, world, box, Hits.SHELL)


static func _turn(entity: Dictionary) -> void:
	entity.mode = BARE_TURN if entity.mode == BARE else TURN
	entity.timer = 26
	entity.vx = 0


static func _fly_step(entity: Dictionary, world: Dictionary) -> void:
	var tick: int = entity.flight_phase
	var time: int = tick if tick <= 150 else 300 - tick
	var numerator: int = 2 * time * time if time < 75 else 22500 - 2 * (150 - time) * (150 - time)
	var amplitude := (112 if entity.colour else 144) * 60
	var velocity: int = entity.flight_direction * amplitude * (22500 - 2 * numerator) / 22500
	entity.vx = 0 if entity.colour else velocity
	entity.vy = velocity if entity.colour else 0
	if entity.vx:
		entity.facing = signi(entity.vx)
	Motion.move(entity, world, bounds(entity), entity.vx, true)
	Motion.move(entity, world, bounds(entity), entity.vy, false)
	entity.flight_phase = (tick + 1) % 300


static func spin(entity: Dictionary, direction: int) -> void:
	entity.mode = SPIN
	entity.timer = 0
	entity.facing = direction
	entity.vx = direction * 432 * 60
	entity.spat = 0


static func eject(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	entity.mode = IDLE
	entity.inside = 0
	entity.vx = 0
	entity.vy = -192 * 60
	var registry: Script = Body.registry_for()
	var direction := 1 if state.x < entity.x else -1
	var runner: Dictionary = registry.spawn_dynamic(
		state,
		world,
		"enemy_runner",
		entity.x,
		entity.y,
		{
			"colour": entity.colour,
			"origin_shell": entity.token,
			"mode": SLIDE,
			"timer": 60,
			"slide_direction": direction,
			"facing": -direction,
			"grace": 1
		}
	)
	if not runner.is_empty():
		entity.runner_token = runner.token
		entity.can_despawn = 0


static func _find_shell(entity: Dictionary, state: Dictionary) -> void:
	var ahead := Body.world_box(entity, bounds(entity))
	ahead[0] += entity.facing * 44 * S
	ahead[2] += entity.facing * 44 * S
	for other: Dictionary in state.entities:
		if (
			other.id == entity.id
			or other.status != 1
			or other.get("held", 0)
			or not other.code in ["e6", "e8"]
		):
			continue
		if (
			other.mode != IDLE
			or other.inside
			or not Body.overlap(ahead, Body.world_box(other, bounds(other)))
		):
			continue
		entity.mode = ENTER
		entity.timer = 24
		entity.target_shell = other.token
		entity.enter_x = entity.x
		entity.enter_y = entity.y
		entity.target_x = other.x
		entity.target_y = other.y
		entity.vx = 0
		entity.vy = 0
		return


static func _enter_step(entity: Dictionary, state: Dictionary) -> void:
	entity.timer -= 1
	var elapsed: int = 24 - entity.timer
	entity.x = entity.enter_x + (entity.target_x - entity.enter_x) * elapsed / 24
	var apex: int = 2 * entity.enter_y - entity.target_y - 32 * S
	if elapsed <= 12:
		entity.y = (
			entity.enter_y + (apex - entity.enter_y) * (144 - (12 - elapsed) * (12 - elapsed)) / 144
		)
	else:
		entity.y = apex + (entity.target_y - apex) * (elapsed - 12) * (elapsed - 12) / 144
	if entity.timer:
		return
	var registry: Script = Body.registry_for()
	var shell: Dictionary = registry.find_token(state, entity.target_shell)
	if (
		not shell.is_empty()
		and shell.status == 1
		and not shell.get("held", 0)
		and shell.mode == IDLE
		and not shell.inside
		and Body.overlap(
			Body.world_box(entity, bounds(entity)), Body.world_box(shell, bounds(shell))
		)
	):
		Body.remove(entity, state)
		shell.inside = 1
		shell.mode = SHAKE
		shell.timer = 120
		shell.facing = entity.facing
	else:
		entity.mode = BARE
	entity.target_shell = 0


static func on_remove(entity: Dictionary, state: Dictionary) -> void:
	if not entity.origin_shell:
		return
	var registry: Script = Body.registry_for()
	var shell: Dictionary = registry.find_token(state, entity.origin_shell)
	if not shell.is_empty():
		shell.can_despawn = 1
		shell.can_respawn = 0
		shell.runner_token = 0


static func contact(entity: Dictionary, state: Dictionary, world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	var touching := Body.player_overlap(entity, state, bounds(entity))
	if not touching:
		entity.contact = 0
		entity.grace = 0
		return
	if entity.grace:
		return
	if entity.y > state.y - 8 * S and not entity.contact:
		if Body.pounding(state):
			Body.remove(entity, state)
		else:
			Body.bounce(entity, state, input)
			if entity.mode in [HOP, HOP_LAND, FLY]:
				entity.mode = WALK
			elif entity.mode >= BARE and entity.mode <= ENTER:
				Body.remove(entity, state)
			elif entity.mode == SPIN:
				entity.mode = IDLE
				entity.vx = 0
			elif entity.inside and entity.mode in [WALK, TURN, IDLE, SHAKE]:
				eject(entity, state, world)
			else:
				spin(entity, 1 if state.x < entity.x else -1)
	elif entity.y < state.y - 8 * S:
		if entity.mode == IDLE:
			spin(entity, 1 if state.x < entity.x else -1)
			entity.grace = 1
		else:
			Body.hurt(entity, state)
	entity.contact = 1


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	var bare: bool = entity.mode in [BARE, SLIDE, BARE_TURN, ENTER]
	if not bare:
		entity.mode = IDLE
		entity.vx = 0
	return Body.tongue(entity, state, 1 if bare else 0)


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, from_x: int
) -> void:
	if Reactions.hit(entity, state, world, kind, ELEMENT_REACTIONS, bounds(entity)):
		return
	if kind == Hits.EGG and entity.mode not in [BARE, SLIDE, BARE_TURN, ENTER]:
		if entity.mode in [HOP, FLY]:
			entity.mode = WALK
		else:
			spin(entity, 1 if from_x < entity.x else -1)
	elif kind == Hits.SPIT and entity.mode == SPIN:
		return
	else:
		Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var kind := Body.projectile_kind(projectile)
	var bare: bool = entity.mode in [BARE, SLIDE, BARE_TURN, ENTER]
	if kind == Hits.EGG and bare:
		projectile.fall_on_terrain = 1
		hit(entity, state, world, kind, projectile.x)
		return 3
	if kind == Hits.SPIT and entity.mode == SPIN:
		return 0
	var both_spin: bool = (
		kind == Hits.SHELL
		and entity.mode == SPIN
		and projectile.code in ["e6", "e8"]
		and projectile.mode == SPIN
	)
	hit(entity, state, world, kind, projectile.x)
	return 1 if kind == Hits.EGG or both_spin else 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var pose := "Walk"
	if entity.mode in [IDLE, SPIN, UP_SPIT, SHAKE]:
		pose = "Shell"
	elif entity.mode in [HOP, FLY]:
		pose = "Winged"
	elif entity.mode == HOP_LAND:
		pose = "WingedLand"
	elif entity.mode in [TURN, BARE_TURN]:
		pose = "Turn"
	elif entity.mode in [RETURN_AIR, ENTER]:
		pose = "Jump"
	elif entity.mode == RETURN_LAND:
		pose = "Land"
	return {"visible": entity.held == 0, "animation": str(entity.colour) + pose}


static func finished(entity: Dictionary) -> bool:
	return entity.status in [2, 3] and entity.held == 0


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.mode >= WALK
		and entity.mode <= UP_SPIT
		and entity.timer >= 0
		and entity.timer <= 120
		and entity.colour in [0, 1]
		and entity.inside in [0, 1]
		and entity.contact in [0, 1]
		and entity.grace in [0, 1]
		and entity.flight_phase >= 0
		and entity.flight_phase < 300
		and entity.flight_direction in [-1, 1]
		and entity.slide_direction in [-1, 1]
		and entity.origin_shell >= 0
		and entity.runner_token >= 0
		and entity.target_shell >= 0
	)
