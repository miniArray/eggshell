extends SceneTree
## Property check: ordinary play keeps every registered type's state saveable.
##
## Each registered code is placed four times on invented terrain (on the floor, in water,
## above a pit and above the player). Seeded random input plays the real step, and between
## steps random hits, tongue grabs and egg contacts strike entities through their hooks, as
## other objects do in play (mostly entities of the code under test). After every step and
## every strike each entity must pass `Registry.valid`, and every tenth step and at the end
## the whole state must pass `Snapshot.valid_state` and round trip, so autosave never
## refuses it. Set VALID_STATES_CODE to check one code. Invented placements and the
## repository collision table only; no frames, recordings or devices.

const Registry = preload("res://src/sim/registry.gd")
const State = preload("res://src/sim/play_state.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const World = preload("res://src/sim/world.gd")
const Table = preload("res://src/level/collision_table.gd")
const Sim = preload("res://src/sim/step.gd")
const Collision = preload("res://src/sim/collision.gd")
const Constants = preload("res://src/sim/script_constants.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const Hits = preload("res://src/sim/hits.gd")
const RegistryTest = preload("res://tests/registry.gd")
const S := preload("res://src/sim/units.gd").SCALE
## Steps played per code, over as many episodes as it takes.
const STEPS := 400
## A strike happens on one step in this many.
const STRIKE_ODDS := 10
## An episode ends once no entity of the code under test was active for this many steps.
const IDLE_STEPS := 40
## Whole-state validation is slower than the entity checks; it runs every this many steps.
const STATE_EVERY := 10
## Where the four placements stand, in pixels. The floor top is at y 448.
const SPOTS := {"floor": [260, 420], "water": [500, 420], "pit": [1040, 240], "above": [230, 300]}
## Each episode starts the player near the next of these spots.
const STARTS := [[200, 420], [470, 420], [900, 420]]
## Bridges need a width and checkpoints a respawn point; the registry's fixture options
## do not place them.
const EXTRA_OPTIONS := {"p1": {"E1": "96"}, "o6": {"E1": "300", "E2": "400"}}
var checks := 0
var failures := 0
var _rng := 1
var _table := {}


func _initialize() -> void:
	_table = Table.read()
	refusal_checks()
	stilt_knock_checks()
	egg_skip_checks()
	var only: String = OS.get_environment("VALID_STATES_CODE")
	for code: String in Registry.codes():
		if only.is_empty() or code == only:
			code_checks(code)
	print("VALID_STATES_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## A refused save names the entity, its code and the field that breaks it.
func refusal_checks() -> void:
	var world := build(level("e35", STARTS[0]))
	var state := State.create(world)
	check(Snapshot.refusal(state) == "", "A valid state has no refusal")
	var walker := first(state, "e35")
	walker.timer = -2
	var reason := Snapshot.refusal(state)
	check(Snapshot.encode(state).is_empty(), "The encoder refuses an out-of-range timer")
	check(
		reason.contains(walker.id) and reason.contains("e35") and reason.contains("timer = -2"),
		"The refusal names the entity, its code and the failing field: " + reason
	)
	walker.timer = 0
	state.flutter_remaining = 99
	reason = Snapshot.refusal(state)
	check(reason.contains("flutter_remaining = 99"), "A player field refusal names it: " + reason)


## A knock that ends in the air leaves the walker walking again with its timer at zero.
func stilt_knock_checks() -> void:
	var world := build(level("e35", STARTS[0]))
	var state := State.create(world)
	var walker := first(state, "e35")
	walker.status = Registry.ACTIVE
	var type: Script = Registry.lookup("e35")
	var lowest := 0
	var refused := -1
	for step in 120:
		if step == 4:
			type.knock(walker, walker.x - 32 * S)
		Sim.advance(state, 0, world)
		lowest = mini(lowest, walker.timer)
		if refused < 0 and not Registry.valid(walker):
			refused = step
	check(refused < 0, "The knocked walker stays valid (first refusal at step %d)" % refused)
	check(lowest == 0, "The knock timer never counts below zero")
	check(walker.phase == type.WALK and walker.timer == 0, "The walker walks again after a knock")


## A thrown egg whose turned integer vector measures a little above its constant speed
## still starts a valid skip on the water.
func egg_skip_checks() -> void:
	var world := build(level("o7", STARTS[0], false))
	var state := State.create(world)
	var type: Script = Registry.lookup("o7")
	var egg := Registry.spawn_dynamic(
		state, world, "o7", 500 * S, 300 * S, {"mode": type.THROWN, "vx": 61_000, "vy": 7400}
	)
	check(not egg.is_empty(), "A thrown egg is created over the pool")
	if egg.is_empty():
		return
	type.enter_liquid(egg, state, world)
	check(egg.mode == type.SKIP, "A shallow entry skips")
	check(egg.skip_vx == type.SPEED / 2, "The skip starts from half the constant egg speed")
	check(Registry.valid(egg), "The skipping egg stays valid: " + Snapshot.refusal(state))


func code_checks(code: String) -> void:
	_rng = 1 + absi(code.hash()) % 100_000
	var failed := ""
	var steps := 0
	var episode := 0
	while steps < STEPS and failed.is_empty():
		var start: Array = STARTS[episode % STARTS.size()]
		var world := build(level(code, start))
		if world.is_empty() and Constants.read(Registry.lookup(code), "DYNAMIC", false):
			# A run-time-only code: an empty course, then created at each spot.
			world = build(level(code, start, false))
		if world.is_empty():
			failed = "placement does not build"
			break
		var state := State.create(world)
		if not dynamic_fill(code, state, world):
			failed = "neither placed nor created at run time"
			break
		var played := play(code, state, world, STEPS - steps)
		steps += played.steps
		failed = played.failed
		if (
			failed.is_empty()
			and not Snapshot.decode(Snapshot.encode(state), world.identity, world).ok
		):
			failed = "the state does not round trip"
		if not failed.is_empty():
			failed = "episode %d: %s" % [episode, failed]
		episode += 1
	check(failed.is_empty(), "%s keeps every play state saveable: %s" % [code, failed])


## Steps one episode with random input and strikes, until the step budget runs out or no
## entity of the code has been active for a while. Returns {steps, failed}: the steps
## played and the first refusal.
func play(code: String, state: Dictionary, world: Dictionary, budget: int) -> Dictionary:
	var input := 0
	var idle := 0
	for step in budget:
		if step % 6 == 0:
			input = random_input()
		Sim.advance(state, input, world)
		var whole := step % STATE_EVERY == STATE_EVERY - 1
		var reason := refusal(state, whole)
		if not reason.is_empty():
			return {"steps": step + 1, "failed": "step %d after a step: %s" % [step, reason]}
		if rand(STRIKE_ODDS) == 0:
			var action := strike(code, state, world)
			reason = refusal(state, whole)
			if not reason.is_empty():
				return {
					"steps": step + 1, "failed": "step %d after %s: %s" % [step, action, reason]
				}
		var active: bool = state.entities.any(
			func(entity: Dictionary) -> bool:
				return entity.code == code and entity.status == Registry.ACTIVE
		)
		idle = 0 if active else idle + 1
		if idle >= IDLE_STEPS:
			return {"steps": step + 1, "failed": refusal(state, true)}
	return {"steps": budget, "failed": refusal(state, true)}


## The encoder's refusal, from a check of each entity or of the whole state.
func refusal(state: Dictionary, whole: bool) -> String:
	if whole:
		return "" if Snapshot.valid_state(state) else Snapshot.refusal(state)
	for entity: Dictionary in state.entities:
		if not Registry.valid(entity):
			return Snapshot.refusal(state)
	return ""


func random_input() -> int:
	var input := 0
	match rand(5):
		0:
			input = InputBits.LEFT
		1, 2:
			input = InputBits.RIGHT
		3:
			input = 0
		4:
			input = InputBits.LEFT if rand(2) else InputBits.RIGHT
	for bit: int in [InputBits.JUMP, InputBits.USE, InputBits.DOWN, InputBits.THROW]:
		if rand(4) == 0:
			input |= bit
	return input


## One strike on a random active entity through a hook the game calls on it; three
## times in four on an entity of the code under test when one is active.
func strike(code: String, state: Dictionary, world: Dictionary) -> String:
	var targets: Array = state.entities.filter(
		func(entity: Dictionary) -> bool:
			return (
				entity.status == Registry.ACTIVE
				and entity.get("held", 0) != 1
				and entity.get("hidden", 0) != 1
			)
	)
	var own := targets.filter(func(entity: Dictionary) -> bool: return entity.code == code)
	if not own.is_empty() and rand(4) != 0:
		targets = own
	if targets.is_empty():
		return "nothing"
	var target: Dictionary = targets[rand(targets.size())]
	var type: Script = Registry.lookup(target.code)
	var from_x: int = target.x + (rand(129) - 64) * S
	var label := "nothing"
	match rand(3):
		0:
			if type.has_method("hit"):
				var kind := 1 + rand(Hits.ICE)
				type.hit(target, state, world, kind, from_x)
				label = "hit %d on %s" % [kind, target.code]
		1:
			if type.has_method("tongue"):
				type.tongue(target, state, world)
				label = "tongue on %s" % target.code
		2:
			if type.has_method("projectile_contact") and Constants.read(type, "ENEMY", false):
				var bounds: Array = type.bounds(target)
				var height: int = maxi(1, (bounds[3] - bounds[1]) / S)
				var egg := thrown_egg(from_x, target.y + bounds[1] + rand(height) * S)
				type.projectile_contact(target, egg, state, world)
				label = "egg on %s" % target.code
	Collision.refresh(world, target)
	return label


## A complete thrown egg record, as the egg passes itself to the objects it meets.
func thrown_egg(x: int, y: int) -> Dictionary:
	var egg := {"code": "o7", "id": "+999999"}
	for pair: Array in Registry.fields("o7"):
		egg[pair[0]] = pair[1]
	egg.x = x
	egg.y = y
	egg.status = Registry.ACTIVE
	return egg


## A code that cannot be placed is created at run time at each spot instead.
func dynamic_fill(code: String, state: Dictionary, world: Dictionary) -> bool:
	if not first(state, code).is_empty():
		return true
	if not Constants.read(Registry.lookup(code), "DYNAMIC", false):
		return false
	var made := false
	for spot: Array in SPOTS.values():
		var entity := Registry.spawn_dynamic(
			state, world, code, spot[0] * S, spot[1] * S, options(code)
		)
		made = made or not entity.is_empty()
	return made


func options(code: String) -> Dictionary:
	return EXTRA_OPTIONS.get(code, RegistryTest.FIXTURE_OPTIONS.get(code, {})).duplicate()


## 64 by 16 cells of 32 px: a floor with a pit, a pool on the floor and a wall.
func level(code: String, start: Array, placed := true) -> Dictionary:
	var solid := []
	var water := []
	for row in 16:
		for column in 64:
			var floor := row >= 14 and (column < 30 or column > 34)
			var wall := row >= 10 and column in [44, 45]
			solid.append("0" if floor or wall else "-1")
			water.append("0" if row >= 9 and row < 14 and column >= 12 and column < 20 else "-1")
	var objects := {}
	for name: String in SPOTS:
		if placed:
			var placement := {"A": code, "X": SPOTS[name][0], "Y": SPOTS[name][1]}
			placement.merge(options(code), true)
			objects[name] = placement
	var tiles := func(cells: Array) -> String:
		return JSON.stringify(
			{"c2tilemap": true, "width": 64, "height": 16, "data": ",".join(cells)}
		)
	return {
		"version": "s3.13.1",
		"name": "Saveable states",
		"desc": "Synthetic property course",
		"author": "Eggshell",
		"flowers": 0,
		"redcoins": 0,
		"startpoint": {"map": 1, "X": start[0], "Y": start[1]},
		"maps":
		{
			"map1":
			{
				"width": 2048,
				"height": 512,
				"layer1": {"castle32": tiles.call(solid), "water3": tiles.call(water)},
				"objects": objects
			}
		}
	}


func build(source: Dictionary) -> Dictionary:
	var built := World.build(JSON.stringify(source), _table)
	return built.world if built.ok else {}


func first(state: Dictionary, code: String) -> Dictionary:
	for entity: Dictionary in state.entities:
		if entity.code == code:
			return entity
	return {}


## Deterministic draws from 0 to `limit` - 1 (a 31-bit linear congruential generator).
func rand(limit: int) -> int:
	_rng = (_rng * 1103515245 + 12345) & 0x7fffffff
	return (_rng >> 8) % limit


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
