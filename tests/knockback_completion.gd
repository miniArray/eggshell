extends SceneTree
## Invented placements only. Global family events keep terminal zero-valued tweens picked.
const Courses = preload("res://tests/moves.gd")
const Registry = preload("res://src/sim/registry.gd")
const Collision = preload("res://src/sim/collision.gd")
const Armor = preload("res://src/sim/types/armored_walker.gd")
const Soft = preload("res://src/sim/types/soft_walker.gd")
const Sim = preload("res://src/sim/step.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const S := 3600
var checks := 0
var failures := 0


func _initialize() -> void:
	for remaining in [1, -1]:
		terminal_armor(remaining)
	for code: String in ["e11", "e23"]:
		for reverse in [false, true]:
			terminal_family(code, reverse)
		pending_restore(code)
	idle_zero_is_not_picked()
	for before_family in [false, true]:
		restart_without_stop(before_family)
	wall_stop_and_restart()
	regular_mode_changes()
	soft_restart_without_stop()
	pending_validation()
	print("KNOCKBACK_COMPLETION_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func fixture(code: String = "e11", younger: bool = false, reverse: bool = false) -> Dictionary:
	var world := Courses.empty_world()
	check(
		(
			Registry
			. compile_map(
				{
					"floor": {"A": "p2", "X": 500, "Y": 316, "E1": "1024"},
					"wall": {"A": "o9", "X": 512, "Y": 272}
				},
				world
			)
			. ok
		),
		"Invented floor and wall compile"
	)
	var state := Courses.actor(world)
	var older := Registry.spawn_dynamic(
		state, world, code, 320 * S, 284 * S, {"can_despawn": 0, "facing": 1}
	)
	var newer := {}
	if younger:
		newer = Registry.spawn_dynamic(
			state, world, "e11", 480 * S, 284 * S, {"can_despawn": 0, "facing": 1}
		)
		newer.roll_direction = 1
		newer.knock_ticks = 30
		if reverse:
			state.entities = state.entities.slice(0, 2) + [newer, older]
			Registry.attach_views(state)
	if code == "e11":
		older.knock_ticks = 1
		older.roll_direction = -1
		older.vx = -448
	else:
		older.mode = Soft.KNOCKED
		older.slide_from = -Soft.KNOCK_SPEED
		older.slide_total = Soft.KNOCK_TICKS
		older.slide_ticks = 1
	return {"world": world, "state": state, "older": older, "newer": newer}


func terminal_armor(remaining: int) -> void:
	var unit := fixture()
	var armor: Dictionary = unit.older
	armor.knock_ticks = remaining
	armor.roll_direction = 1
	armor.vx = 448 if remaining > 0 else 32
	var x: int = armor.x
	var previous_vx: int = armor.vx
	Collision.begin_step(unit.state, unit.world, Registry)
	Registry.advance(unit.state, unit.world, 0)
	check(
		armor.x == x + previous_vx,
		"The terminal body step still uses the preceding assigned velocity"
	)
	check(armor.vx == 0, "Global99 writes the terminal tween value zero")
	check(
		armor.get("knock_pending", 0) == 1,
		"Natural completion stays pending through regular events"
	)
	check(Armor.knockback_active(armor), "A terminal zero is still an active family member")
	Registry.after_step(unit.state, unit.world)
	check(armor.get("knock_pending", 0) == 0, "The late completion trigger clears pending state")
	check(
		not Armor.knockback_active(armor),
		"The late completion removes the zero from the family pick"
	)
	check(armor.vx == 0, "Completion does not restore walking velocity in the same tick")
	Sim.advance(unit.state, 0, unit.world)
	check(armor.vx == 48 * 60, "Normal movement resumes on the following step")


func terminal_family(code: String, reverse: bool) -> void:
	var unit := fixture(code, true, reverse)
	Sim.advance(unit.state, 0, unit.world)
	check(unit.older.vx == 0, "A naturally completed family body ends the step at zero velocity")
	check(
		unit.newer.knock_ticks == 29,
		"The oldest terminal zero remains picked instead of letting a younger tween trigger the wall"
	)
	Sim.advance(unit.state, 0, unit.world)
	check(
		unit.newer.knock_ticks == -90,
		"After the late completion, the younger tween becomes first and rebounds"
	)


func pending_restore(code: String) -> void:
	var unit := fixture(code, true, true)
	Collision.begin_step(unit.state, unit.world, Registry)
	Registry.advance(unit.state, unit.world, 0)
	var type: Script = Registry.lookup(code)
	check(type.knockback_active(unit.older), "Natural zero remains active before the late hook")
	check(type.knockback_velocity(unit.older) == 0, "The pending natural value is zero")
	var bytes := Snapshot.encode(unit.state)
	check(not bytes.is_empty(), "Pending natural completion saves: " + Snapshot.refusal(unit.state))
	var replay := fixture(code, true, true)
	var decoded := Snapshot.decode(bytes, unit.state.identity, replay.world)
	check(decoded.ok, "The terminal family pick restores")
	if not decoded.ok:
		return
	Registry.after_step(unit.state, unit.world)
	Registry.after_step(decoded.state, replay.world)
	check(
		not type.knockback_active(unit.older), "The late hook removes the completed family member"
	)
	check(
		Snapshot.encode(unit.state) == Snapshot.encode(decoded.state),
		"Late completion restores exactly"
	)
	for tick in 6:
		Sim.advance(unit.state, 0, unit.world)
		Sim.advance(decoded.state, 0, replay.world)
		var future := Snapshot.encode(unit.state)
		check(not future.is_empty(), "Terminal knockback future stays valid")
		check(
			future == Snapshot.encode(decoded.state),
			"Restored family selection has the same future"
		)


func idle_zero_is_not_picked() -> void:
	var unit := fixture("e11", true)
	unit.older.knock_ticks = 0
	Sim.advance(unit.state, 0, unit.world)
	check(
		unit.newer.knock_ticks == -90,
		"An ordinary inactive zero does not block the younger family pick"
	)


func restart_without_stop(before_family: bool) -> void:
	var unit := fixture("e11", true)
	Collision.begin_step(unit.state, unit.world, Registry)
	Armor.step(unit.older, unit.state, unit.world)
	Armor.step(unit.newer, unit.state, unit.world)
	if not before_family:
		Armor.after_advance(unit.state, unit.world)
	Armor.knockback(unit.older, unit.state, unit.world, unit.older.x - 100 * S, false)
	check(unit.older.knock_ticks == 60, "Global98 registers a fresh value tween")
	check(
		unit.older.knock_pending == 1,
		"Starting without Stop preserves the already queued completion"
	)
	check(
		Armor.knockback_velocity(unit.older) == 0, "The old completed value is still first by tag"
	)
	if before_family:
		Armor.after_advance(unit.state, unit.world)
	check(
		unit.newer.knock_ticks == 29,
		"Restart without Stop does not replace the family's terminal zero"
	)
	var replay := fixture("e11", true)
	var decoded := Snapshot.decode(Snapshot.encode(unit.state), unit.state.identity, replay.world)
	check(decoded.ok, "An old pending finish and a new counter save together")
	Registry.after_step(unit.state, unit.world)
	check(
		unit.older.knock_pending == 0 and unit.older.knock_ticks == 0,
		"The old finish clears knockback even after a same-step Global98 start"
	)
	if decoded.ok:
		Registry.after_step(decoded.state, replay.world)
		check(
			Snapshot.encode(unit.state) == Snapshot.encode(decoded.state),
			"The queued finish supersedes the same-step start after restore too"
		)
	Sim.advance(unit.state, 0, unit.world)
	check(
		unit.older.vx == 48 * 60,
		"The queued finish restores normal movement instead of continuing the new tween"
	)


func wall_stop_and_restart() -> void:
	var unit := fixture("e11", true)
	unit.older.knock_ticks = 30
	unit.older.roll_direction = 1
	unit.older.vx = 0
	unit.newer.knock_ticks = 1
	unit.newer.vx = 448
	Collision.begin_step(unit.state, unit.world, Registry)
	Registry.advance(unit.state, unit.world, 0)
	check(
		unit.newer.knock_ticks == -90,
		"A faster older family member makes the terminal body rebound"
	)
	check(
		unit.newer.knock_pending == 0,
		"Global101 Stop cancels the queued natural completion before restart"
	)
	check(unit.newer.vx == 0, "Global99 wrote zero before the rebound registered its new tween")
	Registry.after_step(unit.state, unit.world)
	check(
		unit.newer.knock_ticks == -90,
		"The late hook cannot clear an explicitly stopped-and-restarted tween"
	)
	check(Armor.knockback_active(unit.newer), "The wall rebound stays picked after tick2")


func regular_mode_changes() -> void:
	for mode: String in ["roll", "tongue"]:
		var unit := fixture()
		Collision.begin_step(unit.state, unit.world, Registry)
		Registry.advance(unit.state, unit.world, 0)
		if mode == "roll":
			Armor.start_roll(unit.older, 1)
		else:
			Armor.tongue(unit.older, unit.state, unit.world)
		var vx: int = unit.older.vx
		var timer: int = unit.older.timer
		check(
			unit.older.knock_pending == 1,
			"A regular mode change does not silently remove a queued natural finish"
		)
		Registry.after_step(unit.state, unit.world)
		check(
			unit.older.knock_pending == 0,
			"The queued completion still drains after regular mode changes"
		)
		check(
			unit.older.vx == vx and unit.older.timer == timer,
			"Completion leaves the new mode's velocity and timer alone"
		)


func soft_restart_without_stop() -> void:
	var unit := fixture("e23", true)
	Collision.begin_step(unit.state, unit.world, Registry)
	Registry.advance(unit.state, unit.world, 0)
	var burst := Registry.spawn_dynamic(
		unit.state, unit.world, "e23", 400 * S, 284 * S, {"can_despawn": 0}
	)
	Soft.burst(burst, unit.state, unit.world)
	check(
		unit.older.slide_ticks == 60, "A second real soft burst registers another knockback tween"
	)
	check(unit.older.knock_pending == 1, "The second burst does not Stop the old queued completion")
	check(
		Soft.knockback_velocity(unit.older) == 0, "Milde keeps the old terminal value first by tag"
	)
	var replay := fixture("e23", true)
	var decoded := Snapshot.decode(Snapshot.encode(unit.state), unit.state.identity, replay.world)
	check(decoded.ok, "Milde saves an older pending finish alongside the new slide counter")
	Registry.after_step(unit.state, unit.world)
	if decoded.ok:
		Registry.after_step(decoded.state, replay.world)
		check(
			Snapshot.encode(unit.state) == Snapshot.encode(decoded.state),
			"Restored Milde drains the original pending finish after restart"
		)
	check(
		unit.older.slide_ticks == 0 and unit.older.knock_pending == 0,
		"The old completion clears Milde knockback after the new burst"
	)
	check(unit.older.timer == Soft.KNOCK_PAUSE, "Existing soft recovery timing stays unchanged")


func pending_validation() -> void:
	for code: String in ["e11", "e23"]:
		var unit := fixture(code)
		Collision.begin_step(unit.state, unit.world, Registry)
		Registry.advance(unit.state, unit.world, 0)
		check(Registry.valid(unit.older), "A pending terminal body is valid")
		for value: Variant in [-1, 2, "1"]:
			var bad: Dictionary = unit.older.duplicate()
			bad.knock_pending = value
			check(not Registry.valid(bad), "Pending natural completion must be an int64 boolean")
		var inconsistent: Dictionary = unit.older.duplicate()
		if code == "e11":
			inconsistent.knock_ticks = -90
		else:
			inconsistent.slide_total = 0
		check(
			not Registry.valid(inconsistent),
			"Reject pending states that cannot come from a natural completion"
		)


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
