extends SceneTree
## Invented contacts. Damage immunity and the movement lock are separate rules.
const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Registry = preload("res://src/sim/registry.gd")
const Body = preload("res://src/sim/enemy_body.gd")
const Life = preload("res://src/sim/life.gd")
const Bits = preload("res://src/sim/move_input.gd")
const S := State.SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	for code: String in ["e28", "e6"]:
		for phase: int in [Life.HURT_KNOCKED, Life.HURT_NONE, Life.HURT_LOOK_AROUND]:
			_hurt_entry(code, phase)
		_recovered_immunity(code)
		_continuous_contact(code)
		_knock_boundary(code)
		_spin_boundary(code)
	# Flower contacts share the callback but keep their own defeat reaction.
	_hurt_entry("e3", Life.HURT_NONE)
	_recovered_step(Bits.RIGHT | Bits.JUMP)
	_recovered_step(Bits.RIGHT)
	_controllability()
	print("ROLLER_SHELL_CONTACTS_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _scene(code: String) -> Dictionary:
	var built := World.build(
		JSON.stringify(
			{
				"version": "s3.8.0",
				"name": "Invented contacts",
				"author": "Eggshell",
				"desc": "",
				"startpoint": {"map": 1, "X": 64, "Y": 100},
				"maps":
				{
					"map1":
					{
						"width": 2048,
						"height": 1024,
						"objects": {"actor": {"A": code, "X": 400, "Y": 320}}
					}
				}
			}
		),
		{"tilemaps": {}}
	)
	check(built.ok, "Synthetic contact world compiles: " + str(built.get("error", "")))
	var world: Dictionary = built.world
	var state := State.create(world)
	var actor: Dictionary = state.entities[0]
	actor.status = Registry.ACTIVE
	actor.started = 1
	actor.x = 400 * S
	actor.y = 320 * S
	actor.vx = 0
	actor.vy = 0
	actor.mode = 0
	actor.contact = 0
	state.x = actor.x
	state.y = actor.y - 10 * S
	state.vy = 160 * 60
	state.on_floor = 0
	state.flutter_ready = 0
	state.boosted_flutter = 0
	return {"world": world, "state": state, "actor": actor}


func _lock(state: Dictionary, phase: int) -> void:
	state.hurt = 12
	state.hurt_phase = phase
	state.invulnerable = 80


func _touch(scene: Dictionary) -> void:
	# Direct hooks supply this step's raw input just as Sim.advance does before contact.
	scene.state.previous_input = Bits.JUMP
	Registry.lookup(scene.actor.code).contact(scene.actor, scene.state, scene.world, Bits.JUMP)


func _hurt_entry(code: String, phase: int) -> void:
	var scene := _scene(code)
	var state: Dictionary = scene.state
	_lock(state, phase)
	if code == "e28":
		state.vy = -160 * 60
	var incoming: int = state.vy
	_touch(scene)
	check(state.vy == incoming, "%s hurt phase %d preserves vertical motion" % [code, phase])
	check(
		state.flutter_ready == 0 and state.boosted_flutter == 0,
		"A suppressed bounce does not grant flutter"
	)
	check(scene.actor.contact == 1, "Entry while hurt still consumes the contact edge")
	if code == "e28":
		check(scene.actor.mode == 2, "A hurt contact still drops the hanging roller")
	elif code == "e3":
		check(scene.actor.status == 3, "A hurt contact still defeats the flower")
	else:
		check(scene.actor.inside == 0, "A hurt contact still ejects the shell resident")
		check(state.entities.size() == 2, "A hurt contact creates the released runner")
		check(scene.actor.vy == -192 * 60, "Ejection keeps the shell's own upward impulse")


func _recovered_immunity(code: String) -> void:
	var scene := _scene(code)
	scene.state.invulnerable = 80
	_touch(scene)
	check(scene.state.vy == -704 * 60, code + " recovered but immune player can bounce")
	check(scene.state.boosted_flutter == 1, "An allowed bounce grants boosted flutter")


func _continuous_contact(code: String) -> void:
	var scene := _scene(code)
	_lock(scene.state, Life.HURT_KNOCKED)
	_touch(scene)
	scene.state.hurt = 0
	scene.state.hurt_phase = Life.HURT_NONE
	_touch(scene)
	check(scene.state.vy == 160 * 60, code + " recovery does not retrigger continuous overlap")
	scene.state.x += 200 * S
	_touch(scene)
	check(scene.actor.contact == 0, "Separation rearms the contact edge")
	scene.state.x = scene.actor.x
	var expected: int = -absi(scene.actor.vy / 2) - 704 * 60
	_touch(scene)
	check(
		scene.state.vy == expected,
		"%s a new entry after recovery can bounce: %d/%d" % [code, scene.state.vy, expected]
	)


func _knock_boundary(code: String) -> void:
	var scene := _scene(code)
	Life.start_hurt(scene.state, 3, true)
	Life.before_step(scene.state, scene.world)
	_touch(scene)
	check(scene.state.vy == 160 * 60, "The last knocked pose still blocks a bounce")
	Life.before_step(scene.state, scene.world)
	check(
		scene.state.hurt == 1 and Life.locks_input(scene.state),
		"The pose-clear tick still blocks movement input"
	)
	_touch(scene)
	check(scene.state.vy == 160 * 60, "Pose recovery does not retrigger continuous overlap")
	scene.state.x += 200 * S
	_touch(scene)
	scene.state.x = scene.actor.x
	var expected: int = -absi(scene.actor.vy / 2) - 704 * 60
	_touch(scene)
	check(scene.state.vy == expected, code + " pose-clear tick permits a new enemy bounce")


func _spin_boundary(code: String) -> void:
	var scene := _scene(code)
	Life.start_hurt(scene.state, 2, false)
	Life.before_step(scene.state, scene.world)
	check(scene.state.hurt == 1, "The spin is on its final movement-lock tick")
	_touch(scene)
	check(scene.state.vy == 160 * 60, code + " final spin tick still blocks the enemy bounce")


func _recovered_step(input: int) -> void:
	var scene := _scene("e28")
	scene.state.y = scene.actor.y - 15 * S
	# The release case must replace a previously held raw jump, not reuse it.
	scene.state.previous_input = Bits.RIGHT | Bits.JUMP
	Life.start_hurt(scene.state, 2, true)
	Sim.advance(scene.state, input, scene.world)
	check(
		scene.state.hurt == 1 and scene.state.hurt_phase == Life.HURT_RECOVERED,
		"The real step reaches the pose-clear boundary"
	)
	check(scene.state.previous_input == input, "The real step saves current raw input")
	check(scene.state.vx == 0, "The pose-clear step still masks directional movement")
	var expected: int = (-704 if input & Bits.JUMP else -320) * 60
	check(
		scene.state.vy == expected,
		"Recovered bounce uses current held/released jump: %d/%d" % [scene.state.vy, expected]
	)


func _controllability() -> void:
	var scene := _scene("e28")
	for phase: int in range(Life.REJOIN, Life.COMPLETE + 1):
		scene.state.life_phase = phase
		Body.bounce(scene.actor, scene.state, Bits.JUMP)
		check(scene.state.vy == 160 * 60, "Non-play phase %d cannot bounce" % phase)
	scene.state.life_phase = Life.PLAY
	scene.state.captured_by = 1
	Body.bounce(scene.actor, scene.state, Bits.JUMP)
	check(scene.state.vy == 160 * 60, "Captured player cannot bounce")
	scene.state.captured_by = 0
	scene.state.modal_token = scene.actor.token
	Body.bounce(scene.actor, scene.state, Bits.JUMP)
	check(scene.state.vy == 160 * 60, "Modal player cannot bounce")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
