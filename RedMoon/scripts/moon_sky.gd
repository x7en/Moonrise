class_name MoonSky
extends Control
## Procedural pixel night sky (T1.1 / T3.4) with twinkling stars, owner moon sprite art
## (moon_00..03 / moon_00_white / moon_00_red..03_red), and 3-layer Bayer-dithered clouds.
## Reused identically by the moonrise cutscene and the Main Menu backdrop.

var is_blood_mode: bool = false
var red_blend: float = 0.0  # 0.0 = white/normal, 1.0 = full Blood Moon red
var moon_progress: float = 1.0  # 0.0 = below horizon, 1.0 = perched in sky
var cloud_speed_scale: float = 1.0

var _sky_top: ColorRect = null
var _sky_mid: ColorRect = null
var _sky_low: ColorRect = null
var _stars: Array[Dictionary] = []
var _moon_holder: Control = null
var _moon_base: TextureRect = null
var _moon_red: TextureRect = null
var _moon_glow: TextureRect = null
var _cloud_layers: Array[Dictionary] = []
var _silhouette: Control = null
var _time: float = 0.0
var _moon_phase_idx: int = 0
var _view_size: Vector2 = Vector2(640.0, 360.0)


func build(view_size: Vector2 = Config.VIEW_SIZE) -> void:
	_view_size = view_size
	position = Vector2.ZERO
	size = view_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 1. Three-band pixel sky gradient (dark indigo -> dusk violet -> horizon haze).
	_sky_top = ColorRect.new()
	_sky_top.position = Vector2.ZERO
	_sky_top.size = Vector2(view_size.x, view_size.y * 0.45)
	_sky_top.color = Color(0.04, 0.04, 0.11, 1.0)
	add_child(_sky_top)

	_sky_mid = ColorRect.new()
	_sky_mid.position = Vector2(0.0, view_size.y * 0.45)
	_sky_mid.size = Vector2(view_size.x, view_size.y * 0.30)
	_sky_mid.color = Color(0.08, 0.06, 0.16, 1.0)
	add_child(_sky_mid)

	_sky_low = ColorRect.new()
	_sky_low.position = Vector2(0.0, view_size.y * 0.75)
	_sky_low.size = Vector2(view_size.x, view_size.y * 0.25)
	_sky_low.color = Color(0.13, 0.09, 0.18, 1.0)
	add_child(_sky_low)

	# 2. Twinkling pixel stars behind the moon and clouds.
	var srng: RandomNumberGenerator = RandomNumberGenerator.new()
	srng.seed = 4207
	for _i in range(52):
		var star: ColorRect = ColorRect.new()
		var sz: float = 2.0 if srng.randf() < 0.25 else 1.0
		star.position = Vector2(
			floorf(srng.randf_range(8.0, view_size.x - 8.0)),
			floorf(srng.randf_range(6.0, view_size.y * 0.66))
		)
		star.size = Vector2(sz, sz)
		star.color = Color(0.92, 0.94, 1.0, 0.85)
		add_child(star)
		_stars.append({
			"node": star,
			"phase": srng.randf_range(0.0, TAU),
			"spd": srng.randf_range(1.2, 3.0),
		})

	# 3. Back cloud layer (behind the moon).
	_add_cloud_layer(0, 6.0, 26.0, Color(0.16, 0.14, 0.26, 0.72), 111)

	# 4. Crisp 4x scaled owner moon sprite (128x128 from 32x32) with red crossfade overlay.
	_moon_holder = Control.new()
	_moon_holder.size = Vector2(128.0, 128.0)
	add_child(_moon_holder)

	_moon_glow = TextureRect.new()
	_moon_glow.position = Vector2(-24.0, -24.0)
	_moon_glow.size = Vector2(176.0, 176.0)
	_moon_glow.texture = SpriteFactory.get_radial_light_texture(128)
	_moon_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_moon_glow.modulate = Color(0.86, 0.88, 1.0, 0.14)
	_moon_holder.add_child(_moon_glow)

	_moon_base = TextureRect.new()
	_moon_base.position = Vector2.ZERO
	_moon_base.size = Vector2(128.0, 128.0)
	_moon_base.stretch_mode = TextureRect.STRETCH_SCALE
	_moon_base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_moon_holder.add_child(_moon_base)

	_moon_red = TextureRect.new()
	_moon_red.position = Vector2.ZERO
	_moon_red.size = Vector2(128.0, 128.0)
	_moon_red.stretch_mode = TextureRect.STRETCH_SCALE
	_moon_red.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_moon_red.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_moon_holder.add_child(_moon_red)

	# 5. Mid and foreground cloud layers that drift RIGHT IN FRONT OF the moon, occluding it.
	_add_cloud_layer(1, 14.0, 74.0, Color(0.12, 0.10, 0.20, 0.84), 222)
	_add_cloud_layer(2, 24.0, 118.0, Color(0.08, 0.07, 0.14, 0.90), 333)

	# 6. Farmhouse + tree-line silhouette anchored at the bottom horizon.
	_silhouette = Control.new()
	_silhouette.position = Vector2(0.0, view_size.y - 68.0)
	_silhouette.size = Vector2(view_size.x, 68.0)
	add_child(_silhouette)
	_build_horizon_silhouette()

	configure_for_night(1, false)
	update_sky(0.0)


