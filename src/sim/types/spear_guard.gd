extends RefCounted
## A small walker holding an upright spear of placement-defined length. Strikes on its
## front push it back; strikes from behind defeat it. The spear hurts on contact.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e22"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const LAST_FORM := 4
const MAX_SPEAR := 4096
const KNOCK_TICKS := 42
const BLOCK_TICKS := 60
const BOX := [-10 * S, -18 * S, 10 * S, 16 * S]
const FIELDS := (
	Body.FIELDS
	+ [
		["spear", 64 * S],
		["has_spear", 1],
		["block", 0],
		["knock_vx", 0],
		["knock_ticks", 0],
		["grounded", 1],
		["contact", 0]
	]
)


static func prepare(source: Dictionary, world: Dictionary) -> Dictionary:
	var raw: Variant = source.properties.get("E1", "0")
	var length := 0
	if raw is String:
		var text: String = raw.strip_edges()
		var digits := ""
		for index in text.length():
			if text[index].is_valid_int() or (index == 0 and text[index] == "-"):
				digits += text[index]
			else:
				break
		length = digits.to_int() if digits.is_valid_int() else 0
	elif (raw is int or raw is float) and is_finite(raw):
		length = int(raw)
	else:
		return {"ok": false, "error": "Invalid spear length"}
	if length > MAX_SPEAR:
		return {"ok": false, "degrade": true, "error": "Unsupported spear length"}
	source.spear = maxi(0, length) * S
	return Options.prepare(source, LAST_FORM)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.spear = int(source.get("spear", 64 * S))
	return values


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func spear_box(entity: Dictionary) -> Array:
	if not entity.has_spear:
		return []
	# The spear stands at the hand, 24 px above the origin, and rises by its length.
	var x: int = entity.x - entity.facing * S
	return [x - 7 * S, entity.y - 24 * S - entity.spear, x + 7 * S, entity.y + 4 * S]


static func activation_bounds(entity: Dictionary) -> Array:
	var body := Body.world_box(entity, BOX)
	var spear := spear_box(entity)
	if not spear.is_empty():
		body[1] = mini(body[1], spear[1])
	return body


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Body.spit_step(entity, state, world, BOX) or Body.hazards(entity, state, world, BOX):
		return
	if entity.knock_ticks:
		entity.knock_ticks -= 1
		entity.vx = entity.knock_vx * entity.knock_ticks / KNOCK_TICKS
	elif entity.block:
		entity.vx = 0
	else:
		entity.vx = entity.facing * 48 * 60
		if entity.grounded and Motion.edge(entity, world, BOX):
			entity.facing *= -1
			entity.vx = -entity.vx
	if entity.block:
		entity.block -= 1
	var distance: int = entity.vx
	if distance and Motion.move(entity, world, BOX, distance, true) != distance:
		if not entity.knock_ticks and not entity.block:
			entity.facing *= -1
		entity.vx = 0
	var landed := Motion.gravity_box(entity, world, BOX)
	entity.grounded = int(landed or Collision.floor_at(entity, world, BOX) != 0)


static func knock(entity: Dictionary, direction: int) -> void:
	entity.knock_vx = direction * 200 * 60
	entity.knock_ticks = KNOCK_TICKS
	entity.block = BLOCK_TICKS


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if entity.held or entity.spat or entity.status != 1 or state.get("captured_by", 0):
		return
	var player := Body.world_box(state, Moves.player_box(state))
	var spear := spear_box(entity)
	if not spear.is_empty() and Body.overlap(spear, player):
		Body.hurt(entity, state)
		var spear_x: int = (spear[0] + spear[2]) / 2
		state.vx = (-400 if state.x < spear_x else 400) * 60
		return
	var touching := Body.player_overlap(entity, state, BOX)
	if touching and entity.y > state.y - 8 * S:
		if not entity.contact and not entity.has_spear:
			if not Body.pounding(state):
				Body.bounce(entity, state, input)
			Body.remove(entity, state)
	elif touching:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	if entity.held or entity.status != 1:
		return 0
	if entity.has_spear and state.facing == -entity.facing:
		# A tongue at the spear side pushes the walker back and bounces off.
		knock(entity, state.facing)
		return 2
	entity.has_spear = 0
	return Body.tongue(entity, state, 1)


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, _kind: int, _from_x: int
) -> void:
	entity.has_spear = 0
	Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var kind := Body.projectile_kind(projectile)
	if kind != Hits.EGG:
		hit(entity, state, world, kind, projectile.get("x", entity.x))
		return 3
	var heading: int = signi(projectile.get("vx", 0))
	if heading == 0:
		heading = 1 if projectile.get("x", entity.x) < entity.x else -1
	if entity.has_spear and heading == -entity.facing:
		knock(entity, heading)
	else:
		hit(entity, state, world, kind, projectile.get("x", entity.x))
	return 1


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var pose := "Block" if entity.block else ("Spear" if entity.has_spear else "Walk")
	return {"visible": entity.held == 0, "animation": str(entity.variant) + pose}


static func finished(entity: Dictionary) -> bool:
	return entity.status in [2, 3] and entity.held == 0


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant <= LAST_FORM
		and entity.spear >= 0
		and entity.spear <= MAX_SPEAR * S
		and entity.has_spear in [0, 1]
		and entity.block >= 0
		and entity.block <= BLOCK_TICKS
		and entity.knock_ticks >= 0
		and entity.knock_ticks <= KNOCK_TICKS
		and absi(entity.knock_vx) <= 200 * 60
		and entity.grounded in [0, 1]
		and entity.contact in [0, 1]
	)
