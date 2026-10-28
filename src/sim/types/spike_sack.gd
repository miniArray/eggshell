extends RefCounted
## A spiked sack that drifts in a straight line at 120 px/s from its placement
## angle and reflects off solids. Touching it hurts. Nothing defeats it.

const S := preload("res://src/sim/units.gd").SCALE
const Collision = preload("res://src/sim/collision.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Moves = preload("res://src/sim/moves.gd")
const Damage = preload("res://src/sim/damage.gd")
const CODES := ["e34"]
const CONTACT_PHASE := 1
const SPEED := 120 * 60
const FIELDS := [["form", 0], ["heading", 270000]]
## Body half sizes in pixels for the large and small forms.
const HALF := [68, 38]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var registry: Script = load("res://src/sim/registry.gd")
	var angle: Dictionary = registry.numeric_option(source.properties.get("R", 0))
	var form: Variant = source.properties.get("F", 0)
	if (
		not angle.ok
		or not (form is int or form is float)
		or not is_finite(form)
		or form < 0
		or form != floor(form)
	):
		return {"ok": false, "error": "Invalid sack angle or form"}
	if form > 1:
		return {"ok": false, "degrade": true, "error": "sack form F=%d" % form}
	source.form = int(form)
	source.heading = posmod(roundi((angle.value - 90.0) * 1000.0), 360000)
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var heading: int = int(source.heading)
	return {
		"form": int(source.form),
		"heading": heading,
		"vx": SPEED * Motion.turn_cosine(heading) / S,
		"vy": SPEED * Motion.turn_sine(heading) / S,
		"spawn_mode": 1,
		"status": 0,
		"can_despawn": 1,
		"can_respawn": 1
	}


static func bounds(entity: Dictionary) -> Array:
	var half: int = HALF[entity.form] * S
	return [-half, -half, half, half]


static func step(entity: Dictionary, _state: Dictionary, world: Dictionary) -> void:
	var box := bounds(entity)
	# Placed inside a solid it stays trapped until it is free.
	if Collision.overlaps(entity, world, box):
		return
	var bounced := false
	var dx: int = entity.vx
	var dy: int = entity.vy
	if dx and Collision.overlaps(entity, world, box, dx, 0):
		entity.vx = -entity.vx
		bounced = true
	else:
		entity.x += dx
	if dy and Collision.overlaps(entity, world, box, 0, dy):
		entity.vy = -entity.vy
		bounced = true
	else:
		entity.y += dy
	if bounced:
		entity.heading = Motion.angle_to(entity.vx, entity.vy)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if state.get("captured_by", 0):
		return
	var player := Moves.player_box(state)
	var box := bounds(entity)
	if (
		state.x + player[2] > entity.x + box[0]
		and state.x + player[0] < entity.x + box[2]
		and state.y + player[3] > entity.y + box[1]
		and state.y + player[1] < entity.y + box[3]
	):
		Damage.hurt(state, entity.x)


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1, "frame": entity.form}


static func valid(entity: Dictionary) -> bool:
	return entity.form in [0, 1] and entity.heading >= 0 and entity.heading < 360000
