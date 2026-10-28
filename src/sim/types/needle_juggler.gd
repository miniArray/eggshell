extends RefCounted
## An invulnerable head that tosses a spiked hopper up and catches it, three tosses a round.
## Without a hopper it frowns, then grows a new one.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Moves = preload("res://src/sim/moves.gd")
const Collision = preload("res://src/sim/collision.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e42"]
const ENEMY := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const GRAVITY := 1536
const DURATIONS := [1, 1, 1, 1, 2]
const LAST_FRAME := 4
const FAST := 30
const SLOW := 8
const HOLD_TICKS := 6
const PAUSE_TICKS := 18
const FROWN_TICKS := 120
const GROW_TICKS := 300
const RISE_WAIT := 24
const RISE_TICKS := 36
const RISE_OFFSET := 20
# Rising sequence: 0 none, 1 wait before the offset tween, 2 tween, 3 wait before the catch.
const RISE_NONE := 0
const BOX := [-12 * S, -44 * S, 12 * S, 16 * S]
const FIELDS := (
	Body.FIELDS
	+ [
		["frame", 0],
		["forward", 1],
		["playing", 0],
		["speed", 0],
		["clock", 0],
		["cycles", 0],
		["accepting", 0],
		["frowning", 0],
		["offset", 0],
		["needle_token", 0],
		["hold_ticks", 0],
		["pause_ticks", 0],
		["frown_ticks", 0],
		["grow_ticks", 0],
		["rise", RISE_NONE],
		["rise_ticks", 0],
		["thrown_now", 0]
	]
)


static func registry() -> Script:
	return Body.registry_for()


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0, false)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func top(entity: Dictionary) -> int:
	return entity.y - 48 * S


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var fresh: bool = entity.started == 0
	if Body.process(entity, state) == Body.GONE:
		return
	entity.thrown_now = 0
	Motion.gravity_box(entity, world, BOX, GRAVITY)
	if fresh:
		var needle := _make_needle(entity, state, world, top(entity) - 16 * S)
		if not needle.is_empty():
			catch(entity, needle)
	var needle := carried(entity, state)
	if entity.needle_token and needle.is_empty():
		entity.needle_token = 0
	_timers(entity, state, world)
	_animate(entity, state)
	if not needle.is_empty():
		# A toss during the animation lifts the hopper.
		Collision.refresh(world, needle)
	needle = carried(entity, state)
	if not needle.is_empty():
		needle.x = entity.x
		needle.y = top(entity) - 10 * S + entity.offset * S / 60
		needle.facing = entity.facing
		Collision.refresh(world, needle)


static func carried(entity: Dictionary, state: Dictionary) -> Dictionary:
	if not entity.needle_token:
		return {}
	var needle: Dictionary = registry().find_token(state, entity.needle_token)
	if (
		needle.is_empty()
		or needle.status != 1
		or needle.get("held", 0)
		or needle.get("carrier", 0) != entity.token
	):
		return {}
	return needle


static func _make_needle(
	entity: Dictionary, state: Dictionary, world: Dictionary, y: int
) -> Dictionary:
	return registry().spawn_dynamic(state, world, "e40", entity.x, y, {"can_despawn": 1})


static func catch(entity: Dictionary, needle: Dictionary) -> void:
	entity.accepting = 0
	entity.frowning = 0
	entity.offset = 0
	entity.needle_token = needle.token
	needle.carrier = entity.token
	needle.intangible = 0
	needle.vx = 0
	needle.vy = 0
	needle.sinking = 0
	needle.hop_pending = 0
	entity.playing = 1
	entity.speed = FAST
	entity.frown_ticks = 0
	entity.grow_ticks = 0
	entity.rise = RISE_NONE


