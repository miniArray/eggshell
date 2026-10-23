extends Node
## Opt-in frame/visibility evidence. Never writes play state or changes the view.

var _game: Node
var _view: Node2D
var _file: FileAccess
var _events: FileAccess
var _regions: Array[Dictionary] = []
var _seen := {}
var _previous_usec := 0
var _post_draw_usec := 0
var _first_draw := true


func setup(game: Node, view: Node2D, path: String) -> Error:
	_game = game
	_view = view
	_file = FileAccess.open(path + ".stall.csv", FileAccess.WRITE)
	_events = FileAccess.open(path + ".events.jsonl", FileAccess.WRITE)
	if _file == null or _events == null:
		set_process(false)
		return ERR_CANT_OPEN
	_file.store_line(
		(
			"usec,tick,interval_ms,camera_x,camera_y,post_draw_usec,"
			+ "static_bytes,video_bytes,objects,draw_calls"
		)
	)
	process_priority = 100
	_previous_usec = Time.get_ticks_usec()
	RenderingServer.frame_post_draw.connect(_post_draw)
	var terrain_index := 0
	var object_index := 0
	var goal_index := 0
	for root: Node in view.get_children():
		for node: Node in root.get_children():
			if node is TileMapLayer:
				var cells := {}
				for cell: Vector2i in node.get_used_cells():
					cells[cell] = true
				_regions.append(
					{
						"kind": "water" if node.get_meta("water", false) else "terrain",
						"index": terrain_index,
						"node": node,
						"cells": cells,
						"used": node.get_used_rect()
					}
				)
				terrain_index += 1
			elif node is Sprite2D and node != view.get("_player"):
				if node.get_meta("goal", false):
					_regions.append({"kind": "goal", "index": goal_index, "node": node})
					goal_index += 1
				else:
					_regions.append({"kind": "object", "index": object_index, "node": node})
					object_index += 1
	for node: Polygon2D in view.find_children("*", "Polygon2D", true, false):
		if node.polygon.is_empty():
			continue
		var bounds := Rect2(node.polygon[0], Vector2.ZERO)
		for point: Vector2 in node.polygon:
			bounds = bounds.expand(point)
		_regions.append({"kind": "goal", "index": goal_index, "node": node, "bounds": bounds})
		goal_index += 1
	_events.store_line(
		JSON.stringify(
			{
				"event": "probe_ready",
				"usec": Time.get_ticks_usec(),
				"unix": Time.get_unix_time_from_system()
			}
		)
	)
	return OK


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var state: Dictionary = _game.get("state")
	_file.store_line(
		(
			"%d,%d,%.3f,%.3f,%.3f,%d,%d,%d,%d,%d"
			% [
				now,
				state.frame,
				(now - _previous_usec) / 1000.0,
				state.camera_x / 3600.0,
				state.camera_y / 3600.0,
				_post_draw_usec,
				Performance.get_monitor(Performance.MEMORY_STATIC),
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			]
		)
	)
	_previous_usec = now
	var viewport := _view.get_viewport_rect()
	for region: Dictionary in _regions:
		var key := "%s:%d" % [region.kind, region.index]
		if _seen.has(key):
			continue
		var node: Node2D = region.node
		if not node.is_visible_in_tree():
			continue
		var visible := false
		if node is TileMapLayer:
			var inverse := node.get_global_transform_with_canvas().affine_inverse()
			var local_view := inverse * viewport
			var first: Vector2i = node.local_to_map(local_view.position)
			var last: Vector2i = node.local_to_map(local_view.end)
			if not region.used.intersects(Rect2i(first, last - first + Vector2i.ONE)):
				continue
			for x in range(first.x, last.x + 1):
				for y in range(first.y, last.y + 1):
					if region.cells.has(Vector2i(x, y)):
						visible = true
						break
				if visible:
					break
		elif node is Sprite2D:
			visible = viewport.intersects(node.get_global_transform_with_canvas() * node.get_rect())
		elif node is Polygon2D:
			visible = viewport.intersects(node.get_global_transform_with_canvas() * region.bounds)
		if visible:
			_seen[key] = true
			_events.store_line(
				JSON.stringify(
					{
						"event": "first_visible",
						"usec": now,
						"tick": state.frame,
						"kind": region.kind,
						"index": region.index,
						"camera_x": state.camera_x / 3600.0
					}
				)
			)


func _post_draw() -> void:
	_post_draw_usec = Time.get_ticks_usec()
	if _first_draw:
		_first_draw = false
		_events.store_line(
			JSON.stringify({"event": "first_gameplay_draw", "usec": _post_draw_usec})
		)


func _exit_tree() -> void:
	if _file != null:
		_file.close()
	if _events != null:
		_events.close()
