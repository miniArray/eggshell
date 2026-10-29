extends RefCounted
## A numbered ledge. Each time something steps on and off it, its number drops by one;
## stepping off at one breaks it.

const Moves = preload("res://src/sim/moves.gd")
const Near = preload("res://src/sim/types/near_query.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["o32"]
const SOLID := 2
const STEP_PHASE := -1
const CONTACT_PHASE := 1
const MAX_COUNT := 99
# Bodies that can press the ledge besides the player (enemies are added by the registry check).
const PRESSERS := ["o4", "o7", "o11", "o16", "o17"]
const FIELDS := [["count", 1], ["pressed", 0]]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var form: Variant = source.properties.get("F", 0)
	if not (form is int or form is float) or not is_finite(form) or form != floor(form):
		return {"ok": false, "error": "Invalid countdown ledge form"}
	if form < 0 or form >= MAX_COUNT:
		return {"ok": false, "degrade": true, "error": "Unsupported countdown ledge form"}
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"count": int(source.get("variant", 0)) + 1}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func top(entity: Dictionary) -> int:
	return entity.y - 26 * S


static func bounds(_entity: Dictionary) -> Array:
	return [-32 * S, -26 * S, 32 * S, 32 * S]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1:
		return []
	return [entity.x - 32 * S, top(entity), entity.x + 32 * S, top(entity) + 2 * S]


static func contact(entity: Dictionary, state: Dictionary, world: Dictionary, _input: int) -> void:
	if entity.status != 1:
		return
	if not entity.pressed:
		if _pressing(entity, state, world):
			entity.pressed = 1
		return
	if _resting(entity, state, world):
		return
	entity.pressed = 0
	entity.count -= 1
	if entity.count < 1:
		entity.status = 3


static func _pressing(entity: Dictionary, state: Dictionary, world: Dictionary) -> bool:
	# Something whose box, 2 px lower, touches the ledge, with its origin at or above the top
	# and not moving up.
	var box := [entity.x - 32 * S, entity.y - 26 * S, entity.x + 32 * S, entity.y + 32 * S]
	var player := _player_box(state)
	if (
		not player.is_empty()
		and state.y <= top(entity)
		and state.vy >= 0
		and _overlap([player[0], player[1] + 2 * S, player[2], player[3] + 2 * S], box)
	):
		return true
	for other: Dictionary in _bodies(entity, state, world, box):
		var shape: Array = other.box
		if (
			other.entity.y <= top(entity)
			and other.entity.get("vy", 0) >= 0
			and _overlap([shape[0], shape[1] + 2 * S, shape[2], shape[3] + 2 * S], box)
		):
			return true
	return false


static func _resting(entity: Dictionary, state: Dictionary, world: Dictionary) -> bool:
	# The ledge raised by 2 px still touches something.
	var raised := [entity.x - 32 * S, entity.y - 28 * S, entity.x + 32 * S, entity.y + 30 * S]
	var player := _player_box(state)
	if not player.is_empty() and _overlap(player, raised):
		return true
	for other: Dictionary in _bodies(entity, state, world, raised):
		if _overlap(other.box, raised):
			return true
	return false


static func _player_box(state: Dictionary) -> Array:
	if state.get("captured_by", 0):
		return []
	var box := Moves.player_box(state)
	return [state.x + box[0], state.y + box[1], state.x + box[2], state.y + box[3]]


static func _bodies(entity: Dictionary, state: Dictionary, world: Dictionary, area: Array) -> Array:
	var registry: Script = Near.registry()
	var result := []
	var probe := [area[0], area[1] - 4 * S, area[2], area[3] + 4 * S]
	for other: Dictionary in Near.nearby(state, world, probe):
		if (
			other.get("token", 0) == entity.token
			or other.status != 1
			or other.get("held", 0)
			or other.get("hidden", 0)
			or other.get("collected", 0)
			or not (registry.is_enemy(other.code) or other.code in PRESSERS)
		):
			continue
		var type: Script = registry.lookup(other.code)
		if not type.has_method("bounds"):
			continue
		var local: Array = type.bounds(other)
		result.append(
			{
				"entity": other,
				"box":
				[other.x + local[0], other.y + local[1], other.x + local[2], other.y + local[3]]
			}
		)
	return result


static func _overlap(a: Array, b: Array) -> bool:
	return a[0] < b[2] and a[2] > b[0] and a[1] < b[3] and a[3] > b[1]


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {
		"visible": entity.status == 1, "animation": "Pressed" if entity.pressed else "Unpressed"
	}


static func valid(entity: Dictionary) -> bool:
	return entity.count >= 0 and entity.count <= MAX_COUNT and entity.pressed in [0, 1]
