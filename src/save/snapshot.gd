class_name Snapshot
extends RefCounted
## Canonical little-endian int64 fields and UTF-8 codes; never Variant decoding.

const State = preload("res://src/sim/play_state.gd")
const Registry = preload("res://src/sim/registry.gd")
const Maps = preload("res://src/sim/maps.gd")
const VERSION := 5
const HEADER := 76
const CHECKSUM_SIZE := 32
const MAX_ENTITIES := 100_000
const MAX_CODE_BYTES := 4096
const MAX_BYTES := 67_108_864


static func count_offset() -> int:
	return HEADER + State.fields().size() * 8


static func minimum_size() -> int:
	return count_offset() + 4 + CHECKSUM_SIZE


static func schema_hash() -> PackedByteArray:
	var schema := [
		"code-and-id-utf8", State.level_fields(), State.player_fields(), Registry.COMMON_FIELDS
	]
	for code: String in Registry.codes():
		schema.append([code, Registry.fields(code)])
	return checksum(JSON.stringify(schema).to_utf8_buffer())


static func encode(state: Dictionary) -> PackedByteArray:
	if not valid_state(state) or not valid_identity(state.get("identity", "")):
		push_warning("Cannot encode invalid snapshot state")
		return PackedByteArray()
	var body_size := count_offset() + 4
	for entity: Dictionary in state.entities:
		var code_bytes: PackedByteArray = entity.code.to_utf8_buffer()
		var id_bytes: PackedByteArray = entity.id.to_utf8_buffer()
		if code_bytes.size() > MAX_CODE_BYTES or id_bytes.size() > MAX_CODE_BYTES:
			push_warning("Cannot encode oversized entity code or id")
			return PackedByteArray()
		body_size += (
			12 + code_bytes.size() + id_bytes.size() + Registry.fields(entity.code).size() * 8
		)
	if body_size + CHECKSUM_SIZE > MAX_BYTES:
		push_warning("Cannot encode oversized snapshot")
		return PackedByteArray()
	var bytes := PackedByteArray()
	bytes.resize(body_size)
	var magic := "EGGSTATE".to_ascii_buffer()
	for index in magic.size():
		bytes[index] = magic[index]
	bytes.encode_u32(8, VERSION)
	var identity: PackedByteArray = state.identity.hex_decode()
	var schema := schema_hash()
	for index in 32:
		bytes[12 + index] = identity[index]
		bytes[44 + index] = schema[index]
	var cursor := HEADER
	for pair: Array in State.fields():
		bytes.encode_s64(cursor, state[pair[0]])
		cursor += 8
	bytes.encode_u32(cursor, state.entities.size())
	cursor += 4
	for entity: Dictionary in state.entities:
		for text: String in [entity.code, entity.id]:
			var encoded := text.to_utf8_buffer()
			bytes.encode_u32(cursor, encoded.size())
			cursor += 4
			for value: int in encoded:
				bytes[cursor] = value
				cursor += 1
		var fields := Registry.fields(entity.code)
		bytes.encode_u32(cursor, fields.size())
		cursor += 4
		for pair: Array in fields:
			bytes.encode_s64(cursor, entity[pair[0]])
			cursor += 8
	bytes.append_array(checksum(bytes))
	return bytes


