extends RefCounted
## A rooted, three-hit actor with a rotating head and three-shot cycles.

const Body = preload("res://src/sim/enemy_body.gd")
const Moves = preload("res://src/sim/moves.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e41"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const IDLE := 0
const ALIGN := 1
const WAIT := 2
const REST := 3
const HURT := 4
const DEFEAT := 5
const FIELDS := (
	Body.FIELDS
	+ [
		["mode", IDLE],
		["timer", 90],
		["hp", 3],
		["shots", 3],
		["head_angle", 270000],
		["turn_to", 270000],
		["turn_left", 0],
		["spit_ticks", 0]
	]
)
const IDLE_HULL := [[50, 16], [30, 28], [8, 20], [-2, 2], [8, -16], [30, -26], [50, -14], [62, 2]]
const SPIT_HULL := [[52, 28], [27, 32], [8, 24], [-2, 2], [4, -20], [27, -28], [52, -24]]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0, false)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func body_bounds() -> Array:
	return [-16 * S, -10 * S, 16 * S, 16 * S]


static func activation_bounds(entity: Dictionary) -> Array:
	return Body.world_box(entity, body_bounds())


static func head_scale(entity: Dictionary) -> int:
	if entity.mode == DEFEAT:
		return mini(1000, entity.timer * 1000 / 45)
	if entity.mode == IDLE:
		var phase: int = posmod(90 - entity.timer, 18)
		var time := phase if phase <= 9 else 18 - phase
		return 1000 - 100 * time * time / 81
	return 1000


static func head_hull(entity: Dictionary) -> Array:
	var hull := []
	var points: Array = SPIT_HULL if entity.spit_ticks or entity.mode == DEFEAT else IDLE_HULL
	var scale := head_scale(entity)
	var cosine := Motion.turn_cosine(entity.head_angle)
	var sine := Motion.turn_sine(entity.head_angle)
	var joint_x: int = entity.x + (2 if entity.facing > 0 else -2) * S
	var joint_y: int = entity.y - 8 * S
	for point: Array in points:
		var x: int = point[0] * S * scale / 1000
		var y: int = point[1] * S * scale / 1000 * (-1 if entity.facing > 0 else 1)
		hull.append([joint_x + (x * cosine - y * sine) / S, joint_y + (x * sine + y * cosine) / S])
	return hull


static func head_box(entity: Dictionary) -> Array:
	var hull := head_hull(entity)
	var result := [hull[0][0], hull[0][1], hull[0][0], hull[0][1]]
	for point: Array in hull:
		result[0] = mini(result[0], point[0])
		result[1] = mini(result[1], point[1])
		result[2] = maxi(result[2], point[0])
		result[3] = maxi(result[3], point[1])
	return result


static func bounds(entity: Dictionary) -> Array:
	var head := head_box(entity)
	var body := activation_bounds(entity)
	return [
		mini(head[0], body[0]) - entity.x,
		mini(head[1], body[1]) - entity.y,
		maxi(head[2], body[2]) - entity.x,
		maxi(head[3], body[3]) - entity.y
	]


static func touches(entity: Dictionary, box: Array) -> bool:
	return (
		Body.overlap(activation_bounds(entity), box) or Body.polygon_overlap(head_hull(entity), box)
	)


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var fresh: bool = entity.started == 0
	if Body.process(entity, state) in [Body.HELD, Body.GONE]:
		return
	Motion.gravity_box(entity, world, body_bounds())
	if Body.hazards(entity, state, world, body_bounds()):
		return
	if fresh:
		entity.head_angle = Motion.angle_to(state.x - entity.x, state.y - entity.y + 8 * S)
	entity.spit_ticks = maxi(0, entity.spit_ticks - 1)
	entity.facing = 1 if entity.head_angle > 270000 or entity.head_angle < 90000 else -1
	if entity.turn_left:
		entity.head_angle = posmod(
			(
				entity.head_angle
				+ Motion.angle_delta(entity.head_angle, entity.turn_to) / entity.turn_left
			),
			360000
		)
		entity.turn_left -= 1
		if entity.mode == ALIGN:
			if entity.turn_left == 0:
				_shoot(entity, state, world)
			return
	if entity.mode == IDLE:
		var desired := Motion.angle_to(
			state.x - entity.x - (2 if entity.facing > 0 else -2) * S, state.y - entity.y + 8 * S
		)
		entity.head_angle = posmod(
			entity.head_angle + Motion.angle_delta(entity.head_angle, desired) * 37649 / 1000000,
			360000
		)
		if entity.head_angle < 90000:
			entity.head_angle = mini(entity.head_angle, 65000)
		elif entity.head_angle < 115000:
			entity.head_angle = 115000
	entity.timer = maxi(0, entity.timer - 1)
	if entity.timer:
		return
	match entity.mode:
		IDLE, WAIT:
			_align(entity)
		REST, HURT:
			entity.mode = IDLE
			entity.timer = 90
			entity.shots = 3
		DEFEAT:
			Body.remove(entity, state)


