class_name SpriteFactory
extends RefCounted
## Builds and caches textures, SpriteFrames, procedural pixel art (spear & moon), and the UI Theme.

static var _tex_cache: Dictionary = {}
static var _frames_cache: Dictionary = {}
static var _silhouette_cache: Dictionary = {}
static var _theme_cache: Theme = null
static var _spear_tex: ImageTexture = null
static var _moon_tex_cache: Dictionary = {}


## Loads a PNG sprite from res://assets/ and caches it so we never reload from disk twice.
static func tex(key: String) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D

	var res_path: String = SpriteData.path(key)
	var loaded: Texture2D = null
	if ResourceLoader.exists(res_path):
		loaded = load(res_path) as Texture2D

	# If a file is missing, generate a colored box placeholder so the game still runs.
	if loaded == null:
		loaded = _make_placeholder(key)

	_tex_cache[key] = loaded
	return loaded


## Returns an uncompressed RGBA8 Image copy so blit_rect never fails on format mismatches.
static func get_image_rgba8(key: String) -> Image:
	var loaded_tex: Texture2D = tex(key)
	var img: Image = loaded_tex.get_image()
	if img == null:
		img = Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.8, 0.2, 0.7, 1.0))
		return img

	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## Creates a solid-color silhouette matching the exact alpha pixels of a sprite.
## Used for the house's dark-red damage overlay so it never draws a box over the roof corners.
static func get_tinted_silhouette(key: String, fill_color: Color) -> Texture2D:
	var cache_key: String = "%s|%s" % [key, fill_color.to_html()]
	if _silhouette_cache.has(cache_key):
		return _silhouette_cache[cache_key] as Texture2D

	var src: Image = get_image_rgba8(key)
	var width: int = src.get_width()
	var height: int = src.get_height()
	var out: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)

	for y in range(height):
		for x in range(width):
			var pixel: Color = src.get_pixel(x, y)
			if pixel.a > 0.01:
				var tinted: Color = Color(
					fill_color.r,
					fill_color.g,
					fill_color.b,
					pixel.a * fill_color.a
				)
				out.set_pixel(x, y, tinted)
			else:
				out.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))

	var result: ImageTexture = ImageTexture.create_from_image(out)
	_silhouette_cache[cache_key] = result
	return result


## Builds a crisp nearest-neighbor Sprite2D with its feet aligned to the node origin.
static func make_static_sprite(key: String, feet_origin: bool = true) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	var loaded_tex: Texture2D = tex(key)
	sprite.texture = loaded_tex
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if feet_origin:
		var dims: Array = SpriteData.STATIC.get(
			key,
			[loaded_tex.get_width(), loaded_tex.get_height()]
		)
		var width: int = int(dims[0])
		var height: int = int(dims[1])
		sprite.offset = Vector2(-floorf(float(width) * 0.5), -float(height))

	return sprite


## Computes the feet-origin offset for an animated strip frame so characters never float or jump.
static func feet_offset_for_animated(key: String, x_shift: float = 0.0) -> Vector2:
	var info: Array = SpriteData.ANIMATED.get(key, [1, 16, 16])
	var frame_w: float = float(info[1])
	var frame_h: float = float(info[2])
	return Vector2(-floorf(frame_w * 0.5) + x_shift, -frame_h)


## Builds and caches all player animations (idle, run, attack, death) from horizontal strips.
static func get_player_frames(swing_time: float = 0.3) -> SpriteFrames:
	if _frames_cache.has("player"):
		return _frames_cache["player"] as SpriteFrames

	var frames: SpriteFrames = SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	var directions: Array[String] = ["down", "up", "left", "right"]
	for dir_name in directions:
		_add_strip_animation(frames, "idle_" + dir_name, "player/idle_" + dir_name, 6.0, true)
		_add_strip_animation(frames, "run_" + dir_name, "player/run_" + dir_name, 10.0, true)

		var punch_key: String = "player/punch_" + dir_name
		var punch_info: Array = SpriteData.ANIMATED.get(punch_key, [4, 16, 16])
		var punch_fps: float = float(punch_info[0]) / maxf(swing_time, 0.05)
		_add_strip_animation(frames, "punch_" + dir_name, punch_key, punch_fps, false)

	_add_strip_animation(frames, "death_left", "player/death_left", 10.0, false)
	_add_strip_animation(frames, "death_right", "player/death_right", 10.0, false)

	_frames_cache["player"] = frames
	return frames


