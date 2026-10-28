extends Node
## Music and effect playback derived from saved state. It compares a small summary of
## the previous observed state with the current one and never writes state.
##
## A restored or replaced state resynchronizes without events, so a restore never
## replays old sounds. Derivation is pure (`summarize`, `derive`, `level_track`) and
## needs no audio device. Without pack audio, or with `--mute`, nothing plays.

const AudioMap = preload("res://src/view/pack_audio.gd")
const Life = preload("res://src/sim/life.gd")
const Moves = preload("res://src/sim/moves.gd")
const Requests = preload("res://src/sim/move_requests.gd")
const VOICES := 8
## Larger frame gaps between observations count as a jump in time, not play.
const MAX_STEP_GAP := 4
const SWITCH_TICKS := 630
const AIM_TICK_FRAMES := 4
const HELD_EVENTS := ["switch_timer"]
const SNOW_STEP_FRAMES := 18
const QUIET_PHASES := [Life.DEAD, Life.FADE_OUT, Life.RESPAWN, Life.GOAL, Life.COMPLETE]
const REQUEST_EVENTS := {
	Requests.SPIT: "spit",
	Requests.SEED: "spit_seed",
	Requests.HEAT: "spit_fire",
	Requests.COLD: "spit_ice",
	Requests.STORED_EGG: "egg_made",
}
## Object fields that derivation reads, by placement code.
const ENTITY_FIELDS := {
	"o7": ["mode", "bounces"],
	"o8": ["phase", "status", "content"],
	"o9": ["busy"],
	"o11": ["squash"],
	"o31": ["opened"],
}
const OBJECT_EVENTS := [
	"egg_bounce", "cloud_reveal", "cloud_hit", "cloud_release", "egg_block", "spring", "gate_open"
]
const EGG_THROWN := 1
const CACHE_HIDDEN := 0
const CACHE_REVEALED := 2
const CACHE_OPENING := 3
## Saved scalar fields that derivation reads. Missing fields read as their defaults.
const WATCHED := {
	"frame": 0,
	"map_index": 1,
	"life_phase": Life.PLAY,
	"life_ticks": 0,
	"health": 10,
	"health_wait": 0,
	"separated": 0,
	"checkpoint_awards": 0,
	"companion_mode": Life.ATTACHED,
	"coins": 0,
	"redcoins": 0,
	"flowers": 0,
	"invulnerable": 0,
	"vx": 0,
	"vy": 0,
	"on_floor": 0,
	"swimming": 0,
	"boosted_flutter": 0,
	"flutter_remaining": 0,
	"move_pound_delay": 0,
	"move_action": Moves.NORMAL,
	"move_impact": 0,
	"move_eggs": 0,
	"move_aim": 0,
	"move_snow": 0,
	"move_emit_serial": 0,
	"move_emit_kind": 0,
	"move_emit_1_kind": 0,
	"move_emit_2_kind": 0,
	"move_emit_3_kind": 0,
	"switch_ticks": 0,
	"switch_sound_serial": 0,
	"switch_sound_kind": 0,
	"message_stage": 0,
	"message_section": 0,
}

## Cues derived by the last `observe` call; empty after a resynchronization.
var last_cues: Array = []
var _map := AudioMap.new()
var _world: Dictionary = {}
var _targets := {}
var _muted := true
var _music_db := 0.0
var _effects_db := 0.0
var _music: AudioStreamPlayer
var _music_role := ""
var _music_track := ""
var _voices: Array[AudioStreamPlayer] = []
var _voice_events: Array[String] = []
var _voice_order: Array[int] = []
var _order := 0
var _previous: Dictionary = {}
var _source: Dictionary = {}


static func create(
	audio_map: AudioMap, world: Dictionary, settings: Dictionary, muted: bool
) -> Node:
	var player: Node = load("res://src/view/audio_player.gd").new()
	player.name = "AudioPlayer"
	player.setup(audio_map, world, settings, muted)
	return player


