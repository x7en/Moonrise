class_name MoonSky
extends Control

# night sky backdrop shared by the title screen and moonrise cutscene

var is_blood_mode: bool = false
var red_blend: float = 0.0
var moon_progress: float = 1.0  # 0 = hidden under horizon, 1 = up in the sky
var cloud_speed_scale: float = 1.0

var _sky_top: ColorRect
var _sky_mid: ColorRect
var _sky_low: ColorRect
var _stars: Array[Dictionary] = []
var _moon_holder: Control
var _moon_base: TextureRect
var _moon_red: TextureRect
var _moon_glow: TextureRect
var _cloud_layers: Array[Dictionary] = []
var _silhouette: Control
var _time: float = 0.0
var _view_size: Vector2 = Vector2(640.0, 360.0)


func build(view_size: Vector2 = Config.VIEW_SIZE) -> void:
	_view_size = view_size
	position = Vector2.ZERO
	size = view_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# lazy 3-band sky instead of writing a gradient shader lol
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

	# fixed seed so stars dont jump around between title & cutscenes
	var srng := RandomNumberGenerator.new()
	srng.seed = 4207
	for _i in range(52):
		var star := ColorRect.new()
		var sz := 2.0 if srng.randf() < 0.25 else 1.0
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

	# back clouds sit behind the moon
	_add_cloud_layer(0, 6.0, 26.0)

	# 32x32 moon scaled 4x to 128x128, red version fades in on top during blood moon
	_moon_holder = Control.new()
	_moon_holder.size = Vector2(128.0, 128.0)
	add_child(_moon_holder)

	_moon_glow = TextureRect.new()
	_moon_glow.position = Vector2(-42.0, -42.0)
	_moon_glow.size = Vector2(212.0, 212.0)
	_moon_glow.texture = Art.get_radial_light_texture(128)
	_moon_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_moon_glow.modulate = Config.EVEN_MOON_GLOW
	_moon_holder.add_child(_moon_glow)

	# secondary moon ("Even Moon") tinted deep crimson; distinct from bright scarlet Red Moon
	_moon_base = TextureRect.new()
	_moon_base.position = Vector2.ZERO
	_moon_base.size = Vector2(128.0, 128.0)
	_moon_base.stretch_mode = TextureRect.STRETCH_SCALE
	_moon_base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_moon_base.modulate = Config.EVEN_MOON_COLOR
	_moon_holder.add_child(_moon_base)

	_moon_red = TextureRect.new()
	_moon_red.position = Vector2.ZERO
	_moon_red.size = Vector2(128.0, 128.0)
	_moon_red.stretch_mode = TextureRect.STRETCH_SCALE
	_moon_red.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_moon_red.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_moon_holder.add_child(_moon_red)

	# front clouds drift across the moon
	_add_cloud_layer(1, 14.0, 74.0)
	_add_cloud_layer(2, 24.0, 118.0)

	_silhouette = Control.new()
	_silhouette.position = Vector2(0.0, view_size.y - 68.0)
	_silhouette.size = Vector2(view_size.x, 68.0)
	add_child(_silhouette)
	_build_horizon_silhouette()

	configure_for_night(1, false)
	update_sky(0.0)


func configure_for_night(
	_night_num: int,
	is_blood: bool,
	start_white_turn_red: bool = false
) -> void:
	is_blood_mode = is_blood
	if _moon_base != null:
		_moon_base.texture = Art.tex("sky/moon")
	if _moon_red != null:
		_moon_red.texture = Art.tex("sky/blood_moon")
	red_blend = 1.0 if (is_blood and not start_white_turn_red) else 0.0


