extends RefCounted
## Grouped switch blocks and the blocks they toggle. A strike from below or a
## thrown object on a switch flips every block and switch of its group: solid
## blocks become passable outlines and outlines become solid once the player has
## left them. The struck switch lifts briefly and pops bodies above it.

const S := preload("res://src/sim/units.gd").SCALE
const Hits = preload("res://src/sim/hits.gd")
const Moves = preload("res://src/sim/moves.gd")
const Near = preload("res://src/sim/types/near_query.gd")
const CODES := ["o33", "o34"]
const SOLID := 1
const CONTACT_PHASE := -1
const FIELDS := [["group", 0], ["on", 0], ["solid_ready", 1], ["home_y", 0], ["busy", 0]]
const BUMP_TICKS := 12  # 0.1 s up and 0.1 s back.
const LIFT := 32 * S
const MAX_GROUP := 1_000_000


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var raw: Variant = source.properties.get("E4", "0")
	var parsed: Dictionary = registry().numeric_option(
		"0" if raw is String and raw.strip_edges() == "" else raw
	)
	if not parsed.ok:
		return {"ok": false, "error": "Invalid dice group"}
	if absf(parsed.value) > MAX_GROUP:
		return {"ok": false, "degrade": true, "error": "dice group E4 out of range"}
	source.group = int(parsed.value)
	if source.code == "o34":
		var form: Variant = source.properties.get("F", 0)
		if not (form is int or form is float) or not is_finite(form) or form != floor(form):
			return {"ok": false, "error": "Invalid dice block form"}
		if form < 0 or form > 1:
			return {"ok": false, "degrade": true, "error": "dice block form F=%s" % str(form)}
		source.dice_on = int(form == 0)
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var on := int(source.get("dice_on", 0))
	return {"group": int(source.group), "on": on, "solid_ready": 1 - on, "home_y": int(source.y)}


static func bounds(_entity: Dictionary) -> Array:
	return [-16 * S, -16 * S, 16 * S, 16 * S]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1 or (entity.code == "o34" and (entity.on or not entity.solid_ready)):
		return []
	return [entity.x - 16 * S, entity.y - 16 * S, entity.x + 16 * S, entity.y + 16 * S]


static func step(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	if entity.code == "o34":
		if not entity.on and not entity.solid_ready:
			entity.solid_ready = int(not overlaps_player(entity, state))
		return
	if entity.busy:
		entity.busy -= 1
		var offset := mini(BUMP_TICKS - entity.busy, entity.busy)
		entity.y = entity.home_y - LIFT * offset / (BUMP_TICKS / 2)


static func overlaps_player(entity: Dictionary, state: Dictionary) -> bool:
	var box := Moves.player_box(state)
	return registry().overlaps_box(
		entity,
		registry().lookup(entity.code),
		[state.x + box[0], state.y + box[1], state.x + box[2], state.y + box[3]]
	)


static func bump(entity: Dictionary, state: Dictionary, world: Dictionary, side: int) -> void:
	if side == 0 and entity.code == "o33":
		trigger(entity, state, world)


static func projectile_contact(
	entity: Dictionary, _projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if solid_box(entity).is_empty():
		return 0
	if entity.code == "o34" or entity.busy:
		return 3
	trigger(entity, state, world)
	return 1


static func trigger(entity: Dictionary, state: Dictionary, world: Dictionary) -> bool:
	if entity.code != "o33" or entity.busy or entity.status != 1:
		return false
	for other: Dictionary in state.entities:
		if other.code in CODES and other.group == entity.group:
			other.on = 1 - other.on
			if other.code == "o34":
				other.solid_ready = int(not other.on and not overlaps_player(other, state))
	entity.busy = BUMP_TICKS
	var probe := [entity.x - 16 * S, entity.y - 24 * S, entity.x + 16 * S, entity.y + 8 * S]
	Near.strike(state, world, probe, Hits.BUMP, entity.x, entity.token)
	return true


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	if entity.code == "o34":
		return {"visible": entity.status == 1, "animation": str(1 - entity.on)}
	return {"visible": entity.status == 1, "frame": entity.on}


static func valid(entity: Dictionary) -> bool:
	return (
		absi(entity.group) <= MAX_GROUP
		and entity.on in [0, 1]
		and entity.solid_ready in [0, 1]
		and entity.busy >= 0
		and entity.busy <= BUMP_TICKS
		and entity.y <= entity.home_y
		and entity.y >= entity.home_y - LIFT
	)
