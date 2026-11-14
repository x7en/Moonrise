class_name SpriteFactory
extends RefCounted
## Central asset/texture/font factory: cached sprites, SpriteFrames, 3-font retro UI theme,
## 3D-shaded farmhouse variants, 2D light gradients, and crisp procedural pixel icons.

static var _tex_cache: Dictionary = {}
static var _frames_cache: Dictionary = {}
static var _silhouette_cache: Dictionary = {}
static var _house_cache: Dictionary = {}
static var _icon_cache: Dictionary = {}
static var _theme_cache: Theme = null
static var _font_body_cache: Font = null
static var _font_bold_cache: Font = null
static var _font_display_cache: Font = null
static var _light_tex_cache: Dictionary = {}
static var _blob_cache: Dictionary = {}


## Loads a PNG sprite from res://assets/ and caches it so we never reload from disk twice.
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
				out.set_pixel(
					x,
					y,
					Color(fill_color.r, fill_color.g, fill_color.b, pixel.a * fill_color.a)
				)
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
			key, [loaded_tex.get_width(), loaded_tex.get_height()]
		)
		sprite.offset = Vector2(-floorf(float(int(dims[0])) * 0.5), -float(int(dims[1])))
	return sprite


static func feet_offset_for_animated(key: String, x_shift: float = 0.0) -> Vector2:
	var info: Array = SpriteData.ANIMATED.get(key, [1, 16, 16])
	return Vector2(-floorf(float(info[1]) * 0.5) + x_shift, -float(info[2]))


## T0.B: Centralized 3-font retro pixel font accessors (PixelOperator8, Bold, KiwiSoda).
static func font_body() -> Font:
	if _font_body_cache == null:
		_font_body_cache = _load_pixel_font("res://assets/fonts/PixelOperator8.ttf")
	return _font_body_cache


static func font_bold() -> Font:
	if _font_bold_cache == null:
		_font_bold_cache = _load_pixel_font("res://assets/fonts/PixelOperator8-Bold.ttf")
	return _font_bold_cache


static func font_display() -> Font:
	if _font_display_cache == null:
		_font_display_cache = _load_pixel_font("res://assets/fonts/KiwiSoda.ttf")
	return _font_display_cache


static func _load_pixel_font(res_path: String) -> Font:
	if not ResourceLoader.exists(res_path):
		return ThemeDB.fallback_font
	var loaded: Font = load(res_path) as Font
	if loaded == null:
		return ThemeDB.fallback_font
	if loaded is FontFile:
		var ff: FontFile = loaded as FontFile
		ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		ff.hinting = TextServer.HINTING_NONE
		ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		ff.generate_mipmaps = false
	return loaded


## Applies font, integer multiple-of-8 size, nearest filter, and crisp 1px dark outline to a Label.
static func style_label(
	lbl: Label,
	style: String = "body",
	size_px: int = 8,
	color: Color = Color.WHITE
) -> void:
	lbl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var f: Font = font_body()
	if style == "bold":
		f = font_bold()
	elif style == "display":
		f = font_display()
	lbl.add_theme_font_override("font", f)
	lbl.add_theme_font_size_override("font_size", size_px)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.12, 0.95))
	lbl.add_theme_constant_override("outline_size", 1)