## Builds and caches all animations for a given enemy type ("zombie", "raider", or "brute").
static func get_enemy_frames(enemy_type: String) -> SpriteFrames:
	var cache_key: String = "enemy_" + enemy_type
	if _frames_cache.has(cache_key):
		return _frames_cache[cache_key] as SpriteFrames

	var frames: SpriteFrames = SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	var walk_fps: float = 8.0
	if enemy_type == "raider":
		walk_fps = 10.0

	var directions: Array[String] = ["down", "up", "left", "right"]
	for dir_name in directions:
		var walk_key: String = "enemies/%s/walk_%s" % [enemy_type, dir_name]
		_add_strip_animation(frames, "walk_" + dir_name, walk_key, walk_fps, true)

		var attack_key: String = "enemies/%s/attack_%s" % [enemy_type, dir_name]
		var attack_info: Array = SpriteData.ANIMATED.get(attack_key, [4, 16, 16])
		var attack_fps: float = float(attack_info[0]) / 0.3
		_add_strip_animation(frames, "attack_" + dir_name, attack_key, attack_fps, false)

	var death_left_key: String = "enemies/%s/death_left" % enemy_type
	var death_right_key: String = "enemies/%s/death_right" % enemy_type
	_add_strip_animation(frames, "death_left", death_left_key, 10.0, false)
	_add_strip_animation(frames, "death_right", death_right_key, 10.0, false)

	_frames_cache[cache_key] = frames
	return frames


## Draws a crisp 26x7 pixel-art spear pointing right (wooden shaft, red wrap, steel tip).
## Drawn in code so the player has a readable melee weapon without needing extra PNG files.
static func get_spear_texture() -> ImageTexture:
	if _spear_tex != null:
		return _spear_tex

	var img: Image = Image.create_empty(26, 7, false, Image.FORMAT_RGBA8)
	var outline: Color = Color(0.12, 0.08, 0.08, 1.0)
	var wood_dark: Color = Color(0.45, 0.28, 0.16, 1.0)
	var wood_light: Color = Color(0.64, 0.42, 0.24, 1.0)
	var wrap_red: Color = Color(0.78, 0.2, 0.2, 1.0)
	var steel_dark: Color = Color(0.58, 0.64, 0.72, 1.0)
	var steel_bright: Color = Color(0.92, 0.96, 1.0, 1.0)

	# Draw the wooden shaft from x = 0 to x = 16 along the center row (y = 3).
	for x in range(1, 17):
		img.set_pixel(x, 2, outline)
		img.set_pixel(x, 4, outline)
		img.set_pixel(x, 3, wood_light if x % 3 != 0 else wood_dark)
	img.set_pixel(0, 3, outline)

	# Draw a red cloth binding right behind the blade so the spear pops against dark nights.
	for x in range(16, 19):
		img.set_pixel(x, 2, outline)
		img.set_pixel(x, 3, wrap_red)
		img.set_pixel(x, 4, outline)

	# Draw the pointed steel spearhead from x = 19 to x = 25.
	for x in range(19, 25):
		img.set_pixel(x, 3, steel_bright)
	img.set_pixel(19, 1, outline)
	img.set_pixel(20, 1, outline)
	img.set_pixel(21, 1, outline)
	img.set_pixel(19, 2, steel_bright)
	img.set_pixel(20, 2, steel_bright)
	img.set_pixel(21, 2, steel_dark)
	img.set_pixel(22, 2, outline)
	img.set_pixel(23, 2, outline)
	img.set_pixel(19, 4, steel_dark)
	img.set_pixel(20, 4, steel_dark)
	img.set_pixel(21, 4, steel_dark)
	img.set_pixel(22, 4, outline)
	img.set_pixel(23, 4, outline)
	img.set_pixel(19, 5, outline)
	img.set_pixel(20, 5, outline)
	img.set_pixel(21, 5, outline)
	img.set_pixel(25, 3, outline)

	_spear_tex = ImageTexture.create_from_image(img)
	return _spear_tex