static func _align(entity: Dictionary) -> void:
	entity.mode = ALIGN
	entity.turn_to = (
		(257 + 24 * entity.shots) * 1000 if entity.facing > 0 else (283 - 21 * entity.shots) * 1000
	)
	entity.turn_left = maxi(
		1, (absi(Motion.angle_delta(entity.head_angle, entity.turn_to)) + 1999) / 2000
	)


static func _shoot(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	entity.shots -= 1
	entity.spit_ticks = 12
	entity.mode = WAIT if entity.shots else REST
	entity.timer = 60 if entity.shots else 72
	var cosine := Motion.turn_cosine(entity.head_angle)
	var sine := Motion.turn_sine(entity.head_angle)
	var mouth_y := 3 if entity.facing > 0 else -3
	var x: int = entity.x + (2 if entity.facing > 0 else -2) * S + 37 * cosine - mouth_y * sine
	var y: int = entity.y - 8 * S + 37 * sine + mouth_y * cosine
	var registry: Script = Body.registry_for()
	registry.spawn_dynamic(
		state,
		world,
		"enemy_spike",
		x,
		y,
		{"vx": 384 * 60 * cosine / S, "vy": 768 * 60 * sine / S, "facing": entity.facing}
	)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if (
		entity.mode != DEFEAT
		and not entity.held
		and touches(entity, Body.world_box(state, Moves.player_box(state)))
	):
		Body.hurt(entity, state)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	if entity.mode != DEFEAT and Body.polygon_overlap(head_hull(entity), Moves.tongue_box(state)):
		return 2
	return 0


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, kind: int, from_x: int
) -> void:
	if kind == Hits.CLEAR:
		Body.remove(entity, state)
	elif kind in [Hits.EGG, Hits.SPIT, Hits.SHELL] and entity.mode != DEFEAT:
		entity.hp -= 1
		entity.shots = 3
		entity.spit_ticks = 0
		entity.turn_to = 300000 if from_x < entity.x else 240000
		entity.turn_left = 15
		entity.mode = HURT if entity.hp else DEFEAT
		entity.timer = 60 if entity.hp else 105
		if entity.hp == 0:
			entity.can_respawn = 0


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if entity.mode == DEFEAT:
		return 0
	var registry: Script = Body.registry_for()
	var type: Script = registry.lookup(projectile.code)
	if (
		type.has_method("bounds")
		and not touches(entity, Body.world_box(projectile, type.bounds(projectile)))
	):
		return 0
	var kind := Body.projectile_kind(projectile)
	if projectile.code == "e28" and kind == Hits.SHELL:
		Body.remove(entity, state)
		return 3
	hit(entity, state, world, kind, projectile.x)
	return 3 if projectile.code == "e11" else 1


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.mirror == 0
		and entity.held == 0
		and entity.spat == 0
		and entity.mode >= IDLE
		and entity.mode <= DEFEAT
		and entity.hp >= 0
		and entity.hp <= 3
		and entity.shots >= 0
		and entity.shots <= 3
		and entity.timer >= 0
		and entity.timer <= 105
		and entity.head_angle >= 0
		and entity.head_angle < 360000
		and entity.turn_to >= 0
		and entity.turn_to < 360000
		and entity.turn_left >= 0
		and entity.turn_left <= 90
		and entity.spit_ticks >= 0
		and entity.spit_ticks <= 12
	)
