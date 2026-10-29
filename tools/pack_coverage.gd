extends SceneTree
## Graphics coverage facts for one pack and a list of level codes.
##
## The runner builds the game's own level view for every map and reads back what it
## drew: pack art, a diagnostic placeholder, or nothing because the engine has no
## object type. It never renders, steps the simulation or writes saves.
## `tools/pack_coverage.py` turns these facts into the JSON and Markdown reports.
##
## godot --headless --path . --script tools/pack_coverage.gd -- \
##     --pack=/abs/pack --out=/abs/facts.json --level=/abs/a.txt --level=/abs/b.txt

const World = preload("res://src/sim/world.gd")
const Maps = preload("res://src/sim/maps.gd")
const Moves = preload("res://src/sim/moves.gd")
const Registry = preload("res://src/sim/registry.gd")
const CollisionTable = preload("res://src/level/collision_table.gd")
const Pack = preload("res://src/level/asset_pack.gd")
const View = preload("res://src/view/level_view.gd")
const Dressing = preload("res://src/view/pack_dressing.gd")
const Background = preload("res://src/view/pack_background.gd")
const PlayerPose = preload("res://src/view/player_pose.gd")
const Hud = preload("res://src/view/hud.gd")
const Frames = preload("res://src/view/pack_frames.gd")
## Fixed seed and sample count for the pose sweep, so every run lists the same names.
const POSE_SEED := 7
const POSE_SAMPLES := 100000
const LEVEL_CODE := "^[a-z][0-9]+$"


func _initialize() -> void:
	var options := {"level": []}
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2:
			continue
		if pair[0] == "level":
			options.level.append(pair[1])
		else:
			options[pair[0]] = pair[1]
	if not options.has("out") or not options.has("pack"):
		printerr("pack_coverage: --pack=DIR and --out=FILE are required")
		quit(2)
		return
	var report := collect(str(options.pack), options.level)
	var file := FileAccess.open(str(options.out), FileAccess.WRITE)
	if file == null:
		printerr("pack_coverage: cannot write " + str(options.out))
		quit(2)
		return
	file.store_string(JSON.stringify(report, "  ", false))
	file.close()
	quit(1 if report.levels.any(func(level: Dictionary) -> bool: return level.has("error")) else 0)


func collect(pack: String, levels: Array) -> Dictionary:
	var manifest := Pack.read(pack)
	# The game also drops an unreadable pack and draws placeholders only.
	var loaded := not manifest.is_empty()
	var drawn_pack := pack if loaded else ""
	var poses := pose_names()
	var report := {
		"pack": pack,
		"pack_loaded": loaded,
		"density": int(manifest.get("density", 1)),
		"pose_sweep": {"seed": POSE_SEED, "samples": POSE_SAMPLES},
		"engine_poses": poses,
		"implemented_codes": Registry.codes(),
		"pack_object_codes": manifest.get("objects", {}).keys(),
		"hud": hud_slots(manifest, drawn_pack),
		"scenery": scenery_slots(manifest, drawn_pack),
		"runtime": runtime_slots(manifest, drawn_pack),
		"levels": [],
	}
	var player_art := {}
	for path: String in levels:
		var level := level_slots(path, manifest, drawn_pack, poses)
		player_art = level.get("player_animations", player_art)
		level.erase("player_animations")
		report.levels.append(level)
	report["pack_player_animations"] = player_art.keys()
	return report


## Every pose name the view's selector returns over a seeded sweep of player states.
## `dry` holds the names reachable while not swimming; `water` adds the rest.
static func pose_names() -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = POSE_SEED
	var dry := {}
	var all := {}
	var ammo := [0, Moves.SEED, Moves.HEAT, Moves.COLD]
	for sample in POSE_SAMPLES:
		var state := {
			"hurt": flag(random),
			"move_held_id": flag(random),
			"move_ammo_count": 0,
			# Unknown actions fall through to the movement branches, so a wider range
			# also covers actions added later.
			"move_action": random.randi_range(0, 15),
			"move_action_tick": random.randi_range(0, 60),
			"move_tongue_axis": flag(random),
			"move_action_wet": flag(random),
			"move_tongue_phase": random.randi_range(0, 3),
			"move_ammo": ammo[random.randi_range(0, ammo.size() - 1)],
			"on_floor": flag(random),
			"swimming": flag(random),
			"move_aim": flag(random),
			"flutter_remaining": flag(random),
			"vx": random.randi_range(-1, 1),
			"move_duck": flag(random),
			"move_posture_tick": random.randi_range(0, 2),
			"move_look": flag(random),
			"move_water_jump": flag(random),
			"move_water_transition": flag(random) * random.randi_range(1, 9),
			"move_dive": flag(random),
			"move_push": flag(random),
			"move_turn": flag(random),
			"move_turn_ticks": random.randi_range(0, 30),
			"move_gravity_tick": flag(random),
			"movement": random.randi_range(0, 6),
			"frame": sample,
		}
		var name: String = PlayerPose.select(state).name
		all[name] = all.get(name, 0) + 1
		if not state.swimming:
			dry[name] = true
	var water := all.keys().filter(func(name: String) -> bool: return not dry.has(name))
	var dry_names := dry.keys()
	dry_names.sort()
	water.sort()
	# The rarest name's hit count shows how far the sweep is from missing a branch.
	return {"dry": dry_names, "water": water, "rarest_hits": all.values().min()}