func configure_for_night(
	night_num: int,
	is_blood: bool,
	start_white_turn_red: bool = false
) -> void:
	is_blood_mode = is_blood
	_moon_phase_idx = clampi(night_num - 1, 0, 3)
	var base_key: String = (
		"moon/moon_00_white" if start_white_turn_red else ("moon/moon_%02d" % _moon_phase_idx)
	)
	var red_key: String = "moon/moon_%02d_red" % _moon_phase_idx
	if _moon_base != null:
		_moon_base.texture = _load_custom_sky_tex("res://assets/sky/moon_full.png", base_key)
	if _moon_red != null:
		_moon_red.texture = _load_custom_sky_tex("res://assets/sky/moon_blood.png", red_key)
	red_blend = 1.0 if (is_blood and not start_white_turn_red) else 0.0


func set_red_moon_frame(frame_idx: int) -> void:
	var idx: int = clampi(frame_idx, 0, 3)
	if _moon_red != null:
		_moon_red.texture = _load_custom_sky_tex(
			"res://assets/sky/moon_blood.png", "moon/moon_%02d_red" % idx
		)


func _load_custom_sky_tex(custom_path: String, fallback_key: String) -> Texture2D:
	if ResourceLoader.exists(custom_path):
		var loaded: Texture2D = load(custom_path) as Texture2D
		if loaded != null:
			return loaded
	return SpriteFactory.tex(fallback_key)