static func _timers(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.hold_ticks:
		entity.hold_ticks -= 1
		if entity.hold_ticks == 0 and entity.accepting:
			entity.speed = 0
			entity.frame = 1
			entity.clock = 0
	if entity.pause_ticks:
		entity.pause_ticks -= 1
		if entity.pause_ticks == 0:
			entity.playing = 1
	if entity.frown_ticks:
		entity.frown_ticks -= 1
		if entity.frown_ticks == 0:
			entity.playing = 1
			entity.speed = SLOW
			entity.frowning = 1
			entity.cycles = 0
			entity.grow_ticks = GROW_TICKS
	if entity.grow_ticks and entity.frowning:
		entity.grow_ticks -= 1
		if entity.grow_ticks == 0:
			entity.offset = RISE_OFFSET * 60
			var needle := _make_needle(entity, state, world, top(entity) + 16 * S)
			if not needle.is_empty():
				needle.carrier = entity.token
				needle.intangible = 1
				entity.needle_token = needle.token
				entity.rise = 1
				entity.rise_ticks = RISE_WAIT
	if entity.rise:
		entity.rise_ticks -= 1
		if entity.rise == 2:
			entity.offset = RISE_OFFSET * 60 * entity.rise_ticks / RISE_TICKS
		if entity.rise_ticks == 0:
			match entity.rise:
				1:
					entity.rise = 2
					entity.rise_ticks = RISE_TICKS
				2:
					entity.rise = 3
					entity.rise_ticks = RISE_WAIT
				3:
					entity.rise = RISE_NONE
					var needle := carried(entity, state)
					if not needle.is_empty():
						catch(entity, needle)


static func _animate(entity: Dictionary, state: Dictionary) -> void:
	if not entity.playing or entity.speed == 0:
		return
	entity.clock += entity.speed
	var length: int = DURATIONS[entity.frame] * 60
	if entity.clock < length:
		return
	entity.clock -= length
	if entity.forward:
		entity.frame += 1
		if entity.frame > LAST_FRAME:
			entity.forward = 0
			entity.frame = LAST_FRAME - 1
	else:
		entity.frame -= 1
		if entity.frame < 0:
			# The single ping-pong pass ends back on the first frame.
			entity.frame = 0
			entity.forward = 1
			entity.playing = 0
			entity.clock = 0
			return
	_frame_changed(entity, state)


static func _frame_changed(entity: Dictionary, state: Dictionary) -> void:
	if entity.frame == LAST_FRAME:
		if entity.x != state.x:
			entity.facing = 1 if state.x > entity.x else -1
		if entity.frowning:
			entity.playing = 0
		elif entity.cycles == 2:
			entity.playing = 0
			entity.pause_ticks = PAUSE_TICKS
	elif entity.frame == 0 and entity.speed > 0 and not entity.frowning:
		_toss(entity, state)


static func _toss(entity: Dictionary, state: Dictionary) -> void:
	entity.cycles += 1
	entity.accepting = 1
	entity.thrown_now = 1
	entity.frown_ticks = FROWN_TICKS
	var needle := carried(entity, state)
	if not needle.is_empty():
		var height := 80 if entity.cycles < 3 else 176
		needle.carrier = 0
		needle.y -= 12 * S
		needle.vy = -Motion.root(2 * GRAVITY * height * S)
	entity.needle_token = 0
	if entity.cycles != 3:
		entity.hold_ticks = HOLD_TICKS
	else:
		entity.cycles = 0


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if entity.status != 1:
		return
	if entity.accepting and not entity.thrown_now:
		var box := Body.world_box(entity, BOX)
		for other: Dictionary in state.entities:
			if (
				other.code == "e40"
				and other.status == 1
				and not other.held
				and not other.carrier
				and not other.intangible
				and other.y < entity.y - 16 * S
				and Body.overlap(box, Body.world_box(other, [-12 * S, -12 * S, 12 * S, 12 * S]))
			):
				catch(entity, other)
				break
	if not entity.frowning and Body.player_overlap(entity, state, BOX):
		Body.hurt(entity, state)


static func tongue(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> int:
	return 0


static func projectile_contact(
	_entity: Dictionary, _projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	return 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": true, "animation": "Default", "frame": entity.frame}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.frame >= 0
		and entity.frame <= LAST_FRAME
		and entity.forward in [0, 1]
		and entity.playing in [0, 1]
		and entity.speed in [0, SLOW, FAST]
		and entity.clock >= 0
		and entity.clock < 120
		and entity.cycles >= 0
		and entity.cycles <= 2
		and entity.accepting in [0, 1]
		and entity.frowning in [0, 1]
		and entity.offset >= 0
		and entity.offset <= RISE_OFFSET * 60
		and entity.needle_token >= 0
		and entity.hold_ticks >= 0
		and entity.hold_ticks <= HOLD_TICKS
		and entity.pause_ticks >= 0
		and entity.pause_ticks <= PAUSE_TICKS
		and entity.frown_ticks >= 0
		and entity.frown_ticks <= FROWN_TICKS
		and entity.grow_ticks >= 0
		and entity.grow_ticks <= GROW_TICKS
		and entity.rise >= RISE_NONE
		and entity.rise <= 3
		and entity.rise_ticks >= 0
		and entity.rise_ticks <= RISE_TICKS
		and entity.thrown_now in [0, 1]
	)
