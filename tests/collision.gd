extends SceneTree
## Pure synthetic geometry and movement. No level scenes or recorded routes.

const World = preload("res://src/sim/world.gd")
const Polygon = preload("res://src/sim/polygon.gd")
const Collision = preload("res://src/sim/collision.gd")
const Reader = preload("res://src/level/level_code.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Pads = preload("res://src/sim/bounce_pad.gd")
const S := 3600
const BOX := [-4 * S, -8 * S, 4 * S, 0]
const GAP := S / 16
var assertions := 0
var failures := 0


func _initialize() -> void:
	geometry_checks()
	compiler_checks()
	floor_checks()
	slope_checks()
	wall_checks()
	ceiling_checks()
	recovery_checks()
	bridge_checks()
	actor_checks()
	print("COLLISION_RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func geometry_checks() -> void:
	var facts := tile_facts([1, 0, 1, 1, 0, 1])
	var points := World.tile_polygon(0, facts)
	check(not Polygon.overlaps_box(points, S, S, 2 * S, 2 * S), "Triangle empty corner stays empty")
	check(Polygon.overlaps_box(points, 28 * S, 28 * S, 30 * S, 30 * S), "Triangle solid corner")
	check(Polygon.contains_point(points, 16 * S, 16 * S), "Closed diagonal includes contact")
	check(Polygon.contains_point(points, 32 * S, 0), "Polygon includes its vertex")
	var concave := World.tile_polygon(0, tile_facts([0, 0, 1, 0, 1, 0.5, 0.5, 0.5, 0.5, 1, 0, 1]))
	check(
		not Polygon.overlaps_box(concave, 20 * S, 20 * S, 24 * S, 24 * S),
		"Concave notch stays empty"
	)
	check(Polygon.overlaps_box(concave, 4 * S, 20 * S, 8 * S, 24 * S), "Concave lower arm")
	check(
		Polygon.overlaps_box(concave, -S, 7 * S, 33 * S, 8 * S),
		"Edges cross with no contained vertex"
	)
	facts = tile_facts([0, 0, 0.5, 0, 0.5, 1, 0, 1])
	var mirrored := World.tile_polygon(Reader.FLIPPED_HORIZONTAL, facts)
	check(
		World.polygon_bounds(mirrored) == [16 * S, 0, 32 * S, 32 * S], "Horizontal half-cell mirror"
	)
	var diagonal := World.tile_polygon(Reader.FLIPPED_DIAGONAL, facts)
	check(World.polygon_bounds(diagonal) == [0, 0, 32 * S, 16 * S], "Diagonal half-cell transpose")
	var flipped := World.tile_polygon(Reader.FLIPPED_DIAGONAL | Reader.FLIPPED_VERTICAL, facts)
	check(
		World.polygon_bounds(flipped) == [0, 16 * S, 32 * S, 32 * S],
		"Transpose before vertical flip"
	)
	var pixel_edge := World.tile_polygon(0, tile_facts([0.46875, 0, 1, 0, 1, 1, 0.46875, 1]))
	check(pixel_edge[0] == 15 * S, "Tile vertices quantize in pixel units, not tile fractions")
	facts.collision_disabled = [0.0]
	check(World.tile_polygon(0, facts).is_empty(), "Disabled polygon remains empty")
	check(World.tile_polygon(-1, facts).is_empty(), "Empty cell remains empty")


func compiler_checks() -> void:
	var facts := tile_facts([0, 0, 0.5, 0, 0.5, 1, 0, 1])
	facts.collision_disabled = [1.0]
	facts.solid_family = true
	facts.water_family = false
	facts.instances = [{"layer": "L1", "layer_index": 1, "z_order": 0}]
	var grid := JSON.stringify({"c2tilemap": true, "width": 5, "height": 1, "data": "0,0h,0d,1,2"})
	var code := JSON.stringify(
		{
			"version": "1",
			"name": "Unit geometry",
			"desc": "",
			"author": "",
			"startpoint": {"map": 1, "X": 16, "Y": 0},
			"maps":
			{"map1": {"width": 160, "height": 96, "objects": {}, "layer1": {"terrain": grid}}}
		}
	)
	var loaded := World.build(code, {"tilemaps": {"terrain": facts}})
	check(loaded.ok, "Synthetic level compiles integer polygon cache")
	if not loaded.ok:
		return
	var world: Dictionary = loaded.world
	check(world.layers[0].polygons.size() == 5, "Compiler caches each tile and flag combination")
	check(not World.overlaps_box(world, 20 * S, 4 * S, 21 * S, 5 * S), "Compiled half-cell notch")
	check(World.overlaps_box(world, 52 * S, 4 * S, 53 * S, 5 * S), "Compiled mirrored half cell")
	check(World.overlaps_box(world, 84 * S, 4 * S, 85 * S, 5 * S), "Compiled transposed half cell")
	check(
		not World.overlaps_box(world, 84 * S, 24 * S, 85 * S, 25 * S),
		"Compiled transpose empty half"
	)
	check(not World.overlaps_box(world, 100 * S, 4 * S, 101 * S, 5 * S), "Compiled disabled cell")
	check(
		World.overlaps_box(world, 140 * S, 4 * S, 141 * S, 5 * S), "Absent metadata gives full cell"
	)


func floor_checks() -> void:
	var world := terrain([0, 0.5, 1, 0.5, 1, 1, 0, 1])
	var body := actor(80 * S, 80 * S - GAP)
	check(Collision.floor_at(body, world, BOX) == -1, "One-pixel floor probe finds half cell")
	check(not Collision.overlaps(body, world, BOX), "Floor probe leaves position free")
	check(body.y == 80 * S - GAP, "Floor probe does not move state")
	body.y = 78 * S
	check(Collision.floor_at(body, world, BOX) == 0, "Two-pixel gap is airborne")
	body.y = 81 * S
	check(Collision.floor_at(body, world, BOX) == 0, "Embedded actor is not standing")
	check(World.overlaps_box(world, 96 * S, 81 * S, 97 * S, 82 * S), "Far cell edge remains closed")
	check(
		not World.overlaps_box(world, 65 * S, 65 * S, 66 * S, 66 * S), "Half cell empty upper half"
	)
	world = terrain([0, 0, 1, 0, 1, 1, 0, 1], 2, 3)
	body = actor(80 * S, 80 * S - 3 * S / 4)
	body.vy = 200 * 60
	check(Motion.gravity(body, world, "e1"), "Incoming fall detects floor within one pixel")
	check(80 * S - body.y <= GAP, "Incoming floor contact settles instead of hovering")


func slope_checks() -> void:
	var world := terrain([1, 0, 1, 1, 0, 1])
	var body := actor(72 * S, 84 * S - GAP)
	for tick in 8:
		var previous_y: int = body.y
		var support := Collision.floor_at(body, world, BOX)
		check(support == -1, "Uphill support tick %d" % tick)
		check(
			Collision.horizontal(body, world, BOX, 2 * S, support) == 2 * S,
			"Uphill keeps horizontal speed"
		)
		check(body.y == previous_y - 2 * S, "Uphill follows diagonal")
		check(not Collision.overlaps(body, world, BOX), "Uphill ends outside terrain")
	for tick in 8:
		var previous_y: int = body.y
		check(Collision.horizontal(body, world, BOX, -2 * S, -1) == -2 * S, "Downhill keeps speed")
		check(body.y == previous_y + 2 * S, "Downhill snaps to diagonal")
		check(Collision.floor_at(body, world, BOX) == -1, "Downhill stays supported")
	body = actor(99 * S, 64 * S - GAP)
	world.layers.append(terrain([0, 0, 1, 0, 1, 1, 0, 1], 3, 3).layers[0])
	Collision.horizontal(body, world, BOX, 4 * S, -1)
	check(Collision.floor_at(body, world, BOX) == 0, "Leaving slope edge loses floor")
	check(body.y == 64 * S - GAP, "Leaving edge does not snap to a distant floor")
	world = terrain([0, 0.5, 1, 0, 1, 1, 0, 1])
	body = actor(72 * S, 74 * S - GAP)
	Collision.horizontal(body, world, BOX, 4 * S, -1)
	check(body.x == 76 * S and body.y == 72 * S - GAP, "Shallow ramp rises two pixels over four")
	body = actor(72 * S, 84 * S - GAP)
	world = terrain([1, 0, 1, 1, 0, 1])
	body.vy = 100 * 60
	Collision.horizontal(body, world, BOX, 2 * S, -1)
	check(body.vy == 0, "Shallow airborne speed is stopped when mounting a ramp")
	body = actor(72 * S, 84 * S - GAP)
	body.vy = -776 * 60
	Collision.horizontal(body, world, BOX, 2 * S, -1, true)
	check(body.vy == -776 * 60, "Jump speed survives ramp contact")
	world = terrain([0, 0, 1, 1, 0, 1])
	body = actor(88 * S, 84 * S - GAP)
	Collision.horizontal(body, world, BOX, -2 * S, -1)
	check(body.y == 82 * S - GAP, "Mirrored ramp climbs to the left")
	Collision.horizontal(body, world, BOX, 2 * S, -1)
	check(body.y == 84 * S - GAP, "Mirrored ramp descends to the right")
	world = terrain([1, 0, 1, 1, 0, 1])
	world.layers.append(terrain([0, 0, 1, 0, 1, 1, 0, 1], 3, 2).layers[0])
	body = actor(88 * S, 68 * S - GAP)
	Collision.horizontal(body, world, BOX, 8 * S, -1)
	check(body.x == 96 * S and body.y == 64 * S - GAP, "Ramp joins a flat floor without a wall")
	check(Collision.floor_at(body, world, BOX) == -1, "Joined flat floor stays supported")


func wall_checks() -> void:
	var world := terrain([1, 0, 1, 1, 0.5, 1])
	var body := actor(84 * S, 80 * S - GAP)
	var moved := Collision.horizontal(body, world, BOX, 2 * S, -1)
	check(moved < 2 * S, "Steeper-than-diagonal ramp acts as a wall")
	check(body.y == 80 * S - GAP, "Steep ramp does not lift the actor")
	world = terrain([0, 0, 1, 0, 1, 1, 0, 1], 3, 0)
	var layer: Dictionary = world.layers[0]
	for row in 5:
		layer.cells[row * layer.width + 3] = 0
	body = actor(88 * S, 88 * S)
	moved = Collision.horizontal(body, world, BOX, 8 * S, 0)
	check(moved > 0 and moved < 8 * S, "Wall retreat preserves only free horizontal distance")
	check(body.y == 88 * S, "Tall wall does not act as a stair")
	check(body.x + BOX[2] < 96 * S, "Wall retreat leaves actor outside")
	check(96 * S - body.x - BOX[2] <= GAP, "Wall retreat refines to a sixteenth pixel")
	check(Collision.floor_at(body, world, BOX) == 0, "Side wall is not a floor")
	body = actor(91 * S + S / 2, 88 * S)
	body.vx = S / 4
	Collision.horizontal(body, world, BOX, body.vx, 0)
	check(body.vx == 0, "Raised one-pixel wall probe clears velocity before penetration")


func ceiling_checks() -> void:
	var world := terrain([0, 0, 1, 0, 1, 1, 0, 1], 2, 1)
	var body := actor(80 * S, 76 * S)
	body.vy = -8 * S
	var moved := Collision.vertical(body, world, BOX, body.vy)
	check(body.vy == 0, "Ceiling clears upward velocity")
	check(moved > -8 * S and moved < 0, "Ceiling stops upward travel")
	check(body.y + BOX[1] > 64 * S, "Ceiling push-out goes downward")
	check(body.y + BOX[1] - 64 * S <= GAP, "Ceiling push-out refines contact")
	world = terrain([0, 0, 1, 0, 1, 1])
	body = actor(80 * S, 98 * S)
	Collision.vertical(body, world, BOX, -12 * S)
	check(body.y + BOX[1] > 84 * S, "Sloped ceiling uses polygon, not cell bottom")
	check(body.y + BOX[1] - 84 * S <= GAP, "Sloped ceiling has the same contact precision")
	check(Collision.floor_at(body, world, BOX) == 0, "Ceiling contact is not a floor")


func recovery_checks() -> void:
	var world := terrain([0, 0, 1, 0, 1, 1, 0, 1], 2, 3)
	var body := actor(80 * S, 96 * S + S / 2)
	body.vy = 300
	check(
		Collision.prepare(body, world, [-4 * S, -56 * S, 4 * S, 0]),
		"Shallow overlap pushes upward first"
	)
	check(body.y < 96 * S and body.vy == 0, "Upward recovery stops fall velocity")
	check(96 * S - body.y <= GAP, "Upward recovery refines contact")
	world = terrain([0, 0, 1, 0, 1, 1, 0, 1], 3, 0)
	var layer: Dictionary = world.layers[0]
	for row in 5:
		layer.cells[row * layer.width + 3] = 0
	body = actor(94 * S, 88 * S)
	check(Collision.prepare(body, world, BOX), "Deep wall overlap can push sideways")
	check(body.x < 92 * S and body.y == 88 * S, "Sideways recovery tries left before right")
	world = terrain([0, 0, 1, 0, 1, 1, 0, 1], 2, 1)
	body = actor(80 * S, 70 * S)
	check(Collision.prepare(body, world, BOX), "Ceiling overlap can recover downward")
	check(body.y > 72 * S and body.y <= 72 * S + GAP, "Vertical recovery refines below ceiling")
	world = terrain([0, 0, 1, 0, 1, 1, 0, 1])
	body = actor(80 * S, 80 * S)
	check(not Collision.prepare(body, world, BOX), "Enclosed actor reports failed recovery")
	check(body.x == 80 * S and body.y == 80 * S, "Failed recovery restores position")


func bridge_checks() -> void:
	var world := terrain([0, 0, 1, 0, 1, 1, 0, 1], 0, 0)
	world.layers.clear()
	world.bridges = [{"left": 64 * S, "right": 96 * S, "top": 80 * S}]
	var body := actor(80 * S, 79 * S)
	var moved := Collision.vertical(body, world, BOX, 4 * S)
	check(moved < 4 * S and body.y < 80 * S, "Bridge catches downward crossing")
	check(Collision.floor_at(body, world, BOX) == 1, "Bridge support reports its index")
	body = actor(80 * S, 80 * S)
	check(Collision.track_floor(body, world, BOX) == 1, "Exact bridge top is supported")
	check(body.y < 80 * S, "Exact bridge top settles outside the closed surface")
	body = actor(80 * S, 92 * S)
	check(Collision.vertical(body, world, BOX, -16 * S) == -16 * S, "Bridge passes upward travel")
	body = actor(80 * S, 84 * S)
	check(
		Collision.vertical(body, world, BOX, S) == S,
		"Already-overlapped bridge does not catch actor"
	)
	body = actor(60 * S, 84 * S)
	check(
		Collision.horizontal(body, world, BOX, 8 * S, 0) == 8 * S,
		"Bridge side entry from below passes"
	)


func actor_checks() -> void:
	var world := terrain([1, 0, 1, 1, 0, 1])
	var enemy := actor(64 * S, 68 * S)
	enemy.vy = 4 * S
	check(Motion.gravity(enemy, world, "e1"), "Enemy gravity lands on a polygon")
	check(enemy.y + 16 * S < 86 * S, "Enemy follows the diagonal, not the tile top")
	check(86 * S - enemy.y - 16 * S <= GAP, "Enemy gravity shares contact precision")
	enemy.vx = 2 * S
	var before_y: int = enemy.y
	check(
		Motion.move(enemy, world, Motion.box(enemy, "e1"), enemy.vx, true) == 2 * S,
		"Enemy walks uphill"
	)
	check(enemy.y == before_y - 2 * S, "Enemy walking shares slope lift")
	var ball := actor(64 * S, 76 * S)
	ball.vy = 6 * S
	ball.active = 1
	ball.squash = 0
	ball.large = 0
	Pads.advance_entity(ball, world)
	check(ball.y < 82 * S and 82 * S - ball.y <= GAP, "Bounce pad rests on the polygon")
	check(ball.vy == 0, "Bounce pad stops falling on contact")
	check(
		typeof(ball.x) == TYPE_INT and typeof(ball.y) == TYPE_INT, "Contact positions stay integer"
	)
	check(
		typeof(enemy.vx) == TYPE_INT and typeof(enemy.vy) == TYPE_INT,
		"Contact velocities stay integer"
	)


func actor(x: int, y: int) -> Dictionary:
	return {"x": x, "y": y, "vx": 0, "vy": 0}


func tile_facts(polygon: Array) -> Dictionary:
	return {"tile_size": [32, 32], "collision_disabled": [], "collision_polygons": {"0": polygon}}


func terrain(polygon: Array, column: int = 2, row: int = 2) -> Dictionary:
	var points := World.tile_polygon(0, tile_facts(polygon))
	var cells := PackedInt32Array()
	cells.resize(25)
	cells.fill(-1)
	cells[row * 5 + column] = 0
	return {
		"layers":
		[
			{
				"size": 32,
				"width": 5,
				"height": 5,
				"cells": cells,
				"bounds": {0: World.polygon_bounds(points)},
				"polygons": {0: points},
				"solid": true,
				"water": false
			}
		],
		"bridges": []
	}


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
