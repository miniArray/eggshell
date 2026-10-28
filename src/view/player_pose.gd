extends RefCounted
## Read-only selection. Missing pack poses fall back through the pack's normal policy.
const Moves = preload("res://src/sim/moves.gd")


static func select(state: Dictionary) -> Dictionary:
	var full := int(state.get("move_held_id", 0) != 0 or state.get("move_ammo_count", 0) != 0)
	var action: int = state.get("move_action", Moves.NORMAL)
	var tick: int = state.get("move_action_tick", 0)
	var name := ""
	var frame := 0
	if state.hurt:
		name = "Hurt%d" % full
	elif action in [Moves.POUND_START, Moves.POUND_FALL]:
		name = "GroundPound%d" % full
		if action == Moves.POUND_FALL:
			tick += 24
	elif action == Moves.POUND_LAND:
		name = "GPLand%d" % full
	elif action == Moves.TONGUE:
		name = ("TongueUp" if state.move_tongue_axis else "Tongue") + str(state.move_action_wet)
		frame = 1 + mini(1, tick * 24 / 60) if state.move_tongue_phase == Moves.TONGUE_FAILED else 0
	elif action == Moves.SPIT:
		name = ("SpitUp" if state.move_tongue_axis else "Spit") + str(state.move_action_wet)
	elif action == Moves.LAY:
		name = "LayEgg"
	elif action == Moves.EMIT:
		name = "SpewSeed" if state.move_ammo == Moves.SEED else "Spew"
		if state.move_tongue_axis:
			name += "Up"
		if state.move_ammo == Moves.SEED and not state.on_floor and not state.swimming:
			name += "Jump"
		else:
			name += str(state.swimming)
	elif action == Moves.TOSS:
		name = "EggToss%d" % full
	elif action == Moves.SWALLOW:
		name = "InstantSwallow"
	elif action == Moves.HEAD_BUMP:
		name = "HeadBump%d" % full
	elif state.get("move_aim", 0):
		if state.flutter_remaining:
			name = "FlutterAim%d" % full
		elif state.on_floor and state.vx:
			name = "WalkAim%s%d" % ["R" if state.vx > 0 else "L", full]
		else:
			name = "GrabEgg%d" % full
	elif state.get("move_duck", 0):
		name = "Duck%d" % full
		tick = state.get("move_posture_tick", 0)
	elif state.get("move_look", 0):
		name = "LookUp%d" % full
		frame = int(state.get("move_posture_tick", 0) != 0)
	elif state.swimming:
		if state.get("move_water_jump", 0):
			name = "Jump%d" % full
		elif state.get("move_water_transition", 0):
			name = ("Submerge" if state.move_dive else "Unsubmerge") + str(full)
			tick = 9 - state.move_water_transition
		elif state.get("move_dive", 0):
			name = "SwimSubmerged" if state.vx else "Submerge%d" % full
			tick = state.frame if state.vx else 9
		else:
			name = ("Swim" if state.vx else "Float") + str(full)
			tick = state.frame
	elif state.get("move_push", 0):
		name = "Push%d" % full
		tick = state.frame
	elif state.get("move_turn", 0):
		name = "Turn%d" % full
		tick = 30 - state.move_turn_ticks
	elif action == Moves.LAND:
		name = "Land%d" % full
	elif state.get("move_gravity_tick", 0):
		name = "Fall%d" % full
	else:
		name = (
			["Idle", "Walk", "Sprint", "Jump", "Fall", "Idle", "Flutter"][state.movement]
			+ str(full)
		)
		tick = state.frame
	return {"name": name, "tick": tick, "frame": frame}
