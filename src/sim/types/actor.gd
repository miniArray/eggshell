extends RefCounted

const Behavior = preload("res://src/sim/enemies.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Plant = preload("res://src/sim/enemy_plant.gd")
const Fish = preload("res://src/sim/enemy_fish.gd")
const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Hits = preload("res://src/sim/hits.gd")
const Moves = preload("res://src/sim/moves.gd")
const Damage = preload("res://src/sim/damage.gd")
const CODES := ["e1", "e2", "e3", "e5", "e20", "e21"]
const ENEMY := true
const DYNAMIC := true
const FIELDS := (
	Body.FIELDS
	+ [
		["roll", 0],
		["roll_ticks", 0],
		["roll_up", 0],
		["roll_grace", 0],
		["roll_bounce", 0],
		["ground_form", 0],
		["home_x", 0],
		["fish_finish", 0],
		["fish_dry", 0],
		["rise_duration", 60],
		["fish_jumps", 3],
		["fish_ready", 1],
		["fish_exhausted", 0],
		["fish_left", 48 * 3600],
		["fish_right", 48 * 3600],
		["phase", 0],
		["timer", 0],
		["cycles", 0],
		["mode", 0],
		["home_y", 0],
		["water", 0],
		["contact", 0],
		["head_dx", 0],
		["head_dy", 0],
		["head_size", 0],
		["rise_ticks", 0],
		["rise_velocity", 0],
		["pin_size", 0]
	]
)
const GOAL_COIN := true  # Body only; the extended head is not an entity.
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const Units = preload("res://src/sim/units.gd")
const S := Units.SCALE


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var maximum := 4 if source.code in ["e1", "e2"] else (3 if source.code in ["e20", "e21"] else 0)
	return Options.prepare(source, maximum)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.home_y = int(source.y)
	values.home_x = int(source.x)
	return values


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var fresh: bool = entity.started == 0
	var action := Body.process(entity, state)
	if fresh and entity.code in ["e20", "e21"] and entity.variant == 2:
		activate(entity, state, world)
	if action in [Body.HELD, Body.GONE]:
		return
	if action == Body.RELEASED and entity.code in ["e1", "e2"]:
		start_roll(entity, state.facing, entity.vy, entity.vx == 0)
		entity.spat = 0
	if entity.roll:
		roll_step(entity, state, world)
		return
	if Body.spit_step(entity, state, world, bounds(entity)):
		return
	if Body.hazards(entity, state, world, bounds(entity)):
		return
	var source := {"x": entity.spawn_x, "y": entity.spawn_y, "variant": entity.variant}
	match entity.code:
		"e1":
			if entity.timer == 0 and entity.mode == 0:
				activate(entity, state, world)
			Behavior.walker(entity, state, world)
		"e2":
			if entity.ground_form:
				if entity.timer == 0 and entity.mode == 0:
					entity.timer = Motion.random_ticks(state, 60, 150)
					entity.cycles = Motion.random_cycles(state)
				Behavior.walker(entity, state, world)
			else:
				if not entity.cycles:
					activate(entity, state, world)
				Behavior.flyer(entity, source, world)
		"e3":
			Behavior.flower(entity, world)
		"e5":
			Plant.advance(entity, state, world, state.pressed_input)
		"e20", "e21":
			Fish.advance(entity, source, state, world)


static func activate(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	if entity.code == "e2":
		entity.cycles = 1 if entity.facing < 0 else -1
	elif entity.code == "e1":
		entity.timer = Motion.random_ticks(state, 60, 150)
		entity.cycles = Motion.random_cycles(state)
	elif entity.code in ["e20", "e21"] and entity.variant == 2:
		entity.fish_left = (232 if entity.facing < 0 else -24) * S
		entity.fish_right = (-24 if entity.facing < 0 else 232) * S


static func bounds(entity: Dictionary) -> Array:
	var body := Motion.box(entity, entity.code)
	if entity.code == "e5" and entity.head_size:
		var head := Plant.head_box(entity)
		body = [
			mini(body[0], head[0] - entity.x),
			mini(body[1], head[1] - entity.y),
			maxi(body[2], head[2] - entity.x),
			maxi(body[3], head[3] - entity.y)
		]
	return body


static func activation_bounds(entity: Dictionary) -> Array:
	return Body.world_box(entity, Motion.box(entity, entity.code))


static func head_box(entity: Dictionary) -> Array:
	return Plant.head_box(entity) if entity.code == "e5" and entity.head_size else []


static func contact(entity: Dictionary, state: Dictionary, world: Dictionary, input: int) -> void:
	if entity.held or entity.spat or entity.fish_exhausted:
		return
	if entity.roll:
		if (
			entity.roll_grace == 0
			and entity.roll_up == 0
			and Body.player_overlap(entity, state, bounds(entity))
		):
			Body.remove(entity, state)
		return
	Behavior.contact_entity(entity, state, world, input)


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and (
			entity.variant <= 3
			if entity.code in ["e20", "e21"]
			else (entity.variant <= 4 if entity.code in ["e1", "e2"] else entity.variant == 0)
		)
		and not (
			entity.phase < 0
			or entity.phase > 360
			or entity.timer < 0
			or entity.timer > 210
			or entity.cycles < -1
			or entity.cycles > 180
			or entity.mode < 0
			or entity.mode > 5
			or entity.roll not in [0, 1]
			or entity.roll_up not in [0, 1]
			or entity.roll_ticks < 0
			or entity.roll_ticks > 90
			or entity.roll_grace < 0
			or entity.roll_grace > 15
			or entity.roll_bounce not in [0, 1]
			or entity.ground_form not in [0, 1]
			or entity.fish_finish < 0
			or entity.fish_finish > 3
			or entity.fish_dry not in [0, 1]
			or entity.rise_duration not in [3, 60]
			or entity.fish_jumps < 0
			or entity.fish_jumps > 3
			or entity.fish_ready not in [0, 1]
			or entity.fish_exhausted not in [0, 1]
			or entity.water not in [0, 1]
			or entity.contact not in [0, 1]
			or entity.head_dx < -S
			or entity.head_dx > S
			or entity.head_dy < -S
			or entity.head_dy > S
			or entity.head_size < 0
			or entity.head_size > 15
			or entity.pin_size < 0
			or entity.pin_size > 15
			or (entity.mode == 4 and entity.pin_size > entity.head_size)
			or entity.rise_ticks < 0
			or entity.rise_ticks > 60
			or entity.rise_velocity < 0
			or entity.rise_velocity > 704 * 60
			or entity.vx < -512 * 60
			or entity.vx > 512 * 60
			or entity.vy < -944 * 60
			or entity.vy > 704 * 60
		)
	)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	if entity.code == "e5":
		return (
			2
			if Body.overlap(Moves.tongue_box(state), Plant.head_box(entity)) and entity.mode != 0
			else 0
		)
	var result := Body.tongue(entity, state, 1, 1 if entity.code in ["e20", "e21"] else 0)
	if result == 1 and entity.code == "e2":
		entity.ground_form = 1
		entity.mode = 0
		entity.timer = 0
	return result


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, kind: int, from_x: int
) -> void:
	if entity.held or entity.status != 1:
		return
	if kind == Hits.EGG and entity.code in ["e1", "e2"]:
		start_roll(entity, 1 if entity.x > from_x else -1, 0, false)
	else:
		Body.remove(entity, state)


