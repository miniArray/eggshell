extends RefCounted
## The latest sound event in play, for objects that react to what they hear.
## `sound_serial` counts events; `sound_kind`, `sound_x` and `sound_y` describe the latest
## one. Emitting is pure saved state: nothing here plays audio, and the audio view keeps
## deriving its own cues. A listener saves the serial it last heard and reacts when the
## serial differs, so a restored snapshot replays nothing and needs no extra state.

const LEVEL_FIELDS := [["sound_serial", 0], ["sound_kind", 0], ["sound_x", 0], ["sound_y", 0]]
const NONE := 0
## A player sound effect, at the player's body centre.
const PLAYER := 1
## A collected coin, flower or star, at the pickup.
const PICKUP := 2
## A pressed switch, at the switch.
const SWITCH := 3
## A flower releasing a pickup. Listeners hear it at their own position.
const RELEASE := 4
const LAST_KIND := RELEASE
## The standing body centre above the player's feet, in pixels.
const PLAYER_CENTRE := 28
const MAX_SERIAL := 0x7fffffffffffffff
const S := preload("res://src/sim/units.gd").SCALE


static func emit(state: Dictionary, kind: int, x: int, y: int) -> void:
	var serial: int = int(state.get("sound_serial", 0))
	state.sound_serial = 1 if serial >= MAX_SERIAL else serial + 1
	state.sound_kind = kind
	state.sound_x = x
	state.sound_y = y


## A player sound effect. The original lets listeners hear every player effect
## except aiming ticks, pushing and ducking; callers emit only at those moments.
static func player(state: Dictionary) -> void:
	emit(state, PLAYER, int(state.x), int(state.y) - PLAYER_CENTRE * S)


## True when an event happened after the listener's saved serial.
static func heard(state: Dictionary, cursor: int) -> bool:
	return int(state.get("sound_serial", 0)) != cursor


static func valid_state(state: Dictionary) -> bool:
	return (
		int(state.get("sound_serial", 0)) >= 0
		and int(state.get("sound_kind", 0)) >= NONE
		and int(state.get("sound_kind", 0)) <= LAST_KIND
	)
