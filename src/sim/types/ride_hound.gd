extends RefCounted
## A friendly runner with a top-only back. It follows the player, runs where its rider
## faces, jumps at walls, plays with resting eggs and destroys enemies in its path.

const Body = preload("res://src/sim/enemy_body.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const Moves = preload("res://src/sim/moves.gd")
const World = preload("res://src/sim/world.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["o16"]
const SOLID := 2
const STEP_PHASE := 0
const CONTACT_PHASE := -1
const IDLE := 0
const WALK := 1
const TURN := 2
const LOOK := 3
const PREPARE := 4
const JUMP := 5
const FALL := 6
const WAGGLE := 7
const PLAY := 8
const NAMES := ["Idle", "Walk", "Turn", "Look", "PrepareJump", "Jump", "Fall", "Waggle", "Play"]
const POSE_TICKS := {TURN: 7, LOOK: 73, PREPARE: 8, WAGGLE: 63, PLAY: 23}
const MAX_SPEED := 400 * 60
const ACCELERATION := 256
const JUMP_SPEED := 768 * 60
const NEAR := 48 * S
const FAR := 128 * S
const QUEUE_TICKS := 20
const STROKE_TICKS := 24
const SWIM_SPEED := 200 * 60
const LIQUID_FALL := 704 * 60 / 4
## Runtime projectiles that are not enemies to the runner: it passes through them.
const NOT_DESTROYED := ["enemy_pellet", "enemy_spike", "enemy_mace"]
# Body facing left, in pixels around the origin. The back is a 60 x 16 top-only strip.
const BODY := [-34, -6, 20, 16]
# Standing picture facing left, in pixels around the origin.
const IMAGE := [-54, -38, 24, 16]
const FIELDS := (
	Body.FIELDS
	+ [
		["mode", IDLE],
		["timer", 0],
		["decel", 512],
		["ridden", 0],
		["playing", 0],
		["egg_token", 0],
		["queue_turn", 0],
		["grounded", 0],
		["swimming", 0],
		["stroke", 0],
		["stroke_dir", 1]
	]
)


static func registry() -> Script:
	return Body.registry_for()


static func prepare(source: Dictionary, world: Dictionary) -> Dictionary:
	var option: Variant = source.properties.get("E1", "")
	if not option is String:
		return {"ok": false, "error": "Invalid runner option: E1"}
	for key: String in ["F", "M", "R"]:
		var value: Variant = source.properties.get(key, 0)
		if not (value is int or value is float) or value != 0:
			return {"ok": false, "degrade": true, "error": "Unsupported runner option: " + key}
	# Each new runner lowers the shared deceleration; the source counts instances so far.
	var count := 1
	for other: Dictionary in world.get("entities", []):
		if other.get("code", "") == "o16":
			count += 1
	source.decel = 192 if count > 5 else 512 - 64 * (count - 1)
	source.stays = int(option == "1")
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.layer = 7
	values.decel = int(source.get("decel", 512))
	values.can_despawn = 0 if source.get("stays", 0) else 1
	return values


static func bounds(entity: Dictionary) -> Array:
	if entity.facing < 0:
		return [BODY[0] * S, BODY[1] * S, BODY[2] * S, BODY[3] * S]
	return [-BODY[2] * S, BODY[1] * S, -BODY[0] * S, BODY[3] * S]


## Waking on screen uses the whole standing picture (78 x 54 px), which reaches higher
## and farther back than the body.
static func activation_bounds(entity: Dictionary) -> Array:
	var box: Array = IMAGE if entity.facing < 0 else [-IMAGE[2], IMAGE[1], -IMAGE[0], IMAGE[3]]
	return [
		entity.x + box[0] * S, entity.y + box[1] * S, entity.x + box[2] * S, entity.y + box[3] * S
	]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1:
		return []
	return [entity.x - 30 * S, entity.y - 32 * S, entity.x + 30 * S, entity.y - 16 * S]


static func rider_on(entity: Dictionary, state: Dictionary) -> bool:
	if state.get("captured_by", 0) or not state.get("on_floor", 0) or entity.status != 1:
		return false
	var back := solid_box(entity)
	var player := Moves.player_box(state)
	return (
		state.x + player[2] > back[0]
		and state.x + player[0] < back[2]
		and state.y + player[3] + 4 * S >= back[1]
		and state.y < back[1] + 2 * S
	)


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if Body.process(entity, state) == Body.GONE:
		return
	var box := bounds(entity)
	var riding := rider_on(entity, state)
	if riding:
		entity.ridden = 1
		entity.playing = 0
		entity.egg_token = 0
	elif entity.ridden:
		entity.ridden = 0
	var egg := _egg(entity, state)
	if entity.playing and egg.is_empty():
		entity.playing = 0
		entity.egg_token = 0
		if entity.mode in [WAGGLE, PLAY]:
			entity.mode = IDLE
	var control := _decide(entity, state, world, egg)
	if entity.queue_turn:
		entity.queue_turn -= 1
		if entity.queue_turn == 0:
			_pose(entity, TURN)
	var riders := _enemy_riders(entity, state)
	var start_x: int = entity.x
	var start_y: int = entity.y
	_move(entity, world, box, control)
	if riders and (entity.x != start_x or entity.y != start_y):
		Collision.refresh(world, entity)
		_carry(riders, world, entity.x - start_x, entity.y - start_y)
	box = bounds(entity)
	if entity.vx != 0 or entity.vy != 0:
		_destroy_enemies(entity, state, world, box)
	if not entity.ridden and not entity.playing:
		_kick_eggs(entity, state, box)
	if entity.y > world.get("height", 0) + 1664 * S:
		Body.remove(entity, state)


static func _pose(entity: Dictionary, mode: int) -> void:
	entity.mode = mode
	entity.timer = POSE_TICKS.get(mode, 0)


static func _player_behind(entity: Dictionary, state: Dictionary) -> bool:
	return (state.x - entity.x) * entity.facing < 0


static func _wall_ahead(entity: Dictionary, world: Dictionary) -> bool:
	return Motion.overlaps(entity, world, bounds(entity), entity.facing * S, -S)


static func _decide(
	entity: Dictionary, state: Dictionary, world: Dictionary, egg: Dictionary
) -> int:
	match entity.mode:
		TURN, LOOK, PREPARE, WAGGLE, PLAY:
			entity.timer -= 1
			if entity.timer > 0:
				return 0
			match entity.mode:
				TURN:
					entity.facing *= -1
					_pose(entity, IDLE)
				LOOK:
					entity.facing *= -1
					_pose(entity, LOOK if _player_behind(entity, state) else IDLE)
				PREPARE:
					_pose(entity, JUMP)
					if entity.swimming:
						entity.vy = -JUMP_SPEED
				WAGGLE:
					if not egg.is_empty() and _egg_adjacent(entity, egg, 12):
						_pose(entity, PLAY)
					else:
						entity.playing = 0
						entity.egg_token = 0
						_pose(entity, IDLE)
				PLAY:
					if not egg.is_empty() and _egg_adjacent(entity, egg, 12):
						egg.vy = -256 * 60
						egg.floating = 0
					_pose(entity, WAGGLE)
			return 0
		JUMP:
			if entity.grounded and _wall_ahead(entity, world):
				entity.vy = -JUMP_SPEED
				entity.grounded = 0
			elif entity.vy > 0:
				_pose(entity, FALL)
			return entity.facing
		FALL:
			if entity.grounded:
				var look: bool = not entity.ridden and _player_behind(entity, state)
				_pose(entity, LOOK if look else IDLE)
				return 0
			return entity.facing if entity.ridden else 0
	# Standing or walking.
	if (entity.grounded or entity.swimming) and _wall_ahead(entity, world):
		_pose(entity, PREPARE)
		return 0
	if entity.ridden:
		if state.facing != entity.facing:
			if entity.queue_turn == 0:
				entity.queue_turn = QUEUE_TICKS
				entity.vx /= 2
			return 0
		entity.mode = WALK if entity.grounded else FALL
		return entity.facing
	if entity.playing:
		var ahead: int = (egg.x - entity.x) * entity.facing
		if ahead < 0:
			_pose(entity, TURN)
			return 0
		if _egg_adjacent(entity, egg, 8) and egg.vy == 0:
			entity.vx = 0
			_pose(entity, WAGGLE)
			return 0
		entity.mode = WALK
		return entity.facing
	var gap: int = entity.x - state.x
	if absi(gap) > NEAR:
		var toward := -1 if gap > 0 else 1
		if entity.facing == toward:
			if absi(gap) > FAR:
				entity.mode = WALK
				return toward
		elif entity.vx * toward >= 0:
			_pose(entity, TURN)
			return 0
	if entity.mode == WALK and entity.vx == 0:
		_pose(entity, LOOK if _player_behind(entity, state) else IDLE)
	return 0


## Water and lava are both liquids the runner swims in.
static func _wet(world: Dictionary, area: Array) -> bool:
	return (
		World.water_overlaps(world, area[0], area[1], area[2], area[3])
		or World.lava_overlaps(world, area[0], area[1], area[2], area[3])
	)


static func _move(entity: Dictionary, world: Dictionary, box: Array, control: int) -> void:
	var body := Body.world_box(entity, box)
	if not entity.swimming and _wet(world, body):
		entity.swimming = 1
		entity.playing = 0
		entity.egg_token = 0
	elif entity.swimming and not _wet(world, body):
		entity.swimming = 0
		entity.stroke = 0
	if entity.swimming:
		_swim(entity, world, box, control)
		return
	if control != 0:
		entity.vx = clampi(entity.vx + control * ACCELERATION, -MAX_SPEED, MAX_SPEED)
	elif entity.vx > 0:
		entity.vx = maxi(0, entity.vx - entity.decel)
	elif entity.vx < 0:
		entity.vx = mini(0, entity.vx + entity.decel)
	var distance: int = entity.vx
	if distance and Motion.move(entity, world, box, distance, true) != distance:
		entity.vx = 0
	entity.grounded = int(Motion.gravity_box(entity, world, box, 2048, 704 * 60))


static func _swim(entity: Dictionary, world: Dictionary, box: Array, control: int) -> void:
	# In liquid a pressed direction becomes a 0.4 s paddle stroke instead of control.
	if control != 0 and entity.stroke == 0:
		entity.stroke = STROKE_TICKS
		entity.stroke_dir = control
	if entity.stroke:
		entity.stroke -= 1
		var done: int = STROKE_TICKS - entity.stroke
		var span := STROKE_TICKS * STROKE_TICKS
		var left: int = STROKE_TICKS - done
		var part := 2 * done * done if 2 * done < STROKE_TICKS else span - 2 * left * left
		entity.vx = entity.stroke_dir * 400 * 60 * (span - part) / span
	elif entity.vx > 0:
		entity.vx = maxi(0, entity.vx - entity.decel)
	elif entity.vx < 0:
		entity.vx = mini(0, entity.vx + entity.decel)
	entity.vx = clampi(entity.vx, -SWIM_SPEED, SWIM_SPEED)
	var back := solid_box(entity)
	if _wet(world, back):
		entity.vy -= 256
	elif entity.vy > 0:
		entity.vy -= 384
	elif entity.mode not in [PREPARE, JUMP]:
		entity.vy = 0
	if not _wet(world, [back[0], back[1] + 6 * S, back[2], back[3] + 6 * S]):
		entity.y += 16 * 60
	# Every body in a liquid falls at most a quarter of its normal fall speed.
	entity.vy = mini(entity.vy, LIQUID_FALL)
	var distance: int = entity.vx
	if distance and Motion.move(entity, world, box, distance, true) != distance:
		entity.vx = 0
	distance = entity.vy
	if distance and Motion.move(entity, world, box, distance, false) != distance:
		entity.vy = 0
	entity.grounded = int(Collision.floor_at(entity, world, box) != 0)


## Enemies standing on the back move with it, as on any moving support.
static func _enemy_riders(entity: Dictionary, state: Dictionary) -> Array:
	var back := solid_box(entity)
	if back.is_empty():
		return []
	var dispatch := registry()
	var riders := []
	for other: Dictionary in state.entities:
		if (
			other.status != 1
			or other.get("held", 0)
			or other.get("hidden", 0)
			or other.get("vy", 0) < 0
			or not dispatch.is_enemy(other.code)
		):
			continue
		# The body box the enemy moves with, not a wider contact box (a plant's head).
		var box := Body.world_box(other, Motion.box(other, other.code))
		if box[3] <= back[1] and box[3] >= back[1] - S and box[0] < back[2] and box[2] > back[0]:
			riders.append(other)
	return riders


static func _carry(riders: Array, world: Dictionary, dx: int, dy: int) -> void:
	for rider: Dictionary in riders:
		var box := Motion.box(rider, rider.code)
		if dy:
			Motion.move(rider, world, box, dy, false)
		if dx:
			Motion.move(rider, world, box, dx, true)
		Collision.refresh(world, rider)


## A moving runner destroys every active enemy it touches, frozen or not, whatever the
## enemy's own reaction to other strikes.
static func _destroy_enemies(
	entity: Dictionary, state: Dictionary, world: Dictionary, box: Array
) -> void:
	var body := Body.world_box(entity, box)
	var dispatch := registry()
	for other: Dictionary in state.entities:
		if (
			other.status != 1
			or other.get("held", 0)
			or other.get("hidden", 0)
			or not dispatch.is_enemy(other.code)
			or other.code in NOT_DESTROYED
		):
			continue
		var type: Script = dispatch.lookup(other.code)
		if not type.has_method("bounds"):
			continue
		if Body.overlap(body, Body.world_box(other, type.bounds(other))):
			Body.remove(other, state)
			Collision.refresh(world, other)


static func _egg(entity: Dictionary, state: Dictionary) -> Dictionary:
	if not entity.egg_token:
		return {}
	var egg: Dictionary = registry().find_token(state, entity.egg_token)
	if egg.is_empty() or egg.status != 1 or egg.collected or egg.get("mode", 0) != 0:
		return {}
	return egg


static func _egg_box(egg: Dictionary) -> Array:
	return [egg.x - 12 * S, egg.y - 12 * S, egg.x + 12 * S, egg.y + 16 * S]


static func _egg_adjacent(entity: Dictionary, egg: Dictionary, reach: int) -> bool:
	var body := Body.world_box(entity, bounds(entity))
	body[0] += entity.facing * reach * S
	body[2] += entity.facing * reach * S
	return Body.overlap(body, _egg_box(egg))


static func _kick_eggs(entity: Dictionary, state: Dictionary, box: Array) -> void:
	var body := Body.world_box(entity, box)
	for egg: Dictionary in state.entities:
		if (
			egg.code != "o7"
			or egg.status != 1
			or egg.collected
			or egg.mode != 0
			or not Body.overlap(body, _egg_box(egg))
		):
			continue
		egg.floating = 0
		egg.vy = -448 * 60
		egg.vx = (-384 if egg.x < entity.x else 384) * 60
		entity.playing = 1
		entity.egg_token = egg.token
		return


static func tongue(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> int:
	return 0


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	# A thrown egg drops beside a free runner, which starts playing with it.
	if projectile.get("code", "") != "o7" or entity.ridden or entity.playing or entity.swimming:
		return 0
	projectile.mode = 0
	projectile.floating = 0
	projectile.camera = 0
	projectile.vy = -384 * 60
	projectile.vx = (-384 if projectile.x < entity.x else 384) * 60
	entity.playing = 1
	entity.egg_token = projectile.token
	return 2


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": true, "animation": NAMES[entity.mode], "flip_x": entity.facing > 0}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.mode >= IDLE
		and entity.mode <= PLAY
		and entity.timer >= 0
		and entity.timer <= 73
		and entity.decel in [512, 448, 384, 320, 256, 192]
		and entity.ridden in [0, 1]
		and entity.playing in [0, 1]
		and entity.egg_token >= 0
		and entity.queue_turn >= 0
		and entity.queue_turn <= QUEUE_TICKS
		and entity.grounded in [0, 1]
		and entity.swimming in [0, 1]
		and entity.stroke >= 0
		and entity.stroke <= STROKE_TICKS
		and entity.stroke_dir in [-1, 1]
		and absi(entity.vx) <= MAX_SPEED
	)
