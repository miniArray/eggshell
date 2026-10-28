extends RefCounted
## A flyer that hangs from a ceiling, dives at a player below, loops once and flies on.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const World = preload("res://src/sim/world.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e14"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const HANG := 0
const DIVE := 1
const SWOOP := 2
const FORWARD := 3
const FLEE := 4
# Flap frame widths in pixels; the dive drifts sideways by the current width per second.
const FLAP_WIDTHS := [44, 56, 56, 48, 56, 56]
const SWOOP_TICKS := 150
const FIELDS := (
	Body.FIELDS
	+ [
		["mode", HANG],
		["timer", 0],
		["flap", 0],
		["from_x", 0],
		["from_y", 0],
		["target_y", 0],
		["contact", 0]
	]
)


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 1)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.mode = FORWARD if values.variant == 1 else HANG
	if int(source.get("source_index", 0)) == -1:
		values.mode = Options.option(source, "mode", values.mode)
	return values


static func bounds(entity: Dictionary) -> Array:
	if entity.mode == HANG:
		return [-10 * S, -16 * S, 10 * S, 14 * S]
	return [-12 * S, -10 * S, 12 * S, 14 * S]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var fresh: bool = entity.started == 0
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if fresh and entity.mode == HANG:
		# Without a ceiling within 4 px it starts flying straight away.
		var box := bounds(entity)
		if not Motion.overlaps(entity, world, box, 0, -4 * S):
			entity.mode = FORWARD
	if action == Body.RELEASED:
		# Released from the mouth, it flees the way the player faces and never hurts again.
		entity.spat = 0
		entity.mode = FLEE
		entity.facing = state.facing if state.facing != 0 else 1
	if entity.mode != HANG:
		entity.flap = (entity.flap + 1) % 20
	match entity.mode:
		HANG:
			if (
				absi(entity.x - state.x) < 248 * S
				and state.y > entity.y + 12 * S
				and not state.get("captured_by", 0)
			):
				entity.mode = DIVE
				if entity.x != state.x:
					entity.facing = 1 if state.x > entity.x else -1
		DIVE:
			entity.y += 128 * 60
			entity.x += entity.facing * FLAP_WIDTHS[entity.flap * 18 / 60 % 6] * 60
			if entity.y > state.y - 64 * S:
				entity.mode = SWOOP
				entity.timer = 0
				entity.from_x = entity.x
				entity.from_y = entity.y
				entity.target_y = state.y - 32 * S
		SWOOP:
			_swoop(entity)
		FORWARD:
			entity.x += entity.facing * 128 * 60
		FLEE:
			entity.y -= 96 * 60
			entity.x += entity.facing * 224 * 60
	Body.hazards(entity, state, world, bounds(entity))


static func _swoop(entity: Dictionary) -> void:
	# Drop to the player's height (0.3 s), slide 64 px on (0.5 s), then loop: 80 px up and back
	# over 2 s while swinging 40 px forward and back, then 40 px behind and back.
	entity.timer += 1
	var t: int = entity.timer
	var forward: int = entity.facing
	var x: int = entity.from_x + forward * 64 * S * mini(t, 30) / 30
	var y: int = entity.from_y + _out_quad(entity.target_y - entity.from_y, mini(t, 18), 18)
	if t > 30:
		var loop: int = t - 30
		y = entity.target_y - _ping_pong(80 * S, loop, 60, true)
		var swing: int = loop if loop <= 60 else loop - 60
		var side: int = forward if loop <= 60 else -forward
		x += side * _ping_pong(40 * S, swing, 30, false)
	entity.x = x
	entity.y = y
	if t >= SWOOP_TICKS:
		entity.mode = FORWARD
		entity.timer = 0


static func _out_quad(distance: int, tick: int, ticks: int) -> int:
	var left := ticks - tick
	return distance * (ticks * ticks - left * left) / (ticks * ticks)


static func _ping_pong(distance: int, tick: int, ticks: int, in_out: bool) -> int:
	# Out and back over 2 * ticks; the return replays the same ease backwards.
	var phase := mini(tick, 2 * ticks)
	var along := phase if phase <= ticks else 2 * ticks - phase
	if not in_out:
		return _out_quad(distance, along, ticks)
	var span := ticks * ticks
	var part := (
		2 * along * along if 2 * along < ticks else span - 2 * (ticks - along) * (ticks - along)
	)
	return distance * part / span


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	var touching := Body.player_overlap(entity, state, bounds(entity))
	if touching and entity.y > state.y - 8 * S:
		if not entity.contact:
			if not Body.pounding(state):
				Body.bounce(entity, state, input)
			Body.remove(entity, state)
	elif touching and entity.mode != FLEE:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	return Body.tongue(entity, state, 1)


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, _kind: int, _from_x: int
) -> void:
	Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	hit(entity, state, world, Body.projectile_kind(projectile), projectile.get("x", entity.x))
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.held == 0, "animation": "Idle" if entity.mode == HANG else "Fly"}


static func finished(entity: Dictionary) -> bool:
	return entity.status in [2, 3] and entity.held == 0


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant in [0, 1]
		and entity.mode >= HANG
		and entity.mode <= FLEE
		and entity.timer >= 0
		and entity.timer <= SWOOP_TICKS
		and entity.flap >= 0
		and entity.flap < 20
		and entity.contact in [0, 1]
	)
