extends RefCounted
## A flower that swallows one spat-out body dropped into its cup, then releases a number of
## health pickups (coins once health is full) and wilts. Thrown eggs bounce off it.

const Body = preload("res://src/sim/enemy_body.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Near = preload("res://src/sim/types/near_query.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["o22"]
const STEP_PHASE := 0
const CONTACT_PHASE := -1
const OPEN := 0
const FED := 1
const CLOSING := 2
const OPENING := 3
const RELEASED := 4
const WILTING := 5
const FED_TICKS := 60
const CLOSE_TICKS := 15
const OPEN_TICKS := 3
const RELEASE_TICKS := 18
const WILT_TICKS := 120
const MAX_STARS := 1000
# Cup sensor: 56 x 56 around a point 22 px below the flower centre, bottom-heavy.
const CUP := [-28 * S, -26 * S, 28 * S, 30 * S]
const FIELDS := [["phase", OPEN], ["timer", 0], ["stars", 8], ["cup_y", 0]]


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var raw: Variant = source.properties.get("E1", "8")
	var stars := 0
	if raw is String:
		var text: String = raw.strip_edges()
		var digits := ""
		for index in text.length():
			if text[index].is_valid_int() or (index == 0 and text[index] == "-"):
				digits += text[index]
			else:
				break
		stars = digits.to_int() if digits.is_valid_int() else 0
	elif (raw is int or raw is float) and is_finite(raw):
		stars = int(raw)
	else:
		return {"ok": false, "error": "Invalid flower star count"}
	if stars > MAX_STARS:
		return {"ok": false, "degrade": true, "error": "Unsupported flower star count"}
	source.stars = maxi(0, stars)
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"stars": int(source.get("stars", 8)), "status": 0, "spawn_mode": 1, "can_despawn": 1}


static func bounds(_entity: Dictionary) -> Array:
	return [-32 * S, -32 * S, 32 * S, 32 * S]


static func cup(entity: Dictionary) -> Array:
	return [entity.x + CUP[0], entity.y + CUP[1], entity.x + CUP[2], entity.y + CUP[3]]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.phase == OPEN:
		if entity.collected:
			# A flower already fed before the last reset does not come back.
			entity.status = 3
			return
		_swallow(entity, state, world)
		return
	if entity.timer > 0:
		entity.timer -= 1
		if entity.timer > 0:
			return
	match entity.phase:
		FED, RELEASED:
			if entity.phase == RELEASED and entity.stars <= 0:
				entity.phase = WILTING
				entity.timer = WILT_TICKS
			else:
				entity.phase = CLOSING
				entity.timer = CLOSE_TICKS
		CLOSING:
			entity.phase = OPENING
			entity.timer = OPEN_TICKS
		OPENING:
			entity.stars -= 1
			_release(entity, state, world)
			entity.phase = RELEASED
			entity.timer = RELEASE_TICKS
		WILTING:
			# Recorded only now: a collected placement is hidden by the drawing layer.
			entity.collected = 1
			entity.status = 3


static func _swallow(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var sensor := cup(entity)
	var dispatch := registry()
	for other: Dictionary in Near.nearby(state, world, sensor):
		if (
			other.get("token", 0) == entity.token
			or other.status != 1
			or other.get("held", 0)
			or not (other.get("spat", 0) == 1 or other.get("thrown", 0) == 1)
		):
			continue
		var type: Script = dispatch.lookup(other.code)
		if not type.has_method("bounds"):
			continue
		var local: Array = type.bounds(other)
		var box := [other.x + local[0], other.y + local[1], other.x + local[2], other.y + local[3]]
		# It must overlap the cup, sit inside its width, and drop in from above the middle.
		if (
			not Body.overlap(box, sensor)
			or other.x <= sensor[0]
			or other.x >= sensor[2]
			or entity.y + 2 * S <= other.y + (box[3] - box[1]) / 2 - 6 * S
		):
			continue
		Body.remove(other, state)
		other.status = 3
		entity.phase = FED
		entity.timer = FED_TICKS
		entity.can_despawn = 0
		return


static func _release(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var dispatch := registry()
	var stars := 0
	for other: Dictionary in state.entities:
		if other.code == "o4" and other.status == 1:
			stars += 1
	var top: int = entity.y - 32 * S
	if int(state.get("health", 0)) + stars < 30:
		dispatch.spawn_dynamic(
			state,
			world,
			"o4",
			entity.x,
			top,
			{
				"vy": -Motion.random_ticks(state, 256 * 60, 512 * 60),
				"facing": 1 if Motion.random_ticks(state, 0, 1) == 1 else -1,
				"despawn_ticks": 480,
				"max_speed": Motion.random_ticks(state, 64 * 60, 128 * 60)
			}
		)
	else:
		dispatch.spawn_dynamic(
			state,
			world,
			"o1",
			entity.x,
			top,
			{
				"moving": 1,
				"despawn_ticks": 480,
				"vx": Motion.random_ticks(state, -192 * 60, 192 * 60),
				"vy": -Motion.random_ticks(state, 512 * 60, 768 * 60)
			}
		)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	# Eggs drop beside the cup as resting eggs.
	if entity.phase != OPEN or projectile.get("code", "") != "o7":
		return 0
	if not Body.overlap(_box_of(projectile), cup(entity)):
		return 0
	projectile.mode = 0
	projectile.floating = 0
	projectile.camera = 0
	projectile.vy = -384 * 60
	projectile.vx = (-384 if projectile.x < entity.x else 384) * 60
	return 2


static func _box_of(egg: Dictionary) -> Array:
	return [egg.x - 12 * S, egg.y - 12 * S, egg.x + 12 * S, egg.y + 12 * S]


static func tongue(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> int:
	return 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1, "animation": "Default"}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.phase >= OPEN
		and entity.phase <= WILTING
		and entity.timer >= 0
		and entity.timer <= WILT_TICKS
		and entity.stars >= -1
		and entity.stars <= MAX_STARS
	)