## Shared crisp pixel UI Theme using PixelOperator8 (body) and PixelOperator8-Bold (buttons).
static func get_game_theme(_unused_path: String = "") -> Theme:
	if _theme_cache != null:
		return _theme_cache

	var theme: Theme = Theme.new()
	theme.default_font = font_body()
	theme.default_font_size = 8

	theme.set_font("font", "Label", font_body())
	theme.set_font_size("font_size", "Label", 8)
	theme.set_color("font_outline_color", "Label", Color(0.10, 0.07, 0.12, 0.95))
	theme.set_constant("outline_size", "Label", 1)
	theme.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.75))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	theme.set_font("font", "Button", font_bold())
	theme.set_font_size("font_size", "Button", 8)
	theme.set_color("font_color", "Button", Color(0.95, 0.95, 0.95))
	theme.set_color("font_hover_color", "Button", Color(1.0, 0.92, 0.58))
	theme.set_color("font_pressed_color", "Button", Color(1.0, 0.75, 0.45))
	theme.set_color("font_disabled_color", "Button", Color(0.46, 0.42, 0.48))
	theme.set_stylebox(
		"normal",
		"Button",
		_make_button_box(Color(0.12, 0.10, 0.15, 0.96), Color(0.42, 0.34, 0.40))
	)
	theme.set_stylebox(
		"hover",
		"Button",
		_make_button_box(Color(0.22, 0.15, 0.20, 0.98), Color(0.92, 0.36, 0.32))
	)
	theme.set_stylebox(
		"pressed",
		"Button",
		_make_button_box(Color(0.30, 0.12, 0.15, 1.0), Color(1.0, 0.52, 0.42))
	)
	theme.set_stylebox(
		"disabled",
		"Button",
		_make_button_box(Color(0.09, 0.08, 0.11, 0.85), Color(0.26, 0.22, 0.28))
	)
	theme.set_stylebox(
		"focus",
		"Button",
		_make_button_box(Color(0.20, 0.14, 0.19, 0.98), Color(0.95, 0.42, 0.36))
	)

	_theme_cache = theme
	return _theme_cache


