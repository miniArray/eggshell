extends RefCounted
## Timed direction changes and saved projectile redirection.
const CODES := ["o19"]
const S := preload("res://src/sim/units.gd").SCALE
const Turn = preload("res://src/sim/oriented_box.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const FIELDS := [
	["base_angle", 0],
	["angle", 0],
	["rotation_step", 0],
	["rotation_period", 1],
	["age", 0],
	["infinite", 0],
	["last_egg", 0],
	["colour", -1]
]
const RECT := [-12 * S, -14 * S, 12 * S, 14 * S]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var registry: Script = load("res://src/sim/registry.gd")
	var values := []
	for pair: Array in [["R", 0], ["E1", "0"], ["E2", "0"]]:
		var raw: Variant = source.properties.get(pair[0], pair[1])
		var parsed: Dictionary = registry.numeric_option(
			"0" if raw is String and raw == "" else raw
		)
		if not parsed.ok:
			return {"ok": false, "error": "Invalid redirector option: " + pair[0]}
		values.append(parsed.value)
	if not source.properties.get("E3", "") is String:
		return {"ok": false, "error": "Invalid redirector reuse flag"}
	source.base_angle = Turn.angle_wrap(roundi(fposmod(values[0], 360.0) * 1000))
	source.rotation_step = Turn.angle_wrap(int(values[1]) % 360 * 1000)
	source.rotation_period = maxi(1, ceili(values[2] * 60))
	source.infinite = int(source.properties.get("E3", "") == "1")
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {
		"base_angle": int(source.base_angle),
		"angle": int(source.base_angle),
		"rotation_step": int(source.rotation_step),
		"rotation_period": int(source.rotation_period),
		"infinite": int(source.infinite),
		"layer": 9
	}


static func step(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	if entity.colour < 0:
		entity.colour = Motion.random_ticks(state, 0, 3)
	entity.age = 0 if entity.age == 0x7fffffffffffffff else entity.age + 1
	if entity.age % entity.rotation_period == 0:
		entity.angle = Turn.angle_wrap(entity.angle + entity.rotation_step)


static func bounds(entity: Dictionary) -> Array:
	return Turn.bounds(entity.base_angle, RECT)


static func touches(entity: Dictionary, probe: Array) -> bool:
	return Turn.overlaps(entity.base_angle, RECT, probe, entity.x, entity.y)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	if entity.status != 1 or projectile.mode != 1:
		return 0
	var speed := Motion.root(projectile.vx * projectile.vx + projectile.vy * projectile.vy)
	var velocity := Turn.vector(entity.angle - 90000, speed)
	projectile.x = entity.x
	projectile.y = entity.y
	projectile.vx = velocity[0]
	projectile.vy = velocity[1]
	projectile.camera = 1
	var token: int = projectile.get("token", 0)
	if entity.last_egg != token:
		entity.last_egg = token
		projectile.despawn_ticks = 600
	if not entity.infinite:
		entity.status = 3
	return 2


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {
		"visible": entity.status == 1,
		"animation": "Color%d" % maxi(0, entity.colour),
		"frame": entity.age / 10 % 3,
		"rotation": entity.angle / 1000.0
	}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.base_angle >= 0
		and entity.base_angle < Turn.TURN
		and entity.angle >= 0
		and entity.angle < Turn.TURN
		and entity.rotation_step >= 0
		and entity.rotation_step < Turn.TURN
		and entity.rotation_period >= 1
		and entity.age >= 0
		and entity.infinite in [0, 1]
		and entity.last_egg >= 0
		and entity.colour >= -1
		and entity.colour <= 3
	)