func setup(audio_map: AudioMap, world: Dictionary, settings: Dictionary, muted: bool) -> void:
	_map = audio_map if audio_map != null else AudioMap.new()
	_world = world
	_targets = {
		"redcoins": int(world.get("redcoins_target", 0)),
		"flowers": int(world.get("flowers_target", 0))
	}
	var music_volume := int(settings.get("music_volume", 80))
	var effects_volume := int(settings.get("effects_volume", 80))
	_music_db = linear_to_db(music_volume / 100.0) if music_volume > 0 else -INF
	_effects_db = linear_to_db(effects_volume / 100.0) if effects_volume > 0 else -INF
	_muted = muted or _map.is_empty()
	if _muted:
		return
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	add_child(_music)
	for index in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "Effect%d" % index
		add_child(voice)
		_voices.append(voice)
		_voice_events.append("")
		_voice_order.append(0)


## Feed the current state once per simulation step. Muted players still derive cues.
func observe(state: Dictionary) -> void:
	var current := summarize(state)
	var continuous: bool = (
		not _previous.is_empty()
		and is_same(state, _source)
		and current.frame > _previous.frame
		and current.frame - _previous.frame <= MAX_STEP_GAP
	)
	last_cues = derive(_previous, current, _targets) if continuous else []
	_previous = current
	_source = state
	if _muted:
		return
	if not continuous:
		_resync(current)
	else:
		for cue: Dictionary in last_cues:
			_apply(cue)
		_update_music(current)
	_set_event_paused("switch_timer", current.message_stage != 0)


static func summarize(state: Dictionary) -> Dictionary:
	var result := {}
	for name: String in WATCHED:
		var value: Variant = state.get(name, WATCHED[name])
		result[name] = int(value) if value is int or value is float else int(WATCHED[name])
	# Object rows by stable token: [code, field values in ENTITY_FIELDS order].
	var objects := {}
	var eggs := 0
	var rows: Variant = state.get("entities", [])
	for entity: Variant in rows if rows is Array else []:
		if not entity is Dictionary or not ENTITY_FIELDS.has(entity.get("code")):
			continue
		var row := [entity.code]
		for field: String in ENTITY_FIELDS[entity.code]:
			var value: Variant = entity.get(field, 0)
			row.append(int(value) if value is int or value is float else 0)
		objects[int(entity.get("token", 0))] = row
		eggs += int(entity.code == "o7")
	result.objects = objects
	result.eggs = eggs
	return result


## Cues for one observed change. Each cue is {"cue": "effect"|"stop_effect", "event"},
## {"cue": "role", "role"}, {"cue": "stop_music"} or {"cue": "stop_all"}.
static func derive(previous: Dictionary, current: Dictionary, targets: Dictionary = {}) -> Array:
	var cues := []
	var p := previous
	var c := current
	var respawned: bool = c.life_phase == Life.FADE_IN and p.life_phase != Life.FADE_IN
	if c.life_phase != p.life_phase:
		match c.life_phase:
			Life.DEAD:
				cues.append({"cue": "stop_all"})
				cues.append({"cue": "role", "role": "death"})
			Life.FADE_OUT:
				if p.life_phase != Life.DEAD:
					cues.append({"cue": "stop_all"})
					cues.append(_effect("quick_death"))
			Life.GOAL:
				cues.append({"cue": "stop_music"})
				cues.append({"cue": "role", "role": "goal"})
			Life.REJOIN:
				cues.append(_effect("rescue"))
			Life.PLAY:
				if p.life_phase == Life.REJOIN:
					cues.append(_effect("rejoin"))
	if respawned or c.life_phase in [Life.DEAD, Life.FADE_OUT, Life.RESPAWN]:
		return cues
	if (
		c.life_phase == Life.CHECKPOINT
		and c.life_ticks == 45
		and (p.life_phase != Life.CHECKPOINT or p.life_ticks != 45)
	):
		cues.append(_effect("checkpoint"))
	_counter_cues(p, c, targets, cues)
	_health_cues(p, c, cues)
	_move_cues(p, c, cues)
	_level_cues(p, c, cues)
	_object_cues(p, c, cues)
	return cues