func update_sky(delta: float) -> void:
	_time += delta

	# Tint sky bands toward crimson as red_blend rises.
	if _sky_top != null:
		_sky_top.color = Color(0.04, 0.04, 0.11).lerp(Color(0.14, 0.03, 0.05), red_blend)
	if _sky_mid != null:
		_sky_mid.color = Color(0.08, 0.06, 0.16).lerp(Color(0.28, 0.05, 0.08), red_blend)
	if _sky_low != null:
		_sky_low.color = Color(0.13, 0.09, 0.18).lerp(Color(0.40, 0.08, 0.10), red_blend)

	for s in _stars:
		var node: ColorRect = s["node"] as ColorRect
		var pulse: float = 0.45 + 0.55 * sin(_time * float(s["spd"]) + float(s["phase"]))
		node.modulate.a = pulse * (1.0 - red_blend * 0.45)

	# Moon position eases up from behind the horizon into the upper sky.
	if _moon_holder != null:
		var start_y: float = _view_size.y - 36.0
		var end_y: float = 42.0
		var eased: float = 1.0 - pow(1.0 - clampf(moon_progress, 0.0, 1.0), 3.0)
		_moon_holder.position = Vector2(
			floorf(_view_size.x * 0.5 - 64.0),
			floorf(lerpf(start_y, end_y, eased))
		)
	if _moon_red != null:
		_moon_red.modulate.a = clampf(red_blend, 0.0, 1.0)
	if _moon_glow != null:
		_moon_glow.modulate = Color(0.86, 0.88, 1.0, 0.14).lerp(
			Color(0.98, 0.22, 0.22, 0.30), red_blend
		)

	# Scroll parallax pixel clouds seamlessly across the viewport.
	for layer in _cloud_layers:
		var spd: float = float(layer["speed"]) * cloud_speed_scale
		var w: float = float(layer["width"])
		var a: TextureRect = layer["a"] as TextureRect
		var b: TextureRect = layer["b"] as TextureRect
		var x: float = fposmod(float(layer["offset"]) + _time * spd, w)
		a.position.x = floorf(-x)
		b.position.x = floorf(w - x)
		var base_c: Color = layer["base_color"] as Color
		var blood_c: Color = layer["blood_color"] as Color
		var tint: Color = base_c.lerp(blood_c, red_blend)
		a.modulate = tint
		b.modulate = tint


func _add_cloud_layer(
	idx: int,
	speed_px: float,
	y_pos: float,
	base_col: Color,
	seed_val: int
) -> void:
	var strip_w: int = int(_view_size.x)
	var strip_h: int = 86
	var custom_names: Array[String] = ["clouds_back.png", "clouds_mid.png", "clouds_front.png"]
	var custom_path: String = "res://assets/sky/" + custom_names[clampi(idx, 0, 2)]
	var cloud_tex: Texture2D = null
	var is_custom: bool = false
	if ResourceLoader.exists(custom_path):
		cloud_tex = load(custom_path) as Texture2D
		is_custom = cloud_tex != null
	if cloud_tex == null:
		cloud_tex = _generate_dithered_cloud_strip(strip_w, strip_h, seed_val, idx)

	var a: TextureRect = TextureRect.new()
	a.texture = cloud_tex
	a.position = Vector2(0.0, y_pos)
	a.size = Vector2(float(strip_w), float(strip_h))
	a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(a)

	var b: TextureRect = TextureRect.new()
	b.texture = cloud_tex
	b.position = Vector2(float(strip_w), y_pos)
	b.size = Vector2(float(strip_w), float(strip_h))
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(b)

	var night_col: Color = base_col
	var blood_col: Color = Color(
		base_col.r * 1.9 + 0.10, base_col.g * 0.55, base_col.b * 0.55, base_col.a
	)
	if is_custom:
		var shade: float = [0.46, 0.54, 0.36][clampi(idx, 0, 2)]
		night_col = Color(shade * 0.85, shade * 0.84, shade * 1.15, 0.88)
		blood_col = Color(shade * 1.32, shade * 0.44, shade * 0.46, 0.92)

	_cloud_layers.append({
		"a": a,
		"b": b,
		"speed": speed_px,
		"width": float(strip_w),
		"offset": float(idx * 137),
		"base_color": night_col,
		"blood_color": blood_col,
	})


