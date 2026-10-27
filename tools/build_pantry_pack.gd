extends SceneTree
## Offline Pantry pack assembly from the Nano Banana sources in art/pantry/.
## Code only crops, keys, resizes, blends, tints and masks the generated artwork.
const ART := "res://art/pantry/"
const FACTS_PATH := "res://src/level/collision_table.json"
const COLUMNS := 8
const KEY := Color(1, 0, 1)
## Pale haze for objects set back against the wall.
const BACK_TINT := Color("e6dcc6")
## Sheet cells: [sheet, column, row, longest side in px, origin ("bottom" or "center")].
const OBJECTS := {
	"e1": ["actors", 0, 0, 36, "bottom"],
	"e2": ["actors", 1, 0, 28, "center"],
	"e3": ["actors", 2, 0, 34, "bottom"],
	"e5": ["actors", 3, 0, 44, "bottom"],
	"e5_head": ["actors", 0, 1, 30, "center"],
	"e20": ["actors", 1, 1, 32, "center"],
	"o1": ["actors", 2, 1, 18, "center"],
	"o2": ["actors", 3, 1, 18, "center"],
	"o3": ["actors", 0, 2, 18, "center"],
	"o5": ["actors", 1, 2, 44, "center"],
	"o6": ["actors", 2, 2, 30, "center"],
	"o7": ["actors", 3, 2, 28, "center"],
	"o8": ["actors", 0, 3, 30, "center"],
	"o9": ["actors", 1, 3, 24, "center"],
	"o11": ["actors", 2, 3, 32, "bottom"],
	"o17": ["actors", 3, 3, 30, "center"],
	"o18": ["props", 0, 0, 32, "center"],
	"o19": ["props", 1, 0, 32, "center"],
	"o22": ["props", 2, 0, 34, "center"],
	"o23": ["props", 3, 0, 64, "bottom"],
	"p1": ["props", 3, 2, 64, "center"],
	"d1": ["props", 1, 1, 20, "bottom"],
	"d2": ["props", 2, 1, 14, "center"],
	"d3": ["props", 3, 1, 18, "center"],
	"d4": ["props", 0, 2, 22, "center"],
	"recovery": ["props", 1, 2, 24, "center"],
}
const SUPPORTS := {"bracket": ["props", 2, 2, 22, "center"], "shelf": ["props", 3, 2, 64, "center"]}
## Player animations: [speed in frames per second, [[column, row], ...]] from the chick sheet.
const PLAYER := {
	"Idle0": [3, [[0, 0], [1, 0]]],
	"Walk0": [10, [[2, 0], [3, 0], [2, 1], [3, 1]]],
	"Sprint0": [14, [[0, 2], [1, 2], [2, 2], [3, 2]]],
	"Jump0": [1, [[0, 3]]],
	"Fall0": [1, [[2, 3]]],
	"Flutter0": [12, [[1, 3], [3, 3]]],
}
var _out := "res://packs/pantry"
var _facts: Dictionary
var _manifest := {"version": 3, "drawing_facts": "drawing_facts.json", "tiles": {}, "player": {}}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_out = argument.trim_prefix("--output=")
	_facts = JSON.parse_string(FileAccess.get_file_as_string(FACTS_PATH)).tilemaps
	for directory in ["tiles", "player", "objects", "background", "supports"]:
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(_out.path_join(directory))
		)
	var crumb := source("crumb")
	var crust := source("crust")
	var bread64 := terrain("garden64_1", 64, tileable(crumb, 64), tileable(crust, 64), 9, 0.0)
	var bread32 := terrain("garden32", 32, tileable(crumb, 32), tileable(crust, 32), 5, 0.3)
	save_tiles(bread64, "bread-garden64", ["garden64", "garden64_1"])
	save_tiles(bread32, "bread-garden32", ["garden32", "garden32_1"])
	save_tiles(carton(tileable(source("pulp"), 32)), "carton-levelend", ["levelEnd", "levelEnd_2"])
	save_tiles(water(tileable(source("water"), 32)), "water3", ["water3"])
	var sheets := {"actors": source("actors"), "props": source("props"), "chick": source("chick")}
	_manifest["objects"] = {}
	for code: String in OBJECTS:
		_manifest.objects[code] = sprite(sheets, OBJECTS[code], "objects/%s.png" % code)
	_manifest["supports"] = {}
	for code: String in SUPPORTS:
		_manifest.supports[code] = sprite(sheets, SUPPORTS[code], "supports/%s.png" % code).file
	for name: String in PLAYER:
		var frames := []
		for index in PLAYER[name][1].size():
			var cell: Array = PLAYER[name][1][index]
			var path := "player/%s_%d.png" % [name, index]
			frames.append(sprite(sheets, ["chick", cell[0], cell[1], 60, "bottom"], path))
		_manifest.player[name] = {"fps": PLAYER[name][0], "loop": true, "frames": frames}
	_manifest["background"] = {
		"wall": save(resized(source("wall"), 192, 192), "background/wall.png"),
		"counter": save(tileable_strip(source("wood"), 64, 16), "background/counter.png"),
		"cabinet": save(tileable_strip(source("cabinet"), 64, 24), "background/cabinet.png"),
	}
	write_json("manifest.json", _manifest)
	write_json("drawing_facts.json", {"tilemaps": draw_slots()})
	print("PANTRY_PACK: ", _out)
	quit()


