extends SceneTree
## Physical recovery extent is independent of the unchanged collision polygon.

const Courses = preload("res://tests/moves.gd")
const Collision = preload("res://src/sim/collision.gd")
const Bubble = preload("res://src/sim/companion_bubble.gd")
const S := 3600


func _initialize() -> void:
	var world := Courses.empty_world()
	var filled := []
	for row in 32:
		filled.append([16, row])
	world.layers = [Courses.layer("terrain", true, false, filled)]
	Courses.actor(world)
	world.terrain_escapes = {}
	var small := {"x": 513 * S, "y": 512 * S, "vx": 0, "vy": 0}
	var physical := small.duplicate()
	physical.recovery_width = 64 * S
	physical.recovery_height = 64 * S
	var failures := 0
	if Collision.prepare(small, world, Bubble.body()):
		print("FAIL: A 30 px search cannot clear a wall 31 px away")
		failures += 1
	if not Collision.prepare(physical, world, Bubble.body()):
		print(
			"FAIL: Physical width enables the required 32 px search, despite a cached 30 px failure"
		)
		failures += 1
	var displacement: int = 513 * S - physical.x
	if (
		Collision.overlaps(physical, world, Bubble.body())
		or displacement <= 30 * S
		or displacement > 32 * S
	):
		print("FAIL: Recovery clears terrain within the physical search extent: ", displacement)
		failures += 1
	print("RECOVERY_DIMENSIONS_RESULT: 3 assertions, %d failures" % failures)
	quit(1 if failures else 0)
