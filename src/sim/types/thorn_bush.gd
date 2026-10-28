extends RefCounted
## A thorny bush that settles on the ground. Touching it always hurts. Every
## second all bushes swap between spikes out and spikes in, the second form in
## the opposite beat. A thrown egg destroys it and is spent only on spikes.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e36"]
const ENEMY := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const BEAT := 60  # One second per spike phase, shared by every bush.
const FIELDS := Body.FIELDS + [["contact", 0]]
const BOX := [-12 * S, -12 * S, 12 * S, 12 * S]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 1)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(_entity: Dictionary) -> Array:
	return BOX


## The shared beat follows the level clock (opinion: the source starts its global
## timer with the first bush, so the phase may differ from the original).
static func spikes_out(entity: Dictionary, state: Dictionary) -> bool:
	var beat: int = (int(state.get("frame", 0)) / BEAT) % 2
	return (beat == 1) != (entity.variant == 1)


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Body.hazards(entity, state, world, BOX):
		return
	entity.vx = 0
	Motion.gravity_box(entity, world, BOX)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	var touching := Body.player_overlap(entity, state, BOX)
	if touching:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, _kind: int, _from_x: int
) -> void:
	Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var spent := spikes_out(entity, state)
	hit(entity, state, world, Body.projectile_kind(projectile), projectile.x)
	return 1 if spent else 3


static func view_state(entity: Dictionary, state: Dictionary) -> Dictionary:
	return {
		"visible": entity.held == 0,
		"animation": "Red" if entity.variant == 1 else "Green",
		"frame": int(spikes_out(entity, state))
	}


static func valid(entity: Dictionary) -> bool:
	return Body.valid(entity) and entity.variant <= 1 and entity.contact in [0, 1]
