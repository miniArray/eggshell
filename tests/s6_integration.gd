extends SceneTree
## Mixed-family state and read-only node binding. No frames or recordings.
const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Registry = preload("res://src/sim/registry.gd")
const Collision = preload("res://src/sim/collision.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Life = preload("res://src/sim/life.gd")
const View = preload("res://src/view/level_view.gd")
const Message = preload("res://src/view/message_panel.gd")
const Hud = preload("res://src/view/hud.gd")
const Density = preload("res://tests/density_pack.gd")
const Pack = preload("res://src/level/asset_pack.gd")
const S := State.SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	numeric_option_checks()
	egg_enemy_checks()
	mixed_checks()
	view_checks()
	print("S6_INTEGRATION_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func world_for(objects: Dictionary) -> Dictionary:
	var code := {
		"version": "s3.8.0",
		"name": "Mixed objects",
		"author": "Eggshell",
		"desc": "Invented",
		"startpoint": {"map": 1, "X": 64, "Y": 100},
		"maps": {"map1": {"width": 4096, "height": 1024, "objects": objects}}
	}
	var built := World.build(JSON.stringify(code), {"tilemaps": {}})
	check(built.ok, "Mixed placements compile")
	return built.get("world", {})


func by_id(state: Dictionary, id: String) -> Dictionary:
	for entity: Dictionary in state.entities:
		if entity.id == id:
			return entity
	check(false, "Expected placement exists: " + id)
	return {}


func numeric_option_checks() -> void:
	for pair: Array in [["o20", "F", 1], ["o14", "F", 1], ["o7", "F", 3], ["o4", "M", 2]]:
		var code := {
			"version": "s3.8.0",
			"name": "Numeric options",
			"author": "Eggshell",
			"desc": "",
			"startpoint": {"map": 1, "X": 64, "Y": 100},
			"maps": {"map1": {"width": 4096, "height": 1024, "objects": {}}}
		}
		var object := {"A": pair[0], "X": 200, "Y": 200}
		object[pair[1]] = pair[2]
		code.maps.map1.objects["object"] = object
		var built := World.build(JSON.stringify(code), {"tilemaps": {}})
		check(built.ok, "JSON numeric option is accepted: " + pair[0])
		for invalid: Variant in [-1, 0.5, true]:
			object[pair[1]] = invalid
			built = World.build(JSON.stringify(code), {"tilemaps": {}})
			check(not built.ok, "Invalid numeric option is rejected: " + pair[0])
		object[pair[1]] = pair[2] + 1
		built = World.build(JSON.stringify(code), {"tilemaps": {}})
		check(
			built.ok and built.world.entities[0].code == "?" + pair[0],
			"Unbuilt numeric option becomes a placeholder: " + pair[0]
		)


func egg_enemy_checks() -> void:
	var world := world_for({"flat": {"A": "e4", "X": 200, "Y": 200}})
	var state := State.create(world)
	var enemy: Dictionary = state.entities[0]
	enemy.status = Registry.ACTIVE
	enemy.mode = Registry.lookup("e4").FLAT
	var egg := Registry.spawn_dynamic(
		state,
		world,
		"o7",
		172 * S + S / 2,
		188 * S + S / 2,
		{"mode": 1, "vx": 12 * S, "vy": 8 * S, "bounces": 4}
	)
	Collision.begin_step(state, world, Registry)
	Registry.lookup("o7").travel(egg, state, world)
	check(enemy.status == Registry.DEFEATED, "Egg dispatch reaches an actual enemy receiver")
	check(
		egg.vy == 8 * S and egg.bounces == 4 and egg.colour == 0,
		"A defeated top-only enemy is pierced, not treated as a rock bounce"
	)
	check(egg.fall_on_terrain == 1, "Enemy response retains the terrain-fall flag")


func mixed_checks() -> void:
	var world := world_for(
		{
			"coin": {"A": "o1", "X": 200, "Y": 200},
			"red": {"A": "o2", "X": 250, "Y": 200},
			"flower": {"A": "o3", "X": 300, "Y": 200},
			"shell": {"A": "e6", "X": 500, "Y": 200},
			"cloud": {"A": "p3", "X": 600, "Y": 200},
			"decor": {"A": "d6", "X": 700, "Y": 200},
			"switch": {"A": "o14", "X": 800, "Y": 200}
		}
	)
	var state := State.create(world)
	var projectile := Registry.spawn_dynamic(
		state, world, "enemy_spike", 900 * S, 200 * S, {"vx": 384 * 60, "vy": -768 * 60}
	)
	check(not projectile.is_empty(), "Dynamic enemy projectile uses the owner spawner")
	var pickup := Registry.spawn_dynamic(state, world, "o1", 1000 * S, 200 * S, {})
	check(not pickup.is_empty(), "Dynamic pickup shares the saved suffix")
	var bytes := Snapshot.encode(state)
	var restored := Snapshot.decode(bytes, world.identity, world)
	check(
		restored.ok and Snapshot.encode(restored.state) == bytes, "All families round trip together"
	)
	check(bytes.decode_u32(8) == 10, "Combined layout has version ten")
	var old := bytes.duplicate()
	old.encode_u32(8, 9)
	check(
		not Snapshot.decode(old, world.identity).ok,
		"Version nine is rejected before reading fields"
	)
	for code: String in ["o1", "o2", "o3"]:
		var entity: Dictionary = by_id(state, {"o1": "coin", "o2": "red", "o3": "flower"}[code])
		entity.status = Registry.ACTIVE
		state.x = entity.x
		state.y = entity.y
		Registry.lookup(code).contact(entity, state, world, 0)
	check(
		state.coins == 1 and state.redcoins == 1 and state.flowers == 1,
		"Pickup counters stay separate"
	)
	var readouts := Hud.readouts(state)
	check(
		readouts[1].text == "Coins 1" and readouts[2].text.begins_with("Red 1/"),
		"HUD reads separate coin counters"
	)


func view_checks() -> void:
	var text := "An invented message with a long word: " + "x".repeat(80) + "\n"
	text = text.repeat(12)
	var world := world_for(
		{
			"stem": {"A": "e41", "X": 320, "Y": 200},
			"flat": {"A": "e4", "X": 500, "Y": 200},
			"decor": {"A": "d1", "X": 600, "Y": 200},
			"note": {"A": "o18", "X": 800, "Y": 200, "E1": text}
		}
	)
	var state := State.create(world)
	for enemy: Dictionary in state.enemies:
		enemy.status = Registry.ACTIVE
	var runtime := Registry.spawn_dynamic(state, world, "e41", 900 * S, 200 * S, {})
	var coin := Registry.spawn_dynamic(state, world, "o1", 1000 * S, 200 * S, {})
	var path := Density.create()
	var manifest := Pack.read(path)
	manifest.objects.d1 = manifest.objects.o1.duplicate(true)
	Density.write_json(path, "manifest.json", manifest)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	var view := View.new()
	viewport.add_child(view)
	view.setup(world, path)
	var bytes := Snapshot.encode(state)
	view.render(state)
	check(Snapshot.encode(state) == bytes, "All view binding leaves snapshot bytes unchanged")
	var stem := by_id(state, "stem")
	var head: Sprite2D = view._head_nodes[stem.family_index]
	check_head(head, stem, "Placed")
	var entry: Dictionary = view._runtime._nodes[runtime.token]
	check_head(entry.head, runtime, "Dynamic")
	var node: Sprite2D = view._runtime._nodes[coin.token].node
	check(node.scale.abs() == Vector2(0.5, 0.5), "Dynamic pack art preserves density two")
	var decor: Sprite2D = view._placed_nodes.decor
	var part: Node2D = decor.get_child(0)
	var visual: Sprite2D = part.get_child(0)
	check(visual.scale == Vector2(0.5, 0.5), "Decoration parts preserve density two")
	check(
		visual.texture.get_size() * visual.scale == Vector2(8, 10),
		"Decoration dimensions stay in world pixels"
	)
	var flat := by_id(state, "flat")
	flat.held = 1
	state.move_held_id = flat.token
	view.render(state)
	check(not view._enemy_nodes[flat.family_index].visible, "Placed held enemies are hidden")
	flat.held = 0
	state.move_held_id = 0
	flat.hidden = 1
	runtime.hidden = 1
	view.render(state)
	check(not view._enemy_nodes[flat.family_index].visible, "Placed hidden enemies are hidden")
	check(
		not entry.node.visible and not entry.head.visible, "Dynamic hidden body and head are hidden"
	)
	Registry.lookup("o18").bump(by_id(state, "note"), state, world, 0)
	# The step's end disables the opened block; only then is the state saveable.
	Registry.consume_requests(state, world)
	bytes = Snapshot.encode(state)
	check(not bytes.is_empty(), "An opened message is saveable at the step's end")
	view.render(state)
	var hud := view.get_node("RunHud")
	check(
		hud._message.visible and hud._message._text.text == text,
		"HUD binds the complete immutable message"
	)
	check(Snapshot.encode(state) == bytes, "Message binding is read-only")
	state.message_stage = 2
	state.message_ticks = 0
	state.message_section = Registry.lookup("o18").message_state(state, world).sections - 1
	view.render(state)
	check(hud._message._text.size.y > Message.CONTENT.y, "Long text has measured overflow")
	check(
		is_equal_approx(
			hud._message._text.position.y + hud._message._text.size.y, Message.CONTENT.y
		),
		"The last page reaches the end of the text"
	)
	for size: Vector2 in [Vector2(832, 448), Vector2(170, 1280), Vector2(1280, 80), Vector2(1, 1)]:
		var plan := Message.plan(size, size.y * 0.4)
		check(plan.position.x >= 0 and plan.position.y >= 0, "Message stays inside its container")
		check(
			(
				plan.position.x + plan.size.x <= size.x + 0.001
				and plan.position.y + plan.size.y <= size.y + 0.001
			),
			"Message fits both independent container axes"
		)
	var play_ticks: int = state.play_ticks
	var position: int = state.x
	Sim.advance(state, 2, world)
	check(
		state.play_ticks == play_ticks and state.x == position,
		"Message modal runs before lifetime and motion"
	)
	viewport.free()
	Density.remove(path)


func check_head(node: Sprite2D, entity: Dictionary, label: String) -> void:
	var box: Array = Registry.lookup(entity.code).head_box(entity)
	check(
		node.visible and node.position == Vector2(box[0], box[1]) / S,
		label + " head uses head_box position"
	)
	check(
		(node.texture.get_size() * node.scale).is_equal_approx(
			Vector2(box[2] - box[0], box[3] - box[1]) / S
		),
		label + " head uses head_box size"
	)


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)
