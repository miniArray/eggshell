extends RefCounted
## A full-solid block crowned with a deadly spike, turned by its placement angle
## in quarter turns. Touching the spike edge is fatal; the other faces are safe.

const Life = preload("res://src/sim/life.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hull = preload("res://src/sim/player_hull.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["o13"]
const SOLID := 1
const STEP_PHASE := -1
const FIELDS := [["turn", 0]]
const HALF := 16 * S
## The constant bounds, for the entity grid (EntityGrid files rows by it).
const GRID_BOUNDS := {"o13": [-HALF, -HALF, HALF, HALF]}


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var registry: Script = load("res://src/sim/registry.gd")
	var angle: Dictionary = registry.numeric_option(source.properties.get("R", 0))
	if not angle.ok:
		return {"ok": false, "error": "Invalid spike angle"}
	var turned := fposmod(angle.value, 360.0)
	if turned != floor(turned) or int(turned) % 90 != 0:
		return {"ok": false, "degrade": true, "error": "spike angle R=%s" % str(angle.value)}
	source.turn = int(turned) / 90
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"turn": int(source.get("turn", 0))}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func bounds(_entity: Dictionary) -> Array:
	return [-HALF, -HALF, HALF, HALF]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1:
		return []
	return [entity.x - HALF, entity.y - HALF, entity.x + HALF, entity.y + HALF]


## The 32×2 spike edge centred on the face the spike points out of.
static func spike_box(entity: Dictionary) -> Array:
	var angle: int = entity.turn * 90000 - 90000
	var cx: int = entity.x + HALF * Motion.turn_cosine(angle) / S
	var cy: int = entity.y + HALF * Motion.turn_sine(angle) / S
	if entity.turn % 2 == 0:
		return [cx - HALF, cy - S, cx + HALF, cy + S]
	return [cx - S, cy - HALF, cx + S, cy + HALF]


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if entity.status != 1 or state.get("captured_by", 0):
		return
	var spike := spike_box(entity)
	if Hull.misses(state, spike[0], spike[1], spike[2], spike[3]):
		return
	var box := Moves.player_box(state)
	if (
		state.x + box[2] > spike[0]
		and state.x + box[0] < spike[2]
		and state.y + box[3] > spike[1]
		and state.y + box[1] < spike[3]
	):
		Life.kill(state, Life.HAZARD)


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1, "rotation": float(entity.turn * 90)}


static func valid(entity: Dictionary) -> bool:
	return entity.turn >= 0 and entity.turn <= 3
