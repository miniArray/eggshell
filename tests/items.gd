extends SceneTree
## Pure checks on invented placements, integer ticks and canonical snapshots.

const Registry = preload("res://src/sim/registry.gd")
const State = preload("res://src/sim/play_state.gd")
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/sim/collision.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Sim = preload("res://src/sim/step.gd")
const Life = preload("res://src/sim/life.gd")
const Moves = preload("res://src/sim/moves.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const Requests = preload("res://src/sim/move_requests.gd")
const S := State.SCALE
var registry: Script = Registry
var checks := 0
var failures := 0


func _initialize() -> void:
	_check(Registry.implemented("o1"), "A coin has a simulation type")
	_check(registry.has_method("spawn_dynamic"), "Runtime creation is available")
	if registry.has_method("spawn_dynamic"):
		_dynamic_checks()
		_capture_compaction_check()
		_map_reference_reset_check()
		_pickup_checks()
		_origin_checks()
		_encoded_rejection_checks()
		_mixed_enemy_check()
	_check(Registry.implemented("o4"), "Impact health drops have a simulation type")
	if Registry.implemented("o4"):
		_health_checks()
	_check(Registry.implemented("o17"), "A periodic producer has a simulation type")
	if Registry.implemented("o17"):
		_producer_checks()
	_check(Registry.implemented("o9"), "A releasing block has a simulation type")
	_check(Registry.implemented("o15"), "A linked block has a simulation type")
	if Registry.implemented("o9") and Registry.implemented("o15"):
		_block_checks()
		_solid_tongue_check()
		_message_checks()
		_clear_checks()
		_egg_checks()
		_projectile_completion_checks()
		_solid_bump_check()
	_check(
		FileAccess.file_exists("res://src/view/runtime_objects.gd"),
		"Runtime objects have a read-only presentation path"
	)
	if FileAccess.file_exists("res://src/view/runtime_objects.gd"):
		_runtime_view_check()
	print("ITEMS_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _world_for(objects: Dictionary = {}) -> Dictionary:
	var world := {
		"identity": "invented items".sha256_text(),
		"spawn_x": 64 * S,
		"spawn_y": 100 * S,
		"spawn_facing": 1,
		"map_index": 1,
		"initial_map": 1,
		"map_count": 1,
		"flowers_target": 3,
		"redcoins_target": 3,
		"width": 4096 * S,
		"height": 1024 * S,
		"layers": []
	}
	var result := World.setup_objects({"objects": objects}, world)
	_check(result.ok, "Invented placements compile")
	world.maps = {1: world.duplicate()}
	return world


func _dynamic_checks() -> void:
	var world := _world_for({"placed": {"A": "o1", "X": 12, "Y": 20}})
	var state := State.create(world)
	_check(state.entities[0].token == 1, "Placed token follows its immutable source slot")
	var item: Dictionary = registry.call("spawn_dynamic", state, world, "o1", 120 * S, 80 * S, {})
	_check(not item.is_empty(), "A registered dynamic type can be created")
	if item.is_empty():
		return
	_check(item.id == "+1" and item.token == 1_000_001, "Dynamic id and token use the saved serial")
	_check(item.source_index == -1 and state.dynamic_serial == 2, "Creation advances one serial")
	_check(Registry.valid(item) and Snapshot.valid_state(state), "Created state passes its schema")
	_check(Registry.valid_world(state, world), "A world permits an appended dynamic suffix")
	var source: Dictionary = registry.call("source_for", item, world)
	_check(source.x == item.x and source.code == "o1", "Dynamic source lookup is safe")
	_check(
		registry.call("find_token", state, item.token) == item, "Tokens find the live table entry"
	)
	var bytes := Snapshot.encode(state)
	var decoded := Snapshot.decode(bytes, world.identity, world)
	_check(decoded.ok, "Dynamic entity round trips with world validation")
	if decoded.ok:
		_check(bytes == Snapshot.encode(decoded.state), "Restoration preserves canonical bytes")
		var next: Dictionary = registry.call("spawn_dynamic", decoded.state, world, "o1", 0, 0, {})
		_check(next.id == "+2" and next.token == 1_000_002, "Restored serial is never reused")
	var invalid := state.duplicate(true)
	invalid.entities[0].source_index = -1
	_check(not Snapshot.valid_state(invalid), "A dynamic entry cannot replace the placed prefix")
	invalid = state.duplicate(true)
	invalid.entities[1].id = "placed"
	_check(not Snapshot.valid_state(invalid), "A dynamic id cannot duplicate a placement")
	invalid = state.duplicate(true)
	invalid.entities[1].id = "+2"
	invalid.entities[1].token = 1_000_002
	_check(not Snapshot.valid_state(invalid), "A future serial is rejected")
	invalid = state.duplicate(true)
	invalid.entities[1].token = 1
	_check(not Snapshot.valid_state(invalid), "A dynamic token cannot alias a placed token")
	invalid = state.duplicate(true)
	invalid.entities.reverse()
	_check(not Snapshot.valid_state(invalid), "The placed prefix cannot follow dynamic entries")
	state.move_held_id = item.token
	item.status = Registry.DEFEATED
	registry.call("compact", state)
	_check(state.entities.size() == 2, "Compaction preserves a held dynamic entry")
	state.move_held_id = 0
	registry.call("compact", state)
	_check(
		state.entities.size() == 1 and state.entities[0].id == "placed",
		"Only finished dynamic entries are removed"
	)
	var next: Dictionary = registry.call("spawn_dynamic", state, world, "o1", 0, 0, {})
	_check(next.id == "+2", "Compaction does not rewind the serial")
	state.camera_x = 2000 * S
	next.can_despawn = 1
	Registry.lifecycle(next, state, world)
	_check(next.status == Registry.DEFEATED, "Dynamic distance removal cannot camera-respawn")


func _pickup_checks() -> void:
	var world := _world_for(
		{
			"coin": {"A": "o1", "X": 100, "Y": 80},
			"red": {"A": "o2", "X": 200, "Y": 80},
			"flower": {"A": "o3", "X": 300, "Y": 80},
			"dotted": {"A": "o1", "X": 400, "Y": 80, "F": 1},
			"station": {"A": "o6", "X": 500, "Y": 80, "E1": "500", "E2": "100"},
			"later": {"A": "o2", "X": 600, "Y": 80},
		}
	)
	var state := State.create(world)
	for x: int in [100, 200, 300]:
		state.x = x * S
		Registry.contact(state, 0, world)
	_check(
		state.coins == 1 and state.redcoins == 1 and state.flowers == 1,
		"Three pickup kinds use separate lifetime counters"
	)
	Registry.contact(state, 0, world)
	_check(state.flowers == 1, "Repeated contact cannot collect twice")
	state.x = 400 * S
	Registry.contact(state, 0, world)
	_check(state.coins == 1, "A dotted coin is not collectable before a switch")
	Registry.toggle_switch(state, world)
	Registry.contact(state, 0, world)
	_check(state.coins == 2, "A switch enables a dotted coin")
	Registry.toggle_switch(state, world)
	Registry.contact(state, 0, world)
	_check(state.coins == 2, "Toggling cannot restore a collected coin")
	state.x = 500 * S
	Registry.contact(state, 0, world)
	_check(state.life_phase == Life.CHECKPOINT, "A real checkpoint contact captures pickup flags")
	for tick in 300:
		Life.before_step(state, world, Registry.spawn_map)
		if state.life_phase == Life.PLAY:
			break
	state.x = 600 * S
	Registry.contact(state, 0, world)
	_check(state.redcoins == 2, "Collection after the checkpoint changes the current counter")
	Life.quick_restart(state)
	for tick in 400:
		Life.before_step(state, world, Registry.spawn_map)
		if state.life_phase == Life.PLAY:
			break
	_check(state.redcoins == 1 and state.flowers == 1, "Death restores the checkpoint counters")
	_check(
		state.entities[1].collected == 1 and state.entities[5].collected == 0,
		"Death restores each placed pickup flag"
	)
	state.x = 600 * S
	Registry.contact(state, 0, world)
	_check(state.redcoins == 2, "A pickup collected after the checkpoint can be collected again")
	var frozen := state.duplicate(true)
	frozen.life_phase = Life.DEAD
	var item: Dictionary = registry.call(
		"spawn_dynamic", frozen, world, "o1", frozen.x, frozen.y - S, {}
	)
	Registry.contact(frozen, 0, world)
	_check(item.collected == 0, "Pickups do not collect outside the play phase")


func _block_checks() -> void:
	var world := _world_for(
		{
			"release": {"A": "o9", "X": 100, "Y": 80},
			"linked": {"A": "o15", "X": 300, "Y": 80},
		}
	)
	var state := State.create(world)
	var block: Dictionary = state.entities[0]
	var type := Registry.lookup("o9")
	type.bump(block, state, world, 2)
	_check(block.busy == 0, "Side contact does not release an item")
	state.x = 80 * S
	type.bump(block, state, world, 0)
	_check(block.busy == 12, "A lower bump starts a fixed release cycle")
	type.bump(block, state, world, 0)
	for tick in 6:
		Registry.advance(state, world, 0)
	_check(state.entities.size() == 3, "A repeated bump during a cycle releases only one egg")
	if state.entities.size() > 2:
		_check(
			state.entities[2].code == "o7" and state.entities[2].source_index == -1,
			"Released eggs use the saved runtime table"
		)
	for tick in 6:
		Registry.advance(state, world, 0)
	_check(
		block.busy == 0 and block.x == 100 * S and block.y == 80 * S,
		"A block returns to its placement after the bump"
	)
	Moves.give_eggs(state, 6)
	type.bump(block, state, world, 0)
	for tick in 6:
		Registry.advance(state, world, 0)
	_check(state.entities.size() == 3, "A full inventory prevents a new release")
	var linked: Dictionary = state.entities[1]
	var linked_type := Registry.lookup("o15")
	_check(linked_type.solid_box(linked).is_empty(), "An off linked block is not solid")
	state.x = linked.x
	state.y = linked.y
	Registry.toggle_switch(state, world)
	_check(
		linked.enabled == 1 and linked_type.solid_box(linked).is_empty(),
		"Enabling a linked block cannot trap an overlapping player"
	)
	state.x = 700 * S
	Registry.advance(state, world, 0)
	_check(
		not linked_type.solid_box(linked).is_empty(),
		"The linked block becomes solid after the player leaves"
	)
	Registry.toggle_switch(state, world)
	_check(linked_type.solid_box(linked).is_empty(), "The next switch turns the linked block off")


func _egg_checks() -> void:
	var world := _world_for({"egg": {"A": "o7", "X": 100, "Y": 80, "F": 2}})
	var state := State.create(world)
	state.x = 100 * S
	Registry.advance(state, world, 0)
	Registry.contact(state, 0, world)
	_check(
		state.move_eggs == 1 and state.egg_colour_0 == 2,
		"An egg pickup preserves its colour in inventory metadata"
	)
	_check(
		state.entities[0].status == Registry.DEFEATED and state.entities[0].collected == 0,
		"An ordinary egg can return on a map reset"
	)
	state.move_aim = 1
	state.move_aim_angle = 0
	Sim.advance(state, InputBits.THROW, world)
	Registry.consume_requests(state, world)
	_check(
		state.entities.size() == 2 and state.move_eggs == 0,
		"The actual throw request creates one saved projectile"
	)
	if state.entities.size() < 2:
		return
	var projectile: Dictionary = state.entities[1]
	_check(
		projectile.vx == 1024 * 60 and projectile.vy == 0,
		"A horizontal aim uses the fixed projectile speed"
	)
	_check(
		projectile.colour == 2 and projectile.mode == 1,
		"A throw keeps the selected inventory colour"
	)
	Registry.consume_requests(state, world)
	_check(state.entities.size() == 2, "A consumed request is not replayed")
	var bytes := Snapshot.encode(state)
	var restored := Snapshot.decode(bytes, world.identity, world)
	_check(
		restored.ok and Snapshot.encode(restored.state) == bytes,
		"Inventory colour and request cursor round trip"
	)
	if restored.ok:
		Registry.consume_requests(restored.state, world)
		_check(restored.state.entities.size() == 2, "Restoration cannot duplicate a thrown egg")
	world = _world_for({"coin": {"A": "o1", "X": 200, "Y": 60}})
	state = State.create(world)
	projectile = Registry.spawn_dynamic(
		state, world, "o7", 180 * S, 60 * S, {"mode": 1, "vx": 1024 * 60}
	)
	Registry.advance(state, world, 0)
	_check(
		state.coins == 1 and projectile.status == Registry.ACTIVE,
		"A thrown egg collects an ordinary coin without stopping"
	)
	state.move_action = Moves.TONGUE
	state.move_tongue_phase = Moves.TONGUE_OUT
	state.move_tongue_length = 80 * S
	var box := [
		projectile.x - 20 * S, projectile.y - 20 * S, projectile.x + 20 * S, projectile.y + 20 * S
	]
	Registry.tongue_contact(state, world, box)
	_check(
		state.move_tongue_phase == Moves.TONGUE_BLOCKED and projectile.mode == 0,
		"The tongue knocks an egg loose instead of swallowing it"
	)
	_check(projectile.vy == -384 * 60, "A tongue knock uses the fixed vertical impulse")


func _solid_bump_check() -> void:
	var world := _world_for({"release": {"A": "o9", "X": 100, "Y": 80}})
	var state := State.create(world)
	state.x = 100 * S
	state.y = 160 * S
	state.vy = -700 * 60
	Sim.advance(state, 0, world)
	_check(state.entities[0].busy == 12, "The real solid collision dispatches a bump from below")
	for tick in 6:
		Sim.advance(state, 0, world)
		Registry.consume_requests(state, world)
	_check(
		state.entities.size() == 2 and state.entities[1].code == "o7",
		"A real collision bump reaches runtime egg creation"
	)
	_check(
		Snapshot.decode(Snapshot.encode(state), world.identity, world).ok,
		"The collision and release path is saveable"
	)


func _health_checks() -> void:
	var world := _world_for({"drop": {"A": "o4", "X": 100, "Y": 80}})
	var state := State.create(world)
	state.x = 100 * S
	state.health = 29
	Registry.advance(state, world, 0)
	Registry.contact(state, 0, world)
	_check(
		state.health == 30 and state.entities[0].collected == 1,
		"A health drop uses lifetime collection and its cap"
	)
	var drop := Registry.spawn_dynamic(state, world, "o4", 300 * S, 60 * S, {"despawn_ticks": 480})
	state.move_action = Moves.TONGUE
	state.move_tongue_phase = Moves.TONGUE_OUT
	state.move_tongue_length = 80 * S
	Registry.tongue_contact(state, world, [280 * S, 40 * S, 320 * S, 80 * S])
	_check(
		drop.held == 1 and state.move_held_id == drop.token, "The tongue uses the health drop token"
	)
	state.camera_x = 2000 * S
	Registry.lifecycle(drop, state, world)
	_check(drop.status == Registry.ACTIVE, "A held health drop does not despawn")
	Registry.compact(state)
	_check(state.entities.size() == 2, "A held health drop is not compacted")
	state.health = 12
	var requests: Script = Requests
	requests.emit(state, requests.CONSUME, drop.token, state.x, state.y, 0, 0, 0)
	state.move_held_id = 0
	Registry.consume_requests(state, world)
	Registry.compact(state)
	_check(
		state.health == 13 and state.entities.size() == 1,
		"A saved swallow request collects and removes a dynamic health drop"
	)
	Registry.consume_requests(state, world)
	_check(state.health == 13, "The health award is not replayed")


func _producer_checks() -> void:
	var world := _world_for(
		{
			"producer": {"A": "o17", "X": 100, "Y": 80},
			"floor": {"A": "o15", "X": 100, "Y": 112, "F": 1},
		}
	)
	var state := State.create(world)
	var producer: Dictionary = state.entities[0]
	for tick in 62:
		_advance_objects(state, world)
	_check(
		state.entities.size() == 2, "The first producer cycle waits its declared animation duration"
	)
	_advance_objects(state, world)
	_check(state.entities.size() == 3, "A normal producer cycle creates one item")
	if state.entities.size() > 2:
		_check(
			state.entities[2].code == "o7" and state.entities[2].ignore_terrain == 1,
			"Producer eggs preserve their terrain filter"
		)
	state.move_impact += 1
	Registry.consume_requests(state, world)
	_check(producer.fast == 1, "A saved pound impact speeds an active producer")
	var fast_phase: int = producer.phase
	Registry.consume_requests(state, world)
	_check(producer.phase == fast_phase, "A pound impact is not replayed")
	var bytes := Snapshot.encode(state)
	var restored := Snapshot.decode(bytes, world.identity, world)
	_check(
		restored.ok and Snapshot.encode(restored.state) == bytes,
		"The producer cycle and cursor round trip"
	)
	world = _world_for(
		{
			"health": {"A": "o17", "X": 100, "Y": 80, "E1": "o4"},
			"floor": {"A": "o15", "X": 100, "Y": 112, "F": 1},
		}
	)
	state = State.create(world)
	state.health = 30
	for tick in 70:
		_advance_objects(state, world)
	_check(state.entities.size() == 2, "A health producer stops at the health cap")
	state.health = 29
	for tick in 66:
		_advance_objects(state, world)
	_check(
		state.entities.size() == 3 and state.entities[2].code == "o4",
		"The producer selects its declared health payload"
	)


func _message_checks() -> void:
	var world := _world_for(
		{"note": {"A": "o18", "X": 100, "Y": 80, "E1": "A short invented note."}}
	)
	var state := State.create(world)
	var type := Registry.lookup("o18")
	type.bump(state.entities[0], state, world, 0)
	_check(
		state.modal_token == state.entities[0].token and state.message_stage == 1,
		"A message becomes the single modal holder"
	)
	_check(
		type.message(state, world) == "A short invented note.",
		"The read-only message adapter reads immutable text"
	)
	var frame: int = state.frame
	for tick in 78:
		_check(Registry.modal_step(state, world, 0), "The message opening holds the simulation")
	_check(
		state.frame == frame and state.message_stage == 2,
		"Modal ticks do not advance the play frame"
	)
	var bytes := Snapshot.encode(state)
	var restored := Snapshot.decode(bytes, world.identity, world)
	_check(restored.ok and Snapshot.encode(restored.state) == bytes, "An open message round trips")
	Registry.modal_step(state, world, InputBits.THROW)
	_check(state.message_stage == 3, "Throw input closes the message")
	for tick in 30:
		Registry.modal_step(state, world, 0)
	_check(
		state.modal_token == 0 and state.entities[0].busy == 20,
		"Closing releases the holder and starts the reuse delay"
	)
	_check(
		not Registry.modal_step(state, world, 0), "A closed message does not hold the simulation"
	)
	_check(Snapshot.valid_state(state), "Closing leaves valid saved state")
	var invalid := state.duplicate(true)
	invalid.modal_token = 99999
	_check(not Snapshot.valid_state(invalid), "A modal token must name a real modal entity")
	invalid = state.duplicate(true)
	invalid.modal_token = invalid.entities[0].token
	_check(not Snapshot.valid_state(invalid), "A closed message cannot retain the modal holder")
	invalid = state.duplicate(true)
	type.bump(invalid.entities[0], invalid, world, 0)
	invalid.entities[0].busy = 0
	type.bump(invalid.entities[0], invalid, world, 0)
	invalid.message_ticks = 0
	_check(not Snapshot.valid_state(invalid), "An opening message must have a remaining timer")


func _clear_checks() -> void:
	var world := _world_for({"clear": {"A": "o24", "X": 100, "Y": 80}})
	var state := State.create(world)
	var block: Dictionary = state.entities[0]
	var type := Registry.lookup("o24")
	_check(block.y == 48 * S, "The top-anchored clear block uses its placement spawn point")
	for remaining in [2, 1, 0]:
		type.bump(block, state, world, 0)
		_check(block.charges == remaining, "A lower bump uses one clear charge")
		for tick in 6:
			Registry.advance(state, world, 0)
		_check(
			block.height == [0, 22, 34][remaining] * S,
			"Each clear charge shrinks the solid to its declared height"
		)
	_check(
		block.status == Registry.DEFEATED and type.solid_box(block).is_empty(),
		"The last clear charge removes the solid"
	)


func _capture_compaction_check() -> void:
	var world := _world_for()
	var state := State.create(world)
	# These complete schema records exercise compaction independently of spawn opt-in.
	for serial in [1, 2]:
		var entity := (
			Registry
			. create(
				{
					"code": "e1" if serial == 1 else "e5",
					"id": "+%d" % serial,
					"source_index": -1,
					"x": 100 * S,
					"y": 100 * S,
					"variant": 0,
					"mirror": 0,
					"rotation": 0,
					"layer": 8,
					"family_index": serial - 1,
					"properties": {},
				},
				world
			)
		)
		entity.token = Registry.TOKEN_BASE + serial
		entity.spawn_mode = 0
		entity.can_respawn = 0
		entity.status = Registry.DEFEATED if serial == 1 else Registry.ACTIVE
		if serial == 2:
			entity.mode = 4
		state.entities.append(entity)
	state.dynamic_serial = 3
	Registry.attach_views(state)
	state.captured_by = 2
	var captor: Dictionary = state.entities[1]
	Registry.compact(state)
	_check(
		state.entities.size() == 1 and state.entities[0].token == captor.token,
		"Compaction never removes the current captor"
	)
	_check(
		state.captured_by == 1 and state.enemies[0].token == captor.token,
		"Capture follows the captor token when an earlier enemy is removed"
	)


func _runtime_view_check() -> void:
	var world := _world_for()
	var state := State.create(world)
	var item := Registry.spawn_dynamic(state, world, "o1", 100 * S, 80 * S, {"moving": 1})
	var adapter: Script = load("res://src/view/runtime_objects.gd")
	var renderer: RefCounted = adapter.new()
	var presentation: Script = load("res://src/view/level_view.gd")
	var root := Node2D.new()
	var before := Snapshot.encode(state)
	renderer.render(state, world, root, {}, "res://packs/pantry", presentation.placeholder)
	_check(root.get_child_count() == 1, "A dynamic entity creates one presentation node")
	if root.get_child_count() == 1:
		var node: Sprite2D = root.get_child(0)
		_check(
			node.position == Vector2(88, 64) and node.scale == Vector2(0.75, 1),
			"The existing diagnostic texture fits the item's declared bounds"
		)
		item.held = 1
		state.move_held_id = item.token
		renderer.render(state, world, root, {}, "res://packs/pantry", presentation.placeholder)
		_check(not node.visible, "Held dynamic entities do not draw")
		item.held = 0
		state.move_held_id = 0
	_check(before == Snapshot.encode(state), "Presentation never changes the saved state")
	item.status = Registry.DEFEATED
	Registry.compact(state)
	renderer.render(state, world, root, {}, "res://packs/pantry", presentation.placeholder)
	_check(root.get_child_count() == 0, "Compaction removes the obsolete presentation node")
	root.free()


func _advance_objects(state: Dictionary, world: Dictionary) -> void:
	state.frame += 1
	Collision.begin_step(state, world, Registry)
	Registry.advance(state, world, 0)


func _origin_checks() -> void:
	var world := _world_for(
		{
			"origin": {"A": "neutral_origin", "X": 500, "Y": 80},
			"station": {"A": "o6", "X": 200, "Y": 80, "E1": "200", "E2": "100"},
		}
	)
	var state := State.create(world)
	var flower := Registry.spawn_dynamic(
		state, world, "o3", 100 * S, 80 * S, {"origin_token": state.entities[0].token}
	)
	_check(not flower.is_empty(), "A released pickup stores its origin token")
	if flower.is_empty():
		return
	var restored := Snapshot.decode(Snapshot.encode(state), world.identity, world)
	_check(
		restored.ok and restored.state.entities[-1].origin_token == state.entities[0].token,
		"The nonzero pickup origin survives snapshot restoration"
	)
	# A used placed cloud is retained as a tombstone until its flower is collected.
	state.entities[0].status = Registry.DEFEATED
	state.x = 100 * S
	Registry.contact(state, 0, world)
	_check(
		flower.collected == 1 and state.entities[0].collected == 1,
		"Collection marks the live origin as used"
	)
	Registry.spawn_map(state, world, true)
	_check(
		state.entities[0].collected == 0,
		"Origin collection after a checkpoint rolls back with its flag"
	)
	flower = Registry.spawn_dynamic(
		state, world, "o3", 100 * S, 80 * S, {"origin_token": state.entities[0].token}
	)
	Registry.contact(state, 0, world)
	state.x = 200 * S
	Registry.contact(state, 0, world)
	Registry.spawn_map(state, world, true)
	_check(
		state.entities[0].collected == 1 and state.entities[0].checkpoint_collected == 1,
		"A checkpoint preserves the collected origin flag"
	)


func _encoded_rejection_checks() -> void:
	var world := _world_for({"actor": {"A": "e1", "X": 100, "Y": 80}})
	var state := State.create(world)
	var bytes := Snapshot.encode(state)
	var corrupt := _replace_saved_entity_field(bytes, 0, "family_index", 7)
	_check(
		not Snapshot.decode(corrupt, world.identity, world).ok,
		"A checksum-valid wrong enemy family index is rejected, not repaired"
	)
	Registry.spawn_dynamic(state, world, "o1", 200 * S, 80 * S, {})
	bytes = Snapshot.encode(state)
	for pair: Array in [
		["source_index", 0], ["token", 1], ["source_index", -2], ["origin_token", -1]
	]:
		corrupt = _replace_saved_entity_field(bytes, 1, pair[0], pair[1])
		_check(
			not Snapshot.decode(corrupt, world.identity, world).ok,
			"Checksum-valid malformed runtime identity is rejected: " + pair[0]
		)


func _replace_saved_entity_field(
	bytes: PackedByteArray, row: int, field: String, value: int
) -> PackedByteArray:
	var body := bytes.slice(0, -Snapshot.CHECKSUM_SIZE)
	var cursor := Snapshot.count_offset() + 4
	for index in row + 1:
		var code := Snapshot.read_text(body, cursor, body.size())
		cursor = code.cursor
		var id := Snapshot.read_text(body, cursor, body.size())
		cursor = id.cursor + 4
		var schema := Registry.fields(code.value)
		if index == row:
			for slot in schema.size():
				if schema[slot][0] == field:
					body.encode_s64(cursor + slot * 8, value)
					body.append_array(Snapshot.checksum(body))
					return body
		cursor += schema.size() * 8
	_check(false, "A requested saved field exists in the schema")
	return bytes


func _mixed_enemy_check() -> void:
	var added := ""
	for code: String in Registry.codes():
		if (
			code not in Registry.Actor.CODES
			and Registry.lookup(code).get_script_constant_map().get("ENEMY", false)
		):
			added = code
			break
	if added.is_empty():
		print("ITEMS_PENDING: mixed enemy view check requires the enemy track registration")
		return
	var world := _world_for(
		{
			"baseline": {"A": "e1", "X": 100, "Y": 80},
			"added": {"A": added, "X": 200, "Y": 80},
		}
	)
	var state := State.create(world)
	_check(
		state.enemies.size() == 2 and world.enemies.size() == 2,
		"Actor and ENEMY placements share the same enemy view"
	)
	_check(
		(
			state.enemies[0].family_index == 0
			and state.enemies[1].family_index == 1
			and state.enemies[1].layer == 8
		),
		"The mixed view has ordered family indices and the enemy layer"
	)
	var bytes := Snapshot.encode(state)
	var restored := Snapshot.decode(bytes, world.identity, world)
	_check(
		restored.ok and Snapshot.encode(restored.state) == bytes,
		"An Actor and an ENEMY placement round trip together"
	)


func _map_reference_reset_check() -> void:
	var world := _world_for({"actor": {"A": "e5", "X": 100, "Y": 80}})
	var state := State.create(world)
	state.captured_by = 1
	state.move_held_id = 1
	state.move_digest = 1
	state.move_digest_ticks = 8
	var requests: Script = Requests
	requests.emit(state, requests.SPIT, 1, state.x, state.y, 0, 0, 0)
	Registry.spawn_map(state, world)
	_check(
		state.captured_by == 0 and state.move_held_id == 0 and state.move_digest_ticks == 0,
		"A table replacement clears references to the old captor and held item"
	)
	_check(
		state.move_emit_serial == 0 and requests.latest(state).is_empty(),
		"Old-token requests cannot act on reused placed tokens"
	)


func _projectile_completion_checks() -> void:
	var world := _world_for({"block": {"A": "o9", "X": 200, "Y": 60}})
	var state := State.create(world)
	var egg := Registry.spawn_dynamic(
		state, world, "o7", 160 * S, 60 * S, {"mode": 1, "vx": 1024 * 60}
	)
	_advance_objects(state, world)
	_check(
		egg.vx < 0 and egg.bounces == 3 and egg.colour == 1,
		"A solid reaction keeps the normal bounce, budget and colour change"
	)
	_check(
		state.entities[0].busy == 0, "An egg hit does not invent a lower bump on a releasing block"
	)
	world = _world_for()
	state = State.create(world)
	egg = Registry.spawn_dynamic(state, world, "o7", 100 * S, 60 * S, {"mode": 1, "colour": 1})
	egg.status = Registry.DEFEATED
	var type := Registry.lookup("o7")
	type.remove(egg, state, world, true)
	_check(
		state.entities.size() == 2 and state.entities[1].code == "o1",
		"A consuming target may already have stopped the egg before completion"
	)
	type.remove(egg, state, world, true)
	_check(state.entities.size() == 2, "Projectile completion can create loot only once")


func _solid_tongue_check() -> void:
	var world := _world_for({"block": {"A": "o9", "X": 100, "Y": 80}})
	var state := State.create(world)
	state.move_action = Moves.TONGUE
	state.move_tongue_phase = Moves.TONGUE_OUT
	state.move_tongue_length = 80 * S
	Registry.tongue_contact(state, world, [84 * S, 64 * S, 116 * S, 96 * S])
	_check(
		state.move_tongue_phase == Moves.TONGUE_BLOCKED,
		"An enabled full solid blocks the tongue without an edible hook"
	)
	world = _world_for({"off": {"A": "o15", "X": 100, "Y": 80}})
	state = State.create(world)
	state.move_action = Moves.TONGUE
	state.move_tongue_phase = Moves.TONGUE_OUT
	state.move_tongue_length = 80 * S
	Registry.tongue_contact(state, world, [84 * S, 64 * S, 116 * S, 96 * S])
	_check(
		state.move_tongue_phase == Moves.TONGUE_OUT, "An off linked block does not block the tongue"
	)


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)