static func _make_button_box(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_color = border_color
	box.set_border_width_all(1)
	box.content_margin_left = 6.0
	box.content_margin_right = 6.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	return box


## Builds and caches all player animations (idle, run, attack, death) from horizontal strips.
static func get_player_frames(swing_time: float = 0.3) -> SpriteFrames:
	if _frames_cache.has("player"):
		return _frames_cache["player"] as SpriteFrames

	var frames: SpriteFrames = SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	for dir_name in ["down", "up", "left", "right"]:
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

	var walk_fps: float = 10.0 if enemy_type == "raider" else 8.0
	for dir_name in ["down", "up", "left", "right"]:
		var walk_key: String = "enemies/%s/walk_%s" % [enemy_type, dir_name]
		_add_strip_animation(frames, "walk_" + dir_name, walk_key, walk_fps, true)
		var attack_key: String = "enemies/%s/attack_%s" % [enemy_type, dir_name]
		var attack_info: Array = SpriteData.ANIMATED.get(attack_key, [4, 16, 16])
		var attack_fps: float = float(attack_info[0]) / 0.35
		_add_strip_animation(frames, "attack_" + dir_name, attack_key, attack_fps, false)

	_add_strip_animation(frames, "death_left", "enemies/%s/death_left" % enemy_type, 10.0, false)
	_add_strip_animation(frames, "death_right", "enemies/%s/death_right" % enemy_type, 10.0, false)
	_frames_cache[cache_key] = frames
	return frames


## Returns the 3/4 oblique 2D-with-3D-depth farmhouse sprite (or user custom drop-in PNG).
static func get_shaded_house_texture(level: int = 1, door_open: bool = false) -> Texture2D:
	return HouseArt.get_house_texture(level, door_open)


## Soft radial light texture for PointLight2D windows/door/lantern (GL Compatibility safe).
static func get_radial_light_texture(size_px: int = 128) -> GradientTexture2D:
	if _light_tex_cache.has(size_px):
		return _light_tex_cache[size_px] as GradientTexture2D
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var gt: GradientTexture2D = GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = size_px
	gt.height = size_px
	_light_tex_cache[size_px] = gt
	return gt


## Flat dark elliptical blob shadow for player, enemies, trees, cars, and piles (T1.4).
static func get_blob_shadow(width: int, height: int) -> ImageTexture:
	var key: String = "%dx%d" % [width, height]
	if _blob_cache.has(key):
		return _blob_cache[key] as ImageTexture
	var img: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var rx: float = maxf(1.0, float(width) * 0.5)
	var ry: float = maxf(1.0, float(height) * 0.5)
	for y in range(height):
		for x in range(width):
			var nx: float = (float(x) + 0.5 - rx) / rx
			var ny: float = (float(y) + 0.5 - ry) / ry
			var d: float = nx * nx + ny * ny
			if d <= 0.72:
				img.set_pixel(x, y, Color(0.08, 0.06, 0.11, 0.34))
			elif d <= 1.0 and ((x + y) % 2 == 0):
				img.set_pixel(x, y, Color(0.08, 0.06, 0.11, 0.22))
	var result: ImageTexture = ImageTexture.create_from_image(img)
	_blob_cache[key] = result
	return result


## Draws a crisp 26x7 pixel-art spear pointing right.
static func get_spear_texture() -> ImageTexture:
	if _icon_cache.has("spear"):
		return _icon_cache["spear"] as ImageTexture
	var img: Image = Image.create_empty(26, 7, false, Image.FORMAT_RGBA8)
	var out_c: Color = Color(0.16, 0.12, 0.18, 1.0)
	var wood_l: Color = Color(0.64, 0.42, 0.24, 1.0)
	var wood_d: Color = Color(0.45, 0.28, 0.16, 1.0)
	var wrap_c: Color = Color(0.78, 0.20, 0.20, 1.0)
	var steel_b: Color = Color(0.92, 0.96, 1.0, 1.0)
	var steel_d: Color = Color(0.58, 0.64, 0.72, 1.0)

	for x in range(1, 17):
		img.set_pixel(x, 2, out_c)
		img.set_pixel(x, 4, out_c)
		img.set_pixel(x, 3, wood_l if x % 3 != 0 else wood_d)
	img.set_pixel(0, 3, out_c)
	for x in range(16, 19):
		img.set_pixel(x, 2, out_c)
		img.set_pixel(x, 3, wrap_c)
		img.set_pixel(x, 4, out_c)
	for x in range(19, 25):
		img.set_pixel(x, 3, steel_b)
	for x in [19, 20, 21]:
		img.set_pixel(x, 1, out_c)
		img.set_pixel(x, 5, out_c)
		img.set_pixel(x, 2, steel_b if x < 21 else steel_d)
		img.set_pixel(x, 4, steel_d)
	img.set_pixel(22, 2, out_c)
	img.set_pixel(23, 2, out_c)
	img.set_pixel(22, 4, out_c)
	img.set_pixel(23, 4, out_c)
	img.set_pixel(25, 3, out_c)

	var result: ImageTexture = ImageTexture.create_from_image(img)
	_icon_cache["spear"] = result
	return result


## Builds a crisp 9-slice pixel-art panel StyleBoxTexture (with StyleBoxFlat fallback).
static func make_panel_style(
	tex_path: String,
	slice_margin: float = 8.0,
	pad_h: float = 10.0,
	pad_v: float = 8.0,
	fallback_bg: Color = Color(0.09, 0.07, 0.13, 0.96),
	fallback_border: Color = Color(0.84, 0.36, 0.34, 1.0)
) -> StyleBox:
	if ResourceLoader.exists(tex_path):
		var t: Texture2D = load(tex_path) as Texture2D
		if t != null:
			var sb: StyleBoxTexture = StyleBoxTexture.new()
			sb.texture = t
			sb.texture_margin_left = slice_margin
			sb.texture_margin_right = slice_margin
			sb.texture_margin_top = slice_margin
			sb.texture_margin_bottom = slice_margin
			sb.content_margin_left = pad_h
			sb.content_margin_right = pad_h
			sb.content_margin_top = pad_v
			sb.content_margin_bottom = pad_v
			sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
			sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
			return sb
	var flat: StyleBoxFlat = StyleBoxFlat.new()
	flat.bg_color = fallback_bg
	flat.border_color = fallback_border
	flat.set_border_width_all(1)
	flat.content_margin_left = pad_h
	flat.content_margin_right = pad_h
	flat.content_margin_top = pad_v
	flat.content_margin_bottom = pad_v
	return flat


## Procedural icons & gameplay sprites (automatically checks custom drop-in PNGs first).
static func get_icon_texture(icon_id: String) -> Texture2D:
	if _icon_cache.has(icon_id):
		return _icon_cache[icon_id] as Texture2D

	var explicit_map: Dictionary = {
		"cursor": "res://assets/ui/cursor_pointer.png",
		"cursor_crosshair": "res://assets/ui/cursor_crosshair.png",
		"broken_house": "res://assets/ui/icon_danger.png",
		"trophy": "res://assets/ui/icon_trophy.png",
		"bow": "res://assets/weapons/bow_icon.png",
		"heart": "res://assets/ui/icon_heart.png",
		"house_icon": "res://assets/ui/icon_house.png",
		"bag_icon": "res://assets/ui/icon_bag.png",
		"shock_icon": "res://assets/ui/icon_shock.png",
	}
	if explicit_map.has(icon_id):
		var ep: String = String(explicit_map[icon_id])
		if ResourceLoader.exists(ep):
			var et: Texture2D = load(ep) as Texture2D
			if et != null:
				_icon_cache[icon_id] = et
				return et

	var drop_paths: Array[String] = [
		"res://assets/traps/%s.png" % icon_id,
		"res://assets/weapons/%s.png" % icon_id,
		"res://assets/structures/%s.png" % icon_id,
		"res://assets/ui/%s.png" % icon_id,
	]
	for dp in drop_paths:
		if ResourceLoader.exists(dp):
			var custom_tex: Texture2D = load(dp) as Texture2D
			if custom_tex != null:
				_icon_cache[icon_id] = custom_tex
				return custom_tex

	var result: Texture2D = null
	match icon_id:
		"arrow_proj":
			result = _make_arrow_projectile()
		"bow":
			result = _make_bow_icon()
		"scrap":
			result = _make_scrap_icon()
		"arrow":
			result = _make_arrow_icon()
		"trap_spike":
			result = _make_trap_spike_icon()
		"trap_snare":
			result = _make_trap_snare_icon()
		"trap_lure":
			result = _make_trap_lure_icon()
		"watchtower":
			result = _make_watchtower_texture()
		"trophy", "moon", "world", "broken_house":
			result = _make_badge_icon(icon_id)
		"cursor":
			result = _make_pixel_cursor()
		_:
			result = _make_placeholder(icon_id)

	_icon_cache[icon_id] = result
	return result


static func _make_arrow_projectile() -> ImageTexture:
	var img: Image = Image.create_empty(8, 3, false, Image.FORMAT_RGBA8)
	var shaft: Color = Color(0.56, 0.36, 0.20, 1.0)
	var tip: Color = Color(0.92, 0.95, 0.98, 1.0)
	var fletch: Color = Color(0.86, 0.28, 0.26, 1.0)
	img.set_pixel(0, 0, fletch)
	img.set_pixel(0, 2, fletch)
	for x in range(1, 6):
		img.set_pixel(x, 1, shaft)
	img.set_pixel(6, 1, tip)
	img.set_pixel(7, 1, tip)
	img.set_pixel(6, 0, tip)
	img.set_pixel(6, 2, tip)
	return ImageTexture.create_from_image(img)


static func _make_bow_icon() -> ImageTexture:
	var img: Image = Image.create_empty(12, 12, false, Image.FORMAT_RGBA8)
	var wood: Color = Color(0.68, 0.44, 0.24, 1.0)
	var str_c: Color = Color(0.86, 0.86, 0.90, 1.0)
	for y in range(2, 10):
		img.set_pixel(3, y, str_c)
	for pt in [
		Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 2), Vector2i(7, 3),
		Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7),
		Vector2i(7, 8), Vector2i(6, 9), Vector2i(5, 10), Vector2i(4, 10),
	]:
		img.set_pixel(pt.x, pt.y, wood)
	return ImageTexture.create_from_image(img)


