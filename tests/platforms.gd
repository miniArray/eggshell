extends SceneTree
## Pure synthetic solids, carry and callback checks. No game scene or rendering.
const Collision = preload("res://src/sim/collision.gd")
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
