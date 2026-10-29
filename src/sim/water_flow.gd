extends RefCounted
## Flowing water: the `flowWater` tilemap's tiles push the player. A leaf of Moves.
## Each tile id selects a flow kind and the shape of the flow tile the loader makes from it.
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/sim/collision.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const Polygon = preload("res://src/sim/polygon.gd")
const Reader = preload("res://src/level/level_code.gd")
const S := preload("res://src/sim/units.gd").SCALE
const LAYER := "flowWater"
const DOWN := 1
const LEFT := 2
const RIGHT := 4
const LEFT_DOWN := 8
const RIGHT_DOWN := 16
const LOW := [0, 0.5625, 1, 0.5625, 1, 1, 0, 1]
const FULL := [0, 0, 1, 0, 1, 1, 0, 1]
## flowWater tile id: [kind, tile shape in the flow tilemap the loader fills from it].
const SHAPES := {
	0: [DOWN, LOW],
	1: [DOWN, FULL],
	2: [DOWN, [0, 0.5, 0.5, 0, 1, 0, 1, 1, 0, 1]],
	3: [DOWN, [0, 0, 0.5, 0, 1, 0.5, 1, 1, 0, 1]],
	12: [DOWN, FULL],
	4: [LEFT, LOW],
	15: [LEFT, LOW],
	8: [RIGHT, LOW],
	16: [RIGHT, LOW],
	6: [LEFT_DOWN, [0, 0.375, 0.375, 0, 1, 0, 0, 1]],
	7: [LEFT_DOWN, [0, 0.375, 0.375, 0, 1, 0, 0, 1]],
	10: [RIGHT_DOWN, [0.625, 0, 1, 0.375, 1, 1, 0, 0]],
	11: [RIGHT_DOWN, [0.625, 0, 1, 0.375, 1, 1, 0, 0]]
}
## Pushes in 1/3600 px per step: 96 px/s along a flat flow, 200 px/s down a slope.
const PUSH := 96 * S / 60
const SLOPE_PUSH := 200 * S / 60
## Shape points per tile id and size; built once from the constants above.
static var _points := {}


## The flow kinds (bit set) the box touches.
static func kinds(world: Dictionary, left: int, top: int, right: int, bottom: int) -> int:
	var found := 0
	for layer: Dictionary in world.layers:
		if layer.name != LAYER:
			continue
		var size: int = layer.size * S
		var x0 := maxi(0, World.floor_div(left - 1, size))
		var x1 := mini(layer.width - 1, World.floor_div(right, size))
		var y0 := maxi(0, World.floor_div(top - 1, size))
		var y1 := mini(layer.height - 1, World.floor_div(bottom, size))
		for row in range(y0, y1 + 1):
			for column in range(x0, x1 + 1):
				var id: int = layer.cells[row * layer.width + column] & Reader.TILE_ID_MASK
				var shape: Variant = SHAPES.get(id)
				if shape == null or found & shape[0]:
					continue
				if Polygon.overlaps_box(
					_shape_points(id, size),
					left - column * size,
					top - row * size,
					right - column * size,
					bottom - row * size
				):
					found |= shape[0]
	return found


static func _shape_points(id: int, size: int) -> PackedInt64Array:
	var key := id * 100000 + size
	if not _points.has(key):
		var facts := {
			"tile_size": [size / S, size / S],
			"collision_disabled": [],
			"collision_polygons": {"0": SHAPES[id][1]}
		}
		_points[key] = World.tile_polygon(0, facts)
	return _points[key]


## One step of the flow rules, run with the other water rules before the player's own.
## Returns -1 or 1 when a jump press leaves a sloped flow that way, else 0.
static func apply(
	state: Dictionary, world: Dictionary, bounds: Array, pressed: int, pounding: bool
) -> int:
	var box := [state.x + bounds[0], state.y + bounds[1], state.x + bounds[2], state.y + bounds[3]]
	var touching := kinds(world, box[0], box[1], box[2], box[3])
	var below := kinds(world, box[0], box[1] + 4 * S, box[2], box[3] + 4 * S)
	if not (touching | below):
		return 0
	if touching & DOWN and not pounding and not state.on_floor:
		state.vy += 384
	if touching & LEFT and not Collision.by_wall(state, world, bounds, -1):
		state.x -= PUSH
	if touching & RIGHT and not Collision.by_wall(state, world, bounds, 1):
		state.x += PUSH
	var jump := 0
	for kind: int in [LEFT_DOWN, RIGHT_DOWN]:
		if not (touching | below) & kind:  # Touching it, or 4 px above it (an OR block).
			continue
		var way := -1 if kind == LEFT_DOWN else 1
		if state.vx * way < 0:
			state.x -= state.vx / 2  # Moving against the slope loses half the speed.
		if pressed & InputBits.JUMP:
			jump = way
		if not Collision.by_wall(state, world, bounds, way):
			state.x += way * SLOPE_PUSH
		if state.vy >= 0:
			state.vy = 400 * 60
	return jump
