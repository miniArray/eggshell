extends RefCounted
## A bobbing flyer. A stomp or strike knocks it aside; it then charges in a straight line.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e30"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const FLY := 0
const STOMPED := 1
const ANGRY := 2
const CHARGE := 3
const BOB_PERIOD := 180
const BOB := 64 * S
const DRIFT := 64 * 60
const CHARGE_SPEED := 256 * 60
const KNOCK_TICKS := 6
const STOMP_TICKS := 13
const AIM_TICKS := 60
# Body hulls facing left, in pixels around the origin.
const FLY_HULL := [[-24, -14], [2, -14], [16, 12], [16, 30], [-2, 30], [-24, 2]]
const ANGRY_HULL := [[-28, -8], [-2, -8], [16, 12], [16, 30], [-2, 30], [-28, 8]]
const FIELDS := (
	Body.FIELDS
	+ [
		["mode", FLY],
		["timer", 0],
		["bob", 0],
		["bob_sign", -1],
		["drifts", 1],
		["home_y", 0],
		["knock_x", 0],
		["knock_y", 0],
		["knock_dx", 0],
		["knock_dy", 0],
		["contact", 0]
	]
)


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var drift: Variant = source.properties.get("E1", "")
	if not drift is String:
		return {"ok": false, "error": "Invalid flyer option: E1"}
	source.drifts = 0 if drift == "1" else 1
	return Options.prepare(source, 1)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.bob_sign = 1 if values.variant == 1 else -1
	values.drifts = Options.option(source, "drifts", int(source.get("drifts", 1)))
	values.home_y = int(source.y)
	return values


static func hull(entity: Dictionary) -> Array:
	var points: Array = FLY_HULL if entity.mode in [FLY, STOMPED] else ANGRY_HULL
	var result := []
	for point: Array in points:
		var x: int = point[0] * S
		result.append([entity.x + (-x if entity.facing > 0 else x), entity.y + point[1] * S])
	return result


static func bounds(entity: Dictionary) -> Array:
	var left := -24 if entity.mode in [FLY, STOMPED] else -28
	if entity.facing < 0:
		return [left * S, -14 * S, 16 * S, 30 * S]
	return [-16 * S, -14 * S, -left * S, 30 * S]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if action == Body.RELEASED:
		entity.mode = ANGRY
		entity.timer = 0
	if Body.spit_step(entity, state, world, bounds(entity)):
		return
	match entity.mode:
		FLY:
			entity.bob = (entity.bob + 1) % BOB_PERIOD
			entity.y = entity.home_y + Motion.sine(entity.bob, BOB_PERIOD, entity.bob_sign * BOB)
			if entity.drifts:
				entity.x += entity.facing * DRIFT
		STOMPED:
			entity.timer += 1
			if entity.timer <= KNOCK_TICKS:
				var span := KNOCK_TICKS * KNOCK_TICKS
				var left: int = KNOCK_TICKS - entity.timer
				var part: int = span - left * left
				entity.x = entity.knock_x + entity.knock_dx * part / span
				entity.y = entity.knock_y + entity.knock_dy * part / span
			if entity.timer >= STOMP_TICKS:
				entity.mode = ANGRY
				entity.timer = 0
		ANGRY:
			entity.timer += 1
			if entity.x != state.x:
				entity.facing = -1 if entity.x > state.x else 1
			if entity.timer >= AIM_TICKS:
				var angle := Motion.angle_to(state.x - entity.x, state.y - 32 * S - entity.y)
				entity.vx = Motion.turn_cosine(angle, CHARGE_SPEED)
				entity.vy = Motion.turn_sine(angle, CHARGE_SPEED)
				entity.mode = CHARGE
				entity.timer = 0
		CHARGE:
			entity.x += entity.vx
			entity.y += entity.vy
	Body.hazards(entity, state, world, bounds(entity))


static func knock(entity: Dictionary, distance: int, dx: int, dy: int) -> void:
	# Direction (dx, dy) is any vector; the knock covers `distance` pixels along it.
	if entity.mode != FLY:
		return
	var angle := Motion.angle_to(dx, dy)
	entity.mode = STOMPED
	entity.timer = 0
	entity.knock_x = entity.x
	entity.knock_y = entity.y
	entity.knock_dx = Motion.turn_cosine(angle, distance * S)
	entity.knock_dy = Motion.turn_sine(angle, distance * S)
	# Axis strikes stay exact; the integer angle search is only approximate.
	if dx == 0:
		entity.knock_dx = 0
		entity.knock_dy = signi(dy) * distance * S
	elif dy == 0:
		entity.knock_dx = signi(dx) * distance * S
		entity.knock_dy = 0


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	var touching := false
	if (
		not entity.hidden
		and not entity.held
		and not entity.spat
		and entity.status == 1
		and not state.get("captured_by", 0)
	):
		touching = Body.polygon_overlap(hull(entity), Body.world_box(state, Moves.player_box(state)))
	if touching and entity.y > state.y - 16 * S:
		if not entity.contact:
			if Body.pounding(state):
				Body.remove(entity, state)
			else:
				Body.bounce(entity, state, input)
				knock(entity, 12, 0, 1)
	elif touching:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	return Body.tongue(entity, state, 1)


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, kind: int, from_x: int
) -> void:
	if kind in [Hits.POUND, Hits.CLEAR, Hits.BUMP]:
		Body.remove(entity, state)
	else:
		knock(entity, 48, entity.x - from_x, 0)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	# Every strike is absorbed; only a calm flyer is knocked along the strike.
	var dx: int = projectile.get("vx", 0)
	var dy: int = projectile.get("vy", 0)
	if dx == 0 and dy == 0:
		dx = entity.x - projectile.get("x", entity.x)
	knock(entity, 48, dx, dy)
	return 1


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var names := ["Fly", "Stomped", "Angry", "Angry"]
	return {"visible": entity.held == 0, "animation": names[entity.mode]}


static func finished(entity: Dictionary) -> bool:
	return entity.status in [2, 3] and entity.held == 0


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant in [0, 1]
		and entity.mode >= FLY
		and entity.mode <= CHARGE
		and entity.timer >= 0
		and entity.timer <= AIM_TICKS
		and entity.bob >= 0
		and entity.bob < BOB_PERIOD
		and entity.bob_sign in [-1, 1]
		and entity.drifts in [0, 1]
		and entity.contact in [0, 1]
		and absi(entity.knock_dx) <= 48 * S
		and absi(entity.knock_dy) <= 48 * S
	)
