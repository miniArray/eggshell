extends RefCounted
## Smooth drawing between fixed simulation steps. It records drawn positions before
## each step and blends them with the current state for a picture. It reads saved
## state only: the blended picture is a separate shallow copy, never the state.
##
## No blend happens across a restore or replaced state, a frame gap, a map change,
## a respawn, or a move longer than TELEPORT in one step; those draw the current state.

const Life = preload("res://src/sim/life.gd")
const S := preload("res://src/sim/units.gd").SCALE
## A larger move in one step is a jump in place, not motion.
const TELEPORT := 64 * S
## Player-level positions drawn by the view, as [x field, y field] pairs.
const PAIRS := [
	["x", "y"],
	["camera_x", "camera_y"],
	["recovery_x", "recovery_y"],
	["rescue_1_x", "rescue_1_y"],
	["rescue_2_x", "rescue_2_y"],
	["rescue_3_x", "rescue_3_y"],
	["rescue_4_x", "rescue_4_y"],
]
## Saved read views that hold the same rows as the entity table.
const READ_VIEWS := ["enemies", "springs"]

var _pose := {}
var _physics_frame := -1


## Record the drawn positions just before a simulation step.
func before_step(state: Dictionary, physics_frame: int) -> void:
	_pose = capture(state)
	_physics_frame = physics_frame


## Forget the recorded positions, for example after a restore.
func clear() -> void:
	_pose = {}
	_physics_frame = -1


## The picture for a rendered frame. `fraction` is the elapsed part of the current
## step, from 0 to 1. A frame after a tick without a step draws the current state.
func shown(state: Dictionary, physics_frame: int, fraction: float) -> Dictionary:
	if _pose.is_empty() or physics_frame != _physics_frame:
		return state
	return blend(_pose, state, fraction)


static func capture(state: Dictionary) -> Dictionary:
	var pose := {
		"source": state,
		"frame": int(state.get("frame", 0)),
		"map_index": int(state.get("map_index", 1)),
		"life_phase": int(state.get("life_phase", Life.PLAY)),
	}
	for pair: Array in PAIRS:
		for field: String in pair:
			pose[field] = state.get(field)
	var rows: Array = state.get("entities", [])
	var tokens := PackedInt64Array()
	var xs := PackedInt64Array()
	var ys := PackedInt64Array()
	tokens.resize(rows.size())
	xs.resize(rows.size())
	ys.resize(rows.size())
	for index in rows.size():
		var entity: Dictionary = rows[index]
		tokens[index] = int(entity.get("token", 0))
		xs[index] = int(entity.get("x", 0))
		ys[index] = int(entity.get("y", 0))
	pose.tokens = tokens
	pose.xs = xs
	pose.ys = ys
	return pose


static func snaps(pose: Dictionary, state: Dictionary) -> bool:
	return (
		pose.is_empty()
		or not is_same(pose.source, state)
		or int(state.get("frame", 0)) != pose.frame + 1
		or int(state.get("map_index", 1)) != pose.map_index
		or (
			pose.life_phase in [Life.FADE_OUT, Life.RESPAWN]
			and int(state.get("life_phase", Life.PLAY)) == Life.FADE_IN
		)
	)


## A shallow copy of `state` with drawn positions moved `alpha` of the way from the
## recorded pose to the current state. Rows that did not move are shared, not copied.
static func blend(pose: Dictionary, state: Dictionary, alpha: float) -> Dictionary:
	if alpha >= 1.0 or snaps(pose, state):
		return state
	alpha = maxf(alpha, 0.0)
	var view := state.duplicate()
	for pair: Array in PAIRS:
		var x: Variant = state.get(pair[0])
		var y: Variant = state.get(pair[1])
		var was_x: Variant = pose.get(pair[0])
		var was_y: Variant = pose.get(pair[1])
		if x is int and y is int and was_x is int and was_y is int:
			if _near(was_x, was_y, x, y):
				view[pair[0]] = _mix(was_x, x, alpha)
				view[pair[1]] = _mix(was_y, y, alpha)
	var rows: Array = state.get("entities", [])
	var tokens: PackedInt64Array = pose.tokens
	var lookup := {}
	var moved := {}
	var shown := []
	shown.resize(rows.size())
	for index in rows.size():
		var entity: Dictionary = rows[index]
		shown[index] = entity
		var token := int(entity.get("token", 0))
		var at := index
		if index >= tokens.size() or tokens[index] != token:
			if lookup.is_empty():
				for position in tokens.size():
					lookup[tokens[position]] = position
			at = lookup.get(token, -1)
		if at < 0:
			continue
		var x: Variant = entity.get("x")
		var y: Variant = entity.get("y")
		if not x is int or not y is int:
			continue
		var was_x: int = pose.xs[at]
		var was_y: int = pose.ys[at]
		if (was_x == x and was_y == y) or not _near(was_x, was_y, x, y):
			continue
		var copy := entity.duplicate()
		copy.x = _mix(was_x, x, alpha)
		copy.y = _mix(was_y, y, alpha)
		shown[index] = copy
		moved[token] = copy
	view.entities = shown
	for name: String in READ_VIEWS:
		var source: Variant = state.get(name)
		if not source is Array:
			continue
		var replaced := []
		replaced.resize(source.size())
		for index in source.size():
			var row: Dictionary = source[index]
			replaced[index] = moved.get(int(row.get("token", 0)), row)
		view[name] = replaced
	return view


static func _near(was_x: int, was_y: int, x: int, y: int) -> bool:
	return absi(x - was_x) <= TELEPORT and absi(y - was_y) <= TELEPORT


static func _mix(from: int, to: int, alpha: float) -> int:
	return from + roundi((to - from) * alpha)
