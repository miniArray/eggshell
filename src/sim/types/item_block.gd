extends RefCounted
## Full solids with source-specific bump, link and message transitions.

const CODES := ["o9", "o15", "o18", "o24"]
const SOLID := 1
const S := preload("res://src/sim/units.gd").SCALE
const Life = preload("res://src/sim/life.gd")
const Moves = preload("res://src/sim/moves.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Hits = preload("res://src/sim/hits.gd")
const Collision = preload("res://src/sim/collision.gd")
const Screen = preload("res://src/sim/screen.gd")
const FIELDS := [
	["home_x", 0],
	["home_y", 0],
	["busy", 0],
	["bump_direction", 1],
	["enabled", 1],
	["solid_ready", 1],
	["charges", 3],
	["height", 32 * S],
	["height_from", 32 * S]
]
const LEVEL_FIELDS := [
	["message_stage", 0],
	["message_ticks", 0],
	["message_section", 0],
	["message_scroll", 0],
	["message_previous", 0]
]
const CLOSED := 0
const OPENING := 1
const READING := 2
const CLOSING := 3


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	if source.code == "o15":
		var value: Variant = source.properties.get("F", 0)
		if not (value is int or value is float) or not is_finite(value) or value != floor(value):
			return {"ok": false, "error": "Invalid linked block form"}
	if source.code == "o18" and not source.properties.get("E1", "") is String:
		return {"ok": false, "error": "Invalid message text"}
	if source.code == "o24":
		source.y -= 32 * S
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var enabled := int(source.code != "o15" or source.get("variant", 0) == 1)
	var height := (56 if source.code == "o24" else 32) * S
	return {
		"home_x": int(source.x),
		"home_y": int(source.y),
		"enabled": enabled,
		"solid_ready": enabled,
		"height": height,
		"height_from": height
	}


static func bounds(entity: Dictionary) -> Array:
	return (
		[-28 * S, 0, 28 * S, entity.height]
		if entity.code == "o24"
		else [-16 * S, -16 * S, 16 * S, 16 * S]
	)


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1 or entity.collected or not entity.enabled or not entity.solid_ready:
		return []
	var box := bounds(entity)
	return [entity.x + box[0], entity.y + box[1], entity.x + box[2], entity.y + box[3]]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.code == "o15" and entity.enabled and not entity.solid_ready:
		entity.solid_ready = int(not overlaps_player(entity, state))
	if not entity.busy:
		return
	entity.busy -= 1
	if entity.code == "o9":
		var offset := mini(12 - entity.busy, entity.busy)
		entity.x = entity.home_x + entity.bump_direction * 8 * S * offset / 6
		entity.y = entity.home_y - 32 * S * offset / 6
		if entity.busy == 6:
			var eggs: Script = registry().lookup("o7")
			if eggs.has_method("active_count") and eggs.active_count(state, world) < 6:
				(
					registry()
					. spawn_dynamic(
						state,
						world,
						"o7",
						entity.x,
						entity.y - 16 * S,
						{
							"vx":
							entity.bump_direction * Motion.random_ticks(state, 128 * 60, 192 * 60),
							"vy": -256 * 60,
						}
					)
				)
	elif entity.code == "o24":
		var target: int = [0, 22, 34, 56][entity.charges] * S
		entity.height = entity.height_from + (target - entity.height_from) * (6 - entity.busy) / 6
		if not entity.busy and not entity.charges:
			entity.status = 3


static func bump(entity: Dictionary, state: Dictionary, world: Dictionary, side: int) -> void:
	if (
		side != 0
		or entity.busy
		or entity.collected
		or not entity.enabled
		or Life.blocks_step(state)
	):
		return
	match entity.code:
		"o9":
			bump_above(entity, state, world)
			entity.busy = 12
			entity.bump_direction = 1 if state.x < entity.x else -1
		"o18":
			open_message(entity, state, world)
		"o24":
			if entity.charges:
				bump_above(entity, state, world)
				clear_area(state, world)
				entity.charges -= 1
				entity.height_from = entity.height
				entity.busy = 6


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, _from_x: int
) -> void:
	if entity.code == "o18" and kind == Hits.EGG and not entity.busy:
		open_message(entity, state, world)