func source(name: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(ART + name + ".jpg"))
	assert(image != null, "Missing Nano Banana source " + name)
	image.convert(Image.FORMAT_RGBA8)
	return image


static func resized(image: Image, width: int, height: int) -> Image:
	var copy := image.duplicate() as Image
	copy.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return copy


static func tileable(image: Image, size: int) -> Image:
	# Cross-fade with a half-period shifted copy so opposite edges continue each other.
	var base := resized(image, size, size)
	var result := base.duplicate() as Image
	var half := size / 2
	for y in size:
		for x in size:
			var edge := maxf(absf(x + 0.5 - half), absf(y + 0.5 - half)) / half
			var weight := smoothstep(0.55, 1.0, edge)
			var shifted := base.get_pixel((x + half) % size, (y + half) % size)
			result.set_pixel(x, y, base.get_pixel(x, y).lerp(shifted, weight))
	return result


static func tileable_strip(image: Image, width: int, height: int) -> Image:
	var square := tileable(image, width)
	return square.get_region(Rect2i(0, 0, width, height))


func polygon_for(name: String, id: int, size: int) -> PackedVector2Array:
	var coordinates: Array = _facts[name].collision_polygons.get(str(id), [0, 0, 1, 0, 1, 1, 0, 1])
	var polygon := PackedVector2Array()
	for index in range(0, coordinates.size(), 2):
		polygon.append(Vector2(coordinates[index], coordinates[index + 1]) * size)
	return polygon


static func internal_edges(polygon: PackedVector2Array, size: int) -> Array:
	# Cell-border edges may join another tile, so they never receive crust.
	var edges := []
	for index in polygon.size():
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		if a.x == b.x and (a.x == 0 or a.x == size):
			continue
		if a.y == b.y and (a.y == 0 or a.y == size):
			continue
		edges.append([a, b])
	return edges


static func edge_distance(point: Vector2, edges: Array) -> float:
	var best := INF
	for line: Array in edges:
		best = minf(
			best,
			point.distance_to(Geometry2D.get_closest_point_to_segment(point, line[0], line[1]))
		)
	return best


func blank(name: String, size: int) -> Image:
	var count := int(_facts[name].max_tile_id) + 1
	var image := Image.create(
		COLUMNS * size, ceili(float(count) / COLUMNS) * size, false, Image.FORMAT_RGBA8
	)
	image.fill(Color.TRANSPARENT)
	return image


func terrain(
	name: String, size: int, crumb: Image, crust: Image, crust_width: int, fade: float
) -> Image:
	var atlas := blank(name, size)
	for id in int(_facts[name].max_tile_id) + 1:
		if float(id) in _facts[name].collision_disabled:
			continue
		var polygon := polygon_for(name, id, size)
		var edges := internal_edges(polygon, size)
		for y in size:
			for x in size:
				var point := Vector2(x + 0.5, y + 0.5)
				if not Geometry2D.is_point_in_polygon(point, polygon):
					continue
				var distance := edge_distance(point, edges)
				var color := crumb.get_pixel(x, y)
				if distance <= crust_width:
					color = crust.get_pixel(x, y)
					if distance <= 1.5:
						color = color.darkened(0.25)
					elif distance <= 3.0:
						color = color.lightened(0.12)
				elif distance <= crust_width + 6:
					color = color.darkened(0.12 * (1.0 - (distance - crust_width) / 6.0))
				if fade > 0.0:
					color = color.lerp(BACK_TINT, fade).darkened(0.06)
				color.a = 1.0
				atlas.set_pixel((id % COLUMNS) * size + x, (id / COLUMNS) * size + y, color)
	return atlas


