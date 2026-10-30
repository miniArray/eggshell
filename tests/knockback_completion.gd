extends SceneTree
## Invented placements only. Terminal zero remains picked through regular family events.
const Courses = preload("res://tests/moves.gd")
const Registry = preload("res://src/sim/registry.gd")
const Collision = preload("res://src/sim/collision.gd")
const Knockback = preload("res://src/sim/knockback.gd")
const Armor = preload("res://src/sim/types/armored_walker.gd")
const Soft = preload("res://src/sim/types/soft_walker.gd")
const Sim = preload("res://src/sim/step.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const S := 3600
var checks := 0
var failures := 0


func _initialize() -> void:
	for total in [60, 90]:
		terminal_armor(total)
	for code: String in ["e11", "e23"]:
		for reverse in [false, true]:
			terminal_family(code, reverse)
		pending_restore(code)
	idle_zero_is_not_picked()
	wall_stop_and_restart()
	regular_mode_changes()
	print("KNOCKBACK_COMPLETION_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


static func configure_tween(
	entity: Dictionary, remaining: int, from_vx: int, total: int = 60
) -> void:
	Knockback.clear(entity)
	Knockback.start(entity, from_vx, total)
	entity.knock_tweens[0].remaining = remaining
	entity.knock_tweens[0].phase = Knockback.PLAYING


static func active_rows(entity: Dictionary) -> Array:
	return entity.knock_tweens.filter(
		func(tween: Dictionary) -> bool:
			return tween.phase in [Knockback.SCHEDULED, Knockback.PLAYING]
	)


static func fixture(
	code: String = "e11", younger: bool = false, reverse: bool = false
) -> Dictionary:
	var world := Courses.empty_world()
	assert(
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
		)
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
		configure_tween(newer, 30, 448 * 60)
		if reverse:
			state.entities = state.entities.slice(0, 2) + [newer, older]
			Registry.attach_views(state)
	configure_tween(older, 1, -448 * 60)
	older.vx = -448
	if code == "e23":
		older.mode = Soft.KNOCKED
	return {"world": world, "state": state, "older": older, "newer": newer}


func terminal_armor(total: int) -> void:
	var unit := fixture()
	var armor: Dictionary = unit.older
	configure_tween(armor, 1, (448 if total == 60 else 48) * 60, total)
	armor.vx = Knockback.value(armor)
	var x: int = armor.x
	var previous_vx: int = armor.vx
	Collision.begin_step(unit.state, unit.world, Registry)
	Registry.advance(unit.state, unit.world, 0)
	check(armor.x == x + previous_vx, "Terminal body motion uses the preceding assigned velocity")
	check(armor.vx == 0, "Global99 assigns the terminal zero value")
	check(Knockback.pending(armor), "Natural completion stays pending through regular events")
	check(Armor.knockback_active(armor), "A terminal zero remains eligible")
	Registry.after_step(unit.state, unit.world)
	check(active_rows(armor).is_empty(), "The late trigger removes the completed active tween")
	check(
		armor.knock_tweens[0].phase == Knockback.FINISHED_WAITING,
		"Natural release waits for the next behavior tick2"
	)
	check(not Armor.knockback_active(armor), "Global102 clears eligibility")
	check(armor.vx == 0, "Completion does not restore walking velocity this tick")
	Sim.advance(unit.state, 0, unit.world)
	check(armor.vx == 48 * 60, "Normal movement resumes on the next step")


func terminal_family(code: String, reverse: bool) -> void:
	var unit := fixture(code, true, reverse)
	Sim.advance(unit.state, 0, unit.world)
	check(unit.older.vx == 0, "A completed family body ends the step at zero velocity")
	check(
		unit.newer.knock_tweens[0].remaining == 29,
		"The oldest terminal zero blocks the younger tween's wall filter, independent of table order"
	)
	Sim.advance(unit.state, 0, unit.world)
	check(
		unit.newer.knock_tweens[0].total == 90,
		"The younger tween rebounds after eligibility clears"
	)


func pending_restore(code: String) -> void:
	var unit := fixture(code, true, true)
	Collision.begin_step(unit.state, unit.world, Registry)
	Registry.advance(unit.state, unit.world, 0)
	var type: Script = Registry.lookup(code)
	check(type.knockback_active(unit.older), "The pending zero remains eligible")
	check(type.knockback_velocity(unit.older) == 0, "The pending natural value is zero")
	var bytes := Snapshot.encode(unit.state)
	check(not bytes.is_empty(), "Pending completion saves: " + Snapshot.refusal(unit.state))
	var replay := fixture(code, true, true)
	var decoded := Snapshot.decode(bytes, unit.state.identity, replay.world)
	check(decoded.ok, "The terminal family pick restores")
	if not decoded.ok:
		return
	Registry.after_step(unit.state, unit.world)
	Registry.after_step(decoded.state, replay.world)
	check(not type.knockback_active(unit.older), "The late hook removes eligibility")
	for tick in 6:
		Sim.advance(unit.state, 0, unit.world)
		Sim.advance(decoded.state, 0, replay.world)
		var future := Snapshot.encode(unit.state)
		check(not future.is_empty(), "The terminal future stays valid")
		check(future == Snapshot.encode(decoded.state), "Restored selection has the same future")


func idle_zero_is_not_picked() -> void:
	var unit := fixture("e11", true)
	Knockback.clear(unit.older)
	Sim.advance(unit.state, 0, unit.world)
	check(
		unit.newer.knock_tweens[0].total == 90, "An ordinary inactive zero does not block selection"
	)


func wall_stop_and_restart() -> void:
	var unit := fixture("e11", true)
	configure_tween(unit.older, 30, 448 * 60)
	unit.older.vx = 0
	configure_tween(unit.newer, 1, 448 * 60)
	unit.newer.vx = 448
	Collision.begin_step(unit.state, unit.world, Registry)
	Registry.advance(unit.state, unit.world, 0)
	check(
		Knockback.value(unit.newer) == -48 * 60,
		"The faster older body makes the terminal body rebound"
	)
	check(not Knockback.pending(unit.newer), "Global101 Stop cancels the old completion")
	check(unit.newer.vx == 0, "Global99 wrote zero before the rebound registered")
	Registry.after_step(unit.state, unit.world)
	check(
		unit.newer.knock_tweens.size() == 1, "Tick2 releases the stopped row, not the replacement"
	)
	check(Armor.knockback_active(unit.newer), "The wall rebound remains eligible after tick2")


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
			Knockback.pending(unit.older), "A mode change does not delete a queued natural finish"
		)
		Registry.after_step(unit.state, unit.world)
		check(not Knockback.pending(unit.older), "The finish drains after regular mode changes")
		check(
			unit.older.vx == vx and unit.older.timer == timer, "Completion leaves mode motion alone"
		)


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