static func projectile_contact(
	entity: Dictionary, _projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if entity.code == "o18" and entity.enabled and not entity.busy and not state.modal_token:
		open_message(entity, state, world)
		return 1
	return 3 if not solid_box(entity).is_empty() else 0


static func view_state(entity: Dictionary, state: Dictionary) -> Dictionary:
	var result := {"visible": entity.status == 1 and not entity.collected}
	if entity.code == "o15":
		# Literal pack names select the linked solid and outline forms.
		result.animation = "On" if entity.enabled else "Off"
	elif entity.code == "o24":
		result.size_x = 64.0
		result.size_y = entity.height / float(S)
	elif entity.code == "o18" and state.modal_token == entity.token:
		result.frame = 0
		var lift := maxi(0, mini(78 - state.message_ticks, state.message_ticks - 42))
		result.offset_y = -80.0 * lift / 18.0 if state.message_stage == OPENING else 0.0
	return result


static func open_message(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if state.modal_token or entity.busy or Life.blocks_step(state):
		return
	bump_above(entity, state, world)
	# The block stays solid for the rest of this step, so the head bump that opened it
	# stops the player like any ceiling. consume_level_requests disables it at step end.
	state.modal_token = entity.token
	state.message_stage = OPENING
	state.message_ticks = 78
	state.message_section = 0
	state.message_scroll = 0
	state.message_previous = state.previous_input


static func consume_level_requests(state: Dictionary, world: Dictionary) -> void:
	if state.message_stage != OPENING or state.message_ticks != 78:
		return
	var entity: Dictionary = registry().find_token(state, state.modal_token)
	if entity.is_empty() or entity.code != "o18" or not entity.enabled:
		return
	entity.enabled = 0
	entity.solid_ready = 0
	Collision.refresh(world, entity)


static func toggle(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	if entity.code == "o15":
		entity.enabled = 1 - entity.enabled
		entity.solid_ready = int(entity.enabled and not overlaps_player(entity, state))


static func overlaps_player(entity: Dictionary, state: Dictionary) -> bool:
	var box := Moves.player_box(state)
	return registry().overlaps_box(
		entity,
		registry().lookup(entity.code),
		[state.x + box[0], state.y + box[1], state.x + box[2], state.y + box[3]]
	)


static func bump_above(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var box := bounds(entity)
	var probe := [
		entity.x + box[0], entity.y + box[1] - 8 * S, entity.x + box[2], entity.y + box[3] - 8 * S
	]
	var dispatch := registry()
	for other: Dictionary in state.entities:
		var type: Script = dispatch.lookup(other.code)
		if (
			other.token == entity.token
			or other.status != 1
			or other.get("held", 0) == 1
			or other.get("hidden", 0) == 1
		):
			continue
		if type.has_method("hit") and dispatch.overlaps_box(other, type, probe):
			type.hit(other, state, world, Hits.BUMP, entity.x)
			Collision.refresh(world, other)


static func clear_area(state: Dictionary, world: Dictionary) -> void:
	var probe := Screen.area(state, world)
	var dispatch := registry()
	for entity: Dictionary in state.entities:
		var type: Script = dispatch.lookup(entity.code)
		if entity.status != 1 or entity.get("held", 0) == 1 or entity.get("hidden", 0) == 1:
			continue
		if type.has_method("hit") and dispatch.overlaps_box(entity, type, probe):
			type.hit(entity, state, world, Hits.CLEAR, state.x)
			Collision.refresh(world, entity)


static func reset_map(state: Dictionary, _world: Dictionary) -> void:
	for pair: Array in LEVEL_FIELDS:
		state[pair[0]] = pair[1]


static func modal_step(
	entity: Dictionary, state: Dictionary, world: Dictionary, input: int
) -> bool:
	if not state.modal_token or entity.code != "o18":
		return false
	if state.message_stage == OPENING and entity.enabled:
		# A message opened outside a step had no step-end request pass to disable the block.
		entity.enabled = 0
		entity.solid_ready = 0
		Collision.refresh(world, entity)
	var pressed: int = input & ~state.message_previous
	state.message_previous = input
	state.previous_input = input
	state.pressed_input = 0
	if state.message_ticks:
		state.message_ticks -= 1
		if not state.message_ticks:
			if state.message_stage == OPENING:
				state.message_stage = READING
			elif state.message_stage == CLOSING:
				entity.enabled = 1
				entity.solid_ready = 1
				entity.busy = 20
				reset_map(state, world)
				state.modal_token = 0
				return false
		return true
	if state.message_scroll:
		state.message_scroll -= 1
	if state.message_stage == READING:
		var sections: int = message_state(state, world).sections
		if (
			pressed & InputBits.THROW
			or pressed & InputBits.DOWN and state.message_section >= sections - 1
		):
			state.message_stage = CLOSING
			state.message_ticks = 30
		elif not state.message_scroll and pressed & InputBits.DOWN:
			state.message_section += 1
			state.message_scroll = 48
		elif not state.message_scroll and pressed & InputBits.UP and state.message_section:
			state.message_section -= 1
			state.message_scroll = 48
	return true


static func message(state: Dictionary, world: Dictionary) -> String:
	var entity: Dictionary = registry().find_token(state, state.get("modal_token", 0))
	if (
		entity.is_empty()
		or entity.code != "o18"
		or entity.source_index < 0
		or entity.source_index >= world.entities.size()
	):
		return ""
	return world.entities[entity.source_index].properties.get("E1", "")


static func message_state(state: Dictionary, world: Dictionary) -> Dictionary:
	if state.message_stage == CLOSED:
		return {}
	var text := message(state, world)
	return {
		"text": text,
		"stage": state.message_stage,
		"ticks": state.message_ticks,
		"section": state.message_section,
		"sections": maxi(1, (text_rows(text) * 20 + 167) / 168),
		"scroll_ticks": state.message_scroll
	}


static func text_rows(text: String) -> int:
	# Message paging uses a fixed reference width, never a viewport or a pack font.
	var rows := 1
	var width := 0
	for line: String in text.split("\n"):
		if width < 0:
			rows += 1
		width = 0
		for word: String in line.split(" "):
			var size := 0
			for character: String in word:
				size += glyph_width(character)
			if width and width + 16 + size > 304:
				rows += 1
				width = 0
			elif width:
				width += 16
			width += size
			while width > 304:
				rows += 1
				width -= 304
		width = -1
	return rows


static func glyph_width(character: String) -> int:
	if character in ".,;:'|":
		return 6
	if character in 'Ii$()[]\\/"°{}²³':
		return 12
	if character in "1=<>§":
		return 14
	return 16


static func valid(entity: Dictionary) -> bool:
	return (
		entity.busy >= 0
		and entity.busy <= 20
		and entity.bump_direction in [-1, 1]
		and entity.enabled in [0, 1]
		and entity.solid_ready in [0, 1]
		and entity.charges >= 0
		and entity.charges <= 3
		and entity.height >= 0
		and entity.height <= 56 * S
		and entity.height_from >= 0
		and entity.height_from <= 56 * S
	)


static func valid_state(state: Dictionary) -> bool:
	for pair: Array in LEVEL_FIELDS:
		if not state.get(pair[0]) is int:
			return false
	if (
		state.modal_token < 0
		or state.message_stage < CLOSED
		or state.message_stage > CLOSING
		or state.message_ticks < 0
		or state.message_ticks > 78
		or state.message_section < 0
		or state.message_scroll < 0
		or state.message_scroll > 48
		or state.message_previous < 0
		or state.message_previous & ~InputBits.MASK != 0
	):
		return false
	var entity: Dictionary = registry().find_token(state, state.modal_token)
	if state.message_stage != CLOSED:
		return (
			not entity.is_empty()
			and entity.code == "o18"
			and (
				not entity.enabled and not entity.solid_ready
				# Opened in this step: the block stays solid until the step ends.
				or state.message_stage == OPENING and state.message_ticks == 78
			)
			and not entity.collected
			and (
				state.message_stage == READING and state.message_ticks == 0
				or state.message_stage in [OPENING, CLOSING] and state.message_ticks > 0
			)
		)
	if not entity.is_empty() and entity.code in CODES:
		return false
	return (
		state.message_stage == CLOSED
		and not state.message_ticks
		and not state.message_section
		and not state.message_scroll
	)
