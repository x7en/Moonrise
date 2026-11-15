class_name Art
extends RefCounted

# keep textures/fonts in memory so we dont hit disk mid-wave
static var _tex_cache: Dictionary = {}
static var _frames_cache: Dictionary = {}
static var _silhouette_cache: Dictionary = {}
static var _icon_cache: Dictionary = {}
static var _theme_cache: Theme = null
static var _font_body_cache: Font = null
static var _font_bold_cache: Font = null
static var _font_display_cache: Font = null
static var _light_tex_cache: Dictionary = {}
static var _blob_cache: Dictionary = {}


static func tex(key: String) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D

	var res_path := Sprites.path(key)
	var loaded = null
	if ResourceLoader.exists(res_path):
		loaded = load(res_path)
	else:
		var abs_path := ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(abs_path):
			var raw_img := Image.load_from_file(abs_path)
			if raw_img != null and not raw_img.is_empty():
				loaded = ImageTexture.create_from_image(raw_img)

	if loaded == null:
		loaded = _make_placeholder(key)

	_tex_cache[key] = loaded
	return loaded


# blit_rect throws errors if formats dont match, so always hand back uncompressed rgba8
static func get_image_rgba8(key: String) -> Image:
	var loaded_tex := tex(key)
	var img := loaded_tex.get_image()
	if img == null:
		img = Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.8, 0.2, 0.7, 1.0))
		return img

	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


# makes a solid colored cutout of a sprite (mostly used for the red house damage flash)
static func get_tinted_silhouette(key: String, fill_color: Color) -> Texture2D:
	var cache_key := "%s|%s" % [key, fill_color.to_html()]
	if _silhouette_cache.has(cache_key):
		return _silhouette_cache[cache_key] as Texture2D

	var src := get_image_rgba8(key)
	var width := src.get_width()
	var height := src.get_height()
	var out := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)

	for y in range(height):
		for x in range(width):
			var pixel := src.get_pixel(x, y)
			if pixel.a > 0.01:
				out.set_pixel(
					x,
					y,
					Color(fill_color.r, fill_color.g, fill_color.b, pixel.a * fill_color.a)
				)
			else:
				out.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))

	var result := ImageTexture.create_from_image(out)
	_silhouette_cache[cache_key] = result
	return result


static func make_static_sprite(key: String, feet_origin: bool = true) -> Sprite2D:
	var sprite := Sprite2D.new()
	var loaded_tex := tex(key)
	sprite.texture = loaded_tex
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if feet_origin:
		var dims: Array = Sprites.STATIC.get(
			key, [loaded_tex.get_width(), loaded_tex.get_height()]
		)
		sprite.offset = Vector2(-floorf(float(int(dims[0])) * 0.5), -float(int(dims[1])))

	return sprite


static func feet_offset_for_animated(key: String, x_shift: float = 0.0) -> Vector2:
	var info: Array = Sprites.ANIMATED.get(key, [1, 16, 16])
	return Vector2(-floorf(float(info[1]) * 0.5) + x_shift, -float(info[2]))


static func font_body() -> Font:
	if _font_body_cache == null:
		_font_body_cache = _load_pixel_font(Config.FONT_BODY_PATH)
	return _font_body_cache


static func font_bold() -> Font:
	if _font_bold_cache == null:
		_font_bold_cache = _load_pixel_font(Config.FONT_BOLD_PATH)
	return _font_bold_cache


static func font_display() -> Font:
	if _font_display_cache == null:
		_font_display_cache = _load_pixel_font(Config.FONT_DISPLAY_PATH)
	return _font_display_cache


static func _load_pixel_font(res_path: String) -> Font:
	if not ResourceLoader.exists(res_path):
		return ThemeDB.fallback_font

	var loaded = load(res_path)
	if loaded == null:
		return ThemeDB.fallback_font

	# force pixel crispness, godot 4 loves blurring pixel fonts by default
	if loaded is FontFile:
		var ff = loaded
		ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		ff.hinting = TextServer.HINTING_NONE
		ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		ff.generate_mipmaps = false

	return loaded


