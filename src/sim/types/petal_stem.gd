extends RefCounted
## An indestructible stem whose face grows five orbiting petals and fires them outward.
## A ground-pound landing anywhere drops every attached petal.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e18"]
const ENEMY := true
const STEP_PHASE := 0
const CONTACT_PHASE := -1
const GROW := 0
const SHOOT := 1
const FADE := 2
const REGAIN := 3
const GROW_TICKS := 18
const PETAL_TICK := 18
const DANCE_TICK := 78
const FREEZE_TICK := 9
const LAUNCH_TICK := 27
const FADE_TICKS := 78
const REGAIN_TICKS := 180
const PETALS := 5
const ORBIT_STEP := -3200
const PETAL_SPEED := 256 * 60
const BOX := [-12 * S, -16 * S, 12 * S, 16 * S]
const FIELDS := (
	Body.FIELDS
	+ [
		["phase", GROW],
		["timer", 0],
		["shoot_at", 0],
		["orbit", 0],
		["dancing", 0],
		["has_petals", 0]
	]
)


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0, false)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func face_center(entity: Dictionary) -> Array:
	var rise: int = 16 * S * mini(entity.timer, GROW_TICKS) / GROW_TICKS
	if entity.phase != GROW:
		rise = 16 * S
	return [entity.x, entity.y - 16 * S - rise]


static func face_visible(entity: Dictionary) -> bool:
	return entity.phase != REGAIN


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var fresh: bool = entity.started == 0
	if Body.process(entity, state) == Body.GONE:
		return
	if fresh:
		_drop_old(entity, state)
	Motion.gravity_box(entity, world, BOX)
	if int(state.get("move_impact", 0)) > entity.impact_cursor:
		entity.impact_cursor = state.move_impact
		if entity.phase in [GROW, SHOOT]:
			fall_petals(entity, state)
			entity.phase = FADE
			entity.timer = 0
			entity.dancing = 0
	entity.timer += 1
	match entity.phase:
		GROW:
			if entity.timer == PETAL_TICK:
				_spawn_petals(entity, state, world)
			if entity.timer == DANCE_TICK:
				entity.dancing = 1
				entity.shoot_at = DANCE_TICK + Motion.random_ticks(state, 222, 240)
			if entity.dancing:
				entity.orbit = posmod(entity.orbit + ORBIT_STEP, 360000)
			if entity.shoot_at and entity.timer >= entity.shoot_at:
				entity.phase = SHOOT
				entity.timer = 0
		SHOOT:
			if entity.timer < FREEZE_TICK:
				entity.orbit = posmod(entity.orbit + ORBIT_STEP, 360000)
			if entity.timer >= LAUNCH_TICK:
				_launch(entity, state)
				_regain(entity)
		FADE:
			if entity.timer >= FADE_TICKS:
				_regain(entity)
		REGAIN:
			if entity.timer >= REGAIN_TICKS:
				entity.phase = GROW
				entity.timer = 0
				entity.shoot_at = 0
				entity.orbit = 0


static func _regain(entity: Dictionary) -> void:
	entity.phase = REGAIN
	entity.timer = 0
	entity.dancing = 0
	entity.has_petals = 0


static func attached(entity: Dictionary, state: Dictionary) -> Array:
	var result := []
	for other: Dictionary in state.entities:
		if (
			other.code == "enemy_petal"
			and other.status == 1
			and other.held == 0
			and other.stem_token == entity.token
			and other.mode == 0
		):
			result.append(other)
	return result


static func _spawn_petals(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var center := face_center(entity)
	for slot in PETALS:
		registry().spawn_dynamic(
			state,
			world,
			"enemy_petal",
			center[0],
			center[1],
			{"stem_token": entity.token, "slot": slot, "can_despawn": 1}
		)
	entity.has_petals = 1


static func petal_angle(entity: Dictionary, slot: int) -> int:
	return posmod(-90000 + slot * 72000 + entity.orbit, 360000)


static func _launch(entity: Dictionary, state: Dictionary) -> void:
	for petal: Dictionary in attached(entity, state):
		var angle := petal_angle(entity, petal.slot)
		petal.mode = 1
		petal.vx = Motion.turn_cosine(angle, PETAL_SPEED)
		petal.vy = Motion.turn_sine(angle, PETAL_SPEED)


static func fall_petals(entity: Dictionary, state: Dictionary) -> void:
	var center := face_center(entity)
	for petal: Dictionary in attached(entity, state):
		petal.mode = 2
		# Source: vectorX = 16 * offset, then the 128 px/s maximum applies.
		petal.vx = clampi(16 * (petal.x - center[0]), -128 * 60, 128 * 60)
		petal.vy = -128 * 60
	entity.has_petals = 0


static func _drop_old(entity: Dictionary, state: Dictionary) -> void:
	for petal: Dictionary in attached(entity, state):
		Body.remove(petal, state)


static func tongue(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> int:
	return 0


static func projectile_contact(
	_entity: Dictionary, _projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	return 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	# The stem animates only while its petals dance.
	var look := {"visible": true, "animation": "Default"}
	if entity.dancing == 0:
		look.frame = 0
	return look


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.phase >= GROW
		and entity.phase <= REGAIN
		and entity.timer >= 0
		and entity.timer <= DANCE_TICK + 240
		and entity.shoot_at >= 0
		and entity.shoot_at <= DANCE_TICK + 240
		and entity.orbit >= 0
		and entity.orbit < 360000
		and entity.dancing in [0, 1]
		and entity.has_petals in [0, 1]
	)
