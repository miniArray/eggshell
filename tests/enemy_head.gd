extends SceneTree
## Empty head boxes are intentional: ordinary actors and retracted e5 have no head.
const Fixtures = preload("res://tests/fixtures.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Registry = preload("res://src/sim/registry.gd")
const View = preload("res://src/view/level_view.gd")
const Head = preload("res://src/view/enemy_head.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for job: Array in [["actors", 75, "actors"], ["stride", 253, "stride.damage"]]:
		var world := Fixtures.world(job[0])
		var state := State.create(world)
		var replay := Fixtures.recording(job[2])
		for tick: int in job[1]:
			Sim.advance(state, int(replay[tick]) if tick < replay.size() else 0, world)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(832, 448)
		root.add_child(viewport)
		var view := View.new()
		viewport.add_child(view)
		view.setup(world, "")
		var before := Snapshot.encode(state)
		view.render(state)
		var absent := 0
		for index in state.enemies.size():
			var entity: Dictionary = state.enemies[index]
			var type := Registry.lookup(entity.code)
			if entity.status != Registry.ACTIVE or not type.has_method("head_box"):
				continue
			if type.head_box(entity).is_empty():
				absent += 1
				check(
					not view._head_nodes[index].visible,
					"No head drawn for %s at %s-%d" % [entity.code, job[0], job[1]]
				)
		check(absent > 0, "Recording reproduces an active actor with an empty head box")
		var after := Snapshot.encode(state)
		check(before == after, "Head drawing keeps snapshot bytes unchanged")
		print("HEAD_SNAPSHOT %s-%d %s %s" % [job[0], job[1], sha(before), sha(after)])
		viewport.free()
	check_retracted_plant()
	print("ENEMY_HEAD_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func check_retracted_plant() -> void:
	var state := State.create(Fixtures.world("actors"))
	var plant: Dictionary
	for entity: Dictionary in state.enemies:
		if entity.code == "e5":
			plant = entity
	plant.status = Registry.ACTIVE
	plant.head_dx = State.SCALE
	var node := Sprite2D.new()
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	node.texture = ImageTexture.create_from_image(image)
	for size: int in [15, 0, 15]:
		plant.head_size = size
		var before := Snapshot.encode(state)
		Head.present(node, plant, state)
		check(node.visible == (size > 0), "Retracted head hides and extended head returns")
		check(Snapshot.encode(state) == before, "Head visibility does not write simulation state")
	node.free()


static func sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