static func style_label(
	lbl: Label,
	style: String = "body",
	size_px: int = 8,
	color: Color = Color.WHITE
) -> void:
	lbl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var f := font_body()
	if style == "bold":
		f = font_bold()
	elif style == "display":
		f = font_display()

	lbl.add_theme_font_override("font", f)
	lbl.add_theme_font_size_override("font_size", size_px)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.12, 0.95))
	lbl.add_theme_constant_override("outline_size", 1)


static func get_game_theme() -> Theme:
	if _theme_cache != null:
		return _theme_cache

	var theme := Theme.new()
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
		"normal", "Button",
		_make_button_box(Color(0.12, 0.10, 0.15, 0.96), Color(0.42, 0.34, 0.40))
	)
	theme.set_stylebox(
		"hover", "Button",
		_make_button_box(Color(0.22, 0.15, 0.20, 0.98), Color(0.92, 0.36, 0.32))
	)
	theme.set_stylebox(
		"pressed", "Button",
		_make_button_box(Color(0.30, 0.12, 0.15, 1.0), Color(1.0, 0.52, 0.42))
	)
	theme.set_stylebox(
		"disabled", "Button",
		_make_button_box(Color(0.09, 0.08, 0.11, 0.85), Color(0.26, 0.22, 0.28))
	)
	theme.set_stylebox(
		"focus", "Button",
		_make_button_box(Color(0.20, 0.14, 0.19, 0.98), Color(0.95, 0.42, 0.36))
	)

	_theme_cache = theme
	return _theme_cache


