extends SceneTree
## Sound events, the listening ghost and the empty object code. Invented placements and
## controlled states only. No frames, recordings, packs or devices.
const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Registry = preload("res://src/sim/registry.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Sound = preload("res://src/sim/sound_events.gd")
const Ghost = preload("res://src/sim/types/blind_ghost.gd")
const Blank = preload("res://src/sim/types/editor_blank.gd")
const Moves = preload("res://src/sim/moves.gd")
const Damage = preload("res://src/sim/damage.gd")
const Life = preload("res://src/sim/life.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := State.SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	_sound_field_checks()
	_emitter_checks()
	_quiet_ghost_checks()
	_listening_ghost_checks()
	_ghost_contact_checks()
	_restore_checks()
	_empty_code_checks()
	print("LASTCODES_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _level(objects: Dictionary) -> Dictionary:
	return {
		"version": "s3.8.0",
		"name": "Invented sounds",
		"author": "Eggshell",
		"desc": "",
		"startpoint": {"map": 1, "X": 64, "Y": 100},
		"maps": {"map1": {"width": 4096, "height": 1024, "objects": objects}}
	}


func _world_for(objects: Dictionary) -> Dictionary:
	var built := World.build(JSON.stringify(_level(objects)), {"tilemaps": {}})
	check(built.ok, "Invented placements compile: " + str(built.get("error", "")))
	return built.get("world", {})


func _place(code: String, x: int, y: int, options: Dictionary = {}) -> Dictionary:
	var result := {"A": code, "X": x, "Y": y}
	result.merge(options, true)
	return result


func _by_id(state: Dictionary, id: String) -> Dictionary:
	for entity: Dictionary in state.entities:
		if entity.id == id:
			return entity
	check(false, "Expected placement exists: " + id)
	return {}


## Keep the follow point fixed so activation never depends on the player falling.
func _tick(state: Dictionary, world: Dictionary, ticks: int = 1) -> void:
	for _index in ticks:
		state.frame += 1
		state.camera_x = 400 * S
		state.camera_y = 300 * S
		Registry.advance(state, world, 0)


func _ghost_world(x: int = 400, y: int = 300) -> Dictionary:
	return _world_for({"ghost": _place("e39", x, y)})


func _sound_field_checks() -> void:
	var names := State.level_fields().map(func(pair: Array) -> String: return pair[0])
	for name: String in ["sound_serial", "sound_kind", "sound_x", "sound_y"]:
		check(names.has(name), "Level schema declares " + name)
	var state := State.create(_ghost_world())
	check(state.sound_serial == 0 and state.sound_kind == Sound.NONE, "Play starts silent")
	Sound.emit(state, Sound.PICKUP, 5 * S, 6 * S)
	check(
		state.sound_serial == 1 and state.sound_kind == Sound.PICKUP and state.sound_x == 5 * S,
		"An event counts and records its kind and position"
	)
	state.sound_serial = Sound.MAX_SERIAL
	Sound.emit(state, Sound.SWITCH, 0, 0)
	check(state.sound_serial == 1, "The serial wraps to 1, never to the silent 0")
	check(Snapshot.valid_state(state), "A recorded event is valid state")
	state.sound_kind = Sound.LAST_KIND + 1
	check(not Snapshot.valid_state(state), "An unknown event kind is rejected")
	state.sound_kind = Sound.NONE
	state.sound_serial = -1
	check(not Snapshot.valid_state(state), "A negative serial is rejected")


func _emitter_checks() -> void:
	var world := _world_for({"coin": _place("o1", 64, 90)})
	var state := State.create(world)
	Moves.initialize(state)
	Moves.jump(state)
	check(
		state.sound_kind == Sound.PLAYER and state.sound_serial == 1,
		"A jump is a player sound"
	)
	check(
		state.sound_x == state.x and state.sound_y == state.y - Sound.PLAYER_CENTRE * S,
		"A player sound comes from the body centre"
	)
	var serial: int = state.sound_serial
	Damage.hurt(state, state.x + S)
	check(state.sound_serial == serial + 1, "Getting hurt is a player sound")
	var coin := _by_id(state, "coin")
	coin.status = 1
	Registry.lookup("o1").collect(coin, state)
	check(
		state.sound_kind == Sound.PICKUP and state.sound_x == coin.x and state.sound_y == coin.y,
		"A collected coin sounds at the coin"
	)
	serial = state.sound_serial
	Registry.lookup("o1").collect(coin, state)
	check(state.sound_serial == serial, "A coin collected twice sounds once")
	var quiet := State.create(world)
	quiet.quick_death = 1
	Life.kill(quiet)
	check(quiet.sound_serial == 0, "A quick restart is silent to listeners")
	var slow := State.create(world)
	slow.quick_death = 0
	Life.kill(slow)
	check(slow.sound_serial == 1 and slow.sound_kind == Sound.PLAYER, "A slow death is heard")


func _quiet_ghost_checks() -> void:
	var world := _ghost_world()
	var state := State.create(world)
	var ghost := _by_id(state, "ghost")
	Sound.emit(state, Sound.PLAYER, 0, 0)
	_tick(state, world)
	check(ghost.status == 1, "The ghost activates in the reference area")
	check(ghost.heard == state.sound_serial, "A sound before it woke is not news")
	check(ghost.mode == Ghost.FOCUSING and ghost.anim == Ghost.FOCUS, "It wakes up listening")
	var facing: int = ghost.facing
	_tick(state, world, Ghost.LISTEN_TICKS)
	check(ghost.mode == Ghost.CONFUSED, "Two quiet seconds of listening confuse it")
	var flips := 0
	var ticks := 0
	while ghost.mode == Ghost.CONFUSED and ticks < 400:
		var before: int = ghost.facing
		_tick(state, world)
		flips += int(ghost.facing != before)
		ticks += 1
	check(flips == Ghost.TURNS, "It turns around three times")
	check(ghost.mode == Ghost.WANDERING and ghost.wave_on == 1, "Then it starts to wander")
	check(ghost.facing == -facing, "An odd number of turns leaves it facing the other way")
	var start_x: int = ghost.x
	var start_y: int = ghost.y
	_tick(state, world, Ghost.FIRST_LEG_TICKS)
	check(
		ghost.x == start_x + ghost.facing * Ghost.FIRST_LEG,
		"The first wander leg goes 96 px the way it faces"
	)
	check(ghost.y != start_y or ghost.wave_phase == 0, "It bobs on a slow wave while wandering")
	var leg_facing: int = ghost.facing
	_tick(state, world, 4 * Ghost.FRAME_TICKS + 1)
	check(ghost.facing == -leg_facing and ghost.leg_ticks == Ghost.LEG_TICKS, "It turns for the next leg")


func _listening_ghost_checks() -> void:
	var world := _ghost_world()
	var state := State.create(world)
	var ghost := _by_id(state, "ghost")
	_tick(state, world)
	var early := _ghost_world()
	var early_state := State.create(early)
	_tick(early_state, early)
	Sound.emit(early_state, Sound.PLAYER, 100 * S, 300 * S)
	_tick(early_state, early)
	check(
		_by_id(early_state, "ghost").mode == Ghost.CHASING,
		"It wakes up listening, so its first sound sends it at once"
	)
	var ticks := 0
	while ghost.mode != Ghost.WANDERING and ticks < 400:
		_tick(state, world)
		ticks += 1
	Sound.emit(state, Sound.PLAYER, 100 * S, 300 * S)
	_tick(state, world)
	check(ghost.mode == Ghost.FOCUSING and ghost.facing == -1, "A sound to the left: it faces it")
	check(ghost.wave_on == 0 and ghost.leg_ticks == 0, "Listening stops its wandering")
	check(
		ghost.target_x == 100 * S - Ghost.PAST_SOUND and ghost.target_y == 300 * S,
		"It aims 128 px past the sound, away from itself"
	)
	check(ghost.listen_ticks == Ghost.LISTEN_TICKS, "A sound restarts its listening time")
	Sound.emit(state, Sound.PLAYER, 100 * S, 300 * S)
	_tick(state, world)
	check(ghost.mode == Ghost.CHASING and ghost.anim == Ghost.CHASE, "A second sound sends it")
	ticks = 0
	var fastest := 0
	while ghost.mode == Ghost.CHASING and ticks < 600:
		_tick(state, world)
		fastest = maxi(fastest, absi(ghost.vx))
		ticks += 1
	check(ghost.mode == Ghost.FOCUSING, "It stops chasing near its target")
	check(fastest > 0 and fastest <= Ghost.SPEED, "Its chase speed builds up to at most 192 px/s")
	var dx: int = ghost.target_x - ghost.x
	check(absi(dx) < Ghost.ARRIVED, "It arrives within 48 px")
	_tick(state, world, Ghost.SLOW_TICKS)
	check(ghost.vx == 0 and ghost.vy == 0, "It slows to rest after arriving")
	Sound.emit(state, Sound.RELEASE, 4000 * S, 0)
	_tick(state, world)
	check(
		ghost.target_x == ghost.x + Ghost.PAST_SOUND and ghost.target_y == ghost.y,
		"A release sound is heard at its own position"
	)


func _ghost_contact_checks() -> void:
	var world := _ghost_world()
	var state := State.create(world)
	var ghost := _by_id(state, "ghost")
	_tick(state, world)
	state.x = ghost.x
	state.y = ghost.y + 10 * S
	Registry.contact(state, 0, world)
	check(state.invulnerable > 0 and ghost.contact == 1, "Touching it hurts")
	check(state.sound_kind == Sound.PLAYER, "The hurt player makes a sound it can hear")
	check(Ghost.projectile_contact(ghost, {}, state, world) == 0, "Thrown things pass through it")
	Ghost.hit(ghost, state, world, Hits.EGG, 0)
	check(ghost.status == 1, "An egg strike does nothing")
	Ghost.hit(ghost, state, world, Hits.CLEAR, 0)
	check(ghost.status == 3, "Clearing the screen removes it")


func _restore_checks() -> void:
	var world := _ghost_world()
	var state := State.create(world)
	var ghost := _by_id(state, "ghost")
	_tick(state, world)
	Sound.emit(state, Sound.PLAYER, 700 * S, 200 * S)
	_tick(state, world)
	Sound.emit(state, Sound.PLAYER, 700 * S, 200 * S)
	_tick(state, world, 20)
	check(ghost.mode == Ghost.CHASING, "Mid-chase before the snapshot")
	var bytes := Snapshot.encode(state)
	var decoded := Snapshot.decode(bytes, world.identity, world)
	check(decoded.ok and Snapshot.encode(decoded.state) == bytes, "Sound and ghost state round trip")
	var restored: Dictionary = decoded.state
	var serial: int = restored.sound_serial
	_tick(state, world, 90)
	_tick(restored, world, 90)
	check(restored.sound_serial == serial, "A restored state replays no sound")
	check(Snapshot.encode(restored) == Snapshot.encode(state), "Restored play continues the same")
	ghost.mode = 9
	check(not Snapshot.valid_state(state), "An unknown ghost mode is rejected")


func _empty_code_checks() -> void:
	var world := _world_for({"blank": _place("", 300, 300), "named": _place("empty", 310, 300)})
	var sources: Array = world.entities
	check(
		sources.all(func(source: Dictionary) -> bool: return not source.has("placeholder")),
		"An empty code is not a placeholder"
	)
	check(Registry.lookup("") == Blank, "An empty code is the blank editor form")
	var state := State.create(world)
	var blank := _by_id(state, "blank")
	check(blank.code == "", "It keeps its empty code")
	check(not Blank.view_state(blank, state).visible, "It draws nothing")
	var before := blank.duplicate()
	_tick(state, world, 5)
	check(blank == before, "It never acts")
	var bytes := Snapshot.encode(state)
	check(Snapshot.decode(bytes, world.identity, world).ok, "An empty code round trips")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)
