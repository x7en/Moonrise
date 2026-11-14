class_name HouseArt
extends RefCounted
## Generates crisp 3/4 oblique 2D-with-3D-depth pixel art for the Homestead Farmhouse
## (112x96 px: pitched shingled roof, cross-gable truss, 3D stone chimney, glowing windows,
## timber framing, stone foundation, 2-tier steps, and Lv 1-3 fortification progression).
## Automatically loads user-provided drop-in PNGs if placed at:
##   res://assets/structures/house_lv1.png (or house_lv2.png, house_lv3.png, house_custom.png)
##   res://assets/structures/house_lv1_open.png (optional open-door variant)

const WIDTH := 112
const HEIGHT := 96
const DOOR_LOCAL_X := 52.0  # Door center X in texture space (-4 px from sprite center 56)

static var _cache: Dictionary = {}


static func get_house_texture(level: int = 1, door_open: bool = false) -> Texture2D:
	var lv: int = clampi(level, 1, 3)
	var key: String = "lv%d_%s" % [lv, "open" if door_open else "closed"]
	if _cache.has(key):
		return _cache[key] as Texture2D

	# Check for custom user-provided 3/4 house PNG drop-ins first.
	var candidates: Array[String] = []
	if door_open:
		candidates.append("res://assets/structures/house_lv%d_open.png" % lv)
		candidates.append("res://assets/structures/house_custom_open.png")
	candidates.append("res://assets/structures/house_lv%d.png" % lv)
	candidates.append("res://assets/structures/house_custom.png")
	for p in candidates:
		if ResourceLoader.exists(p):
			var loaded: Texture2D = load(p) as Texture2D
			if loaded != null:
				_cache[key] = loaded
				return loaded

	var tex: ImageTexture = _build_procedural_house(lv, door_open)
	_cache[key] = tex
	return tex


