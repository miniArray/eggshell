extends SceneTree
## Invented registered span. Bubble physics must see solids before ordinary actor motion.
const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Registry = preload("res://src/sim/registry.gd")
const Collision = preload("res://src/sim/collision.gd")
const Bubble = preload("res://src/sim/companion_bubble.gd")
const Life = preload("res://src/sim/life.gd")
const Sim = preload("res://src/sim/step.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const S := 3600
var checks := 0
var failures := 0


func _initialize() -> void:
	var direct := fixture()
	Bubble.advance(direct.state, direct.world)
	check(
		direct.state.recovery_y < 144 * S, "Prepared registered geometry stops the falling Bubble"
	)
	var unit := fixture()
	Sim.advance(unit.state, 0, unit.world)
	check(unit.state.frame == 11, "The real step advances beyond the prior solid-context frame")
	check(
		unit.state.recovery_y < 144 * S,
		"Bubble physics sees the current registered span before actor dispatch"
	)
	var saved := fixture()
	var bytes := Snapshot.encode(saved.state)
	check(not bytes.is_empty(), "The falling Bubble saves")
	var restored := fixture()
	var decoded := Snapshot.decode(bytes, saved.world.identity, restored.world)
	check(decoded.ok, "The falling Bubble restores without a saved collision context")
	if decoded.ok:
		Sim.advance(saved.state, 0, saved.world)
		Sim.advance(decoded.state, 0, restored.world)
		check(decoded.state.recovery_y < 144 * S, "Restored Bubble also lands on the span")
		check(
			Snapshot.encode(saved.state) == Snapshot.encode(decoded.state),
			"Solid-context rebuilding preserves replay"
		)
	print("BUBBLE_SOLID_CONTEXT_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func fixture() -> Dictionary:
	var built := World.build(
		JSON.stringify(
			{
				"version": "s3.8.0",
				"name": "Invented Bubble span",
				"author": "Eggshell",
				"desc": "",
				"startpoint": {"map": 1, "X": 600, "Y": 100},
				"maps":
				{
					"map1":
					{
						"width": 1024,
						"height": 1024,
						"objects":
						{"span": {"A": "p6", "X": 128, "Y": 160, "E1": "128", "E2": "32"}}
					}
				}
			}
		),
		{"tilemaps": {}}
	)
	check(built.ok, "Invented registered span compiles")
	var world: Dictionary = built.world
	var state := State.create(world)
	state.entities[0].status = Registry.ACTIVE
	state.frame = 10
	state.separated = 1
	state.companion_mode = Life.BUBBLE
	state.companion_age = 180
	state.companion_direction = 1
	state.recovery_x = 128 * S
	state.recovery_y = 142 * S
	Collision.begin_step(state, world, Registry)
	return {"state": state, "world": world}


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
