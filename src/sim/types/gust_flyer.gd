extends RefCounted
## A flyer that ignores terrain and glides straight along its placement angle,
## easing up to full speed over its first second. With M set it turns to fly
## toward the player's side when it activates.

const Body = preload("res://src/sim/enemy_body.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Moves = preload("res://src/sim/moves.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e33"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const TURN := 360000
const TOP_SPEED := 312
const RAMP_TICKS := 60
## `heading` is the travel direction in millidegrees (0 right, 90000 down).
const FIELDS := Body.FIELDS + [["heading", 180000], ["toward", 0], ["ramp", 0], ["contact", 0]]
## Upright body: the sprite points its front up and travels toward its front.
const UPRIGHT := [-12, -28, 12, 24]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var registry: Script = load("res://src/sim/registry.gd")
	var angle: Dictionary = registry.numeric_option(source.properties.get("R", 0))
	var mirror: Variant = source.properties.get("M", 0)
	if (
		not angle.ok
		or not (mirror is int or mirror is float)
		or not is_finite(mirror)
		or mirror < 0
		or mirror != floor(mirror)
	):
		return {"ok": false, "error": "Invalid flyer angle or mirror"}
	if mirror > 2:
		return {"ok": false, "degrade": true, "error": "flyer mirror M=%d" % mirror}
	source.heading = posmod(roundi((angle.value - 90.0) * 1000.0), TURN)
	source.toward = int(mirror > 0)
	source.mirror = 0
	source.layer = 8
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.heading = int(source.get("heading", 180000))
	values.toward = int(source.get("toward", 0))
	return values


static func bounds(entity: Dictionary) -> Array:
	# Axis-aligned box around the body turned to its sprite angle.
	var sprite: int = entity.heading + 90000
	var cosine := Motion.turn_cosine(sprite)
	var sine := Motion.turn_sine(sprite)
	var left := 1 << 40
	var top := 1 << 40
	var right := -(1 << 40)
	var bottom := -(1 << 40)
	for corner: Array in [
		[UPRIGHT[0], UPRIGHT[1]],
		[UPRIGHT[2], UPRIGHT[1]],
		[UPRIGHT[2], UPRIGHT[3]],
		[UPRIGHT[0], UPRIGHT[3]]
	]:
		var x: int = corner[0] * cosine - corner[1] * sine
		var y: int = corner[0] * sine + corner[1] * cosine
		left = mini(left, x)
		right = maxi(right, x)
		top = mini(top, y)
		bottom = maxi(bottom, y)
	return [left, top, right, bottom]


static func activate(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	if not entity.toward:
		return
	var dx: int = state.x - entity.x
	var dy: int = state.y - entity.y
	# Turn round when the player is nearer the back than the front.
	var along: int = (
		dx / S * Motion.turn_cosine(entity.heading) + dy / S * Motion.turn_sine(entity.heading)
	)
	if along < 0:
		entity.heading = posmod(entity.heading + 180000, TURN)


static func step(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if action == Body.RELEASED:
		# Spat out, it flies on level in the direction it was spat.
		entity.spat = 0
		entity.heading = 0 if entity.facing > 0 else 180000
		entity.vy = 0
	entity.ramp = mini(RAMP_TICKS, entity.ramp + 1)
	var speed: int = TOP_SPEED * 60 * entity.ramp / RAMP_TICKS
	entity.vx = speed * Motion.turn_cosine(entity.heading) / S
	entity.vy = speed * Motion.turn_sine(entity.heading) / S
	entity.x += entity.vx
	entity.y += entity.vy
	entity.facing = 1 if entity.vx > 0 else -1


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	var touching := Body.player_overlap(entity, state, bounds(entity))
	if touching and not entity.contact and entity.y > state.y - 8 * S:
		if not Body.pounding(state):
			Moves.bounce(state, -absi(entity.vy / 2) - 320 * 60, input)
		Body.remove(entity, state)
	elif touching and entity.y < state.y - 8 * S:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	return Body.tongue(entity, state)


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, _kind: int, _from_x: int
) -> void:
	Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var kind := Body.projectile_kind(projectile)
	if projectile.has("fall_on_terrain"):
		projectile.fall_on_terrain = 1
	hit(entity, state, world, kind, projectile.x)
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var sprite: int = posmod(entity.heading + 90000, TURN)
	return {
		"visible": entity.held == 0,
		"rotation": float(sprite) / 1000.0,
		# Upright when travelling rightward or straight down, mirrored otherwise.
		"flip_x": not (sprite >= 1000 and sprite <= 180000)
	}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.heading >= 0
		and entity.heading < TURN
		and entity.toward in [0, 1]
		and entity.ramp >= 0
		and entity.ramp <= RAMP_TICKS
		and entity.contact in [0, 1]
	)