func update_sky(delta: float) -> void:
	_time += delta

	if _sky_top != null:
		_sky_top.color = Color(0.04, 0.04, 0.11).lerp(Color(0.16, 0.01, 0.03), red_blend)
	if _sky_mid != null:
		_sky_mid.color = Color(0.08, 0.06, 0.16).lerp(Color(0.36, 0.02, 0.05), red_blend)
	if _sky_low != null:
		_sky_low.color = Color(0.13, 0.09, 0.18).lerp(Color(0.56, 0.04, 0.07), red_blend)

	for s in _stars:
		var node = s["node"]
		var pulse := 0.45 + 0.55 * sin(_time * float(s["spd"]) + float(s["phase"]))
		node.modulate.a = pulse * (1.0 - red_blend * 0.45)

	# ease out cubic so the moon slows down nicely near the top
	if _moon_holder != null:
		var start_y := _view_size.y - 36.0
		var end_y := 42.0
		var eased := 1.0 - pow(1.0 - clampf(moon_progress, 0.0, 1.0), 3.0)
		_moon_holder.position = Vector2(
			floorf(_view_size.x * 0.5 - 64.0),
			floorf(lerpf(start_y, end_y, eased))
		)

	var red_a := clampf(red_blend, 0.0, 1.0)
	if _moon_base != null:
		var even_c := Config.EVEN_MOON_COLOR
		_moon_base.modulate = Color(even_c.r, even_c.g, even_c.b, 1.0 - red_a)

	if _moon_red != null:
		var pulse_r := 1.18 + 0.10 * sin(_time * 2.4)
		_moon_red.modulate = Color(pulse_r, 0.86, 0.72, red_a)

	if _moon_glow != null:
		var glow_pulse := 0.56 + 0.14 * sin(_time * 2.4)
		_moon_glow.modulate = Config.EVEN_MOON_GLOW.lerp(
			Color(1.0, 0.16, 0.08, glow_pulse), red_a
		)

	for layer in _cloud_layers:
		var spd := float(layer["speed"]) * cloud_speed_scale
		var w := float(layer["width"])
		var a = layer["a"]
		var b = layer["b"]
		var x := fposmod(float(layer["offset"]) + _time * spd, w)

		a.position.x = floorf(-x)
		b.position.x = floorf(w - x)

		var tint = layer["base_color"].lerp(layer["blood_color"], red_blend)
		a.modulate = tint
		b.modulate = tint


func _add_cloud_layer(idx: int, speed_px: float, y_pos: float) -> void:
	var strip_w := int(_view_size.x)
	var strip_h := 86
	var cloud_tex := Art.tex("sky/clouds_%d" % (clampi(idx, 0, 2) + 1))

	var a := TextureRect.new()
	a.texture = cloud_tex
	a.position = Vector2(0.0, y_pos)
	a.size = Vector2(float(strip_w), float(strip_h))
	a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(a)

	var b := TextureRect.new()
	b.texture = cloud_tex
	b.position = Vector2(float(strip_w), y_pos)
	b.size = Vector2(float(strip_w), float(strip_h))
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(b)

	# tuned by eye so the white cloud art looks moody instead of pitch black
	var shade = [0.46, 0.54, 0.36][clampi(idx, 0, 2)]
	var night_col := Color(shade * 0.85, shade * 0.84, shade * 1.15, 0.88)
	var blood_col := Color(shade * 1.68, shade * 0.18, shade * 0.20, 0.94)

	_cloud_layers.append({
		"a": a,
		"b": b,
		"speed": speed_px,
		"width": float(strip_w),
		"offset": float(idx * 137),
		"base_color": night_col,
		"blood_color": blood_col,
	})


func _build_horizon_silhouette() -> void:
	var dark := Color(0.04, 0.03, 0.06, 1.0)

	var ground := ColorRect.new()
	ground.position = Vector2(0.0, 42.0)
	ground.size = Vector2(_view_size.x, 26.0)
	ground.color = dark
	_silhouette.add_child(ground)

	# little farmhouse cutout in the middle
	var cx := floorf(_view_size.x * 0.5)
	var body := ColorRect.new()
	body.position = Vector2(cx - 28.0, 20.0)
	body.size = Vector2(56.0, 24.0)
	body.color = dark
	_silhouette.add_child(body)

	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([
		Vector2(cx - 34.0, 22.0), Vector2(cx, 4.0), Vector2(cx + 34.0, 22.0)
	])
	roof.color = dark
	_silhouette.add_child(roof)

	for wx in [cx - 16.0, cx + 10.0]:
		var win := ColorRect.new()
		win.position = Vector2(wx, 28.0)
		win.size = Vector2(6.0, 6.0)
		win.color = Color(0.98, 0.74, 0.34, 0.95)
		_silhouette.add_child(win)

	var trng := RandomNumberGenerator.new()
	trng.seed = 808
	for x in range(10, int(_view_size.x) - 10, 24):
		if absf(float(x) - cx) < 52.0:
			continue
		var h := trng.randf_range(16.0, 32.0)
		var tree := Polygon2D.new()
		tree.polygon = PackedVector2Array([
			Vector2(float(x) - 10.0, 44.0),
			Vector2(float(x), 44.0 - h),
			Vector2(float(x) + 10.0, 44.0),
		])
		tree.color = dark
		_silhouette.add_child(tree)
