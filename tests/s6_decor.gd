extends SceneTree
## Invented placements and metadata only. No scenes, frames or recordings rendered.

const Registry = preload("res://src/sim/registry.gd")
const State = preload("res://src/sim/play_state.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Sim = preload("res://src/sim/step.gd")
const Decor = preload("res://src/sim/types/decor.gd")
const Ledges = preload("res://src/sim/types/decor_platform.gd")
const Lamp = preload("res://src/sim/types/lamp.gd")
const SnowTree = preload("res://src/sim/types/snow_tree.gd")
const Dressing = preload("res://src/view/pack_dressing.gd")
const S := State.SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	registration_checks()
	option_checks()
	ignored_option_checks()
	ledge_checks()
	lamp_checks()
	snow_checks()
	drawing_checks()
	context_checks()
	look_checks()
	animation_checks()
	detached_node_checks()
	_generic_node_checks()
	packed_node_checks()
	snapshot_checks()
	print("DECOR_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func compile(objects: Dictionary) -> Dictionary:
	var world := {
		"identity": "invented scenery world".sha256_text(),
		"spawn_x": 64 * S,
		"spawn_y": 100 * S,
		"spawn_facing": 1,
		"map_index": 1,
		"initial_map": 1,
		"map_count": 1,
		"flowers_target": 0,
		"redcoins_target": 0,
		"width": 4096 * S,
		"height": 4096 * S,
		"layers": []
	}
	var result := Registry.compile_map(objects, world)
	if result.ok:
		world.maps = {1: world.duplicate()}
	return {"ok": result.ok, "world": world, "error": result.get("error", "")}


func degrades(raw: Dictionary) -> bool:
	var result := compile({"shape": raw})
	if not result.ok or result.world.entities.size() != 1:
		return false
	var source: Dictionary = result.world.entities[0]
	return (
		Registry.degraded(source)
		and source.code == "?" + raw.A
		and source.properties == raw
		and not source.has("decor")
	)


func world_for(objects: Dictionary) -> Dictionary:
	var result := compile(objects)
	check(result.ok, "Synthetic scenery compiles: " + result.error)
	return result.world


func placement(code: String, options: Dictionary = {}) -> Dictionary:
	var result := {"A": code, "X": 512, "Y": 512}
	result.merge(options, true)
	return result


func all_objects() -> Dictionary:
	var result := {}
	for index in range(1, 77):
		result["shape%d" % index] = placement("d%d" % index, {"E1": "320.5"})
	return result


func registration_checks() -> void:
	var world := world_for(all_objects())
	var state := State.create(world)
	check(state.entities.size() == 76, "Every scenery placement creates one saved entity")
	check(Snapshot.valid_state(state), "Every default scenery state validates")
	for index in range(1, 77):
		var code := "d%d" % index
		var type := Registry.lookup(code)
		check(Registry.implemented(code) and code in type.CODES, "Declared scenery: " + code)
		check(type.valid(state.entities[index - 1]), "Default domain: " + code)
		if code in Decor.CODES:
			check(type.FIELDS.is_empty(), "Visual-only scenery adds no saved fields: " + code)
			check(
				Registry.phase_for(type, "STEP_PHASE", 0) == -1,
				"Visual-only scenery skips steps: " + code
			)
		var options := {"F": Decor.frame_count(code) - 1, "E1": "320.5"}
		check(compile({"shape": placement(code, options)}).ok, "Last declared frame: " + code)
		options.F += 1
		check(degrades(placement(code, options)), "Unknown frame becomes a placeholder: " + code)
	var before: Array = state.entities.duplicate(true)
	Registry.advance(state, world, 0)
	check(state.entities == before, "Static scenery and still-player reactions have no step work")


func option_checks() -> void:
	var raw := placement(
		"d3", {"F": 4, "M": 1, "R": 24.125, "E1": "unrelated text", "E2": {"kept": true}}
	)
	var original := raw.duplicate(true)
	var world := world_for({"leaf": raw})
	var source: Dictionary = world.entities[0]
	check(source.decor.rotation == 24.125, "Fractional rotation is not truncated")
	check(
		source.decor.variant == 4 and source.decor.mirror == 1,
		"Frame and mirror have separate roles"
	)
	check(
		raw == original and source.properties == original,
		"Immutable unrelated properties are retained"
	)
	world = world_for({"stem": placement("d14", {"E1": " 320.5 "})})
	check(
		world.entities[0].decor.height == 320.0, "Decimal height text uses integral rendered pixels"
	)
	world = world_for({"plain": placement("d76", {"F": 5, "E1": "retained only"})})
	check(world.entities[0].decor.height == 0.0, "Unrelated height text does not become a resize")
	check(compile({"shape": placement("d14")}).ok, "Missing extension height has a zero default")
	for value: Variant in [-1, "-1", "not a size", "", [], {}, null, INF, NAN, 1.0e30]:
		check(
			not compile({"shape": placement("d14", {"E1": value})}).ok,
			"Malformed height is rejected"
		)
	for key: String in ["F", "M", "R"]:
		for value: Variant in ["1", null, [], INF, NAN, 1.0e30]:
			check(
				not compile({"shape": placement("d3", {key: value})}).ok,
				"Malformed pose is rejected: " + key
			)
	check(degrades(placement("d3", {"M": 2})), "Unknown mirror mode becomes a placeholder")
	check(not compile({"shape": placement("d3", {"M": -1})}).ok, "Negative mirror is malformed")
	check(not compile({"shape": placement("d3", {"F": 0.5})}).ok, "Frame is integral")
	check(degrades(placement("d14", {"R": 90})), "Transformed extension is not guessed")
	check(degrades(placement("d5", {"R": 90})), "Rotated ledge is not guessed")
	check(compile({"shape": placement("d5", {"R": 360})}).ok, "A full turn is the unchanged ledge")
	check(
		not compile({"shape": placement("d1", {"X": Decor.MAX_PIXELS + 1})}).ok,
		"Position keeps integer headroom"
	)


func ignored_option_checks() -> void:
	for pair: Array in [
		["d3", "E1"], ["d3", "E2"], ["d9", "E1"], ["d25", "E1"], ["d25", "E3"], ["d76", "E1"]
	]:
		var baseline := State.create(world_for({"shape": placement(pair[0])}))
		var bytes := Snapshot.encode(baseline)
		for value: Variant in [null, 7, 2.5, "inert option", [], {"kept": true}]:
			var object := placement(pair[0], {pair[1]: value})
			var world := world_for({"shape": object})
			check(
				world.entities[0].properties == object,
				"Inert option keeps its original shape and value"
			)
			check(
				Snapshot.encode(State.create(world)) == bytes,
				"Inert option does not change play state"
			)


func ledge_checks() -> void:
	var expected := {
		"d5": [[-42, -32, 38, -30]],
		"d6": [[-27, -18, 23, -16]],
		"d7": [[-26, -48, 54, -46], [-55, 14, -5, 16]],
		"d8": [[-38, -80, 42, -78], [21, -18, 71, -16], [-70, 16, 10, 18]],
		"d23": [[-32, -16, 28, -14]]
	}
	for code: String in expected:
		var world := world_for({"ledge": placement(code, {"E1": "320"})})
		var entity: Dictionary = State.create(world).entities[0]
		var boxes := Ledges.solid_boxes(entity)
		check(
			Ledges.SOLID == 2 and Registry.phase_for(Ledges, "STEP_PHASE", 0) == -1,
			"Ledge is static and top-only"
		)
		check(boxes.size() == expected[code].size(), "Separate ledge strips: " + code)
		for index in boxes.size():
			var local: Array = expected[code][index]
			check(
				(
					boxes[index]
					== [
						entity.x + local[0] * S,
						entity.y + local[1] * S,
						entity.x + local[2] * S,
						entity.y + local[3] * S
					]
				),
				"Exact fixed-point strip: " + code
			)
		if code != "d23":
			entity.decor_mirror = 1
			var mirrored := Ledges.solid_boxes(entity)
			for index in mirrored.size():
				var local: Array = expected[code][index]
				check(
					(
						mirrored[index][0] == entity.x - local[2] * S
						and mirrored[index][2] == entity.x - local[0] * S
					),
					"Mirror retains disjoint strips: " + code
				)
		entity.decor_variant = Decor.frame_count(code)
		check(not Ledges.valid(entity), "Invalid saved ledge frame: " + code)
	var world := world_for({"wide": placement("d23", {"F": 1, "E1": "64"})})
	var entity: Dictionary = State.create(world).entities[0]
	check(
		Ledges.solid_boxes(entity) == [[452 * S, 464 * S, 568 * S, 466 * S]],
		"Wide support has its own width and top"
	)


func lamp_checks() -> void:
	for color in 2:
		for variant in 4:
			var code := "d25" if color == 0 else "d26"
			var world := world_for({"lamp": placement(code, {"F": variant})})
			var state := State.create(world)
			var entity: Dictionary = state.entities[0]
			check(
				(
					entity.lamp_color == color
					and entity.lamp_style == variant % 2
					and entity.lamp_lit == int(variant < 2)
				),
				"Saved lamp color, body and initial light"
			)
			var before := Snapshot.encode(state)
			var look := Lamp.view_state(entity, state)
			check(
				(
					look.animation
					== "%s:%d:%d" % ["lit" if variant < 2 else "dim", color, variant % 2]
				),
				"Lamp exposes a semantic pose"
			)
			check(before == Snapshot.encode(state), "Lamp look is read-only")
			Registry.advance(state, world, 0)
			check(entity.lamp_lit == int(variant < 2), "No invented element activation")
			entity.lamp_lit = 2
			check(not Lamp.valid(entity), "Invalid saved lamp flag is rejected")


func snow_checks() -> void:
	var world := world_for({"tree": placement("d22", {"E1": "160"})})
	var state := State.create(world)
	var tree: Dictionary = state.entities[0]
	state.x = 512 * S
	state.y = 450 * S
	# A level starts with the body already falling; this check needs it still.
	state.vx = 0
	state.vy = 0
	state.camera_x = state.x
	state.camera_y = state.y
	state.frame = 6
	var rng: int = state.rng
	SnowTree.contact(tree, state, world, 0)
	check(SnowTree.puffs(tree, state.frame).is_empty(), "Still player makes no snow reaction")
	state.vx = 60
	state.frame = 5
	SnowTree.contact(tree, state, world, 0)
	check(SnowTree.puffs(tree, state.frame).is_empty(), "Reaction uses the six-tick cadence")
	state.frame = 6
	Registry.advance(state, world, 0)
	check(SnowTree.puffs(tree, 6).is_empty(), "Canopy skips the movement step")
	Registry.contact(state, 0, world)
	check(
		SnowTree.puffs(tree, 6) == [{"x": 512 * S, "y": 450 * S, "age": 0}],
		"Moving contact records a puff"
	)
	check(
		state.rng == rng and tree.x == 512 * S and tree.y == 512 * S,
		"Cosmetic contact does not move bodies or consume randomness"
	)
	check(
		SnowTree.puffs(tree, 36)[0].y == 450 * S + 112 * S / 3,
		"Puff fall uses saved age and integer interpolation"
	)
	check(
		SnowTree.puffs(tree, 50).size() == 1 and SnowTree.puffs(tree, 51).is_empty(),
		"Puff ends after forty-five ticks"
	)
	check(SnowTree.puffs(tree, 0).is_empty(), "Future puff is not drawn")
	for tick in range(12, 61, 6):
		state.frame = tick
		SnowTree.contact(tree, state, world, 0)
	check(SnowTree.puffs(tree, 60).size() == 8, "Eight slots bound continuous emission")
	var before := tree.duplicate(true)
	state.frame = 66
	state.camera_x += 1000 * S
	SnowTree.contact(tree, state, world, 0)
	check(tree == before, "Activation uses the fixed reference area")
	state.camera_x = state.x
	state.x += 16 * S
	SnowTree.contact(tree, state, world, 0)
	check(tree == before, "Contact band boundaries are strict")
	state.x += 1000 * S
	SnowTree.contact(tree, state, world, 0)
	check(tree == before, "Distant body cannot hit the crown")
	tree.puff_0_tick = -2
	check(not Snapshot.valid_state(state), "Invalid puff timestamp is rejected by the schema")
	world = world_for({"large": placement("d22", {"F": 1, "E1": "320.75"})})
	tree = State.create(world).entities[0]
	check(tree.decor_height == 320 * S, "Canopy helper truncates height in whole pixels")
	check(
		(
			SnowTree.crown(tree)
			== PackedInt64Array([512 * S, 214 * S, 592 * S, 434 * S, 432 * S, 434 * S])
		),
		"Large canopy has its own triangle"
	)


func drawing_checks() -> void:
	var world := world_for(all_objects())
	for source: Dictionary in world.entities:
		var before := source.duplicate(true)
		var plan := Dressing.decoration_plan(source, {})
		check(not plan.is_empty(), "Missing art still has a diagnostic plan: " + source.code)
		check(source == before, "Drawing policy leaves the compiled placement unchanged")
		check(source.decor.layer == Decor.layer_for(source.code), "Code keeps its draw layer")
	check(
		(
			Decor.layer_for("d14") == 5
			and Decor.layer_for("d9") == 12
			and Decor.layer_for("d23") == 6
			and Decor.layer_for("d1") == 7
		),
		"Scenery has four distinct layer policies"
	)
	var source: Dictionary = world.entities[13]
	var plan := Dressing.decoration_plan(source, {})
	check(
		(
			plan.size() == 2
			and plan[0].margins == [16, 16, 64, 0]
			and plan[0].height == 320.0
			and plan[0].bottom
		),
		"Small extension keeps the cap separate"
	)
	plan = Dressing.decoration_plan(world.entities[38], {})
	check(plan[0].margins == [0, 0, 32, 0], "Short curled cap is not stretched into the stem")
	plan = Dressing.decoration_plan(world.entities[55], {})
	check(
		plan[0].margins == [0, 112, 66, 30] and plan[0].position.y == 16,
		"Tall tree keeps both borders and its ground offset"
	)
	plan = Dressing.decoration_plan(world.entities[74], {})
	check(plan[0].margins == [0, 0, 16, 16], "Segmented extension keeps both end caps")
	plan = Dressing.decoration_plan(world.entities[26], {})
	check(
		(
			plan.size() == 2
			and not plan[0].bottom
			and plan[1].position.y == 304.0
			and plan[1].animation == "Hanging"
		),
		"Hanging attachment follows the chain end"
	)
	plan = Dressing.decoration_plan(world.entities[27], {})
	check(
		(
			plan.size() == 3
			and plan[0].bottom
			and plan[1].position.y == -304.0
			and plan[1].animation == "Standing"
		),
		"Standing attachment follows the pole end"
	)
	plan = Dressing.decoration_plan(world.entities[22], {})
	check(
		(
			plan.size() == 2
			and plan[0].tile
			and plan[0].height == 320.0
			and plan[0].position.y == 32
			and plan[1].has("boxes")
		),
		"Pillar tiles beneath a diagnostic support"
	)
	var manifest := {
		"objects":
		{
			"d22":
			{
				"file": "fallback.png",
				"source_types": [20, 21, 22],
				"parts":
				{
					"20": {"file": "wide.png"},
					"21": {"file": "small.png"},
					"22": {"file": "unused.png"}
				}
			},
			"d75": {"file": "fallback.png", "variants": {"5": {"file": "selected.png"}}}
		}
	}
	var original := manifest.duplicate(true)
	check(
		(
			Dressing.decor_entry(manifest, "d22", 0).file == "small.png"
			and Dressing.decor_entry(manifest, "d22", 1).file == "wide.png"
		),
		"Snow image variants do not choose the helper"
	)
	check(
		Dressing.decor_entry(manifest, "d75", 5).file == "selected.png",
		"Explicit pack variants take precedence"
	)
	check(manifest == original, "Variant selection does not mutate the manifest")


func context_checks() -> void:
	var world := world_for({"rock": placement("d10", {"F": 3, "M": 1, "R": 90})})
	var source: Dictionary = world.entities[0]
	var cells := PackedInt32Array()
	cells.resize(100)
	cells.fill(-1)
	cells[88] = 0
	var layer := {
		"name": "cave64_1",
		"layer": "layer1",
		"size": 64,
		"width": 10,
		"height": 10,
		"cells": cells,
		"bounds": {0: [0, 0, 64 * S, 64 * S]},
		"polygons": {0: PackedInt64Array([0, 0, 64 * S, 0, 64 * S, 64 * S, 0, 64 * S])}
	}
	world.layers = [layer]
	var plan := Dressing.decoration_plan(source, {}, world)
	check(
		plan.size() == 2 and plan[1].animation == "Blue" and plan[1].variant == 3,
		"Terrain contact selects a contextual base and its frame"
	)
	check(
		plan[1].position == Vector2(8, 48) and plan[1].counter_mirror,
		"Attachment point mirrors without mirroring spawned art"
	)
	world.layers = [layer.duplicate(true), layer.duplicate(true), layer.duplicate(true)]
	world.layers[0].name = "cave64"
	world.layers[2].name = "cave64_2"
	plan = Dressing.decoration_plan(source, {}, world)
	check(
		(
			plan.size() == 4
			and plan[1].animation == "Default"
			and plan[2].animation == "Blue"
			and plan[3].animation == "Red"
		),
		"Independent terrain contacts retain their order"
	)
	world.layers = [layer.duplicate(true)]
	world.layers[0].layer = "layer3"
	check(
		Dressing.decoration_plan(source, {}, world).size() == 1,
		"Nonphysical overlay terrain does not add a base"
	)
	world.layers[0].layer = "layer1"
	world.layers[0].cells.fill(-1)
	check(
		Dressing.decoration_plan(source, {}, world).size() == 1, "Empty terrain does not add a base"
	)


func look_checks() -> void:
	var base := {
		"position": Vector2(100, 200),
		"scale": Vector2.ONE,
		"size": Vector2(12, 12),
		"rotation": 20.0,
		"alpha": 1.0,
		"visible": true,
		"flip_h": false,
		"position_anchor": true
	}
	var original := base.duplicate(true)
	check(Dressing.look_plan(base, {}) == base, "Missing look keys preserve placement behavior")
	var look := {
		"offset_x": 2.5,
		"offset_y": -3.25,
		"size_x": 24.0,
		"size_y": 6,
		"rotation": 450.5,
		"modulate_alpha": 0.25,
		"visible": false,
		"flip_x": true
	}
	var saved_look := look.duplicate(true)
	var pose := Dressing.look_plan(base, look)
	check(
		pose.position == Vector2(102.5, 196.75) and pose.scale == Vector2(-2, 0.5),
		"Position-anchored art and diagnostics use pixel transforms"
	)
	check(
		pose.rotation == 90.5 and pose.alpha == 0.25 and not pose.visible and not pose.flip_h,
		"Degrees, alpha and visibility have separate roles"
	)
	check(base == original and look == saved_look, "Look policy is read-only")
	check(
		(
			Dressing.look_plan(base, {"size_x": 24}).scale.x == 2
			and Dressing.look_plan(base, {"size_x": 24}).scale.x == 2
		),
		"Repeated application does not compound size"
	)
	base.position_anchor = false
	pose = Dressing.look_plan(base, {"flip_x": true})
	check(pose.flip_h and pose.scale.x == 1, "Box-anchored art keeps its geometry when flipped")
	pose = Dressing.look_plan(
		base,
		{
			"offset_x": INF,
			"offset_y": "2",
			"size_x": -1,
			"size_y": NAN,
			"rotation": INF,
			"visible": 1,
			"flip_x": 1
		}
	)
	check(pose == base, "Malformed optional look values do not corrupt a transform")
	check(
		(
			Dressing.look_plan(base, {"modulate_alpha": 2}).alpha == 1
			and Dressing.look_plan(base, {"modulate_alpha": -1}).alpha == 0
		),
		"Alpha stays in range"
	)


func animation_checks() -> void:
	var a := [{"tag": "a0", "end": 1}, {"tag": "a1", "end": 2}, {"tag": "a2", "end": 3}]
	var b := [{"tag": "b0", "end": 1}, {"tag": "b1", "end": 2}, {"tag": "b2", "end": 3}]
	var art := {
		"animations":
		{
			"one": {"frames": a, "fps": 4, "loop": true, "duration": 3},
			"two": {"frames": b, "fps": 4, "loop": true, "duration": 3}
		},
		"default_animation": "one",
		"states": {"semantic": "two", "one": "two", "variant:2": "two"}
	}
	var original := art.duplicate(true)
	check(
		Dressing.view_sample(art, 15, {}).tag == "a1", "No frame key advances from the saved tick"
	)
	check(
		Dressing.view_sample(art, 0, {"animation": "one"}).tag == "a0",
		"Literal animation beats a colliding semantic key"
	)
	check(
		Dressing.view_sample(art, 0, {"animation": "semantic"}).tag == "b0",
		"Semantic mapping is the first fallback"
	)
	check(
		Dressing.view_sample(art, 0, {"animation": "missing"}).tag == "a0",
		"Default animation is the last fallback"
	)
	check(
		Dressing.view_sample(art, 0, {"animation": "variant"}, 2).tag == "b0",
		"Existing variant state mapping remains available"
	)
	check(
		(
			Dressing.view_sample(art, 0, {"animation": "two", "frame": 2}).tag == "b2"
			and Dressing.view_sample(art, 10000, {"animation": "two", "frame": 2}).tag == "b2"
		),
		"Literal frame holds instead of advancing"
	)
	check(
		Dressing.view_sample(art, 15, {"frame": 999}).tag == "a2", "Frame index is safely clamped"
	)
	check(art == original, "Frame selection does not mutate art metadata")
	var entry := {
		"default_animation": "main",
		"animations":
		{
			"main":
			{
				"fps": 7,
				"loop": true,
				"ping_pong": true,
				"frames": [{"file": "p0.png"}, {"file": "p1.png"}, {"file": "p2.png"}]
			}
		}
	}
	var manifest := {"objects": {"d1": entry}}
	var selected := Dressing.decor_entry(manifest, "d1", 0)
	check(
		(
			selected.animations.main.frames.map(
				func(frame: Dictionary) -> String: return frame.file
			)
			== ["p0.png", "p1.png", "p2.png", "p1.png"]
		),
		"Ping-pong metadata keeps the return frames"
	)
	check(
		entry.animations.main.frames.size() == 3,
		"Ping-pong expansion leaves pack metadata unchanged"
	)
	var lamps := {"default_animation": "0Glow0", "animations": {}}
	for color in 2:
		for variant in 4:
			lamps.animations["%dGlow%d" % [color, variant]] = {"frames": [{"file": "lamp.png"}]}
	selected = Dressing.decor_entry({"objects": {"d26": lamps}}, "d26", 0)
	check(
		selected.states["dim:1:1"] == "1Glow3" and selected.states["lit:0:0"] == "0Glow0",
		"Legacy lamp labels are mapped without changing the look contract"
	)


func detached_node_checks() -> void:
	# Detached canvas nodes never enter a scene tree or render a frame.
	var objects := all_objects()
	var world := world_for(objects)
	var map := {"objects": objects}
	world.source = {"startpoint": {"map": 1}, "maps": {"map1": map}}
	world.map_source = map
	var state := State.create(world)
	var bytes := Snapshot.encode(state)
	var drawn := Engine.get_frames_drawn()
	var root := Node2D.new()
	Dressing.placed(root, {}, "", world)
	check(
		not root.is_inside_tree() and root.get_child_count() == 76,
		"Production placement builds detached diagnostic nodes"
	)
	var nodes := {}
	for child: Sprite2D in root.get_children():
		nodes[child.get_meta("placed_id")] = child
	for entity: Dictionary in state.entities:
		var node: Sprite2D = nodes[entity.id]
		Dressing.update_placed(node, entity, state)
		check(
			node.visible and node.position == Vector2(entity.x, entity.y) / S,
			"Production placement update: " + entity.code
		)
		check(node.z_index == Decor.layer_for(entity.code), "Production node keeps its layer")
	state.entities[0].collected = 1
	Dressing.update_placed(nodes[state.entities[0].id], state.entities[0], state)
	check(not nodes[state.entities[0].id].visible, "Collected placement is hidden")
	state.entities[0].collected = 0
	Dressing.update_placed(nodes[state.entities[0].id], state.entities[0], state)
	check(
		nodes[state.entities[0].id].visible, "Missing look keys do not retain a stale hidden pose"
	)
	check(Snapshot.encode(state) == bytes, "Production node updates leave snapshot bytes unchanged")
	check(Engine.get_frames_drawn() == drawn, "Detached-node checks render no frames")
	root.free()


func _generic_node_checks() -> void:
	var type := GDScript.new()
	type.source_code = (
		"extends RefCounted\n"
		+ "static func bounds(entity: Dictionary) -> Array:\n"
		+ "\treturn entity.box\n"
	)
	check(type.reload() == OK, "Invented bounds fixture parses")
	var entity := {"code": "o6", "box": [-4 * S, -20 * S, 12 * S, 0]}
	check(
		Dressing._body_rect(type, entity) == Rect2(-4, -20, 16, 20),
		"Generic diagnostic follows local simulation bounds"
	)
	var node := Dressing._diagnostic_body(type, entity)
	check(
		node.scale == Vector2(16, 20) / 12 and node.offset == Vector2(-3, -12),
		"Diagnostic bounds retain their asymmetric origin"
	)
	check(
		node.texture == Dressing.placeholder("o6", 12),
		"Generic diagnostic reuses the existing placeholder style"
	)
	node.free()
	var world := world_for({"marker": placement("o6", {"E1": "32", "E2": "64"})})
	var map := {"objects": {"marker": world.entities[0].properties}}
	world.source = {"startpoint": {"map": 1}, "maps": {"map1": map}}
	world.map_source = map
	var state := State.create(world)
	var bytes := Snapshot.encode(state)
	var root := Node2D.new()
	var drawn := Engine.get_frames_drawn()
	Dressing.placed(root, {}, "", world)
	check(root.get_child_count() == 1, "Registered non-enemy without pack art is not dropped")
	node = root.get_child(0)
	check(
		node.get_meta("diagnostic_body", false) and node.scale == Vector2.ONE,
		"A type without bounds gets the small default box"
	)
	var held: Dictionary = state.entities[0].duplicate()
	held.held = 1
	Dressing.update_placed(node, held, state)
	check(not node.visible, "Held entities are not drawn")
	held.held = 0
	held.hidden = 1
	Dressing.update_placed(node, held, state)
	check(not node.visible, "Hidden entities are not drawn")
	Dressing.update_placed(node, state.entities[0], state)
	check(node.visible, "Released or revealed entity uses its current saved visibility")
	root.free()
	world.enemies = [world.entities[0]]
	root = Node2D.new()
	Dressing.placed(root, {}, "", world)
	check(root.get_child_count() == 0, "Entities owned by the enemy path are not drawn twice")
	check(
		Snapshot.encode(state) == bytes and Engine.get_frames_drawn() == drawn,
		"Generic-node checks change no play state and render no frames"
	)
	root.free()


func generated_texture(size: Vector2i) -> Texture2D:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


func packed_node_checks() -> void:
	# Inject authored white textures into the normal cache. No image files or frames.
	var cache: Dictionary = Dressing._frames._textures
	cache["invented-pack/stem.png"] = generated_texture(Vector2i(32, 96))
	cache["invented-pack/cap.png"] = generated_texture(Vector2i(32, 32))
	cache["invented-pack/support.png"] = generated_texture(Vector2i(64, 64))
	cache["invented-pack/pillar.png"] = generated_texture(Vector2i(128, 736))
	cache["invented-pack/tree.png"] = generated_texture(Vector2i(96, 186))
	for index in 3:
		cache["invented-pack/puff%d.png" % index] = generated_texture(Vector2i(32, 32))
	var manifest := {
		"objects":
		{
			"d14": {"file": "stem.png", "origin": [16, 96]},
			"d23":
			{
				"file": "support.png",
				"origin": [32, 32],
				"source_types": [100, 101],
				"parts": {"101": {"file": "pillar.png", "origin": [64, 0]}}
			},
			"d22": {"file": "tree.png", "origin": [48, 186]}
		},
		"visuals":
		{
			"cap":
			{
				"animations":
				{
					"Stem1":
					{"frames": [{"file": "cap.png", "origin": [16, 0]}], "fps": 0, "loop": false}
				}
			},
			"effect":
			{
				"animations":
				{
					"BigDustNoDelay":
					{
						"frames":
						[
							{"file": "puff0.png", "origin": [16, 16]},
							{"file": "puff1.png", "origin": [16, 16]},
							{"file": "puff2.png", "origin": [16, 16]}
						],
						"fps": 4,
						"loop": false
					}
				}
			}
		}
	}
	var original := manifest.duplicate(true)
	var objects := {
		"stem": placement("d14", {"E1": "320.5"}),
		"support": placement("d23", {"E1": "320.5"}),
		"tree": placement("d22", {"E1": "320.5"})
	}
	var world := world_for(objects)
	var map := {"objects": objects}
	world.source = {"startpoint": {"map": 1}, "maps": {"map1": map}}
	world.map_source = map
	var state := State.create(world)
	var root := Node2D.new()
	var drawn := Engine.get_frames_drawn()
	Dressing.placed(root, manifest, "invented-pack", world)
	var stem: Sprite2D = root.get_child(0)
	var patch: NinePatchRect = stem.get_child(0).get_child(0)
	check(
		patch.size == Vector2(32, 320) and patch.position == Vector2(-16, -320),
		"Production extension uses a sliced patch, not a stretched cap"
	)
	check(
		(
			patch.patch_margin_top == 64
			and patch.axis_stretch_vertical == NinePatchRect.AXIS_STRETCH_MODE_TILE
		),
		"Patch edges retain their pixels and tile"
	)
	var pillar: Sprite2D = root.get_child(1).get_child(0).get_child(0)
	check(
		(
			pillar.region_enabled
			and pillar.region_rect.size == Vector2(128, 320)
			and pillar.offset == Vector2(-64, 0)
		),
		"Production pillar repeats from its top origin"
	)
	var tree: Dictionary = state.entities[2]
	state.x = 512 * S
	state.y = 290 * S
	state.camera_x = state.x
	state.camera_y = state.y
	state.vx = 60
	state.frame = 6
	SnowTree.contact(tree, state, world, 0)
	var bytes := Snapshot.encode(state)
	var tree_node: Sprite2D = root.get_child(2)
	Dressing.update_placed(tree_node, tree, state)
	var puffs: Array = tree_node.get_meta("puff_nodes")
	check(
		(
			puffs[0].visible
			and puffs[0].texture == cache["invented-pack/puff0.png"]
			and puffs[0].z_index == 14
			and not puffs[0].z_as_relative
		),
		"Saved birth selects the first front-layer puff frame"
	)
	state.frame = 36
	bytes = Snapshot.encode(state)
	Dressing.update_placed(tree_node, tree, state)
	check(
		puffs[0].texture == cache["invented-pack/puff2.png"] and puffs[0].position.y > -222,
		"Saved age holds the selected frame and advances the fall"
	)
	check(
		bytes == Snapshot.encode(state) and original == manifest,
		"Production pack drawing is read-only"
	)
	check(
		not root.is_inside_tree() and Engine.get_frames_drawn() == drawn,
		"Pack-node checks render no frames"
	)
	root.free()


func snapshot_checks() -> void:
	var world := world_for(all_objects())
	var state := State.create(world)
	var bytes := Snapshot.encode(state)
	var restored := Snapshot.decode(bytes, world.identity, world)
	check(
		not bytes.is_empty() and restored.ok,
		"All scenery types restore through the real snapshot path"
	)
	if not restored.ok:
		return
	check(bytes == Snapshot.encode(restored.state), "Scenery restore is byte exact")
	Sim.advance(state, 0, world)
	Sim.advance(restored.state, 0, world)
	check(
		state.frame == 1 and Snapshot.encode(state) == Snapshot.encode(restored.state),
		"Real pure ticks stay deterministic after restore"
	)
	var before := Snapshot.encode(state)
	for index in state.entities.size():
		Dressing.decoration_plan(world.entities[index], {})
		var type: Script = Registry.lookup(state.entities[index].code)
		if type.has_method("view_state"):
			type.call("view_state", state.entities[index], state)
	check(
		before == Snapshot.encode(state), "All drawing policy paths leave snapshot bytes unchanged"
	)
	world = world_for({"tree": placement("d22", {"E1": "160"})})
	state = State.create(world)
	state.x = 512 * S
	state.y = 450 * S
	state.camera_x = state.x
	state.camera_y = state.y
	state.vx = 60
	state.frame = 6
	SnowTree.contact(state.entities[0], state, world, 0)
	restored = Snapshot.decode(Snapshot.encode(state), world.identity, world)
	check(
		(
			restored.ok
			and (
				SnowTree.puffs(state.entities[0], 24)
				== SnowTree.puffs(restored.state.entities[0], 24)
			)
		),
		"Cosmetic births restore without a wall clock"
	)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
