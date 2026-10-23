extends Node2D
## Fixed workload: 2,000 Sprite2D nodes, four generated 32px frames, all on screen.

const SPRITE_COUNT: int = 2000
const SPRITE_SIZE: int = 32
const FIELD := Vector2(640.0, 480.0)
const WARMUP_SECONDS: float = 2.0
const PALETTE: Array[Color] = [Color("57b8a8"), Color("edcc70"), Color("d78083"), Color("8c9de2")]

var _sprites: Array[Sprite2D] = []
var _origins := PackedVector2Array()
var _elapsed: float = 0.0
var _duration: float = 60.0
var _previous_frame: int = -1
var _start_usec: int = 0


func _ready() -> void:
	get_window().content_scale_size = Vector2i(640, 480)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bench-seconds="):
			_duration = maxf(0.1, argument.trim_prefix("--bench-seconds=").to_float())
	var image := Image.create(SPRITE_SIZE * 4, SPRITE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for frame: int in range(4):
		image.fill_rect(Rect2i(frame * SPRITE_SIZE + 2, 2, 28, 28), PALETTE[frame])
		image.fill_rect(Rect2i(frame * SPRITE_SIZE + 6 + frame * 3, 8, 5, 5), Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	for index: int in range(SPRITE_COUNT):
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.hframes = 4
		sprite.frame = index % 4
		# Co-prime strides distribute all 2,000 sprites deterministically.
		var origin := Vector2(float((index * 73) % 640), float((index * 131) % 480))
		sprite.position = origin
		_origins.append(origin)
		_sprites.append(sprite)
		add_child(sprite)
	_start_usec = Time.get_ticks_usec()
	print("EGGSHELL_BENCH sprites=2000 size=32 viewport=640x480 warmup=2 seconds=%s" % _duration)


func _process(_delta: float) -> void:
	_elapsed = float(Time.get_ticks_usec() - _start_usec) / 1_000_000.0
	var animation_frame: int = int(_elapsed * 8.0) % 4
	var change_frame: bool = animation_frame != _previous_frame
	_previous_frame = animation_frame
	for index: int in range(SPRITE_COUNT):
		var origin: Vector2 = _origins[index]
		_sprites[index].position = Vector2(
			fposmod(origin.x - _elapsed * 60.0, FIELD.x),
			fposmod(origin.y + _elapsed * 15.0, FIELD.y)
		)
		if change_frame:
			_sprites[index].frame = (animation_frame + index) % 4
	if _elapsed >= _duration + WARMUP_SECONDS:
		get_tree().quit()