static func flag(random: RandomNumberGenerator) -> int:
	return int(random.randf() < 0.3)


func level_slots(path: String, manifest: Dictionary, pack: String, poses: Dictionary) -> Dictionary:
	var result := {"file": path}
	if not FileAccess.file_exists(path):
		result.error = "Level file not found"
		return result
	var built := World.build(FileAccess.get_file_as_string(path), CollisionTable.read())
	if not built.ok:
		result.error = str(built.error)
		return result
	var world: Dictionary = built.world
	result.name = str(world.info.name)
	result.maps = int(world.map_count)
	var slots := {}
	var features := {"water": false, "lava": false, "maps": int(world.map_count)}
	var animations := {}
	for index: int in world.maps:
		var selected := Maps.map_world(world, index)
		var view: Node2D = View.new()
		view._build_map(selected, pack)
		animations = view._animations.get("animations", {})
		tile_slots(view, selected, slots, features)
		object_slots(view, selected, manifest, pack, slots)
		background_slots(selected.map_source, manifest, pack, slots)
		# setup() would parent the map effects; _build_map alone leaves them orphaned.
		view._effects.free()
		view.free()
	var names: Array = poses.dry.duplicate()
	if features.water:
		names.append_array(poses.water)
	var fallback := (
		"diagnostic player box"
		if animations.is_empty()
		else "pack default pose %s" % view_default(animations)
	)
	for name: String in names:
		var drawn := animations.has(name)
		add(slots, "player", name, "pack" if drawn else "fallback", 1, "" if drawn else fallback)
	result.features = features
	result.slots = slots.values()
	result.player_animations = animations
	return result


## The pose the view shows for a name the pack lacks (see level_view.gd and pack_frames.gd).
static func view_default(animations: Dictionary) -> String:
	return "Idle0" if animations.has("Idle0") else str(animations.keys()[0])


static func tile_slots(
	view: Node2D, world: Dictionary, slots: Dictionary, features: Dictionary
) -> void:
	var cells := {}
	for layer: Dictionary in world.layers:
		var used := 0
		for cell: int in layer.cells:
			if cell != -1:
				used += 1
		cells[layer.name] = cells.get(layer.name, 0) + used
		features.water = features.water or bool(layer.water)
		features.lava = features.lava or layer.name in World.LAVA_LAYERS
	var strips := {}
	var drawn := {}
	var outside := {}
	for node: Node in view._root.get_children():
		if node.name.begins_with("TerrainStrips_"):
			strips[node.name.trim_prefix("TerrainStrips_")] = true
		if not node is TileMapLayer:
			continue
		var name: String = node.get_meta("tilemap_name")
		var atlas: TileSetAtlasSource = node.tile_set.get_source(0)
		var size := int(node.tile_set.tile_size.x)
		var real := atlas.texture != Dressing.placeholder(name, size)
		drawn[name] = drawn.get(name, false) or real
		if real:
			# A tile id past the end of the pack image leaves its cell empty.
			for cell: Vector2i in node.get_used_cells():
				if not atlas.has_tile(node.get_cell_atlas_coords(cell)):
					outside[name] = outside.get(name, 0) + 1
	for name: String in drawn:
		var detail := "edge strips" if strips.has(name) else ""
		if not drawn[name]:
			detail = "diagnostic squares on colliding cells"
		add(slots, "tileset", name, "pack" if drawn[name] else "fallback", cells[name], detail)
		if outside.has(name):
			add_detail(
				slots,
				"tileset",
				name,
				"pack",
				"cells past the pack image, not drawn",
				outside[name]
			)