## Draws a pixel-art moon disc (pale silver on normal nights, glowing crimson on Blood Moons).
static func get_moon_texture(diameter: int, is_blood_moon: bool) -> ImageTexture:
	var cache_key: String = "%d|%s" % [diameter, "blood" if is_blood_moon else "pale"]
	if _moon_tex_cache.has(cache_key):
		return _moon_tex_cache[cache_key] as ImageTexture

	var img: Image = Image.create_empty(diameter, diameter, false, Image.FORMAT_RGBA8)
	var radius: float = float(diameter) * 0.5 - 1.5
	var center: Vector2 = Vector2(float(diameter) * 0.5, float(diameter) * 0.5)

	# Pick bright/dark palette colors based on whether the Blood Moon has risen.
	var base_col: Color = Color(0.92, 0.94, 0.98, 1.0)
	var crater_col: Color = Color(0.72, 0.76, 0.84, 1.0)
	var rim_col: Color = Color(0.35, 0.42, 0.58, 0.75)
	if is_blood_moon:
		base_col = Color(0.94, 0.18, 0.18, 1.0)
		crater_col = Color(0.64, 0.08, 0.1, 1.0)
		rim_col = Color(0.45, 0.04, 0.06, 0.85)

	# Three small decorative craters so the moon looks textured rather than flat.
	var crater_a: Vector2 = center + Vector2(-radius * 0.32, -radius * 0.18)
	var crater_b: Vector2 = center + Vector2(radius * 0.28, radius * 0.24)
	var crater_c: Vector2 = center + Vector2(-radius * 0.1, radius * 0.38)

	for y in range(diameter):
		for x in range(diameter):
			var sample_pos: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			var dist: float = sample_pos.distance_to(center)
			if dist <= radius:
				var shade: float = clampf(1.0 - (dist / maxf(radius, 1.0)) * 0.25, 0.65, 1.0)
				var is_crater: bool = (
					sample_pos.distance_to(crater_a) <= radius * 0.22
					or sample_pos.distance_to(crater_b) <= radius * 0.18
					or sample_pos.distance_to(crater_c) <= radius * 0.13
				)
				var chosen: Color = crater_col if is_crater else base_col
				var shaded: Color = Color(
					chosen.r * shade,
					chosen.g * shade,
					chosen.b * shade,
					1.0
				)
				img.set_pixel(x, y, shaded)
			elif dist <= radius + 1.2:
				img.set_pixel(x, y, rim_col)
			else:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))

	var result: ImageTexture = ImageTexture.create_from_image(img)
	_moon_tex_cache[cache_key] = result
	return result