func carton(pulp: Image) -> Image:
	# Solid slots are moulded pulp with a cup pocket; decorative slots are the faded lid behind.
	var name := "levelEnd"
	var atlas := blank(name, 32)
	for id in int(_facts[name].max_tile_id) + 1:
		var decorative: bool = float(id) in _facts[name].collision_disabled
		for y in 32:
			for x in 32:
				var color := pulp.get_pixel(x, y)
				var cup := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(16, 18))
				if cup < 10:
					color = color.darkened(0.18 if y < 18 else 0.06)
				elif cup < 12:
					color = color.lightened(0.15)
				if decorative:
					color = color.lerp(BACK_TINT, 0.3).darkened(0.15)
				color.a = 1.0
				atlas.set_pixel((id % COLUMNS) * 32 + x, (id / COLUMNS) * 32 + y, color)
	return atlas


func water(material: Image) -> Image:
	var name := "water3"
	var atlas := blank(name, 32)
	for id in int(_facts[name].max_tile_id) + 1:
		var polygon := polygon_for(name, id, 32)
		var edges := internal_edges(polygon, 32)
		for y in 32:
			for x in 32:
				var point := Vector2(x + 0.5, y + 0.5)
				if not Geometry2D.is_point_in_polygon(point, polygon):
					continue
				var color := material.get_pixel(x, y)
				if edge_distance(point, edges) <= 2.0:
					color = color.lightened(0.45)
				color.a = 0.72
				atlas.set_pixel((id % COLUMNS) * 32 + x, (id / COLUMNS) * 32 + y, color)
	return atlas


func save_tiles(atlas: Image, file: String, names: Array) -> void:
	var path := "tiles/%s.png" % file
	save(atlas, path)
	for name: String in names:
		_manifest.tiles[name] = path


func save(image: Image, path: String) -> String:
	var error := image.save_png(_out.path_join(path))
	assert(error == OK, "Cannot write " + path)
	return path


static func keyed(cell: Image) -> Image:
	var image := cell.duplicate() as Image
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			# Magenta screen: strong red and blue with little green.
			if color.g < 0.45 and color.r > 0.6 and color.b > 0.6 and absf(color.r - color.b) < 0.3:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	# Spread neighbouring colours into keyed pixels so resizing does not pull magenta fringes.
	for pass_index in 3:
		var source := image.duplicate() as Image
		for y in image.get_height():
			for x in image.get_width():
				if source.get_pixel(x, y).a > 0.0:
					continue
				for offset: Vector2i in [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
				]:
					var other := Vector2i(x, y) + offset
					if Rect2i(Vector2i.ZERO, image.get_size()).has_point(other):
						var neighbour := source.get_pixelv(other)
						if neighbour.a > 0.0 or neighbour.r + neighbour.g + neighbour.b > 0.0:
							image.set_pixel(x, y, Color(neighbour.r, neighbour.g, neighbour.b, 0.0))
							break
	return image


func sprite(sheets: Dictionary, spec: Array, path: String) -> Dictionary:
	var sheet: Image = sheets[spec[0]]
	var grid := 4
	var cell_size := sheet.get_size() / grid
	var cell := keyed(sheet.get_region(Rect2i(Vector2i(spec[1], spec[2]) * cell_size, cell_size)))
	var used := cell.get_used_rect()
	var trimmed := cell.get_region(used)
	var longest := float(maxi(used.size.x, used.size.y))
	var scale := float(spec[3]) / longest
	var width := maxi(1, roundi(used.size.x * scale))
	var height := maxi(1, roundi(used.size.y * scale))
	trimmed.resize(width, height, Image.INTERPOLATE_LANCZOS)
	for y in height:
		for x in width:
			var color := trimmed.get_pixel(x, y)
			color.a = 1.0 if color.a >= 0.5 else 0.0
			trimmed.set_pixel(x, y, color)
	save(trimmed, path)
	var origin := [width / 2.0, height] if spec[4] == "bottom" else [width / 2.0, height / 2.0]
	return {"file": path, "origin": origin}


static func draw_slots() -> Dictionary:
	# Pantry draw order: back bread, back carton, water, then front bread and front carton.
	var slots := {}
	for entry: Array in [
		[["garden32", "garden32_1", "garden64", "garden64_1"], 0],
		[["levelEnd", "levelEnd_2"], 1],
		[["water3"], 2],
	]:
		for name: String in entry[0]:
			slots[name] = {
				"instances":
				[
					{"layer": "TilesL2", "layer_index": 4, "z_order": entry[1]},
					{
						"layer": "TilesL1",
						"layer_index": 14 if name == "water3" else 6,
						"z_order": entry[1]
					}
				]
			}
	return slots


func write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(_out.path_join(path), FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  ", false) + "\n")
	file.close()
