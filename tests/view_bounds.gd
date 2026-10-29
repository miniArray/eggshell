extends SceneTree
## Pure decision boundaries and conservative geometry checked against actual node transforms.
const Policy = preload("res://src/view/view_visibility.gd")
const Bounds = preload("res://src/view/visual_bounds.gd")
const View = preload("res://src/view/level_view.gd")
const State = preload("res://src/sim/play_state.gd")
const Dressing = preload("res://src/view/pack_dressing.gd")
const Frames = preload("res://src/view/pack_frames.gd")
const StressPack = preload("res://tests/visibility_pack.gd")
const InputPack = preload("res://tests/density_pack.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var camera := Policy.camera(Vector2(640, 480), Vector2.ZERO, 1)
	check(camera == Rect2(-2, -2, 644, 484), "Camera includes the declared margin")
	for edge: float in [641, 642, 643]:
		check(
			Policy.needed(Rect2(edge, 0, 1, 1), Vector2.ZERO, camera) == (edge <= 642),
			"Right boundary at %s" % edge
		)
		check(
			Policy.needed(Rect2(639 - edge, 0, 1, 1), Vector2.ZERO, camera) == (edge <= 642),
			"Left boundary at %s" % edge
		)
		check(
			Policy.needed(Rect2(0, edge - 160, 1, 1), Vector2.ZERO, camera) == (edge <= 642),
			"Bottom boundary at %s" % edge
		)
		check(
			Policy.needed(Rect2(0, 639 - edge, 1, 1), Vector2.ZERO, camera) == (edge <= 642),
			"Top boundary at %s" % edge
		)
	check(Policy.needed(null, Vector2(999999, 999999), camera), "Unproven bounds always update")
	check(
		Policy.needed(Rect2(10000, 10000, 1, 1), Vector2.ZERO, null),
		"Reference mode always updates"
	)
	check(
		Policy.needed(Rect2(-10, -10, 20, 20), Vector2(645, 240), camera),
		"Art can enter before its origin"
	)
	check(
		(
			Policy.camera(Vector2(160, 768), Vector2(-21, -43), 4)
			== Rect2(Vector2(5.25, 10.75), Vector2(40, 192)).grow(2)
		),
		"Container, actual translation and zoom determine camera independently"
	)
	for density: int in [1, 2, 4]:
		geometry_checks(density)
	print("VIEW_BOUNDS_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func geometry_checks(density: int) -> void:
	var path := StressPack.create(density)
	var world := StressPack.world()
	var state := State.create(world)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var view := View.new()
	viewport.add_child(view)
	view.setup(world, path)
	check(Bounds.placed(view._placed_nodes.snow, "d22") == null, "Independent snow puffs fail open")
	for entity: Dictionary in state.entities:
		if entity.id not in ["coin", "cloud", "stem", "spikes"]:
			continue
		var node: Sprite2D = view._placed_nodes[entity.id]
		var shape := Bounds.geometry(node)
		check(not shape.is_empty(), "Stress art has a proven shape: " + entity.id)
		for size: float in [0, 0.001, 0.1, 1, 16, 100, 1000]:
			for rotation: float in [0, 45, 90, 180]:
				for frame in 3:
					var look := {
						"size_x": size,
						"size_y": size / 2,
						"rotation": rotation,
						"offset_x": -100,
						"offset_y": 80,
						"frame": frame,
						"flip_x": frame % 2 == 1
					}
					var envelope: Rect2 = Bounds.with_look(shape, look)
					for multiple in 3:
						Frames.unsnap(node)
						Dressing.update_placed(node, entity, state, look)
						if density > 1:
							Frames.snap(node, density * (multiple + 1))
						var actual := drawn_bounds(node)
						actual.position -= Vector2(entity.x, entity.y) / State.SCALE
						check(
							envelope.grow(0.001).encloses(actual),
							(
								"Envelope contains actual frame/parts: %s density %d size %f rotation %f frame %d"
								% [entity.id, density, size, rotation, frame]
							)
						)
	view.free()
	viewport.free()
	InputPack.remove(path)


## Read the final submitted geometry, not the production envelope implementation.
static func drawn_bounds(node: Node2D) -> Rect2:
	var rect: Rect2 = node.get_rect() if node is Sprite2D and node.texture != null else Rect2()
	for child: Node in node.get_children():
		if child is CanvasItem and not child.visible:
			continue
		var part := Rect2()
		if child is Node2D:
			part = drawn_bounds(child)
		elif child is Control:
			part = child.get_transform() * Rect2(Vector2.ZERO, child.size)
		rect = rect.merge(part)
	return node.transform * rect


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		if _failures <= 10:
			printerr("FAIL: " + label)
