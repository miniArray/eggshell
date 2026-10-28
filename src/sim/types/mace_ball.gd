extends RefCounted
## A spiked ball. It grows in its thrower's hands, flies straight once thrown, and drops
## when its thrower lets go. Touching it hurts.

const Body = preload("res://src/sim/enemy_body.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Moves = preload("res://src/sim/moves.gd")
const Walker = preload("res://src/sim/types/mace_walker.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["enemy_mace"]
const ENEMY := true
const DYNAMIC := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const HELD := 0
const FLYING := 1
const LOOSE := 2
const SPEED := 256 * 60
# Octagon at full size (radius 16); it grows from a sixteenth of that while conjured.
const HULL := [[-12, -12], [0, -16], [12, -12], [16, 0], [12, 12], [0, 16], [-12, 12], [-16, 0]]
const FIELDS := (
	Body.FIELDS + [["mode", HELD], ["owner_token", 0], ["aim", 1], ["lift", 0], ["growth", 0]]
)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.can_respawn = 0
	return values


static func bounds(entity: Dictionary) -> Array:
	var radius: int = 16 * S * scale_of(entity) / Walker.CONJURE_TICKS
	return [-radius, -radius, radius, radius]


static func scale_of(entity: Dictionary) -> int:
	# 4 px to 64 px over the conjuring time, in steps of CONJURE_TICKS.
	return 3 + (Walker.CONJURE_TICKS - 3) * entity.growth / Walker.CONJURE_TICKS


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if Body.process(entity, state) == Body.GONE:
		return
	match entity.mode:
		HELD:
			var owner: Dictionary = Body.registry_for().find_token(state, entity.owner_token)
			if owner.is_empty() or owner.status != 1 or owner.get("ball_token", 0) != entity.token:
				entity.mode = LOOSE
				entity.owner_token = 0
				return
			_follow(entity, owner)
		FLYING:
			entity.x -= entity.aim * SPEED
			if entity.lift > 0:
				entity.lift -= 1
				entity.y -= S
		LOOSE:
			if entity.vx > 0:
				entity.vx = maxi(0, entity.vx - 1296)
			elif entity.vx < 0:
				entity.vx = mini(0, entity.vx + 1296)
			var box := bounds(entity)
			var distance: int = entity.vx
			if distance and Motion.move(entity, world, box, distance, true) != distance:
				entity.vx = 0
			Motion.gravity_box(entity, world, box)


static func _follow(entity: Dictionary, owner: Dictionary) -> void:
	# Held offsets from the thrower: rise to the hand, then swing back over the head.
	var tick: int = owner.throw_tick
	var aim: int = owner.aim
	entity.growth = mini(tick, Walker.CONJURE_TICKS)
	var dx: int
	var dy: int
	if tick <= Walker.CONJURE_TICKS:
		dx = -4 * S - 18 * S * tick / Walker.CONJURE_TICKS
		dy = -2 * S - 22 * S * tick / Walker.CONJURE_TICKS
	else:
		var swing: int = tick - Walker.CONJURE_TICKS
		var half: int = Walker.AIM_TICKS / 2
		var along: int = swing if swing <= half else Walker.AIM_TICKS - swing
		dx = -22 * S + 32 * S * swing / Walker.AIM_TICKS
		dy = -24 * S - 12 * S * along / half
	entity.x = owner.x + dx * aim
	entity.y = owner.y + dy


static func hull(entity: Dictionary) -> Array:
	var result := []
	var scale := scale_of(entity)
	for point: Array in HULL:
		result.append(
			[
				entity.x + point[0] * S * scale / Walker.CONJURE_TICKS,
				entity.y + point[1] * S * scale / Walker.CONJURE_TICKS
			]
		)
	return result


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if entity.status != 1 or state.get("captured_by", 0):
		return
	if Body.polygon_overlap(hull(entity), Body.world_box(state, Moves.player_box(state))):
		Body.hurt(entity, state)


static func tongue(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> int:
	return 0


static func projectile_contact(
	_entity: Dictionary, _projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	return 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var size := 64.0 * scale_of(entity) / Walker.CONJURE_TICKS
	return {"visible": true, "animation": "Spikeball", "size_x": size, "size_y": size}


static func finished(entity: Dictionary) -> bool:
	return entity.status in [2, 3]


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.mode >= HELD
		and entity.mode <= LOOSE
		and entity.owner_token >= 0
		and entity.aim in [-1, 1]
		and entity.lift >= 0
		and entity.lift <= 12
		and entity.growth >= 0
		and entity.growth <= Walker.CONJURE_TICKS
	)