static func _make_button_box(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_color = border_color
	box.set_border_width_all(1)
	box.content_margin_left = 6.0
	box.content_margin_right = 6.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	return box


static func get_player_frames(swing_time: float = 0.3) -> SpriteFrames:
	if _frames_cache.has("player"):
		return _frames_cache["player"] as SpriteFrames

	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	for dir_name in ["down", "up", "left", "right"]:
		_add_strip_animation(frames, "idle_" + dir_name, "player/idle_" + dir_name, 6.0, true)
		_add_strip_animation(frames, "run_" + dir_name, "player/run_" + dir_name, 10.0, true)

		var punch_key = "player/punch_" + dir_name
		var punch_info: Array = Sprites.ANIMATED.get(punch_key, [4, 16, 16])
		var punch_fps := float(punch_info[0]) / maxf(swing_time, 0.05)
		_add_strip_animation(frames, "punch_" + dir_name, punch_key, punch_fps, false)

	_add_strip_animation(frames, "death_left", "player/death_left", 10.0, false)
	_add_strip_animation(frames, "death_right", "player/death_right", 10.0, false)

	_frames_cache["player"] = frames
	return frames


static func get_enemy_frames(enemy_type: String) -> SpriteFrames:
	var cache_key := "enemy_" + enemy_type
	if _frames_cache.has(cache_key):
		return _frames_cache[cache_key] as SpriteFrames

	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	var walk_fps := 10.0 if enemy_type == "raider" else 8.0

	for dir_name in ["down", "up", "left", "right"]:
		var walk_key := "enemies/%s/walk_%s" % [enemy_type, dir_name]
		_add_strip_animation(frames, "walk_" + dir_name, walk_key, walk_fps, true)

		var attack_key := "enemies/%s/attack_%s" % [enemy_type, dir_name]
		var attack_info: Array = Sprites.ANIMATED.get(attack_key, [4, 16, 16])
		var attack_fps := float(attack_info[0]) / 0.35
		_add_strip_animation(frames, "attack_" + dir_name, attack_key, attack_fps, false)

	_add_strip_animation(frames, "death_left", "enemies/%s/death_left" % enemy_type, 10.0, false)
	_add_strip_animation(frames, "death_right", "enemies/%s/death_right" % enemy_type, 10.0, false)

	_frames_cache[cache_key] = frames
	return frames


static func get_ghost_frames(variant: String = "scythe") -> SpriteFrames:
	var cache_key := "ghost:%s" % variant
	if _frames_cache.has(cache_key):
		return _frames_cache[cache_key] as SpriteFrames

	var strip_key := (
		"enemies/ghost/ghost_lunge_strip" if variant == "lunge"
		else "enemies/ghost/ghost_scythe_strip"
	)
	var info: Array = Sprites.ANIMATED.get(strip_key, [10, 80, 50])
	var frame_count := maxi(1, int(info[0]))
	var frame_w := maxi(1, int(info[1]))
	var frame_h := maxi(1, int(info[2]))
	var strip := tex(strip_key)

	var slices: Array[Texture2D] = []
	for i in range(frame_count):
		if strip.get_width() >= (i + 1) * frame_w and strip.get_height() >= frame_h:
			var atlas := AtlasTexture.new()
			atlas.atlas = strip
			atlas.region = Rect2(float(i * frame_w), 0.0, float(frame_w), float(frame_h))
			slices.append(atlas)
		else:
			slices.append(strip)

	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	var anim_defs := (
		{
			"materialize": {"idx": [0, 1, 2, 3], "fps": 10.0, "loop": false},
			"drift": {"idx": [2, 3], "fps": 6.0, "loop": true},
			"attack": {"idx": [4, 5, 6, 7], "fps": 10.0, "loop": false},
			"dissolve": {"idx": [8, 9], "fps": 10.0, "loop": false},
		} if variant == "lunge" else {
			"materialize": {"idx": [0, 1, 2], "fps": 10.0, "loop": false},
			"drift": {"idx": [3, 4], "fps": 6.0, "loop": true},
			"attack": {"idx": [5, 6, 7], "fps": 10.0, "loop": false},
			"dissolve": {"idx": [8, 9], "fps": 10.0, "loop": false},
		}
	)
	for anim_name in anim_defs.keys():
		var cfg: Dictionary = anim_defs[anim_name]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, float(cfg["fps"]))
		frames.set_animation_loop(anim_name, bool(cfg["loop"]))
		for fi in cfg["idx"]:
			frames.add_frame(anim_name, slices[clampi(int(fi), 0, slices.size() - 1)])

	_frames_cache[cache_key] = frames
	return frames


static func get_shaded_house_texture(level: int = 1, door_open: bool = false) -> Texture2D:
	var lv := clampi(level, 1, 3)
	var suffix := "_open" if door_open else ""
	return tex("house/lv%d%s" % [lv, suffix])


static func get_radial_light_texture(size_px: int = 128) -> GradientTexture2D:
	if _light_tex_cache.has(size_px):
		return _light_tex_cache[size_px] as GradientTexture2D

	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))

	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = size_px
	gt.height = size_px

	_light_tex_cache[size_px] = gt
	return gt


# cheap oval ground shadows so sprites dont look like stickers floating on grass
static func get_blob_shadow(width: int, height: int) -> ImageTexture:
	var key := "%dx%d" % [width, height]
	if _blob_cache.has(key):
		return _blob_cache[key] as ImageTexture

	var img := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var rx := maxf(1.0, float(width) * 0.5)
	var ry := maxf(1.0, float(height) * 0.5)

	for y in range(height):
		for x in range(width):
			var nx := (float(x) + 0.5 - rx) / rx
			var ny := (float(y) + 0.5 - ry) / ry
			var d := nx * nx + ny * ny
			if d <= 0.72:
				img.set_pixel(x, y, Color(0.08, 0.06, 0.11, 0.34))
			elif d <= 1.0 and ((x + y) % 2 == 0):
				img.set_pixel(x, y, Color(0.08, 0.06, 0.11, 0.22))

	var result := ImageTexture.create_from_image(img)
	_blob_cache[key] = result
	return result


