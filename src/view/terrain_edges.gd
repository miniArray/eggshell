extends RefCounted
## Open terrain edges for optional pack strips, found from collision polygons.
## Pure: reads the world's layers and the collision table, returns art-pixel runs.
## An edge is open where the cell next to it, on its outward side, has no terrain of
## the same kind (solid or water) in the same drawing group. The map border counts as closed.

const Dressing = preload("res://src/view/pack_dressing.gd")
const State = preload("res://src/sim/play_state.gd")
## Run kinds. A side edge is "left" when its open side faces -x.
const SURFACE := "surface"
const UNDERSIDE := "underside"
const LEFT := "left"
const RIGHT := "right"
## Coarse probe spacing in world pixels. Every tile edge is a multiple of 8 world pixels long.
const COARSE := 8.0


## Returns runs: {layer, tilemap, kind, start, line}. For surface and underside runs, `start`
## is the first art column and `line[i]` is the art row of the edge in column start + i: the
## first row inside the terrain for a surface, the first open row for an underside. For side
## runs, `start` is the first art row and `line[i]` is the art column of the edge in that row.
static func find(
	world: Dictionary, layers: Array, names: Array, facts: Dictionary, density: int
) -> Array:
	var size := Vector2(world.width, world.height) / State.SCALE
	var cache := {}
	var runs := []
	for index in layers.size():
		var layer: Dictionary = layers[index]
		if not layer.name in names or not (layer.solid or layer.water):
			continue
		var cover: Array = layers.filter(
			func(other: Dictionary) -> bool:
				return (
					other.layer == layer.layer
					and other.solid == layer.solid
					and other.water == layer.water
				)
		)
		var segments := []
		for row in layer.height:
			for column in layer.width:
				var cell: int = layer.cells[row * layer.width + column]
				if cell == -1:
					continue
				var polygon := polygon_of(cache, layer, cell, facts, column, row)
				for corner in polygon.size():
					var a := polygon[corner]
					var b := polygon[(corner + 1) % polygon.size()]
					if a.is_equal_approx(b):
						continue
					var segment := open_segments(a, b, polygon, cover, facts, cache, size, density)
					for part: Dictionary in segment:
						part.layer = index
						part.tilemap = layer.name
						segments.append(part)
		runs.append_array(merged(segments))
	return runs


static func open_segments(
	a: Vector2,
	b: Vector2,
	polygon: PackedVector2Array,
	cover: Array,
	facts: Dictionary,
	cache: Dictionary,
	size: Vector2,
	density: int
) -> Array:
	var normal := Vector2(b.y - a.y, a.x - b.x).normalized()
	var middle := (a + b) / 2.0
	if Geometry2D.is_point_in_polygon(middle + normal * 0.25, polygon):
		normal = -normal
	var across := absf(normal.y) >= absf(normal.x)
	var kind := (
		(SURFACE if normal.y < 0 else UNDERSIDE) if across else (LEFT if normal.x < 0 else RIGHT)
	)
	# Work along x for surfaces and undersides, along y for sides.
	var axis := 0 if across else 1
	var low := minf(a[axis], b[axis])
	var high := maxf(a[axis], b[axis])
	var step := 0.5 / density
	# Skip edges that are closed along their whole length, without probing every art pixel.
	# Tile vertices sit on an 8-world-pixel grid, so each probe stands for its whole interval.
	var probes: Array[float] = [low + step, high - step]
	var at := low + COARSE / 2.0
	while at < high:
		probes.append(at)
		at += COARSE
	var any_open := false
	for probe_at: float in probes:
		if open_at(probe_at, a, b, axis, normal, step, cover, facts, cache, size):
			any_open = true
			break
	if not any_open:
		return []
	var first := roundi(low * density)
	var last := roundi(high * density)
	var result := []
	var current := {}
	for pixel in range(first, last):
		var position := (pixel + 0.5) / density
		var open := open_at(position, a, b, axis, normal, step, cover, facts, cache, size)
		if not open:
			current = {}
			continue
		var exact := cross_at(position, a, b, axis) * density
		# Pixel-centre inclusion, the same rule packs use to mask partial tiles.
		var line := floori(exact + 0.5) if kind == SURFACE or kind == LEFT else ceili(exact - 0.5)
		if current.is_empty():
			current = {"kind": kind, "start": pixel, "line": PackedInt32Array()}
			result.append(current)
		current.line.append(line)
	return result


static func cross_at(position: float, a: Vector2, b: Vector2, axis: int) -> float:
	var other := 1 - axis
	if is_equal_approx(a[axis], b[axis]):
		return a[other]
	return lerpf(a[other], b[other], (position - a[axis]) / (b[axis] - a[axis]))


static func open_at(
	position: float,
	a: Vector2,
	b: Vector2,
	axis: int,
	normal: Vector2,
	step: float,
	cover: Array,
	facts: Dictionary,
	cache: Dictionary,
	size: Vector2
) -> bool:
	var point := Vector2.ZERO
	point[axis] = position
	point[1 - axis] = cross_at(position, a, b, axis)
	# Half an art pixel straight out from the edge, away from the terrain.
	var outward := Vector2.ZERO
	outward[1 - axis] = signf(normal[1 - axis]) * step
	var probe := point + outward
	if probe.x < 0 or probe.y < 0 or probe.x >= size.x or probe.y >= size.y:
		return false
	return not covered(probe, cover, facts, cache)


static func covered(point: Vector2, cover: Array, facts: Dictionary, cache: Dictionary) -> bool:
	for layer: Dictionary in cover:
		var column := floori(point.x / layer.size)
		var row := floori(point.y / layer.size)
		if column < 0 or row < 0 or column >= layer.width or row >= layer.height:
			continue
		var cell: int = layer.cells[row * layer.width + column]
		if cell == -1:
			continue
		var polygon := polygon_of(cache, layer, cell, facts, column, row)
		if not polygon.is_empty() and Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


static func polygon_of(
	cache: Dictionary, layer: Dictionary, cell: int, facts: Dictionary, column: int, row: int
) -> PackedVector2Array:
	# Cell-local polygons are shared by every cell with the same tile and flips.
	var key := "%s/%d" % [layer.name, cell]
	if not cache.has(key):
		cache[key] = Dressing.cell_polygon(cell, layer, facts, 0, 0)
	var local: PackedVector2Array = cache[key]
	var offset := Vector2(column, row) * float(layer.size)
	var placed := PackedVector2Array()
	placed.resize(local.size())
	for index in local.size():
		placed[index] = local[index] + offset
	return placed


static func merged(segments: Array) -> Array:
	# Join runs that continue across tile boundaries, so one ledge is one run.
	segments.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a.kind != b.kind:
				return a.kind < b.kind
			if a.start != b.start:
				return a.start < b.start
			return a.line[0] < b.line[0]
	)
	var result := []
	var open_ends := {}
	for segment: Dictionary in segments:
		var key := "%s/%d" % [segment.kind, segment.start]
		var joined := false
		for run: Dictionary in open_ends.get(key, []):
			if absi(run.line[-1] - segment.line[0]) <= 1:
				open_ends[key].erase(run)
				run.line.append_array(segment.line)
				segment = run
				joined = true
				break
		if not joined:
			result.append(segment)
		var end := "%s/%d" % [segment.kind, segment.start + segment.line.size()]
		if not open_ends.has(end):
			open_ends[end] = []
		open_ends[end].append(segment)
	return result
