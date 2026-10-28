extends RefCounted
## Texture frames share a cache. Frame selection depends only on the supplied tick.
const Pack = preload("res://src/level/asset_pack.gd")
var _textures: Dictionary = {}
var _visuals: Dictionary = {}


func texture(pack: String, file: Variant) -> Texture2D:
	if not Pack.safe_file(file):
		return null
	var path := pack.path_join(file)
	if _textures.has(path):
		return _textures[path]
	var result: Texture2D
	if path.begins_with("res://"):
		result = ResourceLoader.load(path, "Texture2D") as Texture2D
	else:
		var image := Image.load_from_file(path)
		if image != null:
			result = ImageTexture.create_from_image(image)
	_textures[path] = result
	return result


func visual(pack: String, entry: Variant, density: int = 1) -> Dictionary:
	if not Pack.visual_ok(entry):
		return {}
	var key := pack + str(density) + JSON.stringify(entry)
	if _visuals.has(key):
		return _visuals[key]
	var animations: Dictionary = entry.get("animations", {})
	if animations.is_empty():
		animations = {"default": {"frames": [entry], "fps": 0, "loop": false}}
	var loaded := {}
	for name: String in animations:
		var source: Dictionary = animations[name]
		var frames := []
		var duration := 0.0
		for frame: Dictionary in source.frames:
			var image := texture(pack, frame.file)
			if image == null:
				frames.clear()
				break
			var origin: Array = frame.get("origin", source.get("origin", [0, 0]))
			duration += float(frame.get("duration", 1))
			frames.append(
				{"texture": image, "origin": Vector2(origin[0], origin[1]), "end": duration}
			)
		if not frames.is_empty():
			loaded[name] = {
				"frames": frames,
				"duration": duration,
				"fps": float(source.get("fps", source.get("speed", 0))),
				"loop": bool(source.get("loop", true))
			}
	if loaded.is_empty():
		_visuals[key] = {}
		return {}
	var first: String = entry.get("default_animation", "")
	if not loaded.has(first):
		first = loaded.keys()[0]
	var states: Dictionary = (
		entry.get("states", {}) if entry.get("states", {}) is Dictionary else {}
	)
	var result := {
		"density": density,
		"animations": loaded,
		"default_animation": first,
		"states": states,
		"anchor": entry.get("anchor", "box"),
		"facing": -1 if entry.get("facing", 1) == -1 else 1
	}
	result.merge(loaded[first].frames[0])
	_visuals[key] = result
	return result


static func apply(node: Sprite2D, tick: int, state := "") -> void:
	if not node.has_meta("pack_art"):
		return
	var art: Dictionary = node.get_meta("pack_art")
	var frame := sample(art, tick, state, int(node.get_meta("pack_variant", 0)))
	if node.texture != frame.texture:
		node.texture = frame.texture
	if node.offset != -frame.origin:
		node.offset = -frame.origin


static func sample(art: Dictionary, tick: int, state := "", variant := 0) -> Dictionary:
	var variant_key := "%s:%d" % [state, variant]
	var name: String = str(
		art.states.get(variant_key, art.states.get(state, art.default_animation))
	)
	if not art.animations.has(name):
		name = art.default_animation
	var animation: Dictionary = art.animations[name]
	var frames: Array = animation.frames
	var selected: Dictionary = frames[0]
	if animation.fps == 0:
		selected = frames[clampi(variant, 0, frames.size() - 1)]
	else:
		var position := maxf(0, tick * animation.fps / 60.0)
		if animation.loop:
			position = fmod(position, animation.duration)
		else:
			position = minf(position, animation.duration)
		selected = frames[-1]
		for frame: Dictionary in frames:
			if position < frame.end:
				selected = frame
				break
	return selected


static func snap(node: Sprite2D, world_scale: float) -> void:
	# Only dense packs opt into this policy. Legacy transforms remain untouched.
	if not node.has_meta("pack_density"):
		return
	node.set_meta("pack_transform", node.transform)
	# Squash and fit transforms must not shrink or unevenly stretch source pixels.
	for axis in 2:
		var value := node.scale[axis] * world_scale
		node.scale[axis] = signf(value) * maxi(1, roundi(absf(value))) / world_scale
	var corner := node.position + node.transform.basis_xform(node.get_rect().position)
	node.position += (corner * world_scale).round() / world_scale - corner


static func set_density(node: Sprite2D, density: int) -> void:
	node.scale = Vector2.ONE / density
	if density > 1:
		node.set_meta("pack_density", density)


static func unsnap(node: Sprite2D) -> void:
	if node.has_meta("pack_transform"):
		node.transform = node.get_meta("pack_transform")
		node.remove_meta("pack_transform")