# TODO: replace spear, scrap, and watchtower with real sprites if i ever draw them
static func get_spear_texture() -> ImageTexture:
	if _icon_cache.has("spear_world"):
		return _icon_cache["spear_world"] as ImageTexture

	var img := Image.create_empty(26, 7, false, Image.FORMAT_RGBA8)
	var out_c := Color(0.16, 0.12, 0.18, 1.0)
	var wood_l := Color(0.64, 0.42, 0.24, 1.0)
	var wood_d := Color(0.45, 0.28, 0.16, 1.0)
	var wrap_c := Color(0.78, 0.20, 0.20, 1.0)
	var steel_b := Color(0.92, 0.96, 1.0, 1.0)
	var steel_d := Color(0.58, 0.64, 0.72, 1.0)

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

	var result := ImageTexture.create_from_image(img)
	_icon_cache["spear_world"] = result
	return result


static func make_panel_style(
	tex_path: String,
	slice_margin: float = 8.0,
	pad_h: float = 10.0,
	pad_v: float = 8.0,
	fallback_bg: Color = Color(0.09, 0.07, 0.13, 0.96),
	fallback_border: Color = Color(0.84, 0.36, 0.34, 1.0)
) -> StyleBox:
	if ResourceLoader.exists(tex_path):
		var t = load(tex_path)
		if t != null:
			var sb := StyleBoxTexture.new()
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

	var flat := StyleBoxFlat.new()
	flat.bg_color = fallback_bg
	flat.border_color = fallback_border
	flat.set_border_width_all(1)
	flat.content_margin_left = pad_h
	flat.content_margin_right = pad_h
	flat.content_margin_top = pad_v
	flat.content_margin_bottom = pad_v
	return flat


static func get_icon_texture(icon_id: String) -> Texture2D:
	if _icon_cache.has(icon_id):
		return _icon_cache[icon_id] as Texture2D

	var icon_map := {
		"cursor": "ui/cursor",
		"cursor_crosshair": "ui/crosshair",
		"broken_house": "ui/danger",
		"trophy": "ui/trophy",
		"heart": "ui/heart",
		"house_icon": "ui/house",
		"bag_icon": "ui/bag",
		"shock_icon": "ui/shock",
		"bow": "weapons/bow",
		"boomerang": "placeholders/boomerang_placeholder",
		"arrow": "weapons/arrow",
		"arrow_proj": "weapons/arrow",
		"trap_spike": "traps/spike",
		"trap_snare": "traps/snare",
		"trap_lure": "traps/lure",
		"moon": "sky/blood_moon",
		"world": "sky/moon",
	}

	if icon_map.has(icon_id):
		var loaded := tex(String(icon_map[icon_id]))
		_icon_cache[icon_id] = loaded
		return loaded

	# things still drawn in code because no dedicated sprite png exists yet
	var result = null
	if icon_id == "scrap":
		result = _make_scrap_icon()
	elif icon_id == "watchtower":
		result = _make_watchtower_texture()
	elif icon_id == "spear":
		result = _make_spear_icon()
	else:
		result = _make_placeholder(icon_id)

	_icon_cache[icon_id] = result
	return result


static func _make_spear_icon() -> ImageTexture:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	var out_c := Color(0.16, 0.12, 0.18, 1.0)
	var shaft := Color(0.58, 0.38, 0.22, 1.0)
	var tip := Color(0.84, 0.88, 0.94, 1.0)
	for i in range(2, 11):
		var x := i
		var y := 15 - i
		img.set_pixel(x, y, shaft)
		if x + 1 < 16:
			img.set_pixel(x + 1, y, out_c)
	for pt in [
		Vector2i(11, 4), Vector2i(12, 3), Vector2i(13, 2),
		Vector2i(11, 3), Vector2i(12, 4), Vector2i(12, 2), Vector2i(13, 3)
	]:
		img.set_pixel(pt.x, pt.y, tip)
	return ImageTexture.create_from_image(img)


