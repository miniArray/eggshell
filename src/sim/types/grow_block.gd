extends RefCounted
## A small full solid that doubles in size when struck from below, then shrinks back.

const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["o10"]
const SOLID := 1
const IDLE := 0
const RISE := 1
const SETTLE := 2
const HOLD := 3
const SHRINK := 4
const TWEEN := 12
const HOLD_TICKS := 360
const SMALL := 32 * S
const LARGE := 64 * S
const RISE_OFFSET := -62 * S
const HELD_OFFSET := -32 * S
const FIELDS := [["phase", IDLE], ["ticks", 0], ["timer", 0], ["size", SMALL], ["lift", 0]]


static func create(_source: Dictionary, _world: Dictionary) -> Dictionary:
	return {}


static func bounds(entity: Dictionary) -> Array:
	# The block grows around its bottom centre; lift moves that bottom.
	var half: int = entity.size / 2
	var bottom: int = 16 * S + entity.lift
	return [-half, bottom - entity.size, half, bottom]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1:
		return []
	var box := bounds(entity)
	return [entity.x + box[0], entity.y + box[1], entity.x + box[2], entity.y + box[3]]


static func step(entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	if entity.phase == IDLE:
		return
	entity.timer += 1
	if entity.phase == HOLD:
		if entity.timer >= HOLD_TICKS:
			entity.phase = SHRINK
			entity.ticks = 0
		return
	entity.ticks += 1
	match entity.phase:
		RISE:
			entity.lift = ease_in_out(0, RISE_OFFSET, entity.ticks)
			entity.size = SMALL + (LARGE - SMALL) * entity.ticks / TWEEN
		SETTLE:
			entity.lift = ease_in_out(RISE_OFFSET, HELD_OFFSET, entity.ticks)
		SHRINK:
			entity.lift = ease_in_out(HELD_OFFSET, 0, entity.ticks)
			entity.size = LARGE + (SMALL - LARGE) * entity.ticks / TWEEN
	if entity.ticks < TWEEN:
		return
	entity.ticks = 0
	match entity.phase:
		RISE:
			entity.phase = SETTLE
		SETTLE:
			entity.phase = HOLD if entity.timer < HOLD_TICKS else SHRINK
		SHRINK:
			entity.phase = IDLE
			entity.timer = 0


static func ease_in_out(from: int, to: int, tick: int) -> int:
	# Quadratic in-out over TWEEN ticks, in exact integer steps.
	var span := TWEEN * TWEEN
	var part := 2 * tick * tick if 2 * tick < TWEEN else span - 2 * (TWEEN - tick) * (TWEEN - tick)
	return from + (to - from) * part / span


static func contact(entity: Dictionary, state: Dictionary, world: Dictionary, _input: int) -> void:
	if entity.status != 1 or entity.phase != IDLE or state.get("captured_by", 0):
		return
	var box := Moves.player_box(state)
	var block := solid_box(entity)
	# The source tests the player raised by 2 px against the block.
	if (
		state.x + box[2] > block[0]
		and state.x + box[0] < block[2]
		and state.y + box[3] - 2 * S > block[1]
		and state.y + box[1] - 2 * S < block[3]
	):
		entity.phase = RISE
		entity.ticks = 0
		entity.timer = 0
		knock_above(entity, state, world, block)


static func knock_above(
	entity: Dictionary, state: Dictionary, world: Dictionary, block: Array
) -> void:
	var probe := [block[0], block[1] - 8 * S, block[2], block[3] - 8 * S]
	var registry: Script = load("res://src/sim/registry.gd")
	for other: Dictionary in state.entities:
		if (
			other.token == entity.token
			or other.status != 1
			or other.get("held", 0) == 1
			or other.get("hidden", 0) == 1
		):
			continue
		var type: Script = registry.lookup(other.code)
		if type.has_method("hit") and registry.overlaps_box(other, type, probe):
			type.hit(other, state, world, Hits.BUMP, entity.x)


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var size := float(entity.size) / S
	return {
		"visible": entity.status == 1,
		"animation": "Default",
		"offset_y": float(entity.lift) / S,
		"size_x": size,
		"size_y": size
	}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.phase >= IDLE
		and entity.phase <= SHRINK
		and entity.ticks >= 0
		and entity.ticks <= TWEEN
		and entity.timer >= 0
		and entity.timer <= HOLD_TICKS + 2 * TWEEN
		and entity.size >= SMALL
		and entity.size <= LARGE
		and entity.lift >= RISE_OFFSET
		and entity.lift <= 0
	)
