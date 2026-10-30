extends SceneTree
## Bounded normal-input discovery for the authored post course only; no state edits.
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/level/collision_table.gd")
const State = preload("res://src/sim/play_state.gd")
const Step = preload("res://src/sim/step.gd")


func _initialize() -> void:
	var built := World.build(
		FileAccess.get_file_as_string(
			"res://spikes/rust-stack/core/tests/fixtures/posts_target.level.json"
		),
		Collision.read()
	)
	if not built.ok:
		quit(1)
		return
	var best := -1
	for warmup: int in [0, 10, 20, 30, 40]:
		for jump: int in [15, 25, 35, 45, 55]:
			for brake: int in [0, 4, 8, 12]:
				var state := State.create(built.world)
				var supported := 0
				for tick in 180:
					var input := (
						2
						if tick < warmup
						else (
							6
							if tick < warmup + jump
							else (1 if tick < warmup + jump + brake else 0)
						)
					)
					Step.advance(state, input, built.world)
					for entity: Dictionary in state.entities:
						if (
							entity.code == "o23"
							and state.on_floor
							and absi(state.y - (entity.y - entity.height)) < 3600
							and absi(state.x - entity.x) < 28 * 3600
						):
							supported += 1
				if supported > best:
					best = supported
					print(
						(
							"POST_NORMAL_INPUT_CANDIDATE warmup=%d jump=%d brake=%d support=%d"
							% [warmup, jump, brake, supported]
						)
					)
	print("POST_NORMAL_INPUT_PROBE_DONE best_support=%d target_route=false state_edits=0" % best)
	quit(0 if best > 0 else 1)