static func _make_scrap_icon() -> ImageTexture:
	var img: Image = Image.create_empty(12, 12, false, Image.FORMAT_RGBA8)
	var out_c: Color = Color(0.16, 0.12, 0.18, 1.0)
	var metal: Color = Color(0.62, 0.68, 0.74, 1.0)
	var rust: Color = Color(0.68, 0.36, 0.22, 1.0)
	for y in range(3, 9):
		for x in range(2, 10):
			var edge: bool = (x == 2 or x == 9 or y == 3 or y == 8)
			img.set_pixel(x, y, out_c if edge else (rust if (x + y) % 3 == 0 else metal))
	img.set_pixel(4, 5, out_c)
	img.set_pixel(7, 6, out_c)
	return ImageTexture.create_from_image(img)


static func _make_arrow_icon() -> ImageTexture:
	var img: Image = Image.create_empty(12, 12, false, Image.FORMAT_RGBA8)
	var shaft: Color = Color(0.62, 0.42, 0.24, 1.0)
	var tip: Color = Color(0.92, 0.96, 1.0, 1.0)
	var red: Color = Color(0.86, 0.26, 0.24, 1.0)
	for i in range(2, 10):
		img.set_pixel(i, 11 - i, shaft)
	img.set_pixel(9, 2, tip)
	img.set_pixel(8, 2, tip)
	img.set_pixel(9, 3, tip)
	img.set_pixel(2, 8, red)
	img.set_pixel(3, 9, red)
	return ImageTexture.create_from_image(img)


