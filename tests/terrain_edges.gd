extends SceneTree
## Open terrain edges on small generated levels. Pure: no scene, image or pack is loaded.
const Edges = preload("res://src/view/terrain_edges.gd")
const Strips = preload("res://src/view/terrain_strips.gd")
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/level/collision_table.gd")
var _facts: Dictionary = Collision.read().tilemaps
var _checks := 0
var _failures := 0


func _initialize() -> void:
	flat_top()
	stacked_blocks()
	overhang()
	slope()
	flipped_slope()
	bridge_object()
	water()
	drawing_groups()
	density_one()
	family_entries()
	print("TERRAIN_EDGES_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func flat_top() -> void:
	var world := level({"castle32": ["......", "......", ".000..", "......"]})
	var runs := find(world, ["castle32"])
	check(summary(runs, "surface") == [[64, 192, 128, 128]], "Flat top is one open run")
	check(summary(runs, "underside") == [[64, 192, 192, 192]], "Open underside below a ledge")
	check(summary(runs, "left") == [[128, 64, 64, 64]], "Left wall faces open air")
	check(
		summary(runs, "right") == [[128, 64, 256, 256]], "Right wall line is the first open column"
	)


func stacked_blocks() -> void:
	var world := level({"castle32": ["......", "......", "000000", "000000"]})
	var runs := find(world, ["castle32"])
	check(summary(runs, "surface") == [[0, 384, 128, 128]], "Only the top of a stack is open")
	check(summary(runs, "underside").is_empty(), "The map bottom is closed")
	check(
		summary(runs, "left").is_empty() and summary(runs, "right").is_empty(),
		"Map sides are closed"
	)


func overhang() -> void:
	var world := level({"castle32": ["......", "..00..", "000000", "000000"]})
	check(
		(
			summary(find(world, ["castle32"]), "surface")
			== [[0, 128, 128, 128], [128, 128, 64, 64], [256, 128, 128, 128]]
		),
		"A block hides the ground top under it"
	)


func slope() -> void:
	# garden32 tile 20 rises to the right at 45 degrees; flat castle ground continues from its top.
	var world := level(
		{"garden32": ["....", "....", "./..", "...."], "castle32": ["....", "....", "..0.", "...."]}
	)
	var runs := find(world, ["garden32", "castle32"])
	var slopes := runs.filter(
		func(run: Dictionary) -> bool: return run.kind == "surface" and run.tilemap == "garden32"
	)
	check(slopes.size() == 1, "The slope is one surface run")
	var slope_run: Dictionary = slopes[0]
	check(slope_run.start == 64 and slope_run.line.size() == 64, "Slope covers its art columns")
	var stepped := true
	for index in slope_run.line.size():
		stepped = stepped and slope_run.line[index] == 192 - index
	check(stepped, "Slope line steps one art pixel per column, by pixel-centre inclusion")
	var walls := summary(runs, "right")
	check(walls == [[128, 64, 192, 192]], "The block beside the slope keeps its own open wall")


func flipped_slope() -> void:
	var world := level({"garden32": ["....", ".7..", "....", "...."]})
	var runs := find(world, ["garden32"])
	check(
		summary(runs, "surface") == [[64, 64, 64, 64]],
		"A vertically flipped slope keeps a flat top"
	)
	var under: Array = runs.filter(func(run: Dictionary) -> bool: return run.kind == "underside")
	check(
		under.size() == 1 and under[0].line[0] == 64 and under[0].line[63] == 127,
		"Its slope faces down"
	)


func bridge_object() -> void:
	var rows := {"castle32": ["......", "......", "......", "000000"]}
	var plain := find(level(rows), ["castle32"])
	var bridged := find(
		level(rows, {"bridge": {"A": "p1", "X": 64, "Y": 80, "E1": 64}}), ["castle32"]
	)
	check(
		not level(rows, {"bridge": {"A": "p1", "X": 64, "Y": 80, "E1": 64}}).bridges.is_empty(),
		"Bridge compiled"
	)
	check(plain == bridged, "One-way bridges are objects: they neither get nor hide strips")


func water() -> void:
	# water3 tile 0 has open air in its top 10 world pixels; tile 1 is full.
	var world := level(
		{"water3": ["....", "00..", "11..", "...."], "castle32": ["....", "....", "....", "0000"]}
	)
	var runs := find(world, ["water3"])
	check(
		summary(runs, "surface") == [[0, 128, 84, 84]],
		"Water surface is the open top of its polygon"
	)
	check(summary(runs, "underside") == [[0, 128, 192, 192]], "Water only counts water as cover")


func drawing_groups() -> void:
	var world := level(
		{"castle32": ["....", "....", "0000", "...."]},
		{},
		{"castle32": ["....", ".00.", "....", "...."]}
	)
	var front: Array = find(world, ["castle32"]).filter(
		func(run: Dictionary) -> bool: return world.layers[run.layer].layer == "layer1"
	)
	check(
		summary(front, "surface") == [[0, 256, 128, 128]],
		"Back-layer terrain does not cover front edges"
	)


func density_one() -> void:
	var world := level({"castle32": ["......", "......", ".000..", "......"]})
	var runs := Edges.find(world, world.layers, ["castle32"], _facts, 1)
	check(summary(runs, "surface") == [[32, 96, 64, 64]], "Density 1 runs are in world pixels")


func family_entries() -> void:
	var terrain := {
		"garden32": {"surface": {"file": "a.png"}}, "garden64_1": {"side": {"file": "b.png"}}
	}
	check(Strips.entry_for(terrain, "garden32_1").has("surface"), "Tilemap family entry applies")
	check(Strips.entry_for(terrain, "garden64_1").has("side"), "Exact tilemap entry wins")
	check(
		Strips.entry_for(terrain, "garden64").is_empty(),
		"A variant entry does not cover its family"
	)


func find(world: Dictionary, names: Array) -> Array:
	return Edges.find(world, world.layers, names, _facts, 2)


## [start, length, first line, last line] per run of one kind, ordered by start then line.
static func summary(runs: Array, kind: String) -> Array:
	var result := []
	for run: Dictionary in runs:
		if run.kind == kind:
			result.append([run.start, run.line.size(), run.line[0], run.line[-1]])
	result.sort()
	return result


## Builds a one-map level from rows of cells. Every test map uses 32-pixel tiles, 4 rows.
func level(front: Dictionary, objects: Dictionary = {}, back: Dictionary = {}) -> Dictionary:
	var width := 0
	var map := {"objects": objects, "layer1": {}, "layer2": {}, "bgcolor": "0,0,0"}
	for group: String in ["layer1", "layer2"]:
		var source: Dictionary = front if group == "layer1" else back
		for name: String in source:
			var rows: Array = source[name]
			var tokens := []
			for row: String in rows:
				tokens.append_array(cells(row))
			width = cells(rows[0]).size()
			map[group][name] = JSON.stringify(
				{"c2tilemap": true, "width": width, "height": rows.size(), "data": ",".join(tokens)}
			)
	map.width = width * 32
	map.height = 128
	var code := {
		"version": "1",
		"name": "Edges",
		"desc": "",
		"author": "Eggshell",
		"startpoint": {"map": 1, "X": 16, "Y": 16},
		"flowers": 0,
		"redcoins": 0,
		"maps": {"map1": map},
	}
	var built := World.build(JSON.stringify(code), Collision.read())
	assert(built.ok, str(built))
	return built.world


## One character per cell: "." is empty, a digit is that tile id, "/" is garden32's 45-degree
## slope (tile 20) and "7" is the same slope flipped vertically.
static func cells(row: String) -> Array:
	var legend := {".": "-1", "/": "20", "7": "20v"}
	var result := []
	for character in row:
		result.append(legend.get(character, character))
	return result


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
