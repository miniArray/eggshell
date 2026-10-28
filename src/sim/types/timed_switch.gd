extends RefCounted
## A modal press animation followed by a shared, restartable switch interval.
const CODES := ["o14"]
const DYNAMIC := true
const S := preload("res://src/sim/units.gd").SCALE
const Collision = preload("res://src/sim/collision.gd")
const Moves = preload("res://src/sim/moves.gd")
const Life = preload("res://src/sim/life.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const FIELDS := [["repeat", 0], ["phase", 0], ["ticks", 0], ["press_y", 0]]
const LEVEL_FIELDS := [
	["switch_ticks", 0],
	["switch_sound_serial", 0],
	["switch_sound_kind", 0],
	["switch_sound_x", 0],
	["switch_sound_y", 0]
]
const READY := 0
const FLATTEN := 1
const UNFLATTEN := 2
const HIDDEN := 3
const BOX := [-20 * S, -26 * S, 20 * S, 16 * S]


static func _registry() -> Script:
	return load("res://src/sim/registry.gd")


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var form: Variant = source.properties.get("F", 0)
	if not (form is int or form is float) or not is_finite(form) or form < 0 or form != floor(form):
		return {"ok": false, "error": "Invalid switch form"}
	if form > 1:
		return {"ok": false, "degrade": true, "error": "switch form F=%d" % form}
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {
		"repeat": int(source.get("variant", 0) == 1),
		"spawn_mode": 1,
		"status": 0,
		"can_despawn": 1,
		"can_respawn": 1
	}


static func bounds(entity: Dictionary) -> Array:
	return [0, 0, 0, 0] if entity.phase == HIDDEN else BOX


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if _clock_owner(entity, state) and state.switch_ticks:
		state.switch_ticks -= 1
		if state.switch_ticks == 0:
			var registry := _registry()
			registry.toggle_switch(state, world)
			_sound(state, 3, 0, 0)
			for other: Dictionary in state.entities:
				if other.code not in CODES or other.phase != HIDDEN:
					continue
				if other.repeat:
					other.phase = READY
					other.y -= 16 * S
					other.can_despawn = 1
					other.vy = 0
				else:
					other.status = 3
				Collision.refresh(world, other)
	if entity.phase != READY or entity.status != 1:
		return
	if Collision.prepare(entity, world, BOX):
		var support := Collision.track_floor(entity, world, BOX)
		if support:
			entity.vy = 0
		Collision.horizontal(entity, world, BOX, entity.vx, support)
		Collision.vertical(entity, world, BOX, entity.vy, support)
	if Collision.floor_at(entity, world, BOX):
		entity.vy = 0
	else:
		entity.vy = mini(704 * 60, entity.vy + 2048)


static func _clock_owner(entity: Dictionary, state: Dictionary) -> bool:
	for other: Dictionary in state.entities:
		if other.code in CODES and other.status == 1:
			return is_same(entity, other)
	return false


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if (
		entity.phase != READY
		or state.modal_token
		or state.captured_by
		or Life.blocks_step(state)
		or state.vy <= entity.vy
		or state.y >= entity.y - 8 * S
	):
		return
	var box := Moves.player_box(state)
	if (
		state.x + box[2] < entity.x - 20 * S
		or state.x + box[0] > entity.x + 20 * S
		or state.y + box[3] < entity.y - 26 * S
		or state.y + box[1] > entity.y + 16 * S
	):
		return
	entity.phase = FLATTEN
	entity.ticks = 0
	entity.press_y = state.y
	entity.y += 16 * S
	entity.can_despawn = 0
	state.modal_token = entity.token
	Moves.interrupt(state)


static func modal_step(
	entity: Dictionary, state: Dictionary, world: Dictionary, input: int
) -> bool:
	state.previous_input = input
	state.pressed_input = 0
	if entity.phase == FLATTEN:
		entity.ticks = mini(18, entity.ticks + 1)
		state.y = entity.press_y + 24 * S * _flatten(entity.ticks) / S
		if entity.ticks == 18:
			entity.phase = UNFLATTEN
			entity.ticks = 0
			_sound(state, 1, entity.x, entity.y)
		return true
	if entity.phase == UNFLATTEN:
		entity.ticks = mini(9, entity.ticks + 1)
		state.y = entity.press_y + 24 * S * (S - _unflatten(entity.ticks)) / S
		if entity.ticks == 9:
			_finish(entity, state, world, input)
		return true
	state.modal_token = 0
	return false


static func _finish(entity: Dictionary, state: Dictionary, world: Dictionary, input: int) -> void:
	# Modal updates run before collision binding; load dispatch without touching its cache.
	var registry := _registry()
	if not state.switch_ticks:
		registry.toggle_switch(state, world)
	state.switch_ticks = 630
	_sound(state, 2, 0, 0)
	entity.phase = HIDDEN
	entity.ticks = 0
	state.modal_token = 0
	state.y = entity.press_y
	state.vy = (-1008 if input & InputBits.JUMP else -448) * 60
	state.on_floor = 0
	state.support_bridge = 0
	state.jump_buffer = 0
	state.flutter_ready = 1
	state.boosted_flutter = int(bool(input & InputBits.JUMP))


static func _sound(state: Dictionary, kind: int, x: int, y: int) -> void:
	state.switch_sound_serial = (
		1 if state.switch_sound_serial == 0x7fffffffffffffff else state.switch_sound_serial + 1
	)
	state.switch_sound_kind = kind
	state.switch_sound_x = x
	state.switch_sound_y = y


static func _flatten(tick: int) -> int:
	return Motion.sine(tick * 90000 / 18, 360000, S)


static func _unflatten(tick: int) -> int:
	return S - Motion.sine(90000 + tick * 90000 / 9, 360000, S)


static func reset_map(state: Dictionary, _world: Dictionary) -> void:
	for pair: Array in LEVEL_FIELDS:
		state[pair[0]] = pair[1]


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var result := {
		"visible": entity.status == 1 and entity.phase != HIDDEN,
		"animation": "Default",
		"frame": entity.repeat
	}
	var amount := 0
	if entity.phase == FLATTEN:
		amount = _flatten(entity.ticks)
		result.frame = entity.repeat + 2
	elif entity.phase == UNFLATTEN:
		amount = S - _unflatten(entity.ticks)
		result.frame = 4
	result.size_x = 40.0 + 32.0 * amount / S
	result.size_y = 42.0 - 24.0 * amount / S
	return result


static func valid(entity: Dictionary) -> bool:
	return (
		entity.repeat in [0, 1]
		and entity.phase >= READY
		and entity.phase <= HIDDEN
		and entity.ticks >= 0
		and entity.ticks <= 18
	)


static func valid_state(state: Dictionary) -> bool:
	return (
		state.switch_ticks >= 0
		and state.switch_ticks <= 630
		and state.switch_sound_serial >= 0
		and state.switch_sound_kind >= 0
		and state.switch_sound_kind <= 3
	)