static func _make_trap_spike_icon() -> ImageTexture:
	var img: Image = Image.create_empty(18, 16, false, Image.FORMAT_RGBA8)
	var out_c: Color = Color(0.14, 0.10, 0.14, 1.0)
	var plate: Color = Color(0.42, 0.36, 0.34, 1.0)
	var plate_hi: Color = Color(0.58, 0.50, 0.44, 1.0)
	var steel: Color = Color(0.90, 0.94, 0.98, 1.0)
	var rust_tip: Color = Color(0.86, 0.28, 0.24, 1.0)
	for y in range(6, 14):
		for x in range(2, 16):
			var edge: bool = (x == 2 or x == 15 or y == 6 or y == 13)
			img.set_pixel(x, y, out_c if edge else (plate_hi if y == 7 else plate))
	for pt in [
		Vector2i(5, 6), Vector2i(9, 6), Vector2i(13, 6),
		Vector2i(6, 10), Vector2i(11, 10),
	]:
		img.set_pixel(pt.x, pt.y - 3, rust_tip)
		img.set_pixel(pt.x, pt.y - 2, steel)
		img.set_pixel(pt.x - 1, pt.y - 1, out_c)
		img.set_pixel(pt.x, pt.y - 1, steel)
		img.set_pixel(pt.x + 1, pt.y - 1, out_c)
	return ImageTexture.create_from_image(img)


static func _make_trap_snare_icon() -> ImageTexture:
	var img: Image = Image.create_empty(18, 16, false, Image.FORMAT_RGBA8)
	var out_c: Color = Color(0.14, 0.10, 0.14, 1.0)
	var iron_l: Color = Color(0.74, 0.80, 0.86, 1.0)
	var iron_d: Color = Color(0.42, 0.46, 0.54, 1.0)
	var pad: Color = Color(0.86, 0.30, 0.24, 1.0)
	for y in range(2, 14):
		for x in range(2, 16):
			var nx: float = (float(x) - 8.5) / 6.0
			var ny: float = (float(y) - 8.0) / 4.8
			var d: float = nx * nx + ny * ny
			if d >= 0.58 and d <= 1.05:
				var tooth: bool = ((x + y) % 2 == 0)
				img.set_pixel(x, y, iron_l if tooth else iron_d)
			elif d > 1.05 and d <= 1.25:
				img.set_pixel(x, y, out_c)
			elif d <= 0.24:
				img.set_pixel(x, y, pad if d <= 0.12 else out_c)
	return ImageTexture.create_from_image(img)


static func _make_trap_lure_icon() -> ImageTexture:
	var img: Image = Image.create_empty(16, 22, false, Image.FORMAT_RGBA8)
	var out_c: Color = Color(0.14, 0.10, 0.14, 1.0)
	var post: Color = Color(0.60, 0.40, 0.22, 1.0)
	var post_d: Color = Color(0.42, 0.26, 0.14, 1.0)
	var glow: Color = Color(1.0, 0.86, 0.32, 1.0)
	var red: Color = Color(0.92, 0.24, 0.24, 1.0)
	for y in range(4, 20):
		img.set_pixel(6, y, out_c)
		img.set_pixel(7, y, post)
		img.set_pixel(8, y, post_d)
		img.set_pixel(9, y, out_c)
	# Cross-arm + glowing warning beacon lantern.
	for x in range(4, 14):
		img.set_pixel(x, 5, out_c)
		img.set_pixel(x, 6, post)
		img.set_pixel(x, 7, out_c)
	for y in range(7, 13):
		for x in range(10, 15):
			var edge: bool = (x == 10 or x == 14 or y == 7 or y == 12)
			img.set_pixel(x, y, out_c if edge else (glow if y <= 10 else red))
	return ImageTexture.create_from_image(img)


