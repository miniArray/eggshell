extends RefCounted
## A bubble that leaps out of its home and drops back, again and again. It rises
## along its rotation (up when R is 0) at 256 px/s, slowing to a stop
## 32 x (E1 + random 0..E2) + 16 px from home, then steps back 16 px, accelerates
## home at 256 px/s² and hides for E3 seconds. The first leap waits E4 seconds.
## Touching it hurts. Swallowing it loads three fire shots, or three ice shots
## for the cold form F 3. Ice freezes the other forms; fire only defeats the
## cold form. A frozen bubble drops, shatters on landing and thaws after 8 s.

const Body = preload("res://src/sim/enemy_body.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const Life = preload("res://src/sim/life.gd")
const World = preload("res://src/sim/world.gd")
const Constants = preload("res://src/sim/script_constants.gd")
const Near = preload("res://src/sim/types/near_query.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e16"]
const ENEMY := true
const DYNAMIC := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const COLD_FORM := 3
const LAST_FORM := 4
const WAIT := 0
const RISE := 1
const FALL := 2
const SQUASH := 3
## A thawed bubble has lost its leaping motion and only falls.
const LOOSE := 4
const MAX_SPEED := 256 * 60
const ACCELERATION := 256
const STEP_BACK := 16 * S
const LEAP_UNIT := 32 * S
const SQUASH_TICKS := 15
const MAX_OPTION := 10000
const ELEMENT_REACTIONS := Elements.BURNS | Elements.FREEZES | Elements.THAWS
const FIELDS := (
	Body.FIELDS
	+ [
		["form", 0],
		["rise_units", 0],
		["rise_extra", 0],
		["wait_ticks", 0],
		["heading", 270000],
		["phase", WAIT],
		["timer", 0],
		["travel", 0],
		["target", 0],
		["speed", 0],
		["home_x", 0],
		["home_y", 0]
	]
)


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var raw: Dictionary = source.get("properties", {})
	for key: String in ["F", "R"]:
		var value: Variant = raw.get(key, 0)
		if not (value is int or value is float) or not is_finite(value) or value != floor(value):
			return {"ok": false, "error": "Invalid bubble option: " + key}
		if value < 0:
			return {"ok": false, "error": "Invalid bubble option: " + key}
	if raw.get("F", 0) > LAST_FORM or raw.get("R", 0) >= 360:
		return {"ok": false, "degrade": true, "error": "bubble form or rotation out of range"}
	var values := []
	for key: String in ["E1", "E2", "E3", "E4"]:
		var parsed := _number(raw.get(key, "0"))
		if not parsed.ok:
			return {"ok": false, "error": "Invalid bubble option: " + key}
		if parsed.value < 0 or parsed.value > MAX_OPTION:
			return {"ok": false, "degrade": true, "error": "bubble option %s out of range" % key}
		values.append(parsed.value)
	source.variant = int(raw.get("F", 0))
	source.bubble = {
		"rise_units": int(values[0]),
		"rise_extra": int(values[1]),
		"wait_ticks": _ticks(values[2]),
		"start_ticks": _ticks(values[3]),
		"heading": posmod((int(raw.get("R", 0)) - 90) * 1000, 360000)
	}
	return {"ok": true}


static func _number(value: Variant) -> Dictionary:
	if value is String:
		var text: String = value.strip_edges()
		if text.is_empty():
			return {"ok": true, "value": 0.0}
		if not text.is_valid_float():
			return {"ok": false}
		value = text.to_float()
	if not (value is int or value is float) or not is_finite(value):
		return {"ok": false}
	return {"ok": true, "value": float(value)}


static func _ticks(seconds: float) -> int:
	return int(ceil(seconds * 60.0 - 0.000001))


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	var bubble: Dictionary = source.get("bubble", {})
	var heading: int = bubble.get("heading", 270000)
	values.form = int(source.get("variant", 0))
	values.rise_units = bubble.get("rise_units", 0)
	values.rise_extra = bubble.get("rise_extra", 0)
	values.wait_ticks = bubble.get("wait_ticks", 0)
	values.heading = heading
	values.timer = bubble.get("start_ticks", 0)
	# It waits unseen at home, 16 px behind its placement, until the first leap.
	values.home_x = int(source.x) - STEP_BACK * Motion.turn_cosine(heading) / S
	values.home_y = int(source.y) - STEP_BACK * Motion.turn_sine(heading) / S
	values.x = values.home_x
	values.y = values.home_y
	values.hidden = 1
	return values


static func element(entity: Dictionary) -> int:
	return Elements.ICE if entity.form == COLD_FORM else Elements.FIRE


## The body trails 16 px behind the leading point, along the way it moves.
static func bounds(entity: Dictionary) -> Array:
	var pointing: int = entity.heading + (180000 if entity.phase == FALL else 0)
	var cx := -16 * Motion.turn_cosine(pointing)
	var cy := -16 * Motion.turn_sine(pointing)
	return [cx - 14 * S, cy - 14 * S, cx + 14 * S, cy + 14 * S]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	_move_body(entity, state, world)
	_touch_lamps(entity, state, world)


static func _move_body(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	var box := bounds(entity)
	if entity.frozen and not entity.held and not entity.spat:
		entity.phase = LOOSE
		entity.hidden = 0
		var was_falling: bool = entity.vy > 0
		if Reactions.frozen_step(entity, state, world, box, ELEMENT_REACTIONS):
			if entity.status == 1 and entity.frozen and was_falling and entity.vy == 0:
				Reactions.shatter(entity, state)
			return
	if Body.spit_step(entity, state, world, box):
		return
	if entity.phase == LOOSE:
		Motion.gravity_box(entity, world, box)
		Body.hazards(entity, state, world, box)
		return
	match entity.phase:
		WAIT:
			if entity.timer > 0:
				entity.timer -= 1
				return
			_leap(entity, state)
		RISE:
			if _move(entity, entity.target, 0, ACCELERATION):
				# The way back starts at the end of this tick, 16 px below the peak.
				entity.phase = FALL
				entity.travel -= STEP_BACK
				entity.speed = 0
			elif _terrain(entity, world):
				entity.phase = SQUASH
				entity.timer = SQUASH_TICKS
				entity.speed = 0
		SQUASH:
			entity.timer -= 1
			if entity.timer <= 0:
				entity.phase = FALL
				entity.travel -= STEP_BACK
				entity.speed = 0
		FALL:
			if _move(entity, 0, ACCELERATION, 0):
				entity.phase = WAIT
				entity.hidden = 1
				entity.timer = entity.wait_ticks
	_place(entity)


## Every bubble counts as burning for lamps, the cold form and frozen ones too:
## it lights fire lamps and puts out ice lamps it touches.
static func _touch_lamps(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.status != 1 or entity.hidden or entity.held:
		return
	var registry: Script = Body.registry_for(world)
	var box := Body.world_box(entity, bounds(entity))
	for other: Dictionary in Near.nearby(state, world, box):
		if other.status != 1 or other.token == entity.token:
			continue
		var type: Script = registry.lookup(other.code)
		if (
			int(Constants.read(type, "ELEMENT_REACTIONS", 0)) & Elements.LIGHTS
			and registry.overlaps_box(other, type, box)
		):
			type.projectile_contact(other, entity, state, world)


static func _leap(entity: Dictionary, state: Dictionary) -> void:
	state.rng = (state.rng * 1103515245 + 12345) & 0x7fffffff
	var extra: int = (state.rng * (2 * entity.rise_extra) / 2147483648 + 1) / 2
	entity.target = LEAP_UNIT * (entity.rise_units + extra) + STEP_BACK
	entity.travel = STEP_BACK
	entity.speed = MAX_SPEED
	entity.phase = RISE
	entity.hidden = 0
	_place(entity)


## One tick of straight travel toward `goal` along the leap axis, as the source's
## move-to motion does it. Returns true on arrival.
static func _move(entity: Dictionary, goal: int, acceleration: int, deceleration: int) -> bool:
	var distance: int = absi(goal - entity.travel)
	var speed: int = entity.speed
	var limit := MAX_SPEED
	var braking := false
	if deceleration > 0:
		# Exact braking keeps braking to the end; integer rounding must not undo it,
		# so a body already below full speed (it never accelerates here) brakes on.
		if speed < MAX_SPEED or distance * 2 * deceleration * 10000 <= speed * speed * 10001:
			braking = true
			speed = Motion.root(2 * deceleration * distance)
			limit = speed
			entity.speed = speed
	var rate := -deceleration if braking else acceleration
	var advance := mini(speed + rate / 2, limit)
	if braking:
		entity.speed = maxi(entity.speed - deceleration, 0)
		if entity.speed == 0:
			entity.travel = goal
			return true
	else:
		entity.speed = limit if acceleration == 0 else mini(entity.speed + acceleration, limit)
	if distance <= advance:
		entity.travel = goal
		entity.speed = 0
		return true
	entity.travel += advance if goal > entity.travel else -advance
	return false


static func _place(entity: Dictionary) -> void:
	entity.x = entity.home_x + entity.travel * Motion.turn_cosine(entity.heading) / S
	entity.y = entity.home_y + entity.travel * Motion.turn_sine(entity.heading) / S


static func _terrain(entity: Dictionary, world: Dictionary) -> bool:
	var box := Body.world_box(entity, bounds(entity))
	return World.overlaps_box(world, box[0], box[1], box[2], box[3])


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	var box := bounds(entity)
	if Reactions.frozen_contact(entity, state, input, box):
		return
	if entity.hidden:
		return
	if Body.player_overlap(entity, state, box):
		Body.hurt(entity, state)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	if entity.hidden or entity.held or entity.status != 1 or Life.blocks_step(state):
		return 0
	var ammo := Elements.bubble_ammo(element(entity))
	if Moves.catch_item(state, entity.token, 0, ammo[0], ammo[1], 1):
		entity.held = 1
		entity.spat = 0
		entity.vx = 0
		entity.vy = 0
		entity.request_cursor = state.move_emit_serial
		return 1
	return 0


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, _from_x: int
) -> void:
	if kind == Hits.FIRE:
		# Fire only puts out the cold form; it passes through the burning ones.
		if entity.form == COLD_FORM and entity.status == 1:
			Reactions.burn(entity, state)
		return
	if kind == Hits.ICE:
		if entity.form != COLD_FORM:
			Reactions.hit(entity, state, world, kind, ELEMENT_REACTIONS, [])
			if entity.frozen:
				entity.vy = 0
				entity.speed = 0
		return
	Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var kind := Body.projectile_kind(projectile)
	hit(entity, state, world, kind, projectile.x)
	return 1 if kind == Hits.EGG else 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var pointing: int = entity.heading + (180000 if entity.phase == FALL else 0)
	return {
		"visible": entity.held == 0 and entity.hidden == 0,
		"frame": entity.form,
		"rotation": float(posmod(pointing, 360000)) / 1000.0,
		"alpha": 0.6 if entity.frozen else 1.0
	}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.form >= 0
		and entity.form <= LAST_FORM
		and entity.rise_units >= 0
		and entity.rise_units <= MAX_OPTION
		and entity.rise_extra >= 0
		and entity.rise_extra <= MAX_OPTION
		and entity.wait_ticks >= 0
		and entity.heading >= 0
		and entity.heading < 360000
		and entity.phase >= WAIT
		and entity.phase <= LOOSE
		and entity.timer >= 0
		and entity.speed >= 0
		and entity.speed <= MAX_SPEED
	)
