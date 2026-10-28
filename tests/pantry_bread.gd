extends SceneTree
## Check the built Pantry pack: terrain alpha follows the fixed collision shapes, adjoining
## tiles continue each other, the production loader keeps visible pixels, and every
## manifest file loads.
const View = preload("res://src/view/level_view.gd")
const PACK := "res://packs/pantry"
var _failures := 0
var _checks := 0


func _initialize() -> void:
	var facts: Dictionary = (
		JSON
		. parse_string(FileAccess.get_file_as_string("res://src/level/collision_table.json"))
		. tilemaps
	)
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(PACK.path_join("manifest.json"))
	)
	for name: String in ["garden64_1", "garden32", "levelEnd", "water3"]:
		check_shapes(name, facts[name], raw(manifest.tiles[name]))
	var bread := raw(manifest.tiles.garden64_1)
	# Half-height tops 1 and 2, and solid interiors 12 and 13, adjoin in real levels.
	for pair: Array in [[1, 2], [12, 13]]:
		check(joined(bread, pair[0], pair[1], true), "Horizontal join %d to %d" % pair)
	check(joined(bread, 12, 13, false), "Solid vertical join")
	var texture := View.load_texture(PACK.path_join(manifest.tiles.garden64_1))
	check(texture != null and visible_equal(texture.get_image(), bread), "Loader keeps pixels")
	var files: Array = manifest.tiles.values() + manifest.background.values()
	files += manifest.supports.values()
	for entry: Dictionary in manifest.objects.values():
		files.append(entry.file)
	for animation: Dictionary in manifest.player.values():
		for frame: Dictionary in animation.frames:
			files.append(frame.file)
	for file: String in files:
		check(View.load_texture(PACK.path_join(file)) != null, "Loads " + file)
	print("PANTRY_PACK_RESULT: ", _checks, " assertions, ", _failures, " failures")
	quit(1 if _failures else 0)


func raw(file: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(PACK.path_join(file)))
	image.convert(Image.FORMAT_RGBA8)
	return image


func check_shapes(name: String, tile: Dictionary, image: Image) -> void:
	var size := int(tile.tile_size[0])
	for id in int(tile.max_tile_id) + 1:
		var disabled: bool = float(id) in tile.collision_disabled
		var coordinates: Array = tile.collision_polygons.get(str(id), [0, 0, 1, 0, 1, 1, 0, 1])
		var polygon := PackedVector2Array()
		for index in range(0, coordinates.size(), 2):
			polygon.append(Vector2(coordinates[index], coordinates[index + 1]) * size)
		var mismatches := 0
		for y in size:
			for x in size:
				var inside := Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), polygon)
				# Carton decoration is a painted backdrop; other decoration stays empty.
				var expected := inside and (not disabled or name == "levelEnd")
				var painted := image.get_pixel((id % 8) * size + x, (id / 8) * size + y).a > 0.0
				if painted != expected:
					mismatches += 1
		check(mismatches == 0, "%s slot %d matches its fixed shape" % [name, id])


static func joined(image: Image, first: int, second: int, horizontal: bool) -> bool:
	# Neighbouring tiles continue each other: the same coverage on both sides, and a seam no
	# rougher than the 90th-percentile neighbouring line inside the two tiles. The crumb is
	# noisy, so single pixel steps are not a seam signal; a misaligned seam exceeds this.
	var along := Vector2i(0, 1) if horizontal else Vector2i(1, 0)
	var across := Vector2i(1, 0) if horizontal else Vector2i(0, 1)
	var a := origin(first) + across * 63
	var b := origin(second)
	for index in 64:
		if image.get_pixelv(a + along * index).a != image.get_pixelv(b + along * index).a:
			return false
	var interior: Array[float] = []
	for id in [first, second]:
		for line in 63:
			var start := origin(id) + across * line
			interior.append(roughness(image, start, start + across, along))
	interior.sort()
	return roughness(image, a, b, along) <= interior[interior.size() * 9 / 10]


static func origin(id: int) -> Vector2i:
	return Vector2i((id % 8) * 64, (id / 8) * 64)


static func roughness(image: Image, a: Vector2i, b: Vector2i, along: Vector2i) -> float:
	# Summed largest channel step between two parallel 64-pixel lines, over painted pairs.
	var total := 0.0
	for index in 64:
		var left := image.get_pixelv(a + along * index)
		var right := image.get_pixelv(b + along * index)
		if left.a > 0.0 and right.a > 0.0:
			total += maxf(
				maxf(absf(left.r - right.r), absf(left.g - right.g)), absf(left.b - right.b)
			)
	return total


static func visible_equal(loaded: Image, expected: Image) -> bool:
	loaded.convert(Image.FORMAT_RGBA8)
	if loaded.get_size() != expected.get_size():
		return false
	for y in expected.get_height():
		for x in expected.get_width():
			var want := expected.get_pixel(x, y)
			if want.a > 0.0 and not loaded.get_pixel(x, y).is_equal_approx(want):
				return false
	return true


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)