func object_slots(
	view: Node2D, world: Dictionary, manifest: Dictionary, pack: String, slots: Dictionary
) -> void:
	var looks := {}
	for index in view._enemy_nodes.size():
		var enemy: Dictionary = world.enemies[index]
		var art: Dictionary = view._enemy_nodes[index].get_meta("entity_art", {})
		looks[enemy.id] = not art.is_empty()
		var type := Registry.lookup(enemy.code)
		# level_view.gd gives every head_box type a head node named <code>_head.
		var head_code: String = enemy.code + "_head" if type.has_method("head_box") else ""
		if not head_code.is_empty() and can_show_head(type, enemy, world):
			var head_drawn: bool = view._head_nodes[index].has_meta("pack_art")
			add(
				slots,
				"object",
				head_code,
				"pack" if head_drawn else "fallback",
				1,
				"" if head_drawn else "diagnostic square"
			)
	for index in view._spring_nodes.size():
		looks[world.springs[index].id] = view._spring_nodes[index].has_meta("pack_art")
	var goal_drawn := false
	for node: Node in view._root.get_children():
		if node.has_meta("goal"):
			goal_drawn = node.has_meta("pack_art")
	# Bridge sprites keep no per-row reference; this is the same lookup level_view.gd makes.
	var bridge_drawn := not Dressing.object_art(manifest, pack, "p1").is_empty()
	for source: Dictionary in world.entities:
		var code: String = source.properties.A
		var node: Node = view._placed_nodes.get(source.id)
		var status := "fallback"
		var detail := ""
		if Registry.degraded(source) or not Registry.implemented(source.code):
			status = "engine-missing"
			detail = Registry.placeholder_reason(source)
			if node != null and node.has_meta("pack_art"):
				detail += "; pack art drawn as a still sprite"
			elif node != null:
				detail += "; diagnostic square"
			else:
				detail += "; not drawn"
		elif looks.has(source.id):
			status = "pack" if looks[source.id] else "fallback"
		elif code == "o5":
			status = "pack" if goal_drawn else "fallback"
		elif code == "p1":
			status = "pack" if bridge_drawn else "fallback"
		elif node == null:
			detail = "no view node"
		elif node.get_meta("decor", false):
			var parts := decor_parts(node)
			status = "pack" if parts.missing == 0 else "fallback"
			if parts.missing:
				detail = "%d of %d parts drawn as placeholders" % [parts.missing, parts.total]
		else:
			status = "pack" if node.has_meta("pack_art") else "fallback"
		if status == "fallback" and detail.is_empty():
			detail = "diagnostic square"
		add(slots, "object", code, status, 1, detail)


## Head nodes stay hidden while head_box is empty; Actor codes other than e5 never show one.
static func can_show_head(type: Script, source: Dictionary, world: Dictionary) -> bool:
	var entity := Registry.create(source, world)
	if entity.has("head_size"):
		entity.head_size = 15
	return not type.head_box(entity).is_empty()


## A decoration draws as a group of parts; each part without pack art is a diagnostic box.
static func decor_parts(node: Node) -> Dictionary:
	var total := 0
	var missing := 0
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child: Node in current.get_children():
			pending.append(child)
			if child is NinePatchRect:
				total += 1
			elif child is Sprite2D:
				total += 1
				if child.texture == Dressing._diagnostic:
					missing += 1
	return {"total": total, "missing": missing}


static func background_slots(
	map: Dictionary, manifest: Dictionary, pack: String, slots: Dictionary
) -> void:
	var empty := {"bg1": "", "bg2": "", "bg3": "", "gradient": "", "height": map.get("height", 0)}
	for slot: String in ["bg1", "bg2", "bg3"]:
		# The view reads a missing slot as background 0.
		var choice := str(map.get(slot, "0"))
		var probe := empty.duplicate()
		probe[slot] = choice
		var layers: Array = resolved(manifest, pack, probe, "_layers")
		var id := choice.trim_suffix(",0")
		add(
			slots,
			"background",
			id,
			"pack" if not layers.is_empty() else "fallback",
			1,
			"" if not layers.is_empty() else "not drawn; base colour shows"
		)
	if map.has("gradient"):
		var probe := empty.duplicate()
		probe.gradient = str(map.gradient)
		var name := str(map.gradient).split("_")[0]
		var strips: Array = resolved(manifest, pack, probe, "_strips")
		# Same test as pack_background.gd: a non-empty pack entry wins over custom strips.
		var entry: Variant = manifest.get("gradients", {}).get(name, {})
		var from_pack: bool = entry is Dictionary and not entry.is_empty()
		var status := "fallback"
		var detail := "not drawn; base colour shows"
		if not strips.is_empty():
			status = "pack" if from_pack else "level"
			detail = "" if from_pack else "custom strips in the level code"
		add(
			slots,
			"gradient",
			name if from_pack or strips.is_empty() else "custom",
			status,
			1,
			detail
		)
	if map.has("customGradientGenerator"):
		add(slots, "gradient", "generated", "level", 1, "customGradientGenerator in the level code")


