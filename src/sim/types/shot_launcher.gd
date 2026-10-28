extends RefCounted
## A solid launcher that fires one shot at a time: straight, bouncing or homing.
## Fixed launchers fire level toward the player's side; aiming launchers fire
## straight at the player. It fires again five seconds after a shot, once that
## shot is gone. Ice freezes it for good: it stops firing, stops being solid and
## shatters when the player touches it.

const S := preload("res://src/sim/units.gd").SCALE
const Motion = preload("res://src/sim/enemy_motion.gd")
const Shot = preload("res://src/sim/types/launcher_shot.gd")
const Moves = preload("res://src/sim/moves.gd")
const Elements = preload("res://src/sim/elements.gd")
const CODES := ["e37"]
const SOLID := 1
const CONTACT_PHASE := 1
const ELEMENT_REACTIONS := Elements.FREEZES | Elements.ANCHORED
const FIELDS := [
	["aim", 0],
	["form", 0],
	["ready", 1],
	["delay", 0],
	["charge", 0],
	["side", 1],
	["heading", 180000],
	["shot_token", 0],
	["frozen", 0]
]
const CHARGE_TICKS := 30  # 0.5 s between the cue and the shot.
const DELAY_TICKS := 300  # 5 s after a shot before the next.
const SHOT_SPEED := 296


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var mode: Variant = source.properties.get("E1", "Static")
	var form: Variant = source.properties.get("F", 0)
	if not mode is String or not (form is int or form is float) or not is_finite(form):
		return {"ok": false, "error": "Invalid launcher mode or form"}
	if form < 0 or form != floor(form):
		return {"ok": false, "error": "Invalid launcher form"}
	if mode not in ["Static", "Aim"]:
		return {"ok": false, "degrade": true, "error": "launcher mode E1=" + mode}
	if form > 2:
		return {"ok": false, "degrade": true, "error": "launcher shot form F=%d" % form}
	source.aim = int(mode == "Aim")
	source.form = int(form)
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {
		"aim": int(source.aim),
		"form": int(source.form),
		"spawn_mode": 1,
		"status": 0,
		"can_despawn": 1,
		"can_respawn": 1
	}


static func bounds(_entity: Dictionary) -> Array:
	return [-16 * S, -16 * S, 16 * S, 16 * S]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1 or entity.frozen:
		return []
	return [entity.x - 16 * S, entity.y - 16 * S, entity.x + 16 * S, entity.y + 16 * S]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.frozen:
		return
	if entity.charge:
		entity.charge -= 1
		if entity.charge == 0:
			fire(entity, state, world)
		return
	entity.side = 1 if state.x < entity.x else 2
	entity.heading = Motion.angle_to(state.x - entity.x, state.y - 32 * S - entity.y)
	if entity.delay:
		entity.delay -= 1
	if not entity.ready and entity.shot_token:
		var shot: Dictionary = registry().find_token(state, entity.shot_token)
		if shot.is_empty() or shot.status == 3:
			entity.ready = 1
			entity.shot_token = 0
	if entity.ready and entity.delay == 0:
		entity.ready = 0
		entity.charge = CHARGE_TICKS


static func fire(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var heading: int = entity.heading if entity.aim else (180000 if entity.side == 1 else 0)
	var speed := SHOT_SPEED * 60
	var shot: Dictionary = registry().spawn_dynamic(
		state,
		world,
		Shot.CODES[0],
		entity.x,
		entity.y,
		{
			"vx": speed * Motion.turn_cosine(heading) / S,
			"vy": speed * Motion.turn_sine(heading) / S,
			"facing": -1 if entity.side == 1 else 1,
			"form": entity.form,
			"heading": heading
		}
	)
	entity.shot_token = int(shot.get("token", 0))
	entity.ready = int(shot.is_empty())
	entity.delay = DELAY_TICKS


## Ice breath freezes it. Every other projectile keeps meeting only its solid box.
static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	if projectile.get("code", "") == "ice_shot" and entity.status == 1:
		entity.frozen = 1
		entity.charge = 0
	return 0


## Only a frozen launcher reacts to touch: it shatters, and a stomp also bounces.
static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if not entity.frozen or entity.status != 1 or state.get("captured_by", 0):
		return
	var player := Moves.player_box(state)
	if (
		state.x + player[2] > entity.x - 16 * S
		and state.x + player[0] < entity.x + 16 * S
		and state.y + player[3] > entity.y - 16 * S
		and state.y + player[1] < entity.y + 16 * S
	):
		if (
			entity.y > state.y - 8 * S
			and state.move_action not in [Moves.POUND_FALL, Moves.POUND_LAND]
		):
			Moves.bounce(state, -320 * 60, input)
		entity.status = 3
		entity.can_respawn = 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var result := {"visible": entity.status == 1, "animation": str(entity.form)}
	if entity.frozen:
		result.alpha = 0.6
	if entity.aim:
		result.rotation = float(entity.heading) / 1000.0
	return result


static func valid(entity: Dictionary) -> bool:
	return (
		entity.aim in [0, 1]
		and entity.form in [0, 1, 2]
		and entity.ready in [0, 1]
		and entity.delay >= 0
		and entity.delay <= DELAY_TICKS
		and entity.charge >= 0
		and entity.charge <= CHARGE_TICKS
		and entity.side in [1, 2]
		and entity.heading >= 0
		and entity.heading < 360000
		and entity.shot_token >= 0
		and entity.frozen in [0, 1]
	)
