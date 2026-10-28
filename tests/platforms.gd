extends SceneTree
## Pure synthetic solids, carry and callback checks. No game scene or rendering.
const Collision = preload("res://src/sim/collision.gd")
const Registry = preload("res://src/sim/registry.gd")
const State = preload("res://src/sim/play_state.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Sim = preload("res://src/sim/step.gd")
const World = preload("res://src/sim/world.gd")
const Shapes = preload("res://tests/platform_shapes.gd")
const S := 3600
const BOX := [-4 * S, -8 * S, 4 * S, 0]
const GAP := S / 16
var checks := 0
var failures := 0


func _initialize() -> void:
	full_checks()
	one_way_checks()
	strip_checks()
	carry_checks()
	callback_checks()
	span_type_checks()
	crumble_type_checks()
	block_type_checks()
	print("PLATFORMS_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func full_checks() -> void:
	var entity := solid("unit-full", 64 * S, 64 * S)
	var state := player([entity], 64 * S, 56 * S - GAP)
	var world := geometry()
	Collision.begin_step(state, world, Shapes)
	check(Collision.floor_at(state, world, BOX) != 0, "full entity supplies floor support")
	check(not Collision.overlaps(state, world, BOX), "standing gap is free")
	check(
		not Collision.overlaps(entity, world, [-16 * S, -8 * S, 16 * S, 8 * S]),
		"solid body never collides with itself"
	)
	state.x = 44 * S - GAP
	state.y = 64 * S
	state.vx = 4 * S
	var moved := Collision.horizontal(state, world, BOX, 4 * S, 0)
	check(moved < 4 * S and state.vx == 0, "full entity blocks side entry")
	var actor := {"x": 64 * S, "y": 50 * S, "vx": 0, "vy": 12 * S}
	moved = Collision.vertical(actor, world, BOX, 12 * S)
	check(moved < 12 * S and actor.vy == 0, "terrain-aware actor lands on entity")
	state.x = 64 * S
	state.y = 60 * S
	check(Collision.overlaps(state, world, BOX), "active volume is in the collision query")
	entity.status = 3
	check(not Collision.overlaps(state, world, BOX), "inactive entity does not block")
	entity.status = 1
	entity.broken = 1
	check(
		not Collision.overlaps(state, world, BOX),
		"empty provider disables an otherwise active solid"
	)


func one_way_checks() -> void:
	var state := player([solid("unit-top", 64 * S, 64 * S)], 64 * S, 56 * S)
	var world := geometry()
	Collision.begin_step(state, world, Shapes)
	state.vy = 12 * S
	check(
		Collision.vertical(state, world, BOX, 12 * S) < 12 * S,
		"top-only entity catches downward entry"
	)
	state.y = 70 * S
	state.vy = -16 * S
	check(
		Collision.vertical(state, world, BOX, -16 * S) == -16 * S,
		"top-only entity permits upward entry"
	)
	state.x = 40 * S
	state.y = 68 * S
	state.vx = 20 * S
	check(
		Collision.horizontal(state, world, BOX, 20 * S, 0) == 20 * S,
		"top-only entity permits side entry from below"
	)
	check(Collision.floor_at(state, world, BOX) == 0, "top-only overlap is not a floor from below")


func strip_checks() -> void:
	var state := player([solid("unit-strips", 96 * S, 64 * S)], 96 * S, 56 * S)
	var world := geometry()
	Collision.begin_step(state, world, Shapes)
	state.vy = 16 * S
	check(
		Collision.vertical(state, world, BOX, 16 * S) == 16 * S,
		"plural strips retain the open middle gap"
	)
	check(
		not Collision.support_in_box(world, 92 * S, 60 * S, 100 * S, 90 * S),
		"edge probe sees the same strip gap"
	)
	check(
		Collision.support_in_box(world, 60 * S, 60 * S, 68 * S, 90 * S),
		"edge probe includes registered support"
	)
	state.x = 64 * S
	state.y = 56 * S
	state.vy = 16 * S
	check(Collision.vertical(state, world, BOX, 16 * S) < 16 * S, "left strip supplies a landing")
	state.x = 128 * S
	state.y = 64 * S - GAP
	check(Collision.floor_at(state, world, BOX) != 0, "right strip supplies support independently")


func carry_checks() -> void:
	var entity := solid("unit-top", 64 * S, 64 * S)
	var state := player([entity], 64 * S, 64 * S - GAP)
	state.on_floor = 1
	var world := geometry()
	Collision.begin_step(state, world, Shapes)
	entity.x += 3 * S
	entity.y -= 2 * S
	check(Collision.prepare(state, world, BOX), "carried player remains in free space")
	check(
		state.x == 67 * S and state.y == 62 * S - GAP,
		"carry applies both platform axes before floor handling"
	)
	Collision.prepare(state, world, BOX)
	check(state.x == 67 * S, "multiple prepare calls do not repeat carry")
	var restored := state.duplicate(true)
	var clean_world := geometry()
	state.frame += 1
	restored.frame += 1
	Collision.begin_step(state, world, Shapes)
	Collision.begin_step(restored, clean_world, Shapes)
	state.entities[0].x += 2 * S
	restored.entities[0].x += 2 * S
	Collision.prepare(state, world, BOX)
	Collision.prepare(restored, clean_world, BOX)
	check(state == restored, "fresh per-step bindings reproduce restored carry")
	state.vy = -S
	state.frame += 1
	Collision.begin_step(state, world, Shapes)
	state.entities[0].x += 4 * S
	var x: int = state.x
	Collision.prepare(state, world, BOX)
	check(state.x == x, "rising player does not ride the old support")
	var platform := solid("unit-top", 64 * S, 64 * S)
	var wall := solid("unit-full", 96 * S, 56 * S)
	wall.id = "wall"
	state = player([platform, wall], 64 * S, 64 * S - GAP)
	state.on_floor = 1
	world = geometry()
	Collision.begin_step(state, world, Shapes)
	platform.x += 20 * S
	Collision.prepare(state, world, BOX)
	check(
		not Collision.overlaps(state, world, BOX) and state.x < 76 * S,
		"carry retreats opposite platform motion when pressed into a wall"
	)


func callback_checks() -> void:
	var entity := solid("unit-full", 64 * S, 64 * S)
	var state := player([entity], 64 * S, 84 * S)
	var world := geometry()
	Collision.begin_step(state, world, Shapes)
	state.vy = -12 * S
	Collision.vertical(state, world, BOX, -12 * S)
	check(entity.bump_count == 1 and entity.last_side == 0, "ceiling hit calls below bump once")
	var actor := {"x": 64 * S, "y": 84 * S, "vx": 0, "vy": -12 * S}
	Collision.vertical(actor, world, BOX, -12 * S)
	check(entity.bump_count == 1, "actor geometry does not impersonate a player bump")
	state.frame += 1
	Collision.begin_step(state, world, Shapes)
	state.y = 50 * S
	state.vy = 12 * S
	state.move_action = 2
	entity.break_on_pound = 1
	var moved := Collision.vertical(state, world, BOX, 12 * S)
	check(entity.bump_count == 2 and entity.last_side == 1, "pound calls the upper bump hook")
	check(entity.broken == 1 and moved == 12 * S, "broken solid permits the remaining pound motion")


func span_type_checks() -> void:
	check(Registry.implemented("p3"), "cloud span is registered")
	if not Registry.implemented("p3"):
		return
	var world := typed_world({"span": {"A": "p3", "X": 200, "Y": 160, "E1": "96.9"}})
	var state := State.create(world)
	var entity: Dictionary = state.entities[0]
	var type := Registry.lookup(entity.code)
	check(
		type.solid_box(entity) == [152 * S, 144 * S, 248 * S, 146 * S],
		"span width uses truncated input and raised support line"
	)
	state.x = 200 * S
	state.y = 144 * S - GAP
	state.on_floor = 1
	Sim.advance(state, 0, world)
	check(state.on_floor == 1 and state.y < 144 * S, "real step stands on the typed span")
	var data := Snapshot.encode(state)
	var restored := Snapshot.decode(data, world.identity, world)
	check(restored.ok and Snapshot.encode(restored.state) == data, "typed span snapshot round trip")
	check(
		not (
			World
			. setup_objects(
				{"objects": {"bad": {"A": "p3", "X": 0, "Y": 0, "E1": "wide"}}}, geometry()
			)
			. ok
		),
		"invalid span input is rejected"
	)


func crumble_type_checks() -> void:
	check(Registry.implemented("o20"), "crumbling span is registered")
	if not Registry.implemented("o20"):
		return
	var world := typed_world({"fall": {"A": "o20", "X": 160, "Y": 160, "F": 1}})
	var state := State.create(world)
	var entity: Dictionary = state.entities[0]
	var type := Registry.lookup(entity.code)
	state.x = 160 * S
	state.y = 144 * S - GAP
	state.on_floor = 1
	Collision.begin_step(state, world, Registry)
	type.contact(entity, state, world, 0)
	check(entity.age == 1, "standing starts a 1.2 second countdown")
	state.x = 220 * S
	type.contact(entity, state, world, 0)
	check(entity.age == 0, "leaving before the fall cancels the countdown")
	state.x = 160 * S
	type.contact(entity, state, world, 0)
	for tick in 72:
		type.step(entity, state, world)
	check(
		entity.age == 73 and entity.y == 160 * S and entity.vy == 256,
		"countdown enables falling with post-motion gravity"
	)
	type.step(entity, state, world)
	check(entity.y == 160 * S + 256, "falling uses fixed-step velocity")
	entity.y = state.camera_y + 833 * S
	type.step(entity, state, world)
	check(
		entity.y == 160 * S and entity.age == 0 and entity.vy == 0,
		"repeat form resets after falling below the reference region"
	)
	entity.respawns = 0
	entity.age = 73
	entity.y = state.camera_y + 833 * S
	type.step(entity, state, world)
	check(entity.status == 3, "ordinary crumble is removed below the reference region")


func block_type_checks() -> void:
	check(Registry.implemented("o28"), "hard block is registered")
	if not Registry.implemented("o28"):
		return
	var world := typed_world({"block": {"A": "o28", "X": 160, "Y": 160, "F": 4}})
	var state := State.create(world)
	var entity: Dictionary = state.entities[0]
	var type := Registry.lookup(entity.code)
	check(
		type.solid_box(entity) == [128 * S, 128 * S, 192 * S, 192 * S],
		"hard block has full fixed-size volume"
	)
	var projectile := {"bounces": 4}
	check(
		(
			type.projectile_contact(entity, projectile, state, world) == 3
			and entity.form == 5
			and projectile.bounces == 5
		),
		"first strike cracks the selected block form and continues"
	)
	type.projectile_contact(entity, projectile, state, world)
	check(entity.status == 3 and type.solid_box(entity).is_empty(), "second strike removes volume")
	entity.status = 1
	entity.form = 9
	type.hit(entity, state, world, 2, 0)
	check(entity.status == 1, "pound does not invent an unsupported block break")
	type.hit(entity, state, world, 1, 0)
	check(entity.status == 3, "an initially cracked form needs one projectile strike")


func typed_world(objects: Dictionary) -> Dictionary:
	var world := geometry()
	world.identity = "synthetic platform state".sha256_text()
	world.spawn_x = 64 * S
	world.spawn_y = 100 * S
	world.spawn_facing = 1
	world.map_index = 1
	world.initial_map = 1
	world.map_count = 1
	world.flowers_target = 0
	world.redcoins_target = 0
	check(World.setup_objects({"objects": objects}, world).ok, "typed synthetic placements compile")
	world.maps = {1: world.duplicate()}
	return world


static func geometry() -> Dictionary:
	return {"layers": [], "bridges": [], "width": 1024 * S, "height": 1024 * S}


static func solid(code: String, x: int, y: int) -> Dictionary:
	return {
		"code": code,
		"id": "shape",
		"status": 1,
		"x": x,
		"y": y,
		"vx": 0,
		"vy": 0,
		"bump_count": 0,
		"last_side": -1,
		"broken": 0
	}


static func player(entities: Array, x: int, y: int) -> Dictionary:
	return {
		"x": x,
		"y": y,
		"vx": 0,
		"vy": 0,
		"on_floor": 0,
		"move_action": 0,
		"frame": 1,
		"entities": entities
	}


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
