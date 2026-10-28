extends RefCounted
## Shared integer falling motion for released items. Terrain owns every collision.

const Collision = preload("res://src/sim/collision.gd")


static func fall(
	entity: Dictionary, world: Dictionary, box: Array, gravity: int, max_fall: int
) -> bool:
	if entity.get("ignore_terrain", 0):
		entity.vy = mini(max_fall, entity.vy + gravity)
		entity.x += entity.vx
		entity.y += entity.vy
		return false
	if not Collision.prepare(entity, world, box):
		entity.vx = 0
		entity.vy = 0
		return false
	var support := Collision.track_floor(entity, world, box)
	var grounded: bool = support != 0 and entity.vy >= 0
	if grounded:
		entity.vy = 0
	else:
		entity.vy = mini(max_fall, entity.vy + gravity)
	Collision.horizontal(entity, world, box, entity.vx, support, false, 640 * 60)
	var desired: int = entity.vy
	var actual := Collision.vertical(entity, world, box, desired, support)
	var landed := (
		desired >= 0 and (actual != desired or Collision.floor_at(entity, world, box) != 0)
	)
	if actual != desired or landed:
		entity.vy = 0
	return grounded or landed


static func approach(value: int, target: int, amount: int) -> int:
	return mini(value + amount, target) if value < target else maxi(value - amount, target)
