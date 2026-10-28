extends RefCounted
## Read-only presentation of the runtime suffix. Nodes are a disposable view cache.

const Registry = preload("res://src/sim/registry.gd")
const Dressing = preload("res://src/view/pack_dressing.gd")
const Frames = preload("res://src/view/pack_frames.gd")
const S := preload("res://src/sim/units.gd").SCALE
var _nodes := {}
var _root: Node2D
var _pack := ""
var _identity := ""


func render(
	state: Dictionary,
	world: Dictionary,
	root: Node2D,
	manifest: Dictionary,
	pack: String,
	fallback: Callable
) -> void:
	if root != _root or pack != _pack or world.get("identity", "") != _identity:
		clear()
		_root = root
		_pack = pack
		_identity = world.get("identity", "")
	var seen := {}
	# Placement rows are a fixed prefix; only the suffix can contain runtime nodes.
	for index in range(world.get("entities", []).size(), state.entities.size()):
		var entity: Dictionary = state.entities[index]
		if entity.source_index != -1:
			continue
		seen[entity.token] = true
		var type := Registry.lookup(entity.code)
		var style: Dictionary = (
			type.view_state(entity, state) if type.has_method("view_state") else {}
		)
		var visible: bool = style.get("visible", entity.status == 1 and not entity.collected)
		visible = visible and entity.get("held", 0) != 1 and entity.get("hidden", 0) != 1
		var entry: Dictionary = _nodes.get(entity.token, {})
		if not visible:
			if not entry.is_empty() and is_instance_valid(entry.node):
				entry.node.visible = false
			continue
		var variant := int(entity.get("variant", 0))
		if not entry.is_empty() and (entry.code != entity.code or entry.variant != variant):
			if is_instance_valid(entry.node):
				entry.node.free()
			entry = {}
		if entry.is_empty() or not is_instance_valid(entry.node):
			entry = make_node(entity, root, manifest, pack, fallback)
			if entry.is_empty():
				continue
			_nodes[entity.token] = entry
		var node: Sprite2D = entry.node
		node.visible = true
		apply_frame(node, entry.art, state.frame, variant, style)
		var box: Array = (
			type.bounds(entity) if type.has_method("bounds") else [-16 * S, -16 * S, 16 * S, 16 * S]
		)
		place(node, entity, box, entry.art, style)
	for token: int in _nodes.keys():
		if not seen.has(token):
			var node: Sprite2D = _nodes[token].node
			if is_instance_valid(node):
				node.free()
			_nodes.erase(token)


func clear() -> void:
	for entry: Dictionary in _nodes.values():
		if is_instance_valid(entry.node):
			entry.node.free()
	_nodes.clear()


static func make_node(
	entity: Dictionary, root: Node2D, manifest: Dictionary, pack: String, fallback: Callable
) -> Dictionary:
	var variant := int(entity.get("variant", 0))
	var art := Dressing.object_art(manifest, pack, entity.code, variant)
	var node: Sprite2D
	if art.is_empty():
		if not fallback.is_valid():
			return {}
		var texture: Texture2D = fallback.call(entity.code, 32)
		if texture == null:
			return {}
		node = Sprite2D.new()
		node.texture = texture
		node.centered = false
	else:
		node = Dressing.sprite(art, entity.layer)
	node.z_index = clampi(entity.layer, -4096, 4096)
	node.set_meta("stateful", true)
	node.set_meta("entity_token", entity.token)
	root.add_child(node)
	return {"node": node, "art": art, "code": entity.code, "variant": variant}


static func apply_frame(
	node: Sprite2D, art: Dictionary, tick: int, variant: int, style: Dictionary
) -> void:
	if art.is_empty():
		return
	var animation: String = style.get("animation", "")
	var effective := art
	if art.animations.has(animation):
		effective = art.duplicate()
		effective.default_animation = animation
		effective.states = {}
	node.set_meta("pack_art", effective)
	node.set_meta("pack_variant", variant)
	if not style.has("frame"):
		Frames.apply(node, tick, animation)
		return
	# A supplied frame is held literally, independent of animation rate.
	var name: String = effective.states.get(
		"%s:%d" % [animation, variant], effective.states.get(animation, effective.default_animation)
	)
	if not effective.animations.has(name):
		name = effective.default_animation
	var frames: Array = effective.animations[name].frames
	var selected: Dictionary = frames[clampi(int(style.frame), 0, frames.size() - 1)]
	node.texture = selected.texture
	node.offset = -selected.origin


static func place(
	node: Sprite2D, entity: Dictionary, box: Array, art: Dictionary, style: Dictionary
) -> void:
	node.scale = Vector2.ONE
	node.flip_h = false
	node.flip_v = false
	var position_anchor: bool = not art.is_empty() and art.get("anchor", "box") == "position"
	if art.is_empty():
		node.offset = Vector2.ZERO
		node.position = Vector2(entity.x + box[0], entity.y + box[1]) / S
		node.scale = Vector2(box[2] - box[0], box[3] - box[1]) / (32 * S)
	elif position_anchor:
		node.position = Vector2(entity.x, entity.y) / S
		node.scale.x = 1 if entity.facing == art.get("facing", 1) else -1
	else:
		var anchor: float = box[3] if Dressing.bottom_anchored(art) else (box[1] + box[3]) / 2.0
		node.position = Vector2(entity.x + (box[0] + box[2]) / 2.0, entity.y + anchor) / S
		node.flip_h = entity.facing < 0
	if style.has("size_x"):
		node.scale.x = signf(node.scale.x) * float(style.size_x) / node.texture.get_width()
	if style.has("size_y"):
		node.scale.y = float(style.size_y) / node.texture.get_height()
	if style.has("flip_x"):
		if position_anchor:
			node.scale.x = absf(node.scale.x) * (-1 if style.flip_x else 1)
		else:
			node.flip_h = bool(style.flip_x)
	node.position += Vector2(float(style.get("offset_x", 0)), float(style.get("offset_y", 0)))
	node.rotation_degrees = float(style.get("rotation", 0))
	node.modulate.a = clampf(float(style.get("modulate_alpha", 1)), 0, 1)