static func _make_scrap_icon() -> ImageTexture:
	var img := Image.create_empty(12, 12, false, Image.FORMAT_RGBA8)
	var out_c := Color(0.16, 0.12, 0.18, 1.0)
	var metal := Color(0.62, 0.68, 0.74, 1.0)
	var rust := Color(0.68, 0.36, 0.22, 1.0)

	for y in range(3, 9):
		for x in range(2, 10):
			var edge := (x == 2 or x == 9 or y == 3 or y == 8)
			img.set_pixel(x, y, out_c if edge else (rust if (x + y) % 3 == 0 else metal))

	img.set_pixel(4, 5, out_c)
	img.set_pixel(7, 6, out_c)
	return ImageTexture.create_from_image(img)


static func _make_watchtower_texture() -> ImageTexture:
	var img := Image.create_empty(20, 34, false, Image.FORMAT_RGBA8)
	var out_c := Color(0.16, 0.12, 0.18, 1.0)
	var wood_l := Color(0.60, 0.42, 0.26, 1.0)
	var wood_d := Color(0.40, 0.26, 0.16, 1.0)
	var roof := Color(0.48, 0.52, 0.60, 1.0)

	for y in range(14, 33):
		for lx in [4, 5, 14, 15]:
			img.set_pixel(lx, y, wood_l if lx % 2 == 0 else wood_d)

	for y in range(6, 15):
		for x in range(2, 18):
			var edge := (x == 2 or x == 17 or y == 6 or y == 14)
			img.set_pixel(x, y, out_c if edge else (wood_d if x >= 14 else wood_l))

	for y in range(2, 7):
		for x in range(1, 19):
			img.set_pixel(x, y, roof if y > 2 else out_c)

	return ImageTexture.create_from_image(img)


static func _add_strip_animation(
	frames: SpriteFrames,
	anim_name: String,
	key: String,
	fps: float,
	should_loop: bool
) -> void:
	var info: Array = Sprites.ANIMATED.get(key, [1, 16, 16])
	var frame_count := maxi(1, int(info[0]))
	var frame_w := maxi(1, int(info[1]))
	var frame_h := maxi(1, int(info[2]))
	var strip := tex(key)

	if frames.has_animation(anim_name):
		frames.remove_animation(anim_name)
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, should_loop)

	var strip_w := strip.get_width()
	var strip_h := strip.get_height()
	for i in range(frame_count):
		if strip_w >= (i + 1) * frame_w and strip_h >= frame_h:
			var atlas_tex := AtlasTexture.new()
			atlas_tex.atlas = strip
			atlas_tex.region = Rect2(float(i * frame_w), 0.0, float(frame_w), float(frame_h))
			frames.add_frame(anim_name, atlas_tex)
		else:
			frames.add_frame(anim_name, strip)


static func _make_placeholder(key: String) -> ImageTexture:
	var width := 16
	var height := 16
	if Sprites.STATIC.has(key):
		var dims: Array = Sprites.STATIC[key]
		width = maxi(2, int(dims[0]))
		height = maxi(2, int(dims[1]))
	elif Sprites.ANIMATED.has(key):
		var anim_dims: Array = Sprites.ANIMATED[key]
		width = maxi(2, int(anim_dims[1]))
		height = maxi(2, int(anim_dims[2]))

	var hash_val := key.hash() & 0x7FFFFFFF
	var fill := Color(
		0.35 + float(hash_val % 50) / 100.0,
		0.25 + float((hash_val >> 3) % 50) / 100.0,
		0.35 + float((hash_val >> 6) % 50) / 100.0,
		1.0
	)
	var border := Color(fill.r * 0.45, fill.g * 0.45, fill.b * 0.45, 1.0)
	var img := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	img.fill(fill)

	for x in range(width):
		img.set_pixel(x, 0, border)
		img.set_pixel(x, height - 1, border)
	for y in range(height):
		img.set_pixel(0, y, border)
		img.set_pixel(width - 1, y, border)

	return ImageTexture.create_from_image(img)