static func get_house_silhouette(fill_color: Color) -> ImageTexture:
	var key: String = "sil_%s" % fill_color.to_html()
	if _cache.has(key):
		return _cache[key] as ImageTexture
	var base: Image = get_house_texture(1, false).get_image()
	if base.is_compressed():
		base.decompress()
	if base.get_format() != Image.FORMAT_RGBA8:
		base.convert(Image.FORMAT_RGBA8)
	var out: Image = Image.create_empty(base.get_width(), base.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(base.get_height()):
		for x in range(base.get_width()):
			var c: Color = base.get_pixel(x, y)
			if c.a > 0.05:
				out.set_pixel(x, y, Color(fill_color.r, fill_color.g, fill_color.b, c.a * fill_color.a))
	var res: ImageTexture = ImageTexture.create_from_image(out)
	_cache[key] = res
	return res


static func _build_procedural_house(level: int, door_open: bool) -> ImageTexture:
	var img: Image = Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	var out_c: Color = Color(0.14, 0.09, 0.11, 1.0)

	# Roof palette shifts toward fortified slate-steel at Level 3.
	var roof_hi: Color = Color(0.75, 0.37, 0.25, 1.0)
	var roof_mid: Color = Color(0.64, 0.29, 0.19, 1.0)
	var roof_dk: Color = Color(0.51, 0.21, 0.14, 1.0)
	var roof_seam: Color = Color(0.39, 0.16, 0.12, 1.0)
	if level >= 3:
		roof_hi = Color(0.45, 0.50, 0.60, 1.0)
		roof_mid = Color(0.34, 0.39, 0.48, 1.0)
		roof_dk = Color(0.25, 0.29, 0.38, 1.0)
		roof_seam = Color(0.18, 0.21, 0.28, 1.0)

	var wood_hi: Color = Color(0.76, 0.45, 0.26, 1.0)
	var wood_mid: Color = Color(0.61, 0.33, 0.18, 1.0)
	var wood_dk: Color = Color(0.40, 0.21, 0.12, 1.0)
	var wall_lt: Color = Color(0.96, 0.85, 0.66, 1.0)
	var wall_sh: Color = Color(0.84, 0.68, 0.49, 1.0)
	var stone_hi: Color = Color(0.66, 0.70, 0.78, 1.0)
	var stone_mid: Color = Color(0.51, 0.55, 0.65, 1.0)
	var stone_dk: Color = Color(0.34, 0.37, 0.46, 1.0)

	# 1. Soft grounded shadow under the house base.
	_fill_rect(img, 10, 86, 104, 92, Color(0.10, 0.16, 0.08, 0.36))

	# 2. Front vertical wall facade (3/4 oblique vertical face) + stone foundation.
	_fill_rect(img, 12, 57, 102, 82, wall_lt)
	# Roof overhang cast shadow across top of facade wall (creates strong 3D depth!).
	_fill_rect(img, 12, 57, 102, 62, wall_sh)
	# Subtle side ambient shading on right wing and wall edges.
	_fill_rect(img, 12, 62, 16, 82, wall_sh)
	_fill_rect(img, 98, 62, 102, 82, wall_sh)

	# Stone masonry foundation along base (y = 81..87).
	_fill_rect(img, 11, 81, 103, 88, stone_mid)
	for sx in range(12, 102):
		img.set_pixel(sx, 81, out_c)
		img.set_pixel(sx, 87, out_c)
		img.set_pixel(sx, 82, stone_hi if ((sx + 1) % 9 != 0) else stone_dk)
		if sx % 9 == 0:
			img.set_pixel(sx, 83, stone_dk)
			img.set_pixel(sx, 84, stone_dk)
		if (sx + 4) % 9 == 0:
			img.set_pixel(sx, 85, stone_dk)
			img.set_pixel(sx, 86, stone_dk)
		img.set_pixel(sx, 84, stone_dk if sx % 2 == 0 else stone_mid)
	for sy in range(57, 88):
		img.set_pixel(11, sy, out_c)
		img.set_pixel(102, sy, out_c)

	# 3. Structural timber posts framing the facade bays + top beam under eaves.
	_draw_beam_h(img, 12, 102, 57, 60, wood_mid, wood_dk, out_c)
	for post_x in [12, 37, 63, 81, 99]:
		_draw_beam_v(img, post_x, post_x + 3, 58, 81, wood_hi, wood_mid, out_c)

	# 4. Three glowing warm cottage windows with beveled dark outline & wooden sills.
	_draw_window(img, 19, 65, 13, 12, level, wood_mid, out_c)
	_draw_window(img, 68, 65, 11, 12, level, wood_mid, out_c)
	_draw_window(img, 86, 65, 11, 12, level, wood_mid, out_c)

	# 5. Front wooden door (centered at x = 52) + 2-tier stone front porch steps!
	_draw_door(img, 44, 62, 16, 19, level, door_open, out_c)
	_draw_porch_steps(img, 42, 81, 20, stone_hi, stone_mid, stone_dk, out_c)

	# 6. Main pitched shingled roof (asymmetric L-gable, peak at x=46, y=6).
	# Right lower wing roof (x=66..105, y=34..58) drawn first so main slope overlaps cleanly.
	for y in range(34, 58):
		for x in range(66, 105):
			var col: Color = _shingle_color(x, y, 34, roof_hi, roof_mid, roof_dk, roof_seam)
			if y >= 55:
				col = roof_seam
			img.set_pixel(x, y, col)
	for x in range(66, 106):
		img.set_pixel(x, 33, out_c)
		img.set_pixel(x, 57, out_c)
	for y in range(33, 58):
		img.set_pixel(105, y, out_c)

	# Main tall triangular pitched roof (ridge peak at x=46, y=6; slopes down to x=7 and x=78).
	for y in range(6, 58):
		var dy: int = y - 6
		var left_x: int = maxi(7, 46 - dy)
		var right_x: int = mini(78, 46 + dy)
		if y > 45:
			left_x = 7
		for x in range(left_x, right_x + 1):
			var col: Color = _shingle_color(x, y, 6, roof_hi, roof_mid, roof_dk, roof_seam)
			var is_right_outline: bool = (x == right_x and y <= 34)
			if x == left_x or is_right_outline or y == 57:
				col = out_c
			elif x == right_x and y > 34:
				col = roof_seam  # Smooth valley join into right wing roof
			elif x == left_x + 1 or (y <= 8):
				col = roof_hi
			elif y >= 55:
				col = roof_seam
			img.set_pixel(x, y, col)
	# Crisp dark ridge-line outline along peak slopes.
	for dy in range(0, 40):
		_plot(img, 46 - dy, 6 + dy, out_c)
		if dy <= 28:
			_plot(img, 46 + dy, 6 + dy, out_c)
	for y in range(45, 58):
		_plot(img, 7, y, out_c)

	# 7. Front triangular porch cross-gable centered over the front door (peak at x=52, y=32).
	for y in range(33, 58):
		var half_w: int = y - 32
		var gx0: int = 52 - half_w
		var gx1: int = 52 + half_w
		for x in range(gx0, gx1 + 1):
			if x < 16 or x > 88:
				continue
			var dist_edge: int = mini(x - gx0, gx1 - x)
			if dist_edge == 0:
				_plot(img, x, y, out_c)
			elif dist_edge <= 2:
				_plot(img, x, y, wood_mid if dist_edge == 1 else wood_dk)
			elif dist_edge == 3:
				_plot(img, x, y, out_c)
			else:
				# Cream plaster inside the triangular gable truss!
				var plaster: Color = wall_sh if y < 40 else wall_lt
				# Vertical center king-post and horizontal tie-beam at y=47..49.
				if abs(x - 52) <= 1 or (y >= 47 and y <= 49):
					plaster = wood_hi if (x == 51 or y == 47) else wood_mid
				elif abs(abs(x - 52) - (47 - y)) <= 1 and y < 48 and y > 37:
					plaster = wood_mid
				_plot(img, x, y, plaster)
	# Gable base horizontal beam aligned flush with the cross-gable eaves.
	_draw_beam_h(img, 27, 78, 56, 59, wood_hi, wood_dk, out_c)

	# 8. 3D Stone Chimney rising from the left roof slope (x=15..29, y=13..46).
	_draw_chimney(img, 16, 13, 14, 34, stone_hi, stone_mid, stone_dk, out_c)

	# 9. Level 2 & 3 visible fortification reinforcements (iron brackets, rivets, lantern).
	if level >= 2:
		var iron_hi: Color = Color(0.70, 0.74, 0.82, 1.0)
		var iron_dk: Color = Color(0.36, 0.40, 0.48, 1.0)
		for rx in range(28, 76, 8):
			_fill_rect(img, rx, 56, rx + 3, 59, iron_hi)
			_plot(img, rx + 1, 57, iron_dk)
		for by in [63, 74]:
			_fill_rect(img, 12, by, 16, by + 2, iron_hi)
			_fill_rect(img, 98, by, 102, by + 2, iron_hi)
	if level >= 3:
		# Glowing wrought-iron porch lantern above door.
		_fill_rect(img, 50, 58, 54, 62, out_c)
		_fill_rect(img, 51, 59, 53, 61, Color(1.0, 0.90, 0.48, 1.0))

	# 10. Cute pixel grass blades hugging the stone base + stepping stones below steps.
	var grass_d: Color = Color(0.24, 0.48, 0.18, 1.0)
	var grass_l: Color = Color(0.38, 0.68, 0.25, 1.0)
	for gx in [14, 16, 33, 35, 67, 69, 94, 96]:
		_plot(img, gx, 86, grass_l)
		_plot(img, gx, 87, grass_d)
		_plot(img, gx + 1, 87, grass_l)

	# Stepping stone pavers directly below the porch stairs.
	_draw_stone_pad(img, 47, 90, 5, 4, stone_hi, stone_mid, out_c)
	_draw_stone_pad(img, 54, 92, 4, 3, stone_hi, stone_mid, out_c)

	return ImageTexture.create_from_image(img)


static func _shingle_color(
	x: int,
	y: int,
	top_y: int,
	hi: Color,
	mid: Color,
	dk: Color,
	seam: Color
) -> Color:
	# Vertical wooden board / shingle planks with staggered horizontal step seams (Image 2 style).
	var col_idx: int = int(floorf(float(x) / 6.0))
	if x % 6 == 0:
		return seam
	var stagger: int = (col_idx % 2) * 5
	if (y - top_y + stagger) % 10 == 0:
		return seam
	var rel: int = x % 6
	if rel == 1:
		return hi if (col_idx % 3 != 0) else mid
	if rel == 5:
		return dk
	return mid if ((col_idx + int(floorf(float(y) / 10.0))) % 2 == 0) else hi.lerp(mid, 0.55)


static func _draw_chimney(
	img: Image,
	x0: int,
	y0: int,
	w: int,
	h: int,
	hi: Color,
	mid: Color,
	dk: Color,
	out_c: Color
) -> void:
	# Chimney shaft (brick courses).
	for y in range(y0 + 10, y0 + h):
		for x in range(x0 + 1, x0 + w - 1):
			var c: Color = mid
			if x == x0 + 1 or x == x0 + w - 2 or y == y0 + h - 1:
				c = out_c
			elif x <= x0 + 3:
				c = hi
			elif x >= x0 + w - 4:
				c = dk
			var row_off: int = (int(floorf(float(y) / 4.0)) % 2) * 3
			if y % 4 == 0 or (x + row_off) % 6 == 0:
				if c != out_c:
					c = dk
			_plot(img, x, y, c)
	# Chimney crown (wider 3D rim with dark flue cavity on top!).
	for y in range(y0, y0 + 11):
		for x in range(x0 - 1, x0 + w + 1):
			var edge: bool = (x == x0 - 1 or x == x0 + w or y == y0 or y == y0 + 10)
			if edge:
				_plot(img, x, y, out_c)
			elif x >= x0 + 2 and x <= x0 + w - 3 and y >= y0 + 2 and y <= y0 + 6:
				_plot(img, x, y, Color(0.09, 0.08, 0.11, 1.0))  # Deep black chimney opening
			elif y <= y0 + 2 or x <= x0 + 1:
				_plot(img, x, y, hi)
			elif y >= y0 + 8:
				_plot(img, x, y, dk)
			else:
				_plot(img, x, y, mid)


static func _draw_window(
	img: Image,
	x0: int,
	y0: int,
	w: int,
	h: int,
	level: int,
	sill_col: Color,
	out_c: Color
) -> void:
	var glass_hi: Color = Color(1.0, 0.96, 0.62, 1.0)
	var glass_mid: Color = Color(1.0, 0.87, 0.38, 1.0)
	var glass_lo: Color = Color(0.95, 0.72, 0.28, 1.0)
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var is_corner: bool = (
				(x == x0 or x == x0 + w - 1) and (y == y0)
			)
			if is_corner:
				continue
			var border: bool = (
				x == x0 or x == x0 + w - 1 or y == y0 or y == y0 + h - 1
				or ((x == x0 + 1 or x == x0 + w - 2) and y == y0 + 1)
			)
			if border:
				_plot(img, x, y, out_c)
			elif y == y0 + h - 2:
				_plot(img, x, y, sill_col)
			elif y <= y0 + 4:
				_plot(img, x, y, glass_hi)
			elif y <= y0 + 8:
				_plot(img, x, y, glass_mid)
			else:
				_plot(img, x, y, glass_lo)
	# Wooden bottom sill extending 1px on each side.
	_fill_rect(img, x0 - 1, y0 + h - 1, x0 + w + 1, y0 + h + 1, out_c)
	_fill_rect(img, x0, y0 + h - 1, x0 + w, y0 + h, sill_col)
	# Level 2+ dark shutter strips flanking the window.
	if level >= 2:
		var shut: Color = Color(0.32, 0.36, 0.44, 1.0) if level >= 3 else Color(0.45, 0.26, 0.16, 1.0)
		_fill_rect(img, x0 - 2, y0 + 1, x0, y0 + h - 1, shut)
		_fill_rect(img, x0 + w, y0 + 1, x0 + w + 2, y0 + h - 1, shut)


static func _draw_door(
	img: Image,
	x0: int,
	y0: int,
	w: int,
	h: int,
	level: int,
	door_open: bool,
	out_c: Color
) -> void:
	var door_lt: Color = Color(0.47, 0.30, 0.24, 1.0)
	var door_dk: Color = Color(0.35, 0.21, 0.17, 1.0)
	var frame_c: Color = Color(0.55, 0.31, 0.18, 1.0)
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var is_out: bool = (x == x0 or x == x0 + w - 1 or y == y0)
			var is_trim: bool = (x == x0 + 1 or x == x0 + w - 2 or y == y0 + 1)
			if is_out:
				_plot(img, x, y, out_c)
			elif is_trim:
				_plot(img, x, y, frame_c)
			elif door_open:
				# Dark open interior with swung-in door leaf on left edge.
				var col: Color = Color(0.09, 0.06, 0.10, 1.0)
				if x <= x0 + 4:
					col = door_dk if x == x0 + 4 else door_lt
				_plot(img, x, y, col)
			else:
				var col: Color = door_dk if ((x - x0) % 4 == 0) else door_lt
				if y >= y0 + 4 and y <= y0 + 6 and x >= x0 + 4 and x <= x0 + w - 5:
					col = Color(0.16, 0.12, 0.15, 1.0)  # Recessed door peephole window
				if level >= 2 and (y == y0 + 10 or y == y0 + 15):
					col = Color(0.46, 0.50, 0.58, 1.0)  # Iron reinforcement straps
				_plot(img, x, y, col)
	if not door_open:
		_plot(img, x0 + w - 4, y0 + 11, Color(0.95, 0.80, 0.34, 1.0))  # Brass knob
		_plot(img, x0 + w - 4, y0 + 12, Color(0.72, 0.54, 0.20, 1.0))


static func _draw_porch_steps(
	img: Image,
	x0: int,
	y0: int,
	w: int,
	hi: Color,
	mid: Color,
	dk: Color,
	out_c: Color
) -> void:
	# Top stone step (y0..y0+3) & wider bottom stone step (y0+4..y0+7).
	for step_i in range(2):
		var sx0: int = x0 - step_i
		var sx1: int = x0 + w + step_i
		var sy0: int = y0 + step_i * 4
		for y in range(sy0, sy0 + 4):
			for x in range(sx0, sx1):
				if x == sx0 or x == sx1 - 1 or y == sy0 or y == sy0 + 3:
					_plot(img, x, y, out_c)
				elif y == sy0 + 1:
					_plot(img, x, y, hi)
				else:
					_plot(img, x, y, mid if x % 5 != 0 else dk)


static func _draw_stone_pad(
	img: Image, x0: int, y0: int, w: int, h: int, hi: Color, mid: Color, out_c: Color
) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if x == x0 or x == x0 + w - 1 or y == y0 or y == y0 + h - 1:
				_plot(img, x, y, out_c)
			else:
				_plot(img, x, y, hi if y == y0 + 1 else mid)


static func _draw_beam_h(
	img: Image, x0: int, x1: int, y0: int, y1: int, lt: Color, dk: Color, out_c: Color
) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			if y == y0 or y == y1 - 1:
				_plot(img, x, y, out_c)
			else:
				_plot(img, x, y, lt if y == y0 + 1 else dk)


static func _draw_beam_v(
	img: Image, x0: int, x1: int, y0: int, y1: int, lt: Color, dk: Color, out_c: Color
) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			if x == x0 or x == x1 - 1:
				_plot(img, x, y, out_c)
			else:
				_plot(img, x, y, lt if x == x0 + 1 else dk)


static func _fill_rect(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	for y in range(maxi(0, y0), mini(HEIGHT, y1)):
		for x in range(maxi(0, x0), mini(WIDTH, x1)):
			img.set_pixel(x, y, col)


static func _plot(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT:
		img.set_pixel(x, y, col)
