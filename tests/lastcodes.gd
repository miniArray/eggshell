extends SceneTree
## Sound events, the listening ghost, the empty object code and span drawing parts.
## Invented placements and controlled states only. No frames, recordings or devices.
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
const SpanDressing = preload("res://src/view/span_dressing.gd")
const Frames = preload("res://src/view/pack_frames.gd")
const PACK := "res://packs/pantry"
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
	_span_part_checks()
	_span_node_checks()
	_span_body_checks()
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
	check(state.sound_kind == Sound.PLAYER and state.sound_serial == 1, "A jump is a player sound")
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
	check(
		ghost.facing == -leg_facing and ghost.leg_ticks == Ghost.LEG_TICKS,
		"It turns for the next leg"
	)


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
	check(
		decoded.ok and Snapshot.encode(decoded.state) == bytes, "Sound and ghost state round trip"
	)
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


func _span_part_checks() -> void:
	var stem := SpanDressing.parts("p6", {"E2": "64"}, 96)
	check(stem.size() == 1 and stem[0].name == "p6_stem", "A ledge with E2 has a stalk")
	check(stem[0].box == Rect2(-16, 16, 32, 64), "The stalk hangs E2 px from the bottom edge")
	check(SpanDressing.parts("p8", {"E2": 96}, 96)[0].box.size.y == 96, "Numeric E2 works too")
	check(SpanDressing.parts("p7", {"E2": "0"}, 96).is_empty(), "A zero stalk draws nothing")
	check(SpanDressing.parts("p7", {"E2": "-5"}, 96).is_empty(), "A negative stalk draws nothing")
	check(SpanDressing.parts("p7", {}, 96).is_empty(), "No E2, no stalk")
	check(SpanDressing.parts("p6", {"E2": "48px"}, 96)[0].box.size.y == 48, "Leading digits count")
	var spikes := SpanDressing.parts("p11", {"E2": "1"}, 104)
	check(
		spikes.size() == 1 and spikes[0].name == "p11_spikes" and spikes[0].variant == 1,
		"A turning span's E2 picks its spike strip"
	)
	check(spikes[0].box == Rect2(-52, -18, 104, 10), "The strip stands on the span's top edge")
	check(SpanDressing.parts("p12", {"E2": "0"}, 64)[0].box.size.x == 64, "It spans the width")
	check(SpanDressing.parts("p12", {"E2": "2"}, 64).is_empty(), "An unknown strip draws nothing")
	check(SpanDressing.parts("p9", {"E2": "64"}, 64).is_empty(), "Other spans have no parts")


## Parts keep their world size and place while the span node stretches and turns.
func _span_node_checks() -> void:
	var node := Sprite2D.new()
	node.scale = Vector2(2, 0.5)
	SpanDressing.attach(node, {}, PACK, "p11", {"E2": "0"}, 104)
	check(node.get_child_count() == 1, "A diagnostic strip is attached without pack art")
	var part: Node2D = node.get_child(0)
	var world := node.transform * part.transform
	check(
		(
			world.origin.is_equal_approx(Vector2(-52, -18))
			and world.get_scale().is_equal_approx(Vector2.ONE)
		),
		"The strip keeps world size under a stretched span"
	)
	node.scale = Vector2(4, 1)
	node.rotation_degrees = 180
	SpanDressing.follow(node)
	world = node.transform * part.transform
	check(world.origin.is_equal_approx(Vector2(52, 18)), "The strip turns with the span")
	node.free()
	var manifest := {"objects": {"p6_stem": {"file": "objects/e1.png", "origin": [0, 0]}}}
	var ledge := Sprite2D.new()
	# A plain directory path reads the PNG directly, without an editor import.
	var pack := ProjectSettings.globalize_path(PACK)
	SpanDressing.attach(ledge, manifest, pack, "p6", {"E2": "80"}, 96)
	var drawn: Node2D = ledge.get_child(0)
	var image: Sprite2D = drawn.get_child(0) if drawn.get_child_count() else null
	check(
		image != null and image.region_enabled and image.region_rect.size == Vector2(32, 80),
		"Pack stalk art repeats down the stalk's height"
	)
	ledge.free()


## A fixed span's body with pack art draws in the pack's slices, not one stretched image.
func _span_body_checks() -> void:
	var plain := SpanDressing.slices({})
	check(
		plain == {"left": 0, "right": 0, "top": 0, "bottom": 0, "tile": true},
		"Without slices the whole image repeats"
	)
	var cut := SpanDressing.slices(
		{"slices": {"left": 32, "right": 30, "top": 16, "bottom": -1, "fill": "stretch"}}
	)
	check(
		cut.left == 32 and cut.right == 30 and cut.top == 16 and cut.bottom == 0 and not cut.tile,
		"Slices read margins; an invalid margin reads as 0"
	)
	var entry := {"file": "objects/e1.png", "origin": [0, 0], "slices": {"left": 4, "right": 6}}
	var pack := ProjectSettings.globalize_path(PACK)
	var image: Texture2D = Frames.new().texture(pack, "objects/e1.png")
	var span := Sprite2D.new()
	span.centered = false
	span.texture = image
	span.offset = Vector2(-image.get_width() / 2.0, -image.get_height() / 2.0)
	# The stretch the view gives the node: the span's 320 by 56 px over the image.
	span.scale = Vector2(320, 56) / image.get_size()
	SpanDressing.attach(span, {"objects": {"p9": entry}}, pack, "p9", {}, 320)
	var holder: Node2D = span.get_child(0) if span.get_child_count() else null
	var patch: NinePatchRect = holder.get_child(0) if holder != null else null
	check(
		(
			patch != null
			and patch.size.is_equal_approx(Vector2(320, 56))
			and patch.patch_margin_left == 4
			and patch.patch_margin_right == 6
			and patch.axis_stretch_horizontal == NinePatchRect.AXIS_STRETCH_MODE_TILE
		),
		"A log span's body tiles its pack image across the span"
	)
	check(
		(
			holder != null
			and (span.transform * holder.transform).get_scale().is_equal_approx(Vector2.ONE)
			and (span.transform * holder.transform).origin.is_equal_approx(Vector2(-160, -28))
		),
		"The body keeps art pixels at world size over the stretched image's area"
	)
	check(span.self_modulate.a == 0.0, "The node's own stretched image is hidden")
	span.scale = Vector2(-160, 56) / image.get_size()
	span.rotation_degrees = 90
	SpanDressing.follow(span)
	var mirrored := span.transform * holder.transform
	check(
		(
			patch.size.is_equal_approx(Vector2(160, 56))
			and mirrored.basis_xform(Vector2(160, 56)).is_equal_approx(Vector2(-56, 160))
			and mirrored.origin.is_equal_approx(Vector2(28, -80))
		),
		"A narrower, mirrored, turned span keeps the slices on the image's area"
	)
	span.free()
	var plank := Sprite2D.new()
	plank.texture = image
	SpanDressing.attach(plank, {"objects": {"p2": {"file": "objects/e1.png"}}}, pack, "p2", {}, 96)
	check(
		plank.get_child_count() == 0 and plank.self_modulate.a == 1.0,
		"A bridge entry without slices keeps the image the pack drew for it"
	)
	plank.free()
	var bare := Sprite2D.new()
	SpanDressing.attach(bare, {}, pack, "p9", {}, 320)
	check(
		bare.get_child_count() == 0 and bare.self_modulate.a == 1.0,
		"Without pack art the span keeps its diagnostic box"
	)
	bare.free()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)