static func _counter_cues(p: Dictionary, c: Dictionary, targets: Dictionary, cues: Array) -> void:
	if c.coins > p.coins:
		cues.append(_effect("coin"))
	if c.redcoins > p.redcoins:
		var all_red: bool = c.redcoins >= int(targets.get("redcoins", 0))
		cues.append(_effect("all_red_coins" if all_red else "red_coin"))
	if c.flowers > p.flowers:
		cues.append(_effect("flower"))
		if c.flowers >= int(targets.get("flowers", 0)):
			cues.append(_effect("all_flowers"))


static func _health_cues(p: Dictionary, c: Dictionary, cues: Array) -> void:
	if c.invulnerable > p.invulnerable:
		cues.append(_effect("hit"))
	if c.companion_mode == Life.BUBBLE and p.companion_mode != Life.BUBBLE:
		cues.append(_effect("companion_cry"))
	if c.health < p.health and c.separated and p.separated:
		cues.append(_effect("countdown_high" if c.health >= 10 else "countdown_low"))
	if c.health <= p.health:
		return
	if c.life_phase == Life.CHECKPOINT or p.life_phase == Life.CHECKPOINT:
		if c.checkpoint_awards > 0:
			cues.append(_effect("star"))
	elif not p.separated and p.health < 10 and p.health_wait == 1:
		if c.health == 10:
			cues.append(_effect("countdown_full"))
	else:
		cues.append(_effect("star"))


static func _move_cues(p: Dictionary, c: Dictionary, cues: Array) -> void:
	var switched: bool = c.switch_sound_serial != p.switch_sound_serial
	var launched: bool = switched or c.invulnerable > p.invulnerable or _sprung(p, c)
	var rising: bool = c.vy < 0 and p.vy >= 0 and not launched
	var pounding: bool = c.move_action in [Moves.POUND_START, Moves.POUND_FALL, Moves.POUND_LAND]
	if rising and c.boosted_flutter:
		cues.append(_effect("stomp"))
	elif rising and c.move_pound_delay == 6 and not pounding:
		cues.append(_effect("jump"))
	if c.flutter_remaining > 0 and p.flutter_remaining == 0:
		cues.append(_effect("flutter"))
	if c.move_action != p.move_action:
		match c.move_action:
			Moves.POUND_START:
				cues.append(_effect("pound_start"))
			Moves.TONGUE:
				cues.append(_effect("tongue"))
			Moves.TOSS:
				cues.append(_effect("egg_throw"))
			Moves.HEAD_BUMP:
				cues.append(_effect("head_bump"))
	if c.move_impact != p.move_impact:
		cues.append(_effect("pound_land"))
	var made_egg := false
	var fresh: int = c.move_emit_serial - p.move_emit_serial
	if fresh > 0:
		for slot in mini(fresh, Requests.CAPACITY):
			var kind: int = c.move_emit_kind if slot == 0 else c["move_emit_%d_kind" % slot]
			made_egg = made_egg or kind == Requests.STORED_EGG
			if REQUEST_EVENTS.has(kind):
				cues.append(_effect(REQUEST_EVENTS[kind]))
	if c.move_eggs > p.move_eggs and not made_egg:
		cues.append(_effect("egg_pickup"))
	if c.swimming != p.swimming:
		cues.append(_effect("splash"))
	if c.move_aim and _crossed(p.frame, c.frame, AIM_TICK_FRAMES):
		cues.append(_effect("aim_tick"))
	if c.move_snow and c.on_floor and c.vx != 0 and _crossed(p.frame, c.frame, SNOW_STEP_FRAMES):
		cues.append(_effect("snow_step"))


