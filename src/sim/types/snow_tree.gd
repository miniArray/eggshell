extends RefCounted
## Player contact emits cosmetic puffs. Their birth records survive a restore.

const Decor = preload("res://src/sim/types/decor.gd")
const Moves = preload("res://src/sim/moves.gd")
const Polygon = preload("res://src/sim/polygon.gd")
const Screen = preload("res://src/sim/screen.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["d22"]
const STEP_PHASE := -1
const CONTACT_PHASE := 0
const FIELDS := [
	["decor_variant", 0],
	["decor_height", 0],
	["puff_0_x", 0],
	["puff_0_y", 0],
	["puff_0_tick", -1],
	["puff_1_x", 0],
	["puff_1_y", 0],
	["puff_1_tick", -1],
	["puff_2_x", 0],
	["puff_2_y", 0],
	["puff_2_tick", -1],
	["puff_3_x", 0],
	["puff_3_y", 0],
	["puff_3_tick", -1],
	["puff_4_x", 0],
	["puff_4_y", 0],
	["puff_4_tick", -1],
	["puff_5_x", 0],
	["puff_5_y", 0],
	["puff_5_tick", -1],
	["puff_6_x", 0],
	["puff_6_y", 0],
	["puff_6_tick", -1],
	["puff_7_x", 0],
	["puff_7_y", 0],
	["puff_7_tick", -1]
]
const PUFF_TICKS := 45


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Decor.prepare_options(source)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"decor_variant": int(source.variant), "decor_height": int(source.decor.height) * S}


static func crown(entity: Dictionary) -> PackedInt64Array:
	var large: bool = entity.decor_variant == 1
	var center_y: int = entity.y + (290 if large else 144) * S - entity.decor_height
	var half: int = (80 if large else 48) * S
	var top: int = center_y - (268 if large else 138) * S
	var bottom: int = center_y - (48 if large else 18) * S
	return PackedInt64Array([entity.x, top, entity.x + half, bottom, entity.x - half, bottom])


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func contact(entity: Dictionary, state: Dictionary, world: Dictionary, _input: int) -> void:
	if state.frame % 6 != 0 or (state.vx == 0 and state.vy == 0):
		return
	var points := crown(entity)
	var left: int = entity.x - (80 if entity.decor_variant == 1 else 48) * S
	var screen := Screen.area(state, world)
	if (
		left + 160 * S < screen[0]
		or left > screen[2]
		or points[1] > screen[3]
		or points[1] + 316 * S < screen[1]
	):
		return
	var body := Moves.player_box(state)
	if (
		state.x + body[2] < points[4]
		or state.x + body[0] > points[2]
		or state.y + body[3] < points[1]
		or state.y + body[1] > points[3]
	):
		return
	if not Polygon.overlaps_box(
		points, state.x + body[0], state.y + body[1], state.x + body[2], state.y + body[3]
	):
		return
	var dx: int = state.x - entity.x
	var x := 0
	if dx > -16 * S and dx < 16 * S:
		x = entity.x
	elif dx > -48 * S and dx < -16 * S:
		x -= 32 * S
	elif dx > 16 * S and dx < 48 * S:
		x += 32 * S
	elif entity.decor_variant == 1 and dx > -80 * S and dx < -48 * S:
		x -= 64 * S
	elif entity.decor_variant == 1 and dx > 48 * S and dx < 80 * S:
		x += 64 * S
	var top: int = points[1]
	var bottom: int = points[3]
	var y := 0
	if state.y < top:
		y = top + 16 * S
	elif state.y > top and state.y < bottom:
		y = state.y
	elif state.y > bottom:
		y = bottom - 16 * S
	if x <= 0 or y <= 0:
		return
	var slot: int = state.frame / 6 % 8
	entity["puff_%d_x" % slot] = x
	entity["puff_%d_y" % slot] = y
	entity["puff_%d_tick" % slot] = state.frame


static func puffs(entity: Dictionary, tick: int) -> Array:
	var result := []
	for index in 8:
		var born: int = entity["puff_%d_tick" % index]
		if born < 0 or tick < born or tick - born >= PUFF_TICKS:
			continue
		var age := tick - born
		result.append(
			{
				"x": entity["puff_%d_x" % index],
				"y": entity["puff_%d_y" % index] + 112 * S * age / 90,
				"age": age
			}
		)
	return result


static func valid(entity: Dictionary) -> bool:
	if (
		entity.code != "d22"
		or entity.decor_variant not in [0, 1]
		or entity.decor_height < 0
		or entity.decor_height > Decor.MAX_COORD
		or entity.decor_height % S != 0
	):
		return false
	for index in 8:
		if entity["puff_%d_tick" % index] < -1:
			return false
		for axis: String in ["x", "y"]:
			var value: int = entity["puff_%d_%s" % [index, axis]]
			if value < -Decor.MAX_COORD or value > Decor.MAX_COORD:
				return false
	return true
