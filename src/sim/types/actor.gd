extends RefCounted

const Behavior = preload("res://src/sim/enemies.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Plant = preload("res://src/sim/enemy_plant.gd")
const Fish = preload("res://src/sim/enemy_fish.gd")
const CODES := ["e1", "e2", "e3", "e5", "e20"]
const FIELDS := [
	["phase", 0], ["timer", 0], ["cycles", 0], ["mode", 0],
	["home_y", 0], ["water", 0], ["contact", 0],
	["head_dx", 0], ["head_dy", 0], ["head_size", 0],
	["rise_ticks", 0], ["rise_velocity", 0], ["pin_size", 0]
]
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const Units = preload("res://src/sim/units.gd")
const S := Units.SCALE


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"home_y": int(source.y), "spawn_mode": 1, "status": 0,
		"can_despawn": 1, "can_respawn": 1}


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var source: Dictionary = world.entities[entity.source_index]
	match entity.code:
		"e1":
			Behavior.walker(entity, state, world)
		"e2":
			Behavior.flyer(entity, source, world)
		"e3":
			Behavior.flower(entity, world)
		"e5":
			Plant.advance(entity, state, world, state.pressed_input)
		"e20":
			Fish.advance(entity, source, state, world)


static func activate(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	if entity.code == "e2":
		entity.cycles = 1 if entity.facing < 0 else -1
	elif entity.code == "e1":
		entity.timer = Motion.random_ticks(state, 60, 150)
		entity.cycles = Motion.random_cycles(state)


static func bounds(entity: Dictionary) -> Array:
	return Motion.box(entity, entity.code)


static func contact(entity: Dictionary, state: Dictionary, world: Dictionary, input: int) -> void:
	Behavior.contact_entity(entity, state, world, input)


static func valid(entity: Dictionary) -> bool:
	return not (
		entity.phase < 0 or entity.phase > 360
		or entity.timer < 0 or entity.timer > 210
		or entity.cycles < -1 or entity.cycles > 180
		or entity.mode < 0 or entity.mode > 5
		or entity.water not in [0, 1] or entity.contact not in [0, 1]
		or entity.head_dx < -S or entity.head_dx > S
		or entity.head_dy < -S or entity.head_dy > S
		or entity.head_size < 0 or entity.head_size > 15
		or entity.pin_size < 0 or entity.pin_size > 15
		or (entity.mode == 4 and entity.pin_size > entity.head_size)
		or entity.rise_ticks < 0 or entity.rise_ticks > 60
		or entity.rise_velocity < 0 or entity.rise_velocity > 704 * 60
		or entity.vx < -128 * 60 or entity.vx > 128 * 60
		or entity.vy < -944 * 60 or entity.vy > 704 * 60
	)