static func _level_cues(p: Dictionary, c: Dictionary, cues: Array) -> void:
	if c.switch_sound_serial > p.switch_sound_serial:
		match c.switch_sound_kind:
			1:
				cues.append(_effect("switch_press"))
			2:
				cues.append(_effect("switch_timer"))
			3:
				cues.append({"cue": "stop_effect", "event": "switch_timer"})
	if c.message_stage != p.message_stage:
		match [p.message_stage, c.message_stage]:
			[0, 1]:
				cues.append(_effect("message_hit"))
			[1, 2]:
				cues.append(_effect("message_open"))
			[2, 3]:
				cues.append(_effect("message_close"))
	elif c.message_stage == 2 and c.message_section != p.message_section:
		cues.append(_effect("message_scroll"))


static func _sprung(p: Dictionary, c: Dictionary) -> bool:
	var before: Dictionary = p.get("objects", {})
	var after: Dictionary = c.get("objects", {})
	for token: int in after:
		var was: Array = before.get(token, [])
		if after[token][0] == "o11" and was.size() == 2 and was[0] == "o11":
			if after[token][1] > was[1]:
				return true
	return false


static func _object_cues(p: Dictionary, c: Dictionary, cues: Array) -> void:
	var before: Dictionary = p.get("objects", {})
	var after: Dictionary = c.get("objects", {})
	var found := {}
	for token: int in after:
		var now: Array = after[token]
		var was: Array = before.get(token, [])
		if was.is_empty() or was[0] != now[0]:
			continue
		match now[0]:
			"o7":
				if now[1] == EGG_THROWN and now[2] < was[2]:
					found.egg_bounce = true
			"o8":
				if was[1] == CACHE_HIDDEN and now[1] == CACHE_REVEALED:
					found.cloud_reveal = true
				elif was[1] != CACHE_OPENING and now[1] == CACHE_OPENING:
					found.cloud_hit = true
				elif was[1] == CACHE_OPENING and was[2] != 3 and now[2] == 3 and now[3] in [1, 2]:
					found.cloud_release = true
			"o9":
				if was[1] == 7 and now[1] == 6 and c.get("eggs", 0) > p.get("eggs", 0):
					found.egg_block = true
			"o11":
				if now[1] > was[1]:
					found.spring = true
			"o31":
				if now[1] and not was[1]:
					found.gate_open = true
	for event: String in OBJECT_EVENTS:
		if found.has(event):
			cues.append(_effect(event))
			if event == "egg_bounce":
				cues.append(_effect("egg_ricochet"))


## The looping level track for the selected map: {"key", "loop_start", "volume_db"},
## or an empty dictionary when the level asks for silence or for remote music.
static func level_track(world: Dictionary, map_index: int, audio_map: AudioMap) -> Dictionary:
	var maps: Dictionary = world.get("maps", {})
	var map: Dictionary = maps.get(map_index, world)
	var music: Variant = map.get("music", world.get("music", {}))
	if not music is Dictionary:
		return {}
	var key := str(music.get("id", ""))
	if key.is_empty() or not audio_map.music.has(key):
		return {}
	var settings := audio_map.settings_for(key)
	var result := {"key": key, "loop_start": settings.loop_start, "volume_db": settings.volume_db}
	if music.get("custom", false):
		# Custom selections carry "loop_start_seconds,volume_db" from the level code.
		var parts := str(music.get("settings", "0,0")).split(",")
		result.loop_start = maxf(0.0, _number(parts[0] if parts.size() > 0 else ""))
		result.volume_db = clampf(_number(parts[1] if parts.size() > 1 else ""), -60.0, 24.0)
	return result


static func _number(text: String) -> float:
	var value := text.strip_edges()
	return float(value) if value.is_valid_float() else 0.0


static func _effect(event: String) -> Dictionary:
	return {"cue": "effect", "event": event}