static func decode(bytes: PackedByteArray, identity: String, world: Dictionary = {}) -> Dictionary:
	if bytes.size() < 12:
		return error("Snapshot size/truncation")
	if bytes.slice(0, 8).get_string_from_ascii() != "EGGSTATE":
		return error("Snapshot format")
	var version := bytes.decode_u32(8)
	if version != VERSION:
		print("Ignoring snapshot version %d; expected %d" % [version, VERSION])
		return error("Snapshot format/version")
	if bytes.size() < minimum_size() or bytes.size() > MAX_BYTES:
		return error("Snapshot size/truncation")
	var end := bytes.size() - CHECKSUM_SIZE
	if bytes.slice(end) != checksum(bytes.slice(0, end)):
		return error("Snapshot checksum")
	if not valid_identity(identity) or bytes.slice(12, 44).hex_encode() != identity:
		return error("Snapshot level identity")
	if bytes.slice(44, HEADER) != schema_hash():
		return error("Snapshot schema")
	var state := {"identity": identity, "entities": []}
	var cursor := HEADER
	for pair: Array in State.fields():
		state[pair[0]] = bytes.decode_s64(cursor)
		cursor += 8
	var count := bytes.decode_u32(cursor)
	cursor += 4
	if count > MAX_ENTITIES:
		return error("Snapshot entity count")
	for index in count:
		var code_result := read_text(bytes, cursor, end)
		if not code_result.ok:
			return code_result
		cursor = code_result.cursor
		var id_result := read_text(bytes, cursor, end)
		if not id_result.ok:
			return id_result
		cursor = id_result.cursor
		if cursor + 4 > end:
			return error("Snapshot entity schema/truncation")
		var code: String = code_result.value
		var fields := Registry.fields(code)
		if bytes.decode_u32(cursor) != fields.size():
			return error("Snapshot entity schema")
		cursor += 4
		if fields.size() * 8 > end - cursor:
			return error("Snapshot entity fields/truncation")
		var entity := {"code": code, "id": id_result.value}
		for pair: Array in fields:
			entity[pair[0]] = bytes.decode_s64(cursor)
			cursor += 8
		state.entities.append(entity)
	if cursor != end:
		return error("Snapshot trailing bytes/count")
	Registry.attach_views(state, false)
	if not valid_state(state):
		return error("Snapshot invalid state")
	if not world.is_empty():
		# Validate against the saved map without changing the caller's world on rejection.
		var selected := world.duplicate()
		if not Maps.sync(state, selected) or not Registry.valid_world(state, selected):
			return error("Snapshot world entity table")
		if state.support_bridge > selected.bridges.size():
			return error("Snapshot world support")
		Maps.sync(state, world)
	return {"ok": true, "state": state}


static func read_text(bytes: PackedByteArray, cursor: int, end: int) -> Dictionary:
	if cursor + 4 > end:
		return error("Snapshot entity string/truncation")
	var size := bytes.decode_u32(cursor)
	cursor += 4
	if size > MAX_CODE_BYTES or size > end - cursor:
		return error("Snapshot entity string/size")
	var encoded := bytes.slice(cursor, cursor + size)
	var text := encoded.get_string_from_utf8()
	if text.to_utf8_buffer() != encoded:
		return error("Snapshot entity string encoding")
	return {"ok": true, "value": text, "cursor": cursor + size}


static func valid_identity(identity: Variant) -> bool:
	return (
		identity is String
		and identity.length() == 64
		and identity.is_valid_hex_number()
		and identity.to_lower() == identity
	)


static func valid_state(state: Dictionary) -> bool:
	if (
		not State.valid(state)
		or not state.get("entities") is Array
		or state.entities.size() > MAX_ENTITIES
		or not Registry.valid_table(state)
	):
		return false
	var actors := []
	var ids := {}
	var pads := 0
	for index in state.entities.size():
		var entity: Variant = state.entities[index]
		if not entity is Dictionary or not Registry.valid(entity):
			return false
		if ids.has(entity.id):
			return false
		ids[entity.id] = true
		if entity.map_index != state.get("map_index", 0):
			return false
		if Registry.is_enemy(entity.code):
			if entity.family_index != actors.size():
				return false
			actors.append(entity)
		elif entity.code == "o11":
			if entity.family_index != pads:
				return false
			pads += 1
	if state.captured_by > actors.size():
		return false
	if state.captured_by:
		var captor: Dictionary = actors[state.captured_by - 1]
		if captor.code != "e5" or captor.status != 1 or captor.mode != 4:
			return false
	return true


static func error(message: String) -> Dictionary:
	return {"ok": false, "error": message}


static func checksum(bytes: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish()
