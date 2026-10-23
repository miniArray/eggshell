class_name Snapshot
extends RefCounted
## Canonical little-endian bytes; no Variant deserialization or executable objects.

const State = preload("res://src/sim/play_state.gd")
const VERSION := 3
const HEADER := 44
const SPRING_FIELDS := ["x", "y", "vx", "vy", "squash", "active"]
const COUNT_OFFSET := 324  # Version 3: 44-byte header + 35 scalar int64 fields.
const MIN_SIZE := COUNT_OFFSET + 8 + 32


static func encode(state: Dictionary) -> PackedByteArray:
	assert(HEADER + State.FIELDS.size() * 8 == COUNT_OFFSET, "Snapshot version/layout mismatch")
	var body_size: int = (
		MIN_SIZE
		- 32
		+ state.springs.size() * SPRING_FIELDS.size() * 8
		+ state.enemies.size() * State.ENEMY_FIELDS.size() * 8
	)
	var bytes := PackedByteArray()
	bytes.resize(body_size)
	var magic := "EGGSTATE".to_ascii_buffer()
	for index in magic.size():
		bytes[index] = magic[index]
	bytes.encode_u32(8, VERSION)
	var identity: PackedByteArray = state.identity.hex_decode()
	for index in 32:
		bytes[12 + index] = identity[index]
	for index in State.FIELDS.size():
		bytes.encode_s64(HEADER + index * 8, state[State.FIELDS[index]])
	bytes.encode_u32(COUNT_OFFSET, state.springs.size())
	var cursor := COUNT_OFFSET + 4
	for ball: Dictionary in state.springs:
		for field: String in SPRING_FIELDS:
			bytes.encode_s64(cursor, ball[field])
			cursor += 8
	bytes.encode_u32(cursor, state.enemies.size())
	cursor += 4
	for enemy: Dictionary in state.enemies:
		for field: String in State.ENEMY_FIELDS:
			bytes.encode_s64(cursor, enemy[field])
			cursor += 8
	bytes.append_array(checksum(bytes))
	return bytes


static func decode(bytes: PackedByteArray, identity: String) -> Dictionary:
	if bytes.size() < 12:
		return {"ok": false, "error": "Snapshot size/truncation"}
	if bytes.slice(0, 8).get_string_from_ascii() != "EGGSTATE" or bytes.decode_u32(8) != VERSION:
		return {"ok": false, "error": "Snapshot format/version"}
	if bytes.size() < MIN_SIZE:
		return {"ok": false, "error": "Snapshot size/truncation"}
	var count := bytes.decode_u32(COUNT_OFFSET)
	var enemy_offset := COUNT_OFFSET + 4 + count * SPRING_FIELDS.size() * 8
	if enemy_offset + 4 + 32 > bytes.size():
		return {"ok": false, "error": "Snapshot spring count/size"}
	var enemy_count := bytes.decode_u32(enemy_offset)
	if bytes.size() != enemy_offset + 4 + enemy_count * State.ENEMY_FIELDS.size() * 8 + 32:
		return {"ok": false, "error": "Snapshot enemy count/size"}
	if bytes.slice(-32) != checksum(bytes.slice(0, -32)):
		return {"ok": false, "error": "Snapshot checksum"}
	if bytes.slice(12, 44).hex_encode() != identity:
		return {"ok": false, "error": "Snapshot level identity"}
	var state := {"identity": identity, "springs": [], "enemies": []}
	for index in State.FIELDS.size():
		state[State.FIELDS[index]] = bytes.decode_s64(HEADER + index * 8)
	if not valid_player(state):
		return {"ok": false, "error": "Snapshot invalid state"}
	var cursor := COUNT_OFFSET + 4
	for index in count:
		var ball := {}
		for field: String in SPRING_FIELDS:
			ball[field] = bytes.decode_s64(cursor)
			cursor += 8
		if (
			ball.vx != 0
			or ball.vy < 0
			or ball.vy > 704 * 60
			or ball.squash < 0
			or ball.squash > 12
			or ball.active not in [0, 1]
		):
			return {"ok": false, "error": "Snapshot invalid spring"}
		state.springs.append(ball)
	cursor += 4
	for index in enemy_count:
		var enemy := {}
		for field: String in State.ENEMY_FIELDS:
			enemy[field] = bytes.decode_s64(cursor)
			cursor += 8
		if not valid_enemy(enemy):
			return {"ok": false, "error": "Snapshot invalid enemy"}
		state.enemies.append(enemy)
	if state.captured_by > enemy_count:
		return {"ok": false, "error": "Snapshot invalid capture"}
	if state.captured_by:
		var captor: Dictionary = state.enemies[state.captured_by - 1]
		if captor.status != 1 or captor.mode != 4:
			return {"ok": false, "error": "Snapshot invalid capture state"}
	return {"ok": true, "state": state}


static func valid_player(state: Dictionary) -> bool:
	return not (
		state.frame < 0
		or state.deaths < 0
		or state.movement < 0
		or state.movement > 6
		or state.facing not in [-1, 1]
		or state.on_floor not in [0, 1]
		or state.goal_reached not in [0, 1]
		or state.previous_input < 0
		or state.previous_input > 15
		or state.jump_buffer < 0
		or state.jump_buffer > 5
		or state.flutter_remaining < 0
		or state.flutter_remaining > 50
		or state.flutter_cooldown < 0
		or state.flutter_cooldown > 16
		or state.flutter_ready not in [0, 1]
		or state.support_bridge < 0
		or state.swimming not in [0, 1]
		or state.water_wait < 0
		or state.water_wait > 15
		or state.water_phase < 0
		or state.water_phase >= 60
		or state.water_deep not in [0, 1]
		or state.boosted_flutter not in [0, 1]
		or state.hurt < 0
		or state.hurt > 60
		or state.invulnerable < 0
		or state.invulnerable > 120
		or state.health < 1
		or state.health > 30
		or state.health_wait < 0
		or state.health_wait > 120
		or state.separated not in [0, 1]
		or state.recovery_delay < 0
		or state.recovery_delay > 36
		or state.hits < 0
		or state.captured_by < 0
		or state.rng < 0
		or state.rng > 0x7fffffff
		or state.hurt_deceleration not in [0, 648, 1296]
		or (state.hurt > 0 and state.hurt_deceleration == 0)
		or (state.health_wait == 0 and (state.separated == 1 or state.health < 10))
		or (state.flutter_remaining > 40 and state.boosted_flutter == 0)
	)


static func valid_enemy(enemy: Dictionary) -> bool:
	return not (
		enemy.status < 0
		or enemy.status > 3
		or enemy.facing not in [-1, 1]
		or enemy.phase < 0
		or enemy.phase > 360
		or enemy.timer < 0
		or enemy.timer > 210
		or enemy.cycles < -1
		or enemy.cycles > 180
		or enemy.mode < 0
		or enemy.mode > 5
		or enemy.water not in [0, 1]
		or enemy.contact not in [0, 1]
		or enemy.offscreen not in [0, 1]
		or absi(enemy.head_dx) > 3600
		or absi(enemy.head_dy) > 3600
		or enemy.head_size < 0
		or enemy.head_size > 15
		or enemy.pin_size < 0
		or enemy.pin_size > 15
		or (enemy.mode == 4 and enemy.pin_size > enemy.head_size)
		or enemy.rise_ticks < 0
		or enemy.rise_ticks > 60
		or enemy.rise_velocity < 0
		or enemy.rise_velocity > 704 * 60
		or absi(enemy.vx) > 128 * 60
		or enemy.vy < -944 * 60
		or enemy.vy > 704 * 60
	)


static func checksum(bytes: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish()
