extends RefCounted
## A walker on tall stilts. It strides 24 px every step, turning at walls and
## ledges. Its legs hurt; landing on its top knocks the rider off as a plain
## walker of its colour, and a ground pound destroys it outright. Tongue, low eggs
## and low thrown bodies only knock it back; an egg at the rider unseats it.

const Body = preload("res://src/sim/enemy_body.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e35"]
const ENEMY := true
const ELEMENT_REACTIONS := Elements.BURNS | Elements.FREEZES
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const WALK := 0
const KNOCKED := 1
const STRIDE := 24 * S
const STRIDE_TICKS := 36  # Twelve frames at 20 per second; half speed in water.
const KNOCK_TICKS := 36  # 0.6 s.
const FIELDS := (
	Body.FIELDS + [["height", 68 * S], ["phase", WALK], ["timer", 0], ["stride", 0], ["contact", 0]]
)
const MAX_HEIGHT := 100_000


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var result := Options.prepare(source, 4)
	if not result.ok:
		return result
	var parsed: Dictionary = registry().numeric_option(source.properties.get("E1", "50"))
	if not parsed.ok or parsed.value < 0:
		return {"ok": false, "error": "Invalid stilt height"}
	if parsed.value > MAX_HEIGHT:
		return {"ok": false, "degrade": true, "error": "stilt height E1 out of range"}
	source.height = (int(parsed.value) + 18) * S
	source.y += 16 * S  # The stilts stand on the placement's lower edge.
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.height = int(source.get("height", 68 * S))
	return values


static func bounds(entity: Dictionary) -> Array:
	return [-8 * S, -entity.height, 8 * S, 0]


static func top(entity: Dictionary) -> int:
	return entity.y - entity.height


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	var box := bounds(entity)
	if Body.hazards(entity, state, world, box):
		return
	var grounded := Collision.floor_at(entity, world, box) != 0
	if entity.phase == KNOCKED:
		# A finished knock timer stops at zero; the walker walks again once it lands.
		entity.timer = maxi(entity.timer - 1, 0)
		if entity.timer > 0:
			var distance: int = entity.vx
			Motion.move(entity, world, box, distance, true)
			if grounded and entity.vy >= 0:
				entity.vy = -192 * 60
		elif grounded:
			entity.phase = WALK
			entity.vx = 0
			entity.facing = -entity.facing
			entity.stride = 0
	else:
		entity.vx = 0
		var wet := int(
			World.water_overlaps(
				world, entity.x + box[0], entity.y + box[1], entity.x + box[2], entity.y + box[3]
			)
		)
		entity.stride += 1
		if entity.stride >= STRIDE_TICKS * (wet + 1):
			entity.stride = 0
			stride(entity, world, box)
	Motion.gravity_box(entity, world, box)


## One step: turn instead when a solid or a missing floor lies one stride ahead.
static func stride(entity: Dictionary, world: Dictionary, box: Array) -> void:
	var ahead: int = entity.facing * STRIDE
	var blocked := Collision.overlaps(entity, world, box, ahead, -S)
	var x: int = entity.x + ahead
	var floor := Collision.support_in_box(
		world, x + box[0], entity.y, x + box[2], entity.y + 32 * S, entity
	)
	if blocked or not floor:
		entity.facing = -entity.facing
	else:
		entity.x = x


static func knock(entity: Dictionary, from_x: int) -> void:
	var away := 1 if entity.x >= from_x else -1
	entity.phase = KNOCKED
	entity.timer = KNOCK_TICKS
	entity.facing = away
	entity.vx = away * 48 * 60


## The rider drops off as a plain walker of the same colour; the stilts are gone.
static func unseat(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.status != 1:
		return
	registry().spawn_dynamic(
		state,
		world,
		"e1",
		entity.x,
		top(entity) + 34 * S,
		{"F": entity.variant, "facing": entity.facing}
	)
	Body.remove(entity, state)


static func contact(entity: Dictionary, state: Dictionary, world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	var touching := Body.player_overlap(entity, state, bounds(entity))
	var high: bool = state.y <= top(entity) + 50 * S
	if touching and not entity.contact and high:
		if Body.pounding(state):
			Body.remove(entity, state)
		else:
			Moves.bounce(state, -absi(entity.vy / 2) - 320 * 60, input)
			unseat(entity, state, world)
	elif touching and not high:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	if entity.status != 1:
		return 0
	knock(entity, state.x)
	return 2


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, from_x: int
) -> void:
	if Reactions.hit(entity, state, world, kind, ELEMENT_REACTIONS, bounds(entity)):
		return
	if kind in [Hits.POUND, Hits.CLEAR]:
		unseat(entity, state, world)
	else:
		knock(entity, from_x)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var at_rider: bool = projectile.get("y", entity.y) < top(entity) + 50 * S
	if at_rider:
		unseat(entity, state, world)
	else:
		knock(entity, projectile.x)
	return 1 if Body.projectile_kind(projectile) == Hits.EGG else 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.held == 0, "size_y": float(entity.height) / S}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.height > 0
		and entity.height <= (MAX_HEIGHT + 18) * S
		and entity.phase in [WALK, KNOCKED]
		and entity.timer >= 0
		and entity.timer <= KNOCK_TICKS
		and entity.stride >= 0
		and entity.stride < STRIDE_TICKS * 2
		and entity.contact in [0, 1]
	)
