extends SceneTree
## Invented geometry only. Real contacts register starts; real Sim steps finish them.
const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Registry = preload("res://src/sim/registry.gd")
const Giant = preload("res://src/sim/types/soft_giant.gd")
const Small = preload("res://src/sim/types/soft_walker.gd")
const Birth = preload("res://src/sim/entity_lifecycle.gd")
const Life = preload("res://src/sim/life.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Moves = preload("res://src/sim/moves.gd")
const S := State.SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	_regular_boundary()
	_registration()
	_duration_and_begin_level()
	_scenario([["A", "B"]], ["B", "A"], ["A", "B"])
	_scenario([["A"], ["B"]], ["A", "B"], ["B", "A"])
	_scenario([["A", "B"], ["C", "D"]], ["D", "B", "A", "C"], ["C", "D", "A", "B"])
	_validation()
	print("SOFT_GIANT_SCHEDULING_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _world(objects: Dictionary = {}) -> Dictionary:
	var built := World.build(
		JSON.stringify(
			{
				"version": "s3.8.0",
				"name": "Invented split scheduling",
				"author": "Eggshell",
				"desc": "",
				"startpoint": {"map": 1, "X": 64, "Y": 100},
				"maps": {"map1": {"width": 4096, "height": 1024, "objects": objects}}
			}
		),
		{"tilemaps": {}}
	)
	check(built.ok, "Invented world compiles")
	return built.world


func _fixture(labels: Array) -> Dictionary:
	var world := _world()
	var state := State.create(world)
	var parents := {}
	# Birth/UID order deliberately differs from start-registration order.
	var reversed := labels.duplicate()
	reversed.reverse()
	for label: String in reversed:
		parents[label] = Registry.spawn_dynamic(
			state, world, "e24", (400 + 160 * labels.find(label)) * S, 268 * S, {}
		)
		check(not parents[label].is_empty(), "Real runtime giant is created: " + label)
	return {"state": state, "world": world, "parents": parents}


func _start(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	entity.status = Registry.ACTIVE
	state.x = entity.x
	state.y = entity.y - 50 * S
	state.vx = 0
	state.vy = 300 * 60
	state.move_action = Moves.POUND_FALL
	# Invoke the real contact, not a manually assigned mode or scheduling stamp.
	Giant.contact(entity, state, world, 0)
	check(entity.mode == Giant.SQUASH, "Real pound contact registers squash")


func _children(state: Dictionary) -> Array:
	return state.entities.filter(func(entity: Dictionary) -> bool: return entity.code == "e23")


func _restore(state: Dictionary, world: Dictionary) -> Dictionary:
	var bytes := Snapshot.encode(state)
	check(not bytes.is_empty(), "Saved scheduling state encodes: " + Snapshot.refusal(state))
	var restored := Snapshot.decode(bytes, world.identity, world)
	check(restored.ok, "Saved scheduling state restores: " + str(restored.get("error", "")))
	return restored.get("state", {})


func _regular_boundary() -> void:
	var objects := {"giant": {"A": "e24", "X": 400, "Y": 268}}
	var world := _world(objects)
	var state := State.create(world)
	var giant: Dictionary = state.entities[0]
	_start(giant, state, world)
	for tick in Giant.SQUASH_TICKS:
		Registry.advance(state, world, 0)
	check(giant.timer == 0 and Giant.height(giant) == 32, "Natural timer reaches half height")
	check(giant.status == Registry.ACTIVE, "Completion retains parent during regular events")
	check(_children(state).is_empty(), "Children do not exist during regular events")
	state.x += 10 * S
	state.y += 5 * S
	Registry.contact(state, 0, world)
	check(
		state.x == giant.x + giant.pin_dx and state.y == giant.y - 28 * S,
		"Regular contacts retain the half-height pin after player movement"
	)
	Life.after_step(state, world)
	check(_children(state).is_empty(), "Life.after_step still precedes the split")
	var restored_world := _world(objects)
	var restored := _restore(state, restored_world)
	Registry.after_step(state, world)
	Registry.after_step(restored, restored_world)
	check(giant.status == Registry.DEFEATED, "Post-regular-step boundary removes the parent")
	_check_children(state, {"A": giant}, ["A"])
	check(
		Snapshot.encode(state) == Snapshot.encode(restored), "Pending natural completion restores"
	)
	Registry.after_step(state, world)
	check(_children(state).size() == 4, "A repeated late boundary does not split twice")


func _registration() -> void:
	var fixture := _fixture(["A"])
	var state: Dictionary = fixture.state
	var world: Dictionary = fixture.world
	var giant: Dictionary = fixture.parents.A
	state.x = giant.x
	state.y = giant.y - 50 * S
	state.vy = 300 * 60
	Giant.contact(giant, state, world, 0)
	check(giant.mode == Giant.PAUSE, "Plain landing stalls without a schedule registration")
	check(state.soft_squash_batch == 0, "No batch exists before a pound starts SQUASH")
	giant.contact = 0
	_start(giant, state, world)
	Giant.contact(giant, state, world, 0)
	check(
		state.soft_squash_batch == 1 and state.soft_squash_ordinal == 1,
		"Repeated squash contacts do not register a second start"
	)
	Sim.advance(state, 0, world)
	check(state.soft_squash_ordinal == 0, "The real next pretick drains pending starts")


func _duration_and_begin_level() -> void:
	var fixture := _fixture(["A"])
	var state: Dictionary = fixture.state
	var world: Dictionary = fixture.world
	var giant: Dictionary = fixture.parents.A
	_start(giant, state, world)
	for tick in Giant.SQUASH_TICKS - 1:
		Sim.advance(state, 0, world)
	check(
		giant.timer == 1 and _children(state).is_empty(), "Normal squash lasts 0.25 s, not 14 ticks"
	)
	Sim.advance(state, 0, world)
	_check_children(state, fixture.parents, ["A"])
	check(giant.status == Registry.DEFEATED, "Real Sim.advance dispatches the natural completion")
	check(not state.entities.has(giant), "Runtime parent compacts only after its split")

	fixture = _fixture(["A"])
	state = fixture.state
	world = fixture.world
	giant = fixture.parents.A
	_start(giant, state, world)
	giant.timer = 1
	Sim.begin_level(state, world)
	var children := _children(state)
	check(children.size() == 4, "begin_level also runs the genuine late boundary")
	for child: Dictionary in children:
		check(
			(
				child.slide_ticks == 29
				and child.birth_frame == 0
				and child.birth_phase == Birth.TICK2_BIRTH
			),
			"A begin_level split child runs only in the next warm-up step"
		)


func _scenario(batches: Array, row_order: Array, expected: Array) -> void:
	var labels := []
	for batch: Array in batches:
		labels.append_array(batch)
	var fixture := _fixture(labels)
	var state: Dictionary = fixture.state
	var world: Dictionary = fixture.world
	var parents: Dictionary = fixture.parents
	for batch_index in batches.size():
		for label: String in batches[batch_index]:
			_start(parents[label], state, world)
		if batch_index < batches.size() - 1:
			# A real pretick drain, without a frame or parent-birth change. This is
			# deliberately not a frame-based grouping of schedule registrations.
			Registry.advance(state, world, 0)
	for label: String in labels:
		parents[label].timer = 2  # Align different natural durations at one completion step.
	var reordered := []
	for label: String in row_order:
		reordered.append(parents[label])
	state.entities = reordered
	Registry.attach_views(state)
	check(state.frame == 0, "Distinct pending-list drains can happen in the same frame")
	check(state.soft_squash_batch == batches.size(), "Each actual start batch has one saved number")
	for batch_index in batches.size():
		for ordinal in batches[batch_index].size():
			var parent: Dictionary = parents[batches[batch_index][ordinal]]
			check(
				parent.squash_batch == batch_index + 1 and parent.squash_ordinal == ordinal + 1,
				"Contact saves batch and start-registration ordinal independently of row/UID"
			)
	var restored_world := _world()
	var restored := _restore(state, restored_world)  # Includes undrained last-batch starts.
	Sim.advance(state, 0, world)
	Sim.advance(restored, 0, restored_world)
	check(_children(state).is_empty(), "Aligned timers still wait for their natural last tick")
	check(
		Snapshot.encode(state) == Snapshot.encode(restored),
		"Undrained starts restore the same future"
	)
	var playing_world := _world()
	var playing := _restore(state, playing_world)  # All start batches are now playing.
	Sim.advance(state, 0, world)
	Sim.advance(restored, 0, restored_world)
	Sim.advance(playing, 0, playing_world)
	_check_children(state, parents, expected)
	check(
		Snapshot.encode(state) == Snapshot.encode(restored),
		"Restore retains ordered completion output"
	)
	check(
		Snapshot.encode(state) == Snapshot.encode(playing),
		"Playing batches restore ordered completion output"
	)
	check(
		state.entities.size() == labels.size() * 4,
		"All runtime parents compact after late creation"
	)
	for tick in 12:
		Sim.advance(state, 0, world)
		Sim.advance(restored, 0, restored_world)
		Sim.advance(playing, 0, playing_world)
	check(
		Snapshot.encode(state) == Snapshot.encode(restored),
		"Restored undrained queue has the same later future"
	)
	check(
		Snapshot.encode(state) == Snapshot.encode(playing),
		"Restored playing queue has the same later future"
	)
	# High-water state survives after every original runtime parent was removed.
	var next := Registry.spawn_dynamic(state, world, "e24", 1000 * S, 268 * S, {})
	_start(next, state, world)
	check(
		next.squash_batch == batches.size() + 1, "Later starts do not reuse compacted batch numbers"
	)


func _check_children(state: Dictionary, parents: Dictionary, expected: Array) -> void:
	var children := _children(state)
	check(children.size() == expected.size() * 4, "Four copies per ordered natural completion")
	if children.size() != expected.size() * 4:
		return
	var previous_birth := 0
	for group in expected.size():
		var parent: Dictionary = parents[expected[group]]
		for ordinal in Giant.COPIES.size():
			var child: Dictionary = children[group * 4 + ordinal]
			var copy: Array = Giant.COPIES[ordinal]
			check(
				child.x == parent.x + copy[0] * S and child.y == parent.y + copy[1] * S,
				"Completion order %s, native child action %d" % [expected, ordinal + 1]
			)
			check(
				(
					child.mode == Small.TUMBLE
					and child.slide_from == copy[2] * 60
					and child.vy == copy[3] * 60
					and child.facing == signi(copy[2])
					and child.slide_ticks == 30
					and child.slide_total == 30
					and child.vx == 0
				),
				"Launch velocities and duration are unchanged; no regular-step child tick"
			)
			check(
				(
					child.birth_frame == state.frame
					and child.birth_phase == Birth.TICK2_BIRTH
					and child.birth_serial > previous_birth
				),
				"All four action-ordered births have saved TICK2 identity"
			)
			previous_birth = child.birth_serial


func _validation() -> void:
	var fixture := _fixture(["A", "B"])
	var state: Dictionary = fixture.state
	var world: Dictionary = fixture.world
	for parent: Dictionary in fixture.parents.values():
		_start(parent, state, world)
	check(Snapshot.valid_state(state), "Registered starts pass saved-state validation")
	for field: String in ["soft_squash_batch", "soft_squash_ordinal"]:
		for value: Variant in [-1, "1", Giant.MAX_SCHEDULE + 1]:
			var bad := state.duplicate(true)
			bad[field] = value
			check(not State.valid(bad), "Reject invalid level scheduling counter " + field)
	for field: String in ["squash_batch", "squash_ordinal"]:
		for value: Variant in [-1, 0, "1", Giant.MAX_SCHEDULE + 1]:
			var bad := state.duplicate(true)
			bad.entities[0][field] = value
			check(not Snapshot.valid_state(bad), "Reject invalid entity scheduling field " + field)
	var beyond := state.duplicate(true)
	beyond.entities[0].squash_batch = state.soft_squash_batch + 1
	check(not Snapshot.valid_state(beyond), "Reject a batch beyond the saved high-water counter")
	beyond = state.duplicate(true)
	beyond.entities[0].squash_ordinal = state.soft_squash_ordinal + 1
	check(not Snapshot.valid_state(beyond), "Reject a pending ordinal beyond the saved counter")
	var duplicate := state.duplicate(true)
	duplicate.entities[0].squash_ordinal = duplicate.entities[1].squash_ordinal
	check(not Snapshot.valid_state(duplicate), "Reject duplicate registration identities")
	var inconsistent := state.duplicate(true)
	inconsistent.entities[0].mode = Giant.WAIT
	check(not Snapshot.valid_state(inconsistent), "Reject a registration stamp outside SQUASH")
	inconsistent = state.duplicate(true)
	inconsistent.entities[0].timer = Giant.SQUASH_TICKS + 1
	check(not Snapshot.valid_state(inconsistent), "Reject a squash timer longer than 0.25 s")
	var wide := state.duplicate(true)
	wide.soft_squash_batch = 1 << 40
	wide.entities[0].squash_batch = wide.soft_squash_batch
	wide.entities[1].squash_batch = wide.soft_squash_batch
	check(Snapshot.valid_state(wide), "Registration validation keeps full int64 batch identity")
	wide.entities[0].squash_batch = 1
	wide.entities[1].squash_batch = (1 << 32) + 1
	wide.entities[1].squash_ordinal = wide.entities[0].squash_ordinal
	check(Snapshot.valid_state(wide), "Distinct int64 batches must not alias as 32-bit keys")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)
