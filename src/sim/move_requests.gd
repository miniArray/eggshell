extends RefCounted
## A saved four-request history. Consumers poll each tick with a saved serial cursor.
const CAPACITY := 4
const EGG := 1
const SPIT := 2
const SEED := 3
const HEAT := 4
const COLD := 5
const CONSUME := 6
const STORED_EGG := 7
const PARTS := ["serial", "kind", "item", "x", "y", "angle", "vx", "vy"]


static func emit(
	state: Dictionary, kind: int, item: int, x: int, y: int, angle: int, vx: int, vy: int
) -> void:
	if state.move_emit_serial == 9223372036854775807:
		for slot in CAPACITY:
			for part: String in PARTS:
				state[_field(slot, part)] = 0
	for slot in range(CAPACITY - 1, 0, -1):
		for part: String in PARTS:
			state[_field(slot, part)] = state[_field(slot - 1, part)]
	state.move_emit_serial += 1
	state.move_emit_kind = kind
	state.move_emit_item = item
	state.move_emit_x = x
	state.move_emit_y = y
	state.move_emit_angle = angle
	state.move_emit_vx = vx
	state.move_emit_vy = vy


static func latest(state: Dictionary) -> Dictionary:
	return _record(state, 0) if state.get("move_emit_serial", 0) else {}


static func since(state: Dictionary, after_serial: int) -> Dictionary:
	var current: int = state.get("move_emit_serial", 0)
	if after_serial < 0:
		return {"ok": false, "error": "Invalid move request cursor"}
	if after_serial > current:
		return {"ok": false, "error": "Move request sequence reset"}
	if current == after_serial:
		return {"ok": true, "requests": [], "latest": current}
	if current - after_serial > CAPACITY:
		return {"ok": false, "error": "Move request history expired"}
	var requests := []
	for slot in range(CAPACITY - 1, -1, -1):
		var record := _record(state, slot)
		if record.serial > after_serial:
			requests.append(record)
	return {"ok": true, "requests": requests, "latest": current}


static func valid_state(state: Dictionary) -> bool:
	for slot in CAPACITY:
		for part: String in PARTS:
			if not state.get(_field(slot, part)) is int:
				return false
		var record := _record(state, slot)
		if record.serial != maxi(0, state.move_emit_serial - slot):
			return false
		if (
			record.kind < 0
			or record.kind > STORED_EGG
			or record.item < 0
			or record.angle < -180000
			or record.angle > 180000
		):
			return false
		if not record.serial:
			for part: String in PARTS:
				if record[part] != 0:
					return false
		elif not record.kind:
			return false
	return state.move_emit_serial >= 0


static func _record(state: Dictionary, slot: int) -> Dictionary:
	var record := {}
	for part: String in PARTS:
		record[part] = state[_field(slot, part)]
	return record


static func _field(slot: int, part: String) -> String:
	return "move_emit_%s" % part if slot == 0 else "move_emit_%d_%s" % [slot, part]
