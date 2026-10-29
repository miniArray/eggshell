extends RefCounted
## Floating hidden/revealed caches release typed items after a hit animation.
const CODES := ["o8"]
const S := preload("res://src/sim/units.gd").SCALE
const Collision = preload("res://src/sim/collision.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const Elements = preload("res://src/sim/elements.gd")
const Screen = preload("res://src/sim/screen.gd")
## Fire and ice breath opens the cloud at once, even while it is hidden.
const ELEMENT_REACTIONS := Elements.OPENS
const FIELDS := [
	["content", 0], ["count", 0], ["phase", 1], ["age", 0], ["home_y", 0], ["release_failures", 0]
]
const HIDDEN := 0
const VISIBLE := 1
const REVEALED := 2
const OPENING := 3
const MAX_RELEASE := 1024
const FLAP := [0, 1, 2, 3, 2, 1]
## The original creates the cache at level load and its wave runs through the level
## intro. It has run 151 steps when the level-start world tick runs it once more.
const INTRO_PHASE := Motion.LEVEL_INTRO_TICKS - 1


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var registry: Script = load("res://src/sim/registry.gd")
	var values := []
	for key: String in ["E1", "E2"]:
		var raw: Variant = source.properties.get(key, "0")
		var parsed: Dictionary = registry.numeric_option(
			"0" if raw is String and raw == "" else raw
		)
		if not parsed.ok:
			return {"ok": false, "error": "Invalid cache option: " + key}
		values.append(int(parsed.value))
	if values[0] < 0 or not source.properties.get("E3", "") is String:
		return {"ok": false, "error": "Invalid cache contents or hidden flag"}
	if values[0] > 4 or values[1] > MAX_RELEASE:
		return {
			"ok": false,
			"degrade": true,
			"error": "cache contents E1=%d or count E2=%d" % [values[0], values[1]]
		}
	source.cache_content = values[0]
	source.cache_count = maxi(0, values[1])
	source.cache_phase = HIDDEN if source.properties.get("E3", "") == "1" else VISIBLE
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {
		"content": int(source.cache_content),
		"count": int(source.cache_count),
		"phase": int(source.cache_phase),
		"age": INTRO_PHASE,
		"home_y": int(source.y)
	}


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.status != 1:
		return
	if entity.collected:
		entity.status = 3
		return
	if entity.phase == OPENING:
		entity.age = mini(30, entity.age + 1)
		if entity.age == 30:
			_release(entity, state, world)
		return
	entity.age = (entity.age + 1) % 180
	entity.y = entity.home_y + Motion.sine(entity.age, 180, 16 * S)
	if entity.phase == REVEALED and not _on_screen(entity, state, world):
		entity.phase = HIDDEN


static func bounds(entity: Dictionary) -> Array:
	if entity.phase == OPENING:
		return [-16 * S, -16 * S, 16 * S, 16 * S]
	var frame := _frame(entity)
	return [
		-16 * S, [-18 * S, -57257, -14 * S, -12 * S][frame], 16 * S, [14, 16, 18, 20][frame] * S
	]


static func _frame(entity: Dictionary) -> int:
	return FLAP[entity.age * 16 / 60 % FLAP.size()]


static func _on_screen(entity: Dictionary, state: Dictionary, world: Dictionary) -> bool:
	var frame := _frame(entity)
	var half: int = [30, 36, 42, 34][frame] * S
	var top: int = [28, 18, 14, 12][frame] * S
	var bottom: int = [14, 16, 18, 26][frame] * S
	var screen := Screen.area(state, world)
	return (
		entity.x + half >= screen[0]
		and entity.x - half <= screen[2]
		and entity.y + bottom >= screen[1]
		and entity.y - top <= screen[3]
	)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if entity.status != 1 or entity.phase != HIDDEN or entity.collected:
		return
	var a := Moves.player_box(state)
	var b := bounds(entity)
	if (
		state.x + a[2] >= entity.x + b[0]
		and state.x + a[0] <= entity.x + b[2]
		and state.y + a[3] >= entity.y + b[1]
		and state.y + a[1] <= entity.y + b[3]
	):
		entity.phase = REVEALED


static func hit(
	entity: Dictionary, _state: Dictionary, _world: Dictionary, kind: int, _from_x: int
) -> void:
	if (
		kind not in [1, 3, 5, Hits.FIRE, Hits.ICE]
		or entity.status != 1
		or entity.collected
		or entity.phase == OPENING
	):
		return
	if entity.phase == HIDDEN and kind not in [Hits.FIRE, Hits.ICE]:
		entity.phase = REVEALED
	else:
		entity.phase = OPENING
		entity.age = 0


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if projectile.mode != 1 or entity.status != 1 or entity.collected or entity.phase == OPENING:
		return 0
	hit(entity, state, world, 1, projectile.get("x", entity.x))
	return 1


static func tongue(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> int:
	return 0


static func _release(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var registry := Collision.registry_for(world)
	entity.release_failures = 0
	var count: int = entity.count if entity.content in [1, 2] else int(entity.content in [3, 4])
	for index in count:
		var code := ""
		var options := {"layer": int(entity.layer)}
		if entity.content == 1 or entity.content == 2 and state.health + index + 1 > 30:
			code = "o1"
			options.merge(
				{
					"moving": 1,
					"vx": Motion.random_ticks(state, -192 * 60, 192 * 60),
					"vy": Motion.random_ticks(state, -768 * 60, -512 * 60),
					"despawn_ticks": 480,
					"pickup_delay": 0
				}
			)
		elif entity.content == 2:
			code = "o4"
			options.merge(
				{
					"vy": Motion.random_ticks(state, -512 * 60, -256 * 60),
					"facing": 1 if Motion.random_ticks(state, -1000000, 1000000) > 0 else -1,
					"max_speed": Motion.random_ticks(state, 64 * 60, 128 * 60),
					"despawn_ticks": 480,
					"pickup_delay": 0
				}
			)
		elif entity.content == 3:
			code = "o3"
			options.origin_token = int(entity.token)
		elif entity.content == 4:
			code = "o14"
		var spawned: Dictionary = (
			registry.spawn_dynamic(state, world, code, entity.x, entity.y, options)
			if registry != null
			else {}
		)
		if spawned.is_empty():
			entity.release_failures += 1
	entity.status = 3
	# A missing provider must not turn a failed release into a permanent collected flag.
	if entity.content != 3 and entity.release_failures == 0:
		entity.collected = 1


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var result := {
		"visible": entity.status == 1 and entity.phase != HIDDEN and not entity.collected,
		"modulate_alpha": 0.5 if entity.phase == REVEALED else 1.0
	}
	if entity.phase == OPENING:
		var size := 32.0 + 16.0 * minf(entity.age, 18) / 18.0
		result.merge({"animation": "Wingless", "frame": 0, "size_x": size, "size_y": size})
	else:
		result.merge({"animation": "Default", "frame": _frame(entity)})
	return result


static func valid(entity: Dictionary) -> bool:
	return (
		entity.content >= 0
		and entity.content <= 4
		and entity.count >= 0
		and entity.count <= MAX_RELEASE
		and entity.phase >= HIDDEN
		and entity.phase <= OPENING
		and entity.age >= 0
		and entity.age <= (30 if entity.phase == OPENING else 179)
		and entity.release_failures >= 0
		and entity.release_failures <= MAX_RELEASE
	)
