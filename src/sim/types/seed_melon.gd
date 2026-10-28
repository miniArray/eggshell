extends RefCounted
## A melon that falls to the ground and waits to be eaten. Eating a plain melon
## loads the player with seeds to spit; forms 3 to 5 load fire and forms 6 to 8
## load ice, three, one or nine shots by size.

const S := preload("res://src/sim/units.gd").SCALE
const Moves = preload("res://src/sim/moves.gd")
const Requests = preload("res://src/sim/move_requests.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Life = preload("res://src/sim/life.gd")
const Elements = preload("res://src/sim/elements.gd")
const CODES := ["o25"]
const STEP_PHASE := 0
const CONTACT_PHASE := -1
const FIELDS := [["form", 0], ["held", 0], ["request_cursor", 0]]
const BOX := [-16 * S, -16 * S, 16 * S, 16 * S]
## Seeds loaded by each plain form.
const SEEDS := [30, 10, 60]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var form: Variant = source.properties.get("F", 0)
	if not (form is int or form is float) or not is_finite(form) or form != floor(form):
		return {"ok": false, "error": "Invalid melon form"}
	if form < 0:
		return {"ok": false, "error": "Invalid melon form"}
	if form > Elements.LAST_MELON:
		return {"ok": false, "degrade": true, "error": "melon form F=%d" % form}
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {
		"form": int(source.get("variant", 0)),
		"spawn_mode": 1,
		"status": 0,
		"can_despawn": 1,
		"can_respawn": 1
	}


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func step(entity: Dictionary, _state: Dictionary, world: Dictionary) -> void:
	if entity.held:
		return
	Motion.gravity_box(entity, world, BOX)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	if entity.held or entity.status != 1 or Life.blocks_step(state):
		return 0
	var ammo := ammunition(entity.form)
	if Moves.catch_item(state, entity.token, 0, ammo[0], ammo[1], 1):
		entity.held = 1
		entity.vy = 0
		entity.request_cursor = state.move_emit_serial
		return 1
	return 0


## `[ammunition kind, count]` loaded by eating one melon form.
static func ammunition(form: int) -> Array:
	if form < SEEDS.size():
		return [Moves.SEED, SEEDS[form]]
	return Elements.melon_ammo(form)


static func consume_requests(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	if not entity.held:
		return
	var result := Requests.since(state, entity.request_cursor)
	entity.request_cursor = state.move_emit_serial
	if not result.ok:
		return
	for request: Dictionary in result.requests:
		if request.item == entity.token and request.kind == Requests.CONSUME:
			entity.held = 0
			entity.status = 3
			entity.can_respawn = 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1 and entity.held == 0, "frame": entity.form}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.form >= 0
		and entity.form <= Elements.LAST_MELON
		and entity.held in [0, 1]
		and entity.request_cursor >= 0
	)