## The drawn layers or gradient strips that pack_background.gd resolves for one map setting.
static func resolved(manifest: Dictionary, pack: String, map: Dictionary, part: String) -> Array:
	var background: Node2D = Background.new()
	background.setup(manifest, pack, map)
	var result: Array = background.get(part).duplicate()
	background.free()
	return result


func hud_slots(manifest: Dictionary, pack: String) -> Array:
	var hud: Node2D = Hud.new()
	hud.setup(manifest, pack)
	var root := Node2D.new()
	hud._setup_companion(root)
	var result := []
	var names := ["countdown", "coins", "redcoins", "flowers"]
	for index in names.size():
		var drawn: bool = not hud._icons[index].is_empty()
		result.append(slot("hud", names[index], drawn, "text only, no icon"))
	result.append(
		slot(
			"hud",
			"font",
			not hud._bitmap.is_empty() or hud._font != ThemeDB.fallback_font,
			"engine default font"
		)
	)
	result.append(slot("hud", "backing", not hud._backing.is_empty(), "no backing"))
	result.append(slot("hud", "companion", hud._companion.has_meta("pack_art"), "plain white box"))
	result.append(slot("hud", "bubble", hud._bubble.has_meta("pack_art"), "generated ring"))
	result.append(slot("hud", "captor", hud._rescuers[0].has_meta("pack_art"), "plain white box"))
	root.free()
	hud.free()
	return result


## Pantry-style room wall and shelf supports (pack_dressing.gd room() and supports()).
## They are optional: without them the view draws nothing extra.
static func scenery_slots(manifest: Dictionary, pack: String) -> Array:
	var wall := (
		manifest.has("background")
		and Dressing.load_texture(pack.path_join(manifest.background.wall)) != null
	)
	var supports := (
		manifest.has("supports")
		and Dressing.load_texture(pack.path_join(manifest.supports.shelf)) != null
		and Dressing.load_texture(pack.path_join(manifest.supports.bracket)) != null
	)
	return [
		slot("scenery", "room wall", wall, "optional; nothing drawn"),
		slot("scenery", "supports", supports, "optional; nothing drawn"),
	]


## Engine-internal codes that exist only as runtime rows (shots, pellets and the like).
static func runtime_slots(manifest: Dictionary, pack: String) -> Array:
	var pattern := RegEx.create_from_string(LEVEL_CODE)
	var result := []
	for code: String in Registry.codes():
		var type := Registry.lookup(code)
		if pattern.search(code) != null or not Registry.constant(type, "DYNAMIC", false):
			continue
		var drawn := not Dressing.object_art(manifest, pack, code).is_empty()
		result.append(slot("runtime", code, drawn, "diagnostic square"))
	return result


static func slot(kind: String, id: String, drawn: bool, fallback: String) -> Dictionary:
	return {
		"kind": kind,
		"id": id,
		"status": "pack" if drawn else "fallback",
		"instances": 1,
		"detail": "" if drawn else fallback,
	}


static func add(
	slots: Dictionary, kind: String, id: String, status: String, count: int, detail: String
) -> void:
	var key := "%s|%s|%s" % [kind, id, status]
	if not slots.has(key):
		slots[key] = {"kind": kind, "id": id, "status": status, "instances": 0, "details": {}}
	slots[key].instances += count
	if not detail.is_empty():
		add_detail(slots, kind, id, status, detail, count)


static func add_detail(
	slots: Dictionary, kind: String, id: String, status: String, detail: String, count: int
) -> void:
	var details: Dictionary = slots["%s|%s|%s" % [kind, id, status]].details
	details[detail] = details.get(detail, 0) + count