static func on_remove(entity: Dictionary, state: Dictionary) -> void:
	if entity.code == "e5" and state.captured_by == entity.family_index + 1:
		if not state.separated:
			Damage.separate(state, -entity.facing * 400 * 60)
		Plant.release(entity, state)


static func start_roll(entity: Dictionary, direction: int, velocity_y: int, upward: bool) -> void:
	entity.roll = 1
	entity.ground_form = 1
	entity.roll_up = int(upward)
	entity.roll_ticks = 90 if upward else 0
	entity.roll_grace = 0 if upward else 15
	entity.roll_bounce = 0 if upward else 1
	entity.facing = direction
	entity.vx = 0 if upward else direction * 432 * 60
	entity.vy = velocity_y


static func roll_step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	entity.roll_grace = maxi(0, entity.roll_grace - 1)
	if entity.roll_up:
		entity.roll_ticks = maxi(0, entity.roll_ticks - 1)
		entity.vx = 0
		if entity.roll_ticks == 0:
			entity.roll = 0
			entity.mode = 0
			entity.timer = Motion.random_ticks(state, 60, 150)
			return
	else:
		entity.vx = entity.facing * 432 * 60
	var distance: int = entity.vx
	var actual := Motion.move(entity, world, Motion.box(entity, "e1"), distance, true)
	if actual != distance and not entity.roll_up:
		Body.remove(entity, state)
		return
	if Motion.gravity_box(entity, world, Motion.box(entity, "e1")) and entity.roll_up:
		entity.vy = (-384 if not entity.roll_bounce else -256) * 60
		entity.roll_bounce = 1
	if not Body.hazards(entity, state, world, Motion.box(entity, "e1")):
		Body.hit_others(entity, state, world, Motion.box(entity, "e1"), Hits.SPIT, true)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var kind := Body.projectile_kind(projectile)
	if entity.code == "e5" and kind != Hits.CLEAR:
		var registry: Script = Body.registry_for()
		var type: Script = registry.lookup(projectile.code)
		var head := head_box(entity)
		var touching_head: bool = (
			not head.is_empty()
			and type.has_method("bounds")
			and Body.overlap(head, Body.world_box(projectile, type.bounds(projectile)))
		)
		if kind != Hits.SHELL and not touching_head:
			return 0
		hit(entity, state, world, kind, projectile.x)
		return (
			1
			if (
				touching_head
				and (
					kind == Hits.EGG
					or projectile.code in ["e6", "e8"]
					or projectile.get("spat", 0)
					or projectile.get("roll", 0)
				)
			)
			else 3
		)
	if kind == Hits.SPIT and entity.roll and projectile.code in ["e1", "e2"] and projectile.roll:
		return 0
	hit(entity, state, world, kind, projectile.x)
	if kind == Hits.EGG:
		if entity.code in ["e1", "e2"]:
			return 1
		if entity.code == "e3":
			projectile.fall_on_terrain = 1
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var result := {"visible": entity.held == 0 and entity.hidden == 0}
	if entity.code in ["e1", "e2"]:
		var pose := "Idle" if entity.mode == 0 else "Walk"
		if entity.code == "e2" and not entity.ground_form:
			pose = "Fly"
		result.animation = "Roll" if entity.roll else str(entity.variant) + pose
	elif entity.code in ["e20", "e21"]:
		var pose := "Swim"
		if entity.mode == 1:
			pose = "TurnRight" if entity.facing < 0 else "TurnLeft"
		elif entity.mode == 2:
			pose = "PrepareJump"
		elif entity.mode == 3:
			pose = "Jump" if entity.vy < 0 else "Fall"
		elif entity.mode == 4:
			pose = "JumpArc"
		elif entity.fish_dry:
			pose = "OutOfWater"
		result.animation = pose
	return result
