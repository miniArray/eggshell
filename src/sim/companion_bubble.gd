extends RefCounted
## Bubble body motion is separate from event-sheet drift toward the current player.

const Collision = preload("res://src/sim/collision.gd")
const S := preload("res://src/sim/units.gd").SCALE
const BOX := [-30 * S, -60 * S, 30 * S, 0]
const PHYSICAL_WIDTH := 64 * S
const PHYSICAL_HEIGHT := 64 * S
const POINTS := [-22, -52, 0, -60, 22, -52, 30, -30, 22, -8, 0, 0, -22, -8, -30, -30]
static var _body_cache: Array = []


static func body() -> Array:
	if _body_cache.is_empty():
		_body_cache = BOX.duplicate()
		_body_cache.append(points())
		_body_cache.make_read_only()
	return _body_cache


static func points() -> PackedInt64Array:
	var result := PackedInt64Array()
	for coordinate: int in POINTS:
		result.append(coordinate * S)
	return result


static func advance(state: Dictionary, world: Dictionary, platform_enabled: bool = true) -> void:
	if state.bubble_bound_ticks < 0:
		return
	if platform_enabled:
		state.companion_age = 61 if state.companion_age >= 300 else state.companion_age + 1
		var age: int = state.companion_age
		if age <= 60:
			state.companion_vy = -192 * 60 * age / 60
		else:
			# The swing starts after the ramp reports its end on the following step.
			var leg := (age - 61) % 240
			state.companion_vy = -192 * 60 + 384 * 60 * mini(leg, 240 - leg) / 120
	if state.bubble_bound_ticks > 0:
		var remaining: int = state.bubble_bound_ticks - 1
		var span: int = state.bubble_bound_to_x - state.bubble_bound_from_x
		state.recovery_x = state.bubble_bound_from_x + span * (6 - remaining) / 6
		# -1 queues natural completion. Cancellation clears it without a callback.
		state.bubble_bound_ticks = remaining if remaining else -1
		if platform_enabled:
			state.recovery_y += state.companion_vy
		return
	if not platform_enabled:
		return
	var bounds := body()
	var here := {"x": state.recovery_x, "y": state.recovery_y}
	# This step's control precedes the wall events that change the next direction.
	var control: int = state.companion_direction
	if state.companion_direction < 0 and Collision.by_wall(here, world, bounds, -1, 2, 3):
		state.companion_direction = 1
	if state.companion_direction > 0 and Collision.by_wall(here, world, bounds, 1, 2, 3):
		state.companion_direction = -1
	var moving := {
		"x": state.recovery_x,
		"y": state.recovery_y,
		"vx": state.companion_vx,
		"vy": state.companion_vy,
		"recovery_width": PHYSICAL_WIDTH,
		"recovery_height": PHYSICAL_HEIGHT
	}
	# Platform keeps the pre-recovery floor for ramp following, even while rising.
	var support := Collision.floor_at(moving, world, bounds)
	if Collision.prepare(moving, world, bounds):
		var previous: int = moving.vx
		var accelerated: int = previous + control * 512
		var next := clampi(accelerated, -48 * 60, 48 * 60)
		# Platform caps displacement separately, after integrating acceleration.
		var distance: int = (
			clampi((previous + accelerated) / 2, -48 * 60, 48 * 60) if previous else 0
		)
		Collision.horizontal(moving, world, bounds, distance, support, false, 640 * 60)
		Collision.vertical(moving, world, bounds, moving.vy, support)
		moving.vx = (
			clampi(moving.vx + control * 512, -48 * 60, 48 * 60) if moving.vx != previous else next
		)
		if moving.vx != 0 and Collision.by_wall(moving, world, bounds, signi(moving.vx)):
			moving.vx = 0
	state.recovery_x = moving.x
	state.recovery_y = moving.y
	state.companion_vx = moving.vx
	state.companion_vy = moving.vy


## Called after player motion and catch handling, before rescuer events.
static func events(state: Dictionary, world: Dictionary) -> void:
	drift(state, world)
	if state.bubble_collision_disabled:
		return
	var left := 32 * S
	var right: int = maxi(left, world.width - 32 * S)
	if state.recovery_x < left or state.recovery_x > right:
		state.bubble_bound_ticks = 6
		state.bubble_collision_disabled = 1
		state.bubble_bound_from_x = state.recovery_x
		state.bubble_bound_to_x = clampi(state.recovery_x, left, right)
		state.companion_direction = 1 if state.recovery_x < left else -1
		state.companion_vx = 0


static func complete_events(state: Dictionary) -> void:
	if state.bubble_bound_ticks == -1:
		state.bubble_bound_ticks = 0
		state.bubble_collision_disabled = 0


## The physical bubble-only entry point omits player catch and rescuer events.
static func finish_events(state: Dictionary, world: Dictionary) -> void:
	events(state, world)
	complete_events(state)


## Overlap selection runs once; each child event reads the preceding child's position.
static func drift(state: Dictionary, world: Dictionary) -> void:
	if state.bubble_collision_disabled or state.rescue_mask:
		return
	var here := {"x": state.recovery_x, "y": state.recovery_y}
	if not Collision.overlaps(here, world, body()):
		return
	if state.recovery_x > state.x:
		state.recovery_x -= 96 * 60
	if state.recovery_x < state.x:
		state.recovery_x += 96 * 60
	if state.recovery_y > state.y:
		state.recovery_y -= 96 * 60
	if state.recovery_y < state.y:
		state.recovery_y += 96 * 60


static func settle(state: Dictionary, world: Dictionary) -> void:
	var moving := {
		"x": state.recovery_x,
		"y": state.recovery_y,
		"vx": 0,
		"vy": 0,
		"recovery_width": PHYSICAL_WIDTH,
		"recovery_height": PHYSICAL_HEIGHT
	}
	Collision.prepare(moving, world, body())
	state.recovery_x = moving.x
	state.recovery_y = moving.y
