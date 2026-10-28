extends SceneTree
## Small synthetic reader and map-policy checks. No gameplay or drawing.

const Reader = preload("res://src/level/level_code.gd")
const World = preload("res://src/sim/world.gd")
const Maps = preload("res://src/sim/maps.gd")
const Effects = preload("res://src/view/map_effects.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	reader_checks()
	world_checks()
	effect_checks()
	effect_binding_checks()
	hazard_checks()
	check(checks >= 89, "Every check section completed")
	print("FORMAT_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func reader_checks() -> void:
	var code := level()
	code.author = 0
	var parsed := Reader.parse(JSON.stringify(code))
	check(parsed.ok, "Numeric missing-author sentinel loads")
	if parsed.ok:
		check(parsed.level.author == "0", "Numeric author becomes display text")
	code = level()
	code.version = "s3.7.2"
	code.maps.map1.objects = {"4": {"A": "o14", "X": 32, "Y": 64, "E1": "1"}}
	parsed = Reader.parse(JSON.stringify(code))
	check(parsed.ok, "Older revision loads")
	if parsed.ok:
		var object: Dictionary = parsed.level.maps.map1.objects["4"]
		check(object.get("F") == 1, "Older toggle moves to frame")
		check(not object.has("E1"), "Migrated toggle no longer has old key")
	code.version = "s3.13.1"
	parsed = Reader.parse(JSON.stringify(code))
	check(parsed.ok, "Two-digit revision loads")
	if parsed.ok:
		check(
			parsed.level.maps.map1.objects["4"].get("F") == 1,
			"Legacy string gate is preserved for two-digit revisions"
		)
		check(
			Reader.revision(parsed.level.version) == [3, 13, 1],
			"Metadata revision components remain numeric"
		)
	for field: String in ["flowers", "redcoins"]:
		code = level()
		code.erase(field)
		parsed = Reader.parse(JSON.stringify(code))
		check(parsed.ok and parsed.level.get(field, -1) == 0, "Missing target defaults to zero")
		code[field] = -1
		parsed = Reader.parse(JSON.stringify(code))
		check(parsed.ok and parsed.level[field] == -1, "Negative exported total remains loadable")
	code = level()
	code.maps.map2 = code.maps.map1.duplicate(true)
	code.startpoint.map = 2
	parsed = Reader.parse(JSON.stringify(code))
	check(parsed.ok and parsed.level.maps.size() == 2, "Every map retained")
	code.maps.map2.layer3 = {
		"blocks": JSON.stringify({"c2tilemap": true, "width": 1, "height": 1, "data": "0"})
	}
	parsed = Reader.parse(JSON.stringify(code))
	check(parsed.ok, "Optional third layer decoded")
	if parsed.ok:
		check(
			parsed.level.maps.map2.layer3.blocks.cells == PackedInt32Array([0]),
			"Third layer gets decoded cells"
		)
	code = level()
	code.maps.map1.music = {"src": "local-track", "dat": "12,-3"}
	check(Reader.parse(JSON.stringify(code)).ok, "Structured music selector retained without I/O")


func world_checks() -> void:
	var code := level()
	code.startpoint = {"map": 2, "X": 64, "Y": 96, "M": 1, "palette": "10,20,30_40,50,60_70,80,90"}
	code.maps.map2 = code.maps.map1.duplicate(true)
	code.maps.map2.width = 640
	code.maps.map2.music = 4
	code.maps.map2.diceBlockColours = JSON.stringify(
		{"c2array": true, "size": [1, 1, 1], "data": [[["10,20,30"]]]}
	)
	var tile := JSON.stringify({"c2tilemap": true, "width": 1, "height": 1, "data": "0"})
	code.maps.map2.layer1 = {"blocks": tile}
	code.maps.map2.layer3 = {"blocks": tile}
	var built := World.build(JSON.stringify(code), facts())
	check(built.ok, "Several maps compile")
	if not built.ok:
		push_error(built.error)
		return
	var world: Dictionary = built.world
	check(
		world.maps.size() == 2 and world.initial_map == 2,
		"All maps cached; selected spawn map retained"
	)
	check(world.info.name == code.name and world.info.author == code.author, "Level info consumed")
	check(
		world.info.desc == code.desc and world.info.version == code.version,
		"Description and revision consumed"
	)
	check(world.music.id == "4", "Numeric music selector becomes an id")
	check(world.player_palette[0] == [10, 20, 30], "Three-tone player palette decoded")
	check(world.dice_colours == [[10, 20, 30]], "Nested colour table decoded")
	check(world.layers.size() == 2, "Overlay terrain compiled")
	check(
		world.layers[1].layer == "layer3" and not world.layers[1].solid,
		"Overlay draws later and never collides"
	)
	check(world.layers[0].solid, "Regular terrain remains solid")
	var state := {"x": 64 * 3600, "y": 96 * 3600, "facing": 1}
	Maps.initialize(state, world)
	check(state.map_index == 2 and state.map_count == 2, "Saved map fields initialized from level")
	check(state.flowers_target == 3 and state.redcoins_target == 7, "Counter targets initialized")
	check(state.facing == -1, "Spawn mirror sets facing")
	var legacy := {"facing": 1}
	check(Maps.sync(legacy, world), "Legacy callers initialize at their first sync")
	check(
		legacy.map_index == 2 and legacy.flowers_target == 3 and legacy.facing == -1,
		"Legacy initialization consumes map, target and mirror"
	)
	check(Maps.valid_state(state), "Initial map state validates")
	state.map_index = 1
	check(
		Maps.sync(state, world) and world.width == 320 * 3600, "Sync selects restored map geometry"
	)
	check(state.flowers_target == 3, "Map selection keeps level targets")
	state.map_index = 3
	check(not Maps.valid_state(state), "Out-of-range map rejected")
	state.map_index = 1
	state.redcoins_target = -1
	check(not Maps.valid_state(state), "Negative target rejected by save boundary")
	state.redcoins_target = 7
	var before := state.duplicate(true)
	check(not Maps.change(state, world, 99, 0, 0, reset_empty_map), "Missing destination rejected")
	check(state == before, "Rejected destination leaves state unchanged")
	state.entities = [{"x": 1}]
	state.collected = 2
	check(
		Maps.change(state, world, 2, 128 * 3600, 96 * 3600, reset_empty_map),
		"Map travel accepts a pure actor reset"
	)
	check(state.map_index == 2 and world.width == 640 * 3600, "Map travel swaps active geometry")
	check(state.x == 128 * 3600 and state.y == 96 * 3600, "Map travel places exact destination")
	check(
		state.entities.is_empty() and state.collected == 2,
		"Map travel resets actors and retains level counters"
	)
	check(
		state.camera_x == state.x and state.camera_y == state.y - 28 * 3600,
		"Map travel resets follow point"
	)
	check(
		state.vx == 0 and state.vy == 0 and state.captured_by == 0,
		"Map travel clears old movement and actor attachment"
	)
	check(not Maps.change(state, world, 1, 0, 0, Callable()), "Missing reset callback rejected")
	check(
		World.music({"src": "local-track", "dat": "12,-3"}).custom,
		"Custom music selection remains local metadata"
	)
	check(World.rgb("999,20,-1") == [255, 20, 0], "Colour channels bounded")
	code.flowers = -17
	built = World.build(JSON.stringify(code), facts())
	check(
		built.ok and built.world.flowers_target == 0, "Non-positive totals have no positive target"
	)
	check(
		World.rgb("999999999999999999999999,20,0") == [255, 20, 0],
		"Large colour channels clamp before integer conversion"
	)
	code = level()
	code.maps.map7 = code.maps.map1.duplicate(true)
	code.startpoint.map = 7
	built = World.build(JSON.stringify(code), facts())
	check(
		built.ok and built.world.initial_map == 2,
		"Sparse source labels get stable internal indices"
	)
	check(Maps.index_for(built.world, 7) == 2, "Sparse source label resolves for callers")
	check(Maps.index_for(built.world, 2) == 0, "Missing source label does not alias an ordinal")


func effect_checks() -> void:
	var world := {"bgcolor": "10,20,30", "darkness": 75, "tint": "90_100,50,25"}
	var state := {"x": 64 * 3600, "y": 96 * 3600, "frame": 60}
	var before := state.duplicate(true)
	var view_plan := {"offset": Vector2(10, 20), "scale": 2.0}
	var policy := Effects.plan(world, state, view_plan, Vector2(320, 180))
	check(is_equal_approx(policy.darkness, 0.75), "Darkness percentage consumed")
	check(is_equal_approx(policy.tint.a, 0.5), "Tint clamps to fifty percent")
	check(is_equal_approx(policy.tint.r, 100.0 / 255), "Tint RGB consumed")
	check(
		policy.background == Color(10.0 / 255, 20.0 / 255, 30.0 / 255), "Background colour consumed"
	)
	check(
		policy.light_origin == Vector2(138, 156) and policy.light_radius == 256.0,
		"Light tracks the projected player in world units"
	)
	check(state == before, "Effect planning does not change state")
	world.tint = "-5_255,255,255"
	world.darkness = -5
	policy = Effects.plan(world, state, view_plan, Vector2(40, 2000))
	check(policy.tint.a == 0 and policy.darkness == 0, "Negative effects are disabled")
	check(Effects.shimmer_swaps("blocks", 78).is_empty(), "Shimmer does not touch other terrain")
	check(Effects.shimmer_swaps("cave64", 59).is_empty(), "Shimmer waits for first fixed second")
	var expected := [1, 1, 2, 3, 2, 2, 1, 0]
	for index in expected.size():
		check(
			Effects.shimmer_swaps("cave64", 60 + index * 6).size() == expected[index],
			"Shimmer phase %d" % index
		)
	check(
		Effects.shimmer_swaps("cave64", 60) == Effects.shimmer_swaps("cave64", 120),
		"Shimmer repeats from saved ticks"
	)
	check(
		Effects.dice_colour({"dice_colours": [[10, 20, 30]]}, {"E4": "0"}) == [10, 20, 30],
		"Linked colour table consumed"
	)
	check(
		Effects.dice_colour({}, {"E1": "10", "E2": "20", "E3": "30"}) == [10, 20, 30],
		"Unlinked colours use placed RGB"
	)


func effect_binding_checks() -> void:
	# Bind resources without putting this tree on screen or advancing a frame.
	var root_node := Node2D.new()
	var player := Sprite2D.new()
	var cave := TileMapLayer.new()
	cave.set_meta("tilemap_name", "cave64")
	var placed := Sprite2D.new()
	placed.set_meta("placed_code", "o34")
	placed.set_meta("placed_source", {"E4": "0"})
	root_node.add_child(player)
	root_node.add_child(cave)
	root_node.add_child(placed)
	var effects := Effects.new()
	var state := {"x": 64 * 3600, "y": 96 * 3600, "frame": 60}
	var before := state.duplicate(true)
	var world := {
		"player_palette": [[10, 20, 30], [40, 50, 60], [70, 80, 90]],
		"dice_colours": [[10, 20, 30]],
		"cave_shimmer": 1
	}
	var view_plan := {"offset": Vector2.ZERO, "scale": 1.0}
	effects.update(root_node, player, world, state, view_plan, Vector2(320, 180))
	check(
		player.material is ShaderMaterial and player.material.get_shader_parameter("count") == 3,
		"Player palette binds three replacements"
	)
	check(
		cave.material is ShaderMaterial and cave.material.get_shader_parameter("count") == 1,
		"Cave swaps bind from saved frame"
	)
	check(
		placed.self_modulate == Color(10.0 / 255, 20.0 / 255, 30.0 / 255),
		"Placed linked colour reaches its visual"
	)
	check(state == before, "Effect resource binding does not mutate play state")
	state.frame = 102
	effects.update(root_node, player, world, state, view_plan, Vector2(40, 2000))
	check(
		cave.material.get_shader_parameter("count") == 0,
		"Inactive shimmer restores the texture palette"
	)
	effects.free()
	root_node.free()


func hazard_checks() -> void:
	for name: String in ["lava", "lava_3", "ySSpikes"]:
		var code := level()
		var table := facts()
		var entry: Dictionary = table.tilemaps.blocks.duplicate(true)
		entry.solid_family = false
		entry.collision_polygons = {"0": [0, 0, 1, 0, 0, 1]}
		table.tilemaps[name] = entry
		code.maps.map1.layer1 = {
			name: JSON.stringify({"c2tilemap": true, "width": 1, "height": 1, "data": "0"})
		}
		var built := World.build(JSON.stringify(code), table)
		check(built.ok, "Contact-only terrain compiles")
		if not built.ok:
			continue
		var world: Dictionary = built.world
		check(
			not world.layers[0].solid and not world.layers[0].water,
			"Contact-only terrain never becomes solid or water"
		)
		check(
			World.named_overlaps(world, name, 2 * 3600, 2 * 3600, 4 * 3600, 4 * 3600),
			"Named polygon contact answers inside triangle"
		)
		check(
			not World.named_overlaps(world, name, 28 * 3600, 28 * 3600, 30 * 3600, 30 * 3600),
			"Named polygon contact rejects empty triangle corner"
		)


static func reset_empty_map(state: Dictionary, _world: Dictionary) -> void:
	state.entities = []


static func facts() -> Dictionary:
	return {
		"tilemaps":
		{
			"blocks":
			{
				"tile_size": [32, 32],
				"solid_family": true,
				"water_family": false,
				"collision_disabled": [],
				"collision_polygons": {},
				"instances":
				[
					{"layer": "TilesL1", "layer_index": 6, "z_order": 0},
					{"layer": "TilesL2", "layer_index": 4, "z_order": 0}
				]
			}
		}
	}


static func level() -> Dictionary:
	return {
		"version": "s3.13.1",
		"name": "Two rooms",
		"desc": "Synthetic rooms",
		"author": "Eggshell",
		"flowers": 3,
		"redcoins": 7,
		"startpoint": {"map": 1, "X": 64, "Y": 96},
		"maps": {"map1": {"width": 320, "height": 192, "objects": {}}}
	}


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