static func _crossed(from_frame: int, to_frame: int, period: int) -> bool:
	return floori(to_frame / float(period)) > floori(from_frame / float(period))


func _resync(current: Dictionary) -> void:
	for index in _voices.size():
		_voices[index].stop()
		_voice_events[index] = ""
	# A one-shot role belongs to the old timeline. The same level track keeps playing.
	if not _music_role.is_empty():
		_music.stop()
		_music_role = ""
		_music_track = ""
	_update_music(current)
	if current.switch_ticks > 0 and current.life_phase not in QUIET_PHASES:
		_play_effect("switch_timer", (SWITCH_TICKS - current.switch_ticks) / 60.0)


func _update_music(current: Dictionary) -> void:
	if current.life_phase in QUIET_PHASES:
		if not _music_role.is_empty() or _music_track.is_empty():
			return
		_music.stop()
		_music_track = ""
		return
	var track := level_track(_world, current.map_index, _map)
	var key: String = track.get("key", "")
	if key == _music_track and _music_role.is_empty():
		return
	_music.stop()
	_music_role = ""
	_music_track = key
	if key.is_empty() or _music_db == -INF:
		return
	var stream := _map.stream("music", key)
	if stream == null:
		return
	_set_loop(stream, true, track.loop_start)
	_music.stream = stream
	_music.volume_db = _music_db + track.volume_db
	_music.play()
	print("EGGSHELL_MUSIC ", key)


func _apply(cue: Dictionary) -> void:
	match cue.cue:
		"effect":
			_play_effect(cue.event)
		"stop_effect":
			for index in _voices.size():
				if _voice_events[index] == cue.event:
					_voices[index].stop()
					_voice_events[index] = ""
		"stop_all":
			for index in _voices.size():
				_voices[index].stop()
				_voice_events[index] = ""
			_music.stop()
			_music_track = ""
			_music_role = ""
		"stop_music":
			_music.stop()
			_music_track = ""
			_music_role = ""
		"role":
			_play_role(cue.role)


func _play_role(role: String) -> void:
	_music.stop()
	_music_track = ""
	_music_role = role
	var key := _map.track_key(role)
	var stream := _map.stream("music", key)
	if stream == null or _music_db == -INF:
		return
	_set_loop(stream, false, 0.0)
	_music.stream = stream
	_music.volume_db = _music_db + _map.settings_for(key).volume_db
	_music.play()
	print("EGGSHELL_MUSIC ", key)


func _play_effect(event: String, from_position := 0.0) -> void:
	if _effects_db == -INF:
		return
	var stream := _map.stream("effects", _map.effect_key(event, int(_previous.get("frame", 0))))
	if stream == null:
		return
	var chosen := _voice_events.find(event)
	if chosen < 0:
		for index in _voices.size():
			if not _voices[index].playing:
				chosen = index
				break
	if chosen < 0:
		# Steal the oldest voice, but keep the long switch timer sound.
		for index in _voices.size():
			if _voice_events[index] in HELD_EVENTS:
				continue
			if chosen < 0 or _voice_order[index] < _voice_order[chosen]:
				chosen = index
	_order += 1
	var voice := _voices[chosen]
	voice.stop()
	voice.stream_paused = false
	if stream is AudioStreamOggVorbis:
		_set_loop(stream, false, 0.0)
	voice.stream = stream
	voice.volume_db = _effects_db
	voice.play(from_position)
	_voice_events[chosen] = event
	_voice_order[chosen] = _order


func _set_event_paused(event: String, paused: bool) -> void:
	for index in _voices.size():
		if _voice_events[index] == event:
			_voices[index].stream_paused = paused


static func _set_loop(stream: AudioStream, loop: bool, loop_start: float) -> void:
	if stream is AudioStreamOggVorbis:
		stream.loop = loop
		stream.loop_offset = loop_start if loop else 0.0
