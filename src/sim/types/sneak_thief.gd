extends RefCounted
## A patrolling thief. It chases a near player, snatches the companion on touch and runs off
## with the bubble; when a bubble appears it races to grab it. Stomps and strikes wear it down.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const Damage = preload("res://src/sim/damage.gd")
const Life = preload("res://src/sim/life.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e10"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
# Poses (the animation that drives the source logic).
const WALK := 0
const IDLE := 1
const PREPARE := 2
const HIGH_PREPARE := 3
const JUMP := 4
const JUMP_MOVE := 5
const FALL := 6
const FALL_MOVE := 7
const SIT := 8
const GET_UP := 9
const SPRINT := 10
const NAMES := [
	"Walk",
	"Idle",
	"PrepareJump",
	"PrepareHighJump",
	"Jump",
	"JumpAndMove",
	"Fall",
	"FallAndMove",
	"Sit",
	"GetUp",
	"Sprint"
]
const POSE_TICKS := {PREPARE: 8, HIGH_PREPARE: 8, SIT: 12, GET_UP: 12}
# Plans.
const PATROL := 0
const CHASE := 1
const EVADE := 2
const AFTER := 3
const IGNORE := 4
const SLOW := 48 * 60
const FAST := 368 * 60
const ACCELERATION := 512
const DECELERATION := 64
const IDLE_FRAME := 20
const BOX := [-14 * S, -26 * S, 14 * S, 16 * S]
const FIELDS := (
	Body.FIELDS
	+ [
		["pose", WALK],
		["timer", 0],
		["plan", PATROL],
		["max_speed", SLOW],
		["home_x", 0],
		["idle_frames", 0],
		["idle_tick", 0],
		["jump_health", 3],
		["hit_health", 6],
		["carrying", 0],
		["get_up", 0],
		["grounded", 1],
		["saw_bubble", 0],
		["contact", 0]
	]
)


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.home_x = int(source.x)
	return values


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func bubble_out(state: Dictionary) -> bool:
	return state.get("companion_mode", Life.ATTACHED) == Life.BUBBLE


static func bubble_box(state: Dictionary) -> Array:
	var box: Array = Life.BUBBLE_BOX
	return [
		state.recovery_x + box[0],
		state.recovery_y + box[1],
		state.recovery_x + box[2],
		state.recovery_y + box[3]
	]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var fresh: bool = entity.started == 0
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if fresh:
		entity.home_x = entity.x
	if Body.spit_step(entity, state, world, BOX) or Body.hazards(entity, state, world, BOX):
		return
	_bubble_plans(entity, state)
	var control := _decide(entity, state, world)
	_move(entity, world, control)
	if entity.carrying:
		if bubble_out(state):
			# The stolen bubble rides on the thief.
			state.recovery_x = entity.x
			state.recovery_y = entity.y + 30 * S
		else:
			entity.carrying = 0


static func _bubble_plans(entity: Dictionary, state: Dictionary) -> void:
	var out := bubble_out(state)
	if out and not entity.saw_bubble and entity.plan in [PATROL, CHASE]:
		entity.plan = AFTER
		entity.max_speed = FAST
	if not out and entity.saw_bubble:
		if entity.plan == AFTER:
			entity.plan = CHASE
		elif entity.plan == IGNORE:
			entity.plan = PATROL
		elif entity.plan == EVADE:
			entity.plan = PATROL
			entity.max_speed = SLOW
			entity.vx = 0
			_pose(entity, SIT)
	entity.saw_bubble = int(out)


static func _pose(entity: Dictionary, pose: int) -> void:
	entity.pose = pose
	entity.timer = POSE_TICKS.get(pose, 0)
	entity.idle_tick = 0


static func _wall_ahead(entity: Dictionary, world: Dictionary) -> bool:
	return Motion.overlaps(entity, world, BOX, entity.facing * S, -S)


static func _face(entity: Dictionary, target_x: int, away: bool) -> void:
	if target_x == entity.x:
		return
	var toward := 1 if target_x > entity.x else -1
	entity.facing = -toward if away else toward


static func _decide(entity: Dictionary, state: Dictionary, world: Dictionary) -> int:
	match entity.plan:
		CHASE:
			_face(entity, state.x, false)
		EVADE:
			_face(entity, state.x, true)
		AFTER:
			_face(entity, state.recovery_x, false)
	if entity.timer > 0:
		entity.timer -= 1
		if entity.timer == 0:
			match entity.pose:
				PREPARE:
					_pose(entity, JUMP_MOVE)
					entity.vy = -576 * 60
					entity.grounded = 0
				HIGH_PREPARE:
					_pose(entity, JUMP_MOVE)
					entity.vy = -768 * 60
					entity.vx /= 4
					entity.grounded = 0
				SIT:
					entity.get_up = 1
				GET_UP:
					_pose(entity, IDLE if entity.plan == PATROL else SPRINT)
					if entity.pose == IDLE:
						entity.idle_frames = 0
	if entity.get_up and entity.grounded:
		entity.get_up = 0
		entity.vx = 0
		_pose(entity, GET_UP)
	var hurried: bool = entity.plan in [CHASE, EVADE, AFTER]
	if entity.pose == WALK:
		if absi(entity.x - entity.home_x) > 64 * S:
			entity.idle_frames = Motion.random_ticks(state, 3, 6)
			entity.vx = 0
			_pose(entity, IDLE)
		elif entity.grounded and Motion.edge(entity, world, BOX):
			entity.facing *= -1
	elif entity.pose == IDLE:
		entity.idle_tick += 1
		if entity.idle_tick % IDLE_FRAME == 0:
			if entity.idle_frames > 0:
				entity.idle_frames -= 1
			if entity.idle_frames <= 0:
				var frame: int = (entity.idle_tick / IDLE_FRAME) % 2
				if entity.facing < 0 and frame == 1:
					entity.facing = 1
				elif entity.facing > 0 and frame == 0:
					entity.facing = -1
				entity.home_x = entity.x
				_pose(entity, WALK)
	if entity.plan in [PATROL, IGNORE] and _wall_ahead(entity, world):
		entity.facing *= -1
	if (
		hurried
		and entity.grounded
		and entity.pose not in [PREPARE, HIGH_PREPARE, SIT, GET_UP]
		and _wall_ahead(entity, world)
	):
		_pose(entity, PREPARE)
	if (
		entity.plan == PATROL
		and absi(entity.x - state.x) < 160 * S
		and entity.pose not in [SIT, GET_UP]
		and not state.get("captured_by", 0)
	):
		entity.plan = CHASE
		entity.vy = -320 * 60
		entity.grounded = 0
		entity.max_speed = FAST
		_pose(entity, JUMP)
	if entity.plan == AFTER:
		if (
			entity.grounded
			and entity.pose != HIGH_PREPARE
			and absi(entity.x - state.recovery_x) < 96 * S
		):
			_pose(entity, HIGH_PREPARE)
		if entity.pose in [WALK, IDLE]:
			_pose(entity, SIT)
		if (
			not entity.carrying
			and entity.pose not in [SIT, GET_UP]
			and Body.overlap(Body.world_box(entity, BOX), bubble_box(state))
		):
			_grab(entity, state)
	if entity.pose in [WALK, SPRINT, JUMP_MOVE]:
		return entity.facing
	return 0


static func _grab(entity: Dictionary, state: Dictionary) -> void:
	entity.carrying = 1
	entity.plan = EVADE
	entity.vx = 0
	entity.vy = 0
	# The other thieves give up the chase.
	for other: Dictionary in state.entities:
		if other.code == "e10" and other.status == 1 and other.token != entity.token:
			if other.plan != EVADE:
				other.plan = IGNORE
				other.max_speed = SLOW
				_pose(other, IDLE)


static func _move(entity: Dictionary, world: Dictionary, control: int) -> void:
	if control != 0:
		entity.vx = clampi(entity.vx + control * ACCELERATION, -entity.max_speed, entity.max_speed)
	elif entity.vx > 0:
		entity.vx = maxi(0, entity.vx - DECELERATION)
	elif entity.vx < 0:
		entity.vx = mini(0, entity.vx + DECELERATION)
	var distance: int = entity.vx
	if distance and Motion.move(entity, world, BOX, distance, true) != distance:
		entity.vx = 0
	var was_grounded: bool = entity.grounded == 1
	var landed := Motion.gravity_box(entity, world, BOX)
	if not landed and entity.vy > 0:
		if entity.pose == JUMP:
			_pose(entity, FALL)
		elif entity.pose == JUMP_MOVE:
			_pose(entity, FALL_MOVE)
	if landed and not was_grounded:
		if entity.pose == FALL:
			_pose(entity, SIT)
		elif entity.pose == FALL_MOVE:
			_pose(entity, SPRINT)
	entity.grounded = int(landed or Collision.floor_at(entity, world, BOX) != 0)


static func contact(entity: Dictionary, state: Dictionary, world: Dictionary, input: int) -> void:
	var touching := Body.player_overlap(entity, state, BOX)
	if touching and not entity.contact and state.vy > entity.vy and entity.y > state.y - 8 * S:
		if Body.pounding(state):
			_defeat(entity, state, world)
		else:
			Body.bounce(entity, state, input)
			entity.jump_health -= 1
			if entity.jump_health > 0:
				_pose(entity, SIT)
				entity.vx = 0
				state.vx = (-128 if state.x < entity.x else 128) * 60
			else:
				_defeat(entity, state, world)
	elif (
		touching
		and entity.y <= state.y - 8 * S
		and not state.get("separated", 0)
		and not state.get("invulnerable", 0)
		and state.get("companion_mode", Life.ATTACHED) == Life.ATTACHED
	):
		# A touch from the side takes the companion straight into a bubble the thief carries.
		Damage.separate(state, 0)
		if bubble_out(state):
			_grab(entity, state)
			entity.saw_bubble = 1
	entity.contact = int(touching)


static func _defeat(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	for index in 3:
		_coin(entity, state, world, 30)
	Body.remove(entity, state)


static func _coin(entity: Dictionary, state: Dictionary, world: Dictionary, delay: int) -> void:
	Body.registry_for().spawn_dynamic(
		state,
		world,
		"o1",
		entity.x,
		entity.y,
		{
			"moving": 1,
			"despawn_ticks": 480,
			"pickup_delay": delay,
			"vx": Motion.random_ticks(state, -256 * 60, 256 * 60),
			"vy": -Motion.random_ticks(state, 256 * 60, 384 * 60)
		}
	)


static func _struck(entity: Dictionary, state: Dictionary, world: Dictionary, from_x: int) -> void:
	_pose(entity, SIT)
	entity.hit_health -= 1
	entity.vx = (256 if entity.x > from_x else -256) * 60
	if entity.hit_health >= 3:
		_coin(entity, state, world, 0)
	elif entity.hit_health > 0:
		Body.registry_for().spawn_dynamic(
			state,
			world,
			"o4",
			entity.x,
			entity.y,
			{
				"vy": -Motion.random_ticks(state, 256 * 60, 512 * 60),
				"facing": 1 if Motion.random_ticks(state, 0, 1) == 1 else -1,
				"despawn_ticks": 480,
				"max_speed": Motion.random_ticks(state, 64 * 60, 128 * 60)
			}
		)
	else:
		Body.remove(entity, state)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	# The tongue bounces off and shoves the thief away.
	if entity.held or entity.status != 1:
		return 0
	entity.vx = (128 if entity.x > state.x else -128) * 60
	_pose(entity, SIT)
	return 2


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, from_x: int
) -> void:
	if kind == Hits.POUND:
		_defeat(entity, state, world)
	elif kind == Hits.CLEAR:
		Body.remove(entity, state)
	else:
		_struck(entity, state, world, from_x)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	_struck(entity, state, world, projectile.get("x", entity.x))
	# The egg is used up; a thrown body that can be destroyed is destroyed too.
	return 1


static func on_remove(entity: Dictionary, _state: Dictionary) -> void:
	entity.carrying = 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.held == 0, "animation": NAMES[entity.pose]}


static func finished(entity: Dictionary) -> bool:
	return entity.status in [2, 3] and entity.held == 0


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.pose >= WALK
		and entity.pose <= SPRINT
		and entity.timer >= 0
		and entity.timer <= 12
		and entity.plan >= PATROL
		and entity.plan <= IGNORE
		and entity.max_speed in [SLOW, FAST]
		and entity.idle_frames >= 0
		and entity.idle_frames <= 6
		and entity.idle_tick >= 0
		and entity.jump_health <= 3
		and entity.hit_health <= 6
		and entity.carrying in [0, 1]
		and entity.get_up in [0, 1]
		and entity.grounded in [0, 1]
		and entity.saw_bubble in [0, 1]
		and entity.contact in [0, 1]
		and absi(entity.vx) <= FAST
	)