static func _make_watchtower_texture() -> ImageTexture:
	var img: Image = Image.create_empty(20, 34, false, Image.FORMAT_RGBA8)
	var out_c: Color = Color(0.16, 0.12, 0.18, 1.0)
	var wood_l: Color = Color(0.60, 0.42, 0.26, 1.0)
	var wood_d: Color = Color(0.40, 0.26, 0.16, 1.0)
	var roof: Color = Color(0.48, 0.52, 0.60, 1.0)
	for y in range(14, 33):
		for lx in [4, 5, 14, 15]:
			img.set_pixel(lx, y, wood_l if lx % 2 == 0 else wood_d)
	for y in range(6, 15):
		for x in range(2, 18):
			var edge: bool = (x == 2 or x == 17 or y == 6 or y == 14)
			img.set_pixel(x, y, out_c if edge else (wood_d if x >= 14 else wood_l))
	for y in range(2, 7):
		for x in range(1, 19):
			img.set_pixel(x, y, roof if y > 2 else out_c)
	return ImageTexture.create_from_image(img)


static func _make_badge_icon(kind: String) -> ImageTexture:
	var img: Image = Image.create_empty(14, 14, false, Image.FORMAT_RGBA8)
	var c1: Color = Color(0.95, 0.80, 0.30, 1.0)
	if kind == "moon":
		c1 = Color(0.94, 0.26, 0.26, 1.0)
	elif kind == "world":
		c1 = Color(0.42, 0.84, 0.54, 1.0)
	elif kind == "broken_house":
		c1 = Color(0.62, 0.54, 0.58, 1.0)
	var out_c: Color = Color(0.16, 0.12, 0.18, 1.0)
	for y in range(2, 12):
		for x in range(2, 12):
			var d: float = Vector2(float(x) - 6.5, float(y) - 6.5).length()
			if kind == "broken_house":
				if y >= 6 and (x < 6 or x > 7):
					img.set_pixel(x, y, c1)
				elif y < 6 and absf(float(x) - 6.5) <= float(y):
					img.set_pixel(x, y, c1.darkened(0.2))
			elif d <= 4.2:
				img.set_pixel(x, y, c1)
			elif d <= 5.2:
				img.set_pixel(x, y, out_c)
	return ImageTexture.create_from_image(img)


static func _make_pixel_cursor() -> ImageTexture:
	var img: Image = Image.create_empty(12, 12, false, Image.FORMAT_RGBA8)
	var out_c: Color = Color(0.10, 0.07, 0.12, 1.0)
	var fill_c: Color = Color(0.98, 0.94, 0.86, 1.0)
	for y in range(0, 10):
		for x in range(0, y + 1):
			if x > 7:
				continue
			var edge: bool = (x == 0 or x == y or y == 9)
			img.set_pixel(x, y, out_c if edge else fill_c)
	return ImageTexture.create_from_image(img)


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
	var fill: Color = Color(
		0.35 + float(hash_val % 50) / 100.0,
		0.25 + float((hash_val >> 3) % 50) / 100.0,
		0.35 + float((hash_val >> 6) % 50) / 100.0,
		1.0
	)
	var border: Color = Color(fill.r * 0.45, fill.g * 0.45, fill.b * 0.45, 1.0)
	var img: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	for x in range(width):
		img.set_pixel(x, 0, border)
		img.set_pixel(x, height - 1, border)
	for y in range(height):
		img.set_pixel(0, y, border)
		img.set_pixel(width - 1, y, border)
	return ImageTexture.create_from_image(img)