## Generates a tileable procedural pixel-art cloud bank using ordered 2x2 Bayer dithering.
func _generate_dithered_cloud_strip(w: int, h: int, seed_val: int, layer_idx: int) -> ImageTexture:
	var img: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var crng: RandomNumberGenerator = RandomNumberGenerator.new()
	crng.seed = seed_val
	var puffs: Array[Dictionary] = []
	var count: int = 11 + layer_idx * 3
	for _i in range(count):
		puffs.append({
			"cx": crng.randf_range(0.0, float(w)),
			"cy": crng.randf_range(24.0, float(h) - 22.0),
			"rx": crng.randf_range(34.0, 68.0),
			"ry": crng.randf_range(12.0, 22.0),
		})

	var bayer: Array[float] = [0.0, 0.5, 0.75, 0.25]
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var density: float = 0.0
			for p in puffs:
				var dx: float = absf(float(x) - float(p["cx"]))
				dx = minf(dx, float(w) - dx)
				var dy: float = absf(float(y) - float(p["cy"]))
				var nx: float = dx / float(p["rx"])
				var ny: float = dy / float(p["ry"])
				var d: float = 1.0 - (nx * nx + ny * ny)
				if d > density:
					density = d
			if density <= 0.04:
				continue
			var thresh: float = bayer[((y >> 1) & 1) * 2 + ((x >> 1) & 1)]
			var col: Color = Color(0.0, 0.0, 0.0, 0.0)
			if density > 0.52:
				col = Color(0.92, 0.92, 0.96, 1.0)
			elif density > 0.26 + thresh * 0.24:
				col = Color(0.76, 0.76, 0.84, 0.95)
			elif density > 0.06 + thresh * 0.22:
				col = Color(0.58, 0.58, 0.68, 0.78)
			if col.a > 0.01:
				for oy in range(2):
					for ox in range(2):
						if x + ox < w and y + oy < h:
							img.set_pixel(x + ox, y + oy, col)

	return ImageTexture.create_from_image(img)


func _build_horizon_silhouette() -> void:
	if ResourceLoader.exists("res://assets/sky/horizon_silhouette.png"):
		var custom_sil: TextureRect = TextureRect.new()
		custom_sil.texture = load("res://assets/sky/horizon_silhouette.png") as Texture2D
		custom_sil.position = Vector2.ZERO
		custom_sil.size = Vector2(_view_size.x, 68.0)
		custom_sil.stretch_mode = TextureRect.STRETCH_SCALE
		custom_sil.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_silhouette.add_child(custom_sil)
		return
	var dark: Color = Color(0.04, 0.03, 0.06, 1.0)
	var ground: ColorRect = ColorRect.new()
	ground.position = Vector2(0.0, 42.0)
	ground.size = Vector2(_view_size.x, 26.0)
	ground.color = dark
	_silhouette.add_child(ground)

	# Stylized farmhouse roofline in the center.
	var cx: float = floorf(_view_size.x * 0.5)
	var body: ColorRect = ColorRect.new()
	body.position = Vector2(cx - 28.0, 20.0)
	body.size = Vector2(56.0, 24.0)
	body.color = dark
	_silhouette.add_child(body)

	var roof: Polygon2D = Polygon2D.new()
	roof.polygon = PackedVector2Array([
		Vector2(cx - 34.0, 22.0), Vector2(cx, 4.0), Vector2(cx + 34.0, 22.0)
	])
	roof.color = dark
	_silhouette.add_child(roof)

	# Warm glowing farmhouse windows in the silhouette.
	for wx in [cx - 16.0, cx + 10.0]:
		var win: ColorRect = ColorRect.new()
		win.position = Vector2(wx, 28.0)
		win.size = Vector2(6.0, 6.0)
		win.color = Color(0.98, 0.74, 0.34, 0.95)
		_silhouette.add_child(win)

	# Tree-line silhouettes left and right of the farmhouse.
	var trng: RandomNumberGenerator = RandomNumberGenerator.new()
	trng.seed = 808
	for x in range(10, int(_view_size.x) - 10, 24):
		if absf(float(x) - cx) < 52.0:
			continue
		var h: float = trng.randf_range(16.0, 32.0)
		var tree: Polygon2D = Polygon2D.new()
		tree.polygon = PackedVector2Array([
			Vector2(float(x) - 10.0, 44.0),
			Vector2(float(x), 44.0 - h),
			Vector2(float(x) + 10.0, 44.0),
		])
		tree.color = dark
		_silhouette.add_child(tree)
