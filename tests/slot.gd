extends SceneTree
## Exercise the actual game composition's one-slot contract, including pending writes.
const Game = preload("res://src/view/game.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Sim = preload("res://src/sim/step.gd")
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if "--block-slot-write" in arguments:
		for argument: String in arguments:
			if argument.begins_with("--save-dir="):
				DirAccess.make_dir_recursive_absolute(
					argument.trim_prefix("--save-dir=").path_join("slot.egg")
				)
	var game := Game.new()
	root.add_child(game)
	for tick in 10:
		await physics_frame
	var expected := Snapshot.encode(game.state)
	game.save_slot("slot")
	# Advance through the public core while storage is pending or unavailable.
	Sim.advance(game.state, Sim.LEFT | Sim.JUMP, game.world)
	game.load_slot("slot")
	check(Snapshot.encode(game.state) == expected, "Immediate load restores a pending manual save")
	for tick in 20:
		await physics_frame
	check(Snapshot.encode(game.state) != expected, "The real game continues between save and load")
	game.load_slot("slot")
	check(Snapshot.encode(game.state) == expected, "Later load restores the exact same slot bytes")
	print("SLOT_RESULT: 3 assertions, %d failures" % failures)
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
