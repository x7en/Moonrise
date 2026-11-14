class_name SpriteFactory
extends RefCounted
## Cached textures, SpriteFrames built from horizontal strips, and safe placeholders.

static var _tex_cache: Dictionary = {}
static var _frames_cache: Dictionary = {}
static var _silhouette_cache: Dictionary = {}


static func tex(key: String) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D

	var res_path: String = SpriteData.path(key)
	var loaded: Texture2D = null
	if ResourceLoader.exists(res_path):
		loaded = load(res_path) as Texture2D

	if loaded == null:
		loaded = _make_placeholder(key)

	_tex_cache[key] = loaded
	return loaded


static func get_image_rgba8(key: String) -> Image:
	var t: Texture2D = tex(key)
	var img: Image = t.get_image()
	if img == null:
		img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.8, 0.2, 0.7, 1.0))
		return img
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


static func get_tinted_silhouette(key: String, fill_color: Color) -> Texture2D:
	var cache_key: String = "%s|%s" % [key, fill_color.to_html()]
	if _silhouette_cache.has(cache_key):
		return _silhouette_cache[cache_key] as Texture2D

	var src: Image = get_image_rgba8(key)
	var w: int = src.get_width()
	var h: int = src.get_height()
	var out: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var px: Color = src.get_pixel(x, y)
			if px.a > 0.01:
				out.set_pixel(x, y, Color(fill_color.r, fill_color.g, fill_color.b, px.a * fill_color.a))
			else:
				out.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))

	var result: ImageTexture = ImageTexture.create_from_image(out)
	_silhouette_cache[cache_key] = result
	return result


static func make_static_sprite(key: String, feet_origin: bool = true) -> Sprite2D:
	var spr: Sprite2D = Sprite2D.new()
	var t: Texture2D = tex(key)
	spr.texture = t
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if feet_origin:
		var dims: Array = SpriteData.STATIC.get(key, [t.get_width(), t.get_height()])
		var w: int = int(dims[0])
		var h: int = int(dims[1])
		spr.offset = Vector2(-floorf(float(w) * 0.5), -float(h))
	return spr


static func feet_offset_for_animated(key: String, x_shift: float = 0.0) -> Vector2:
	var info: Array = SpriteData.ANIMATED.get(key, [1, 16, 16])
	var fw: float = float(info[1])
	var fh: float = float(info[2])
	return Vector2(-floorf(fw * 0.5) + x_shift, -fh)


static func get_player_frames(swing_time: float = 0.3) -> SpriteFrames:
	if _frames_cache.has("player"):
		return _frames_cache["player"] as SpriteFrames

	var sf: SpriteFrames = SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")

	var dirs: Array[String] = ["down", "up", "left", "right"]
	for d in dirs:
		_add_strip_animation(sf, "idle_" + d, "player/idle_" + d, 6.0, true)
		_add_strip_animation(sf, "run_" + d, "player/run_" + d, 10.0, true)
		var punch_key: String = "player/punch_" + d
		var punch_info: Array = SpriteData.ANIMATED.get(punch_key, [4, 16, 16])
		var punch_fps: float = float(punch_info[0]) / maxf(swing_time, 0.05)
		_add_strip_animation(sf, "punch_" + d, punch_key, punch_fps, false)

	_add_strip_animation(sf, "death_left", "player/death_left", 10.0, false)
	_add_strip_animation(sf, "death_right", "player/death_right", 10.0, false)

	_frames_cache["player"] = sf
	return sf


static func get_enemy_frames(enemy_type: String) -> SpriteFrames:
	var cache_key: String = "enemy_" + enemy_type
	if _frames_cache.has(cache_key):
		return _frames_cache[cache_key] as SpriteFrames

	var sf: SpriteFrames = SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")

	var walk_fps: float = 8.0 if enemy_type == "zombie" else 10.0
	if enemy_type == "brute":
		walk_fps = 8.0

	var dirs: Array[String] = ["down", "up", "left", "right"]
	for d in dirs:
		_add_strip_animation(sf, "walk_" + d, "enemies/%s/walk_%s" % [enemy_type, d], walk_fps, true)
		var atk_key: String = "enemies/%s/attack_%s" % [enemy_type, d]
		var atk_info: Array = SpriteData.ANIMATED.get(atk_key, [4, 16, 16])
		var atk_fps: float = float(atk_info[0]) / 0.3
		_add_strip_animation(sf, "attack_" + d, atk_key, atk_fps, false)

	_add_strip_animation(sf, "death_left", "enemies/%s/death_left" % enemy_type, 10.0, false)
	_add_strip_animation(sf, "death_right", "enemies/%s/death_right" % enemy_type, 10.0, false)

	_frames_cache[cache_key] = sf
	return sf


static func _add_strip_animation(
	sf: SpriteFrames,
	anim_name: String,
	key: String,
	fps: float,
	should_loop: bool
) -> void:
	var info: Array = SpriteData.ANIMATED.get(key, [1, 16, 16])
	var frame_count: int = maxi(1, int(info[0]))
	var fw: int = maxi(1, int(info[1]))
	var fh: int = maxi(1, int(info[2]))
	var strip: Texture2D = tex(key)

	if sf.has_animation(anim_name):
		sf.remove_animation(anim_name)
	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, fps)
	sf.set_animation_loop(anim_name, should_loop)

	var strip_w: int = strip.get_width()
	var strip_h: int = strip.get_height()
	for i in range(frame_count):
		if strip_w >= (i + 1) * fw and strip_h >= fh:
			var atlas_tex: AtlasTexture = AtlasTexture.new()
			atlas_tex.atlas = strip
			atlas_tex.region = Rect2(float(i * fw), 0.0, float(fw), float(fh))
			sf.add_frame(anim_name, atlas_tex)
		else:
			sf.add_frame(anim_name, strip)


static func _make_placeholder(key: String) -> ImageTexture:
	var w: int = 16
	var h: int = 16
	if SpriteData.STATIC.has(key):
		var dims: Array = SpriteData.STATIC[key]
		w = maxi(2, int(dims[0]))
		h = maxi(2, int(dims[1]))
	elif SpriteData.ANIMATED.has(key):
		var anim_dims: Array = SpriteData.ANIMATED[key]
		w = maxi(2, int(anim_dims[1]))
		h = maxi(2, int(anim_dims[2]))

	var hv: int = key.hash() & 0x7FFFFFFF
	var r: float = 0.35 + float(hv % 50) / 100.0
	var g: float = 0.25 + float((hv >> 3) % 50) / 100.0
	var b: float = 0.35 + float((hv >> 6) % 50) / 100.0
	var fill: Color = Color(r, g, b, 1.0)
	var border: Color = Color(r * 0.45, g * 0.45, b * 0.45, 1.0)

	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	for x in range(w):
		img.set_pixel(x, 0, border)
		img.set_pixel(x, h - 1, border)
	for y in range(h):
		img.set_pixel(0, y, border)
		img.set_pixel(w - 1, y, border)
	return ImageTexture.create_from_image(img)
