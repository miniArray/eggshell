extends RefCounted
## A head-box view for types with a separate saved head hull.
const Registry = preload("res://src/sim/registry.gd")
const Dressing = preload("res://src/view/pack_dressing.gd")
const Frames = preload("res://src/view/pack_frames.gd")
const S := preload("res://src/sim/units.gd").SCALE


static func create(
	code: String, root: Node2D, manifest: Dictionary, pack: String, fallback: Callable
) -> Sprite2D:
	var art := Dressing.object_art(manifest, pack, code + "_head")
	var node: Sprite2D
	if art.is_empty():
		node = Sprite2D.new()
		node.texture = fallback.call(code + "_head", 32)
	else:
		node = Dressing.sprite(art, 10)
	node.centered = false
	node.z_index = 10
	node.set_meta("stateful", true)
	root.add_child(node)
	return node


static func present(node: Sprite2D, entity: Dictionary, state: Dictionary) -> void:
	node.visible = (
		entity.status == Registry.ACTIVE
		and not entity.collected
		and not entity.get("held", 0)
		and not entity.get("hidden", 0)
	)
	if not node.visible:
		return
	Frames.apply(node, state.frame)
	var box: Array = Registry.lookup(entity.code).head_box(entity)
	node.position = Vector2(box[0], box[1]) / S
	node.offset = Vector2.ZERO
	node.scale = Vector2(box[2] - box[0], box[3] - box[1]) / S / node.texture.get_size()