## Builds one shared UI Theme that applies the user's retro pixel .ttf font to all UI controls.
## Falls back cleanly to Godot's built-in font if the .ttf has not been placed yet.
static func get_game_theme(primary_font_path: String) -> Theme:
	if _theme_cache != null:
		return _theme_cache

	var theme: Theme = Theme.new()
	theme.default_font_size = 8

	# Check the configured font path first, then common pixel font filenames in assets/fonts/.
	var candidate_paths: Array[String] = [
		primary_font_path,
		"res://assets/fonts/KiwiSoda.ttf",
		"res://assets/fonts/dogicapixel.ttf",
		"res://assets/fonts/PixelDogica.ttf",
	]
	var loaded_font: Font = null
	for path in candidate_paths:
		if not path.is_empty() and ResourceLoader.exists(path):
			loaded_font = load(path) as Font
			if loaded_font != null:
				break

	if loaded_font != null:
		if loaded_font is FontFile:
			var font_file: FontFile = loaded_font as FontFile
			# Disable smoothing so pixel fonts stay razor sharp at 480x270.
			font_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			font_file.hinting = TextServer.HINTING_NONE
		theme.default_font = loaded_font

	# Give Labels a crisp 1-pixel drop shadow by default so text reads over bright or dark ground.
	theme.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.92))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	# Style Buttons cleanly for the Pause Menu and Lose Screen.
	theme.set_font_size("font_size", "Button", 8)
	theme.set_color("font_color", "Button", Color(0.95, 0.95, 0.95))
	theme.set_color("font_hover_color", "Button", Color(1.0, 0.92, 0.58))
	theme.set_color("font_pressed_color", "Button", Color(1.0, 0.75, 0.45))
	theme.set_stylebox(
		"normal",
		"Button",
		_make_button_box(Color(0.12, 0.1, 0.14, 0.95), Color(0.42, 0.34, 0.38))
	)
	theme.set_stylebox(
		"hover",
		"Button",
		_make_button_box(Color(0.22, 0.15, 0.18, 0.98), Color(0.9, 0.35, 0.32))
	)
	theme.set_stylebox(
		"pressed",
		"Button",
		_make_button_box(Color(0.3, 0.12, 0.14, 1.0), Color(1.0, 0.5, 0.42))
	)
	theme.set_stylebox(
		"focus",
		"Button",
		_make_button_box(Color(0.2, 0.14, 0.18, 0.98), Color(0.95, 0.42, 0.36))
	)

	_theme_cache = theme
	return _theme_cache


## Helper to build a crisp pixel-bordered StyleBoxFlat for menu buttons.
static func _make_button_box(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_color = border_color
	box.set_border_width_all(1)
	box.content_margin_left = 6.0
	box.content_margin_right = 6.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	return box


## Slices a horizontal PNG strip into individual AtlasTexture frames for a SpriteFrames resource.
static func _add_strip_animation(
	frames: SpriteFrames,
	anim_name: String,
	key: String,
	fps: float,
	should_loop: bool
) -> void:
	var info: Array = SpriteData.ANIMATED.get(key, [1, 16, 16])
	var frame_count: int = maxi(1, int(info[0]))
	var frame_w: int = maxi(1, int(info[1]))
	var frame_h: int = maxi(1, int(info[2]))
	var strip: Texture2D = tex(key)

	if frames.has_animation(anim_name):
		frames.remove_animation(anim_name)
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, should_loop)

	var strip_w: int = strip.get_width()
	var strip_h: int = strip.get_height()
	for i in range(frame_count):
		if strip_w >= (i + 1) * frame_w and strip_h >= frame_h:
			var atlas_tex: AtlasTexture = AtlasTexture.new()
			atlas_tex.atlas = strip
			atlas_tex.region = Rect2(float(i * frame_w), 0.0, float(frame_w), float(frame_h))
			frames.add_frame(anim_name, atlas_tex)
		else:
			frames.add_frame(anim_name, strip)


## Builds a deterministic colored rectangle fallback when an asset file is missing.
static func _make_placeholder(key: String) -> ImageTexture:
	var width: int = 16
	var height: int = 16
	if SpriteData.STATIC.has(key):
		var dims: Array = SpriteData.STATIC[key]
		width = maxi(2, int(dims[0]))
		height = maxi(2, int(dims[1]))
	elif SpriteData.ANIMATED.has(key):
		var anim_dims: Array = SpriteData.ANIMATED[key]
		width = maxi(2, int(anim_dims[1]))
		height = maxi(2, int(anim_dims[2]))

	var hash_val: int = key.hash() & 0x7FFFFFFF
	var red: float = 0.35 + float(hash_val % 50) / 100.0
	var green: float = 0.25 + float((hash_val >> 3) % 50) / 100.0
	var blue: float = 0.35 + float((hash_val >> 6) % 50) / 100.0
	var fill: Color = Color(red, green, blue, 1.0)
	var border: Color = Color(red * 0.45, green * 0.45, blue * 0.45, 1.0)

	var img: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	for x in range(width):
		img.set_pixel(x, 0, border)
		img.set_pixel(x, height - 1, border)
	for y in range(height):
		img.set_pixel(0, y, border)
		img.set_pixel(width - 1, y, border)
	return ImageTexture.create_from_image(img)
