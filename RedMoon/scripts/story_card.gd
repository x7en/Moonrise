class_name StoryCard
extends CanvasLayer
## Reusable full-screen overlay for Title, Story Cards 1-5, Game Over, and Ending.

signal advance_requested()
signal retry_requested()

enum Mode { NONE, TITLE, STORY, LOST, WON }

var mode: Mode = Mode.NONE

var _root: Control = null
var _diorama_border: ColorRect = null
var _diorama: Control = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _story_label: Label = null
var _prompt_label: Label = null
var _credits_label: Label = null

var _input_lock: float = 0.0
var _blink_time: float = 0.0
var _moon_tex: ImageTexture = null


func _ready() -> void:
	name = "StoryCard"
	layer = 10

	_moon_tex = _make_red_moon_texture(36)

	_root = Control.new()
	_root.name = "Root"
	_root.position = Vector2.ZERO
	_root.size = Config.VIEW_SIZE
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg: ColorRect = ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Config.VIEW_SIZE
	bg.color = Color(0.02, 0.02, 0.03, 1.0)
	_root.add_child(bg)

	_diorama_border = ColorRect.new()
	_diorama_border.position = Vector2(109.0, 41.0)
	_diorama_border.size = Vector2(262.0, 128.0)
	_diorama_border.color = Color(0.28, 0.22, 0.24, 1.0)
	_root.add_child(_diorama_border)

	_diorama = Control.new()
	_diorama.position = Vector2(110.0, 42.0)
	_diorama.size = Vector2(260.0, 126.0)
	_diorama.clip_contents = true
	_root.add_child(_diorama)

	_title_label = _make_label(
		"",
		Vector2(0.0, 10.0),
		Vector2(480.0, 30.0),
		18,
		Color(0.92, 0.22, 0.22)
	)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_title_label)

	_subtitle_label = _make_label(
		"",
		Vector2(0.0, 174.0),
		Vector2(480.0, 18.0),
		11,
		Color(0.88, 0.88, 0.92)
	)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_subtitle_label)

	_story_label = _make_label(
		"",
		Vector2(28.0, 178.0),
		Vector2(424.0, 38.0),
		9,
		Color(0.96, 0.94, 0.9)
	)
	_story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_story_label)

	_prompt_label = _make_label(
		"",
		Vector2(0.0, 224.0),
		Vector2(480.0, 16.0),
		8,
		Color(0.82, 0.84, 0.9)
	)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_prompt_label)

	_credits_label = _make_label(
		"Art: Post-Apocalyptic Pixel Art Asset Pack by TheLazyStone",
		Vector2(0.0, 252.0),
		Vector2(480.0, 14.0),
		8,
		Color(0.58, 0.58, 0.64)
	)
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_credits_label)

	hide_card()


func _process(delta: float) -> void:
	if not visible:
		return
	var real_dt: float = delta / maxf(Engine.time_scale, 0.01)
	if _input_lock > 0.0:
		_input_lock = maxf(0.0, _input_lock - real_dt)
	_blink_time += real_dt
	var pulse: float = 0.55 + 0.45 * sin(_blink_time * 4.2)
	_prompt_label.modulate.a = pulse


func _unhandled_input(event: InputEvent) -> void:
	if not visible or mode == Mode.NONE or _input_lock > 0.0:
		return
	if not (event is InputEventKey):
		return
	var key_ev: InputEventKey = event as InputEventKey
	if not key_ev.pressed or key_ev.echo:
		return

	var code: Key = key_ev.physical_keycode
	if code == KEY_NONE:
		code = key_ev.keycode

	# Ignore pure modifier keys, mute key, and debug function keys.
	if code in [
		KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK,
		KEY_M, KEY_F1, KEY_F2, KEY_F3, KEY_F4
	]:
		return

	if mode == Mode.LOST:
		if code in [KEY_R, KEY_ENTER, KEY_KP_ENTER]:
			get_viewport().set_input_as_handled()
			retry_requested.emit()
		return

	get_viewport().set_input_as_handled()
	advance_requested.emit()


func hide_card() -> void:
	visible = false
	mode = Mode.NONE


func show_title() -> void:
	mode = Mode.TITLE
	_input_lock = 0.25
	_blink_time = 0.0
	visible = true

	_title_label.text = "RED MOON"
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.2, 0.22))
	_title_label.visible = true

	_subtitle_label.text = "Bounce Back"
	_subtitle_label.visible = true

	_story_label.visible = false
	_prompt_label.text = "Press any key to start"
	_credits_label.visible = true

	_build_diorama_title()


func show_story(card_id: int) -> void:
	mode = Mode.WON if card_id == 5 else Mode.STORY
	_input_lock = 0.28
	_blink_time = 0.0
	visible = true

	_title_label.visible = (card_id == 3 or card_id == 5)
	if card_id == 3:
		_title_label.text = "RED MOON  -  Bounce Back"
		_title_label.add_theme_font_size_override("font_size", 14)
		_title_label.add_theme_color_override("font_color", Color(0.9, 0.32, 0.28))
	elif card_id == 5:
		_title_label.text = "VICTORY"
		_title_label.add_theme_font_size_override("font_size", 18)
		_title_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.44))

	_subtitle_label.visible = false
	_story_label.visible = true
	_credits_label.visible = false

	match card_id:
		1:
			_story_label.text = "Our village was quiet."
			_prompt_label.text = "Press any key"
			_build_diorama_card1()
		2:
			_story_label.text = "Then the king's army came and burned it all."
			_prompt_label.text = "Press any key"
			_build_diorama_card2()
		3:
			_story_label.text = "Only ruins are left. Night is coming."
			_prompt_label.text = "Press any key"
			_build_diorama_card3()
		4:
			_story_label.text = (
				"The zombies are gone. The silence is worse. "
				+ "The road out of the ruins is open."
			)
			_prompt_label.text = "Press any key"
			_build_diorama_card4()
		_:
			_story_label.text = "The house still stands. The king's castle is next."
			_prompt_label.text = "Press any key to return to title"
			_build_diorama_card5()


func show_lost(night_num: int) -> void:
	mode = Mode.LOST
	_input_lock = 0.35
	_blink_time = 0.0
	visible = true

	_title_label.text = "The house fell. Bounce back."
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.26, 0.26))
	_title_label.visible = true

	_subtitle_label.visible = false
	_story_label.visible = true
	_story_label.text = "Night %d failed. Your base will be restored to dusk." % night_num
	_prompt_label.text = "Press R or Enter to retry"
	_credits_label.visible = false

	_build_diorama_lost()


func _clear_diorama() -> void:
	for child in _diorama.get_children():
		child.queue_free()


func _add_rect(pos: Vector2, sz: Vector2, color: Color) -> ColorRect:
	var r: ColorRect = ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = color
	_diorama.add_child(r)
	return r


func _add_ground_strip(
	tile_key: String,
	y_start: float,
	rows: int,
	tint: Color = Color.WHITE
) -> void:
	var t: Texture2D = SpriteFactory.tex(tile_key)
	for row in range(rows):
		for col in range(17):
			var tr: TextureRect = TextureRect.new()
			tr.texture = t
			tr.position = Vector2(float(col * 16), y_start + float(row * 16))
			tr.size = Vector2(16.0, 16.0)
			tr.stretch_mode = TextureRect.STRETCH_KEEP
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.modulate = tint
			_diorama.add_child(tr)


func _add_sprite(key: String, pos: Vector2, tint: Color = Color.WHITE) -> TextureRect:
	var t: Texture2D = SpriteFactory.tex(key)
	var tr: TextureRect = TextureRect.new()
	tr.texture = t
	tr.position = pos
	tr.size = Vector2(float(t.get_width()), float(t.get_height()))
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.modulate = tint
	_diorama.add_child(tr)
	return tr


func _add_strip_frame(
	key: String,
	frame_idx: int,
	pos: Vector2,
	tint: Color = Color.WHITE
) -> TextureRect:
	var info: Array = SpriteData.ANIMATED.get(key, [1, 16, 16])
	var fw: int = int(info[1])
	var fh: int = int(info[2])
	var strip: Texture2D = SpriteFactory.tex(key)
	var tex_to_use: Texture2D = strip
	if strip.get_width() >= (frame_idx + 1) * fw and strip.get_height() >= fh:
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = strip
		atlas.region = Rect2(float(frame_idx * fw), 0.0, float(fw), float(fh))
		tex_to_use = atlas

	var tr: TextureRect = TextureRect.new()
	tr.texture = tex_to_use
	tr.position = pos
	tr.size = Vector2(float(fw), float(fh))
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.modulate = tint
	_diorama.add_child(tr)
	return tr


func _add_red_moon(pos: Vector2) -> void:
	var tr: TextureRect = TextureRect.new()
	tr.texture = _moon_tex
	tr.position = pos
	tr.size = Vector2(float(_moon_tex.get_width()), float(_moon_tex.get_height()))
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_diorama.add_child(tr)


func _build_diorama_title() -> void:
	_clear_diorama()
	_add_rect(Vector2.ZERO, Vector2(260.0, 82.0), Color(0.1, 0.03, 0.05, 1.0))
	_add_red_moon(Vector2(184.0, 10.0))
	_add_ground_strip("terrain/grass_0", 78.0, 3, Color(0.62, 0.34, 0.34))
	_add_sprite("nature/tree_6_pine_big_green", Vector2(18.0, 42.0), Color(0.55, 0.25, 0.26))
	_add_sprite("nature/tree_5_big_green", Vector2(212.0, 40.0), Color(0.55, 0.25, 0.26))
	_add_sprite("structures/house", Vector2(82.0, 26.0), Color(0.86, 0.45, 0.45))
	_add_strip_frame("player/idle_down", 0, Vector2(124.0, 100.0), Color(0.95, 0.72, 0.72))
	_add_strip_frame("enemies/zombie/walk_right", 0, Vector2(36.0, 96.0), Color(0.82, 0.38, 0.38))
	_add_strip_frame("enemies/zombie/walk_left", 0, Vector2(204.0, 98.0), Color(0.82, 0.38, 0.38))


func _build_diorama_card1() -> void:
	_clear_diorama()
	_add_rect(Vector2.ZERO, Vector2(260.0, 76.0), Color(0.46, 0.72, 0.88, 1.0))
	_add_ground_strip("terrain/grass_0", 74.0, 4, Color.WHITE)
	_add_sprite("nature/tree_7_birch_green", Vector2(14.0, 36.0))
	_add_sprite("nature/tree_6_pine_big_green", Vector2(212.0, 34.0))
	_add_sprite("nature/tree_3_normal_green", Vector2(186.0, 52.0))
	_add_sprite("structures/house", Vector2(82.0, 24.0))
	_add_sprite("nature/bush_2_green", Vector2(46.0, 96.0))
	_add_sprite("nature/bush_1_green", Vector2(194.0, 98.0))
	_add_strip_frame("player/idle_down", 0, Vector2(124.0, 102.0))


func _build_diorama_card2() -> void:
	_clear_diorama()
	var raid_tint: Color = Color(0.95, 0.4, 0.35)
	_add_rect(Vector2.ZERO, Vector2(260.0, 76.0), Color(0.42, 0.09, 0.08, 1.0))
	_add_ground_strip("terrain/wasteland_0", 74.0, 4, raid_tint)
	_add_sprite("nature/tree_2_spruce-sparse_green", Vector2(20.0, 50.0), raid_tint)
	_add_sprite("structures/house", Vector2(64.0, 24.0), Color(0.75, 0.28, 0.25))
	_add_sprite("structures/ruins/gray-brick_debris", Vector2(44.0, 96.0), raid_tint)
	_add_sprite("structures/ruins/metal-plates", Vector2(154.0, 98.0), raid_tint)
	_add_sprite("structures/ruins/iron-beam", Vector2(118.0, 112.0), raid_tint)
	_add_strip_frame("enemies/raider/walk_left", 0, Vector2(184.0, 86.0), Color(1.0, 0.55, 0.5))
	_add_strip_frame("enemies/raider/attack_left", 2, Vector2(212.0, 96.0), Color(1.0, 0.55, 0.5))


func _build_diorama_card3() -> void:
	_clear_diorama()
	var dusk_tint: Color = Config.TINT_DUSK
	_add_rect(Vector2.ZERO, Vector2(260.0, 76.0), Color(0.28, 0.19, 0.26, 1.0))
	_add_ground_strip("terrain/grass_1", 74.0, 4, dusk_tint)
	_add_sprite("nature/tree-trunk_2_grass_green", Vector2(20.0, 86.0), dusk_tint)
	_add_sprite("structures/house", Vector2(82.0, 24.0), dusk_tint)
	var dmg: TextureRect = TextureRect.new()
	dmg.texture = SpriteFactory.get_tinted_silhouette(
		"structures/house",
		Color(0.55, 0.0, 0.0, 0.35)
	)
	dmg.position = Vector2(82.0, 24.0)
	dmg.size = Vector2(96.0, 90.0)
	dmg.stretch_mode = TextureRect.STRETCH_KEEP
	dmg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_diorama.add_child(dmg)
	_add_sprite("structures/ruins/gray-brick_debris", Vector2(54.0, 102.0), dusk_tint)
	_add_sprite("structures/ruins/gray-brick_debris", Vector2(186.0, 96.0), dusk_tint)
	_add_sprite("props/barrel_rust_red_1", Vector2(218.0, 88.0), dusk_tint)
	_add_sprite("pickups_planks/pallet_2", Vector2(124.0, 108.0), dusk_tint)


func _build_diorama_card4() -> void:
	_clear_diorama()
	var dawn_tint: Color = Color(0.76, 0.82, 0.92)
	_add_rect(Vector2.ZERO, Vector2(260.0, 76.0), Color(0.24, 0.3, 0.4, 1.0))
	_add_ground_strip("terrain/wasteland_0", 74.0, 4, dawn_tint)
	_add_sprite("structures/house", Vector2(18.0, 26.0), dawn_tint)
	_add_sprite("nature/tree_1_spruce_green", Vector2(126.0, 52.0), dawn_tint)
	_add_sprite("props/container_3_gray_horizontal", Vector2(158.0, 62.0), dawn_tint)
	_add_sprite("vehicles/car_4_rust_red", Vector2(204.0, 92.0), dawn_tint)
	_add_sprite("pickups_planks/pallet_1", Vector2(142.0, 100.0), dawn_tint)
	_add_strip_frame("player/idle_right", 0, Vector2(106.0, 96.0), dawn_tint)


func _build_diorama_card5() -> void:
	_clear_diorama()
	var sunrise_tint: Color = Color(1.0, 0.9, 0.74)
	_add_rect(Vector2.ZERO, Vector2(260.0, 76.0), Color(0.66, 0.38, 0.24, 1.0))
	_add_ground_strip("terrain/grass_0", 74.0, 4, sunrise_tint)
	_add_sprite("nature/tree_5_big_green", Vector2(12.0, 30.0), sunrise_tint)
	_add_sprite("nature/tree_7_birch_green", Vector2(210.0, 36.0), sunrise_tint)
	_add_sprite("structures/house", Vector2(82.0, 22.0), sunrise_tint)
	for x_pos in [48.0, 64.0, 180.0, 196.0]:
		_add_sprite("structures/fence_reinforced/horizontal", Vector2(x_pos, 96.0), sunrise_tint)
	_add_strip_frame("player/idle_down", 0, Vector2(124.0, 100.0), sunrise_tint)


func _build_diorama_lost() -> void:
	_clear_diorama()
	var lost_tint: Color = Color(0.62, 0.25, 0.25)
	_add_rect(Vector2.ZERO, Vector2(260.0, 76.0), Color(0.14, 0.03, 0.04, 1.0))
	_add_red_moon(Vector2(112.0, 12.0))
	_add_ground_strip("terrain/wasteland_1", 74.0, 4, lost_tint)
	_add_sprite("structures/house", Vector2(82.0, 26.0), Color(0.45, 0.14, 0.14))
	_add_sprite("structures/ruins/gray-brick_debris", Vector2(68.0, 96.0), lost_tint)
	_add_sprite("structures/ruins/metal-plates", Vector2(120.0, 96.0), lost_tint)
	_add_sprite("structures/ruins/gray-brick_debris", Vector2(162.0, 98.0), lost_tint)
	_add_strip_frame("player/death_right", 5, Vector2(118.0, 108.0), Color(0.85, 0.55, 0.55))


func _make_red_moon_texture(diameter: int) -> ImageTexture:
	var img: Image = Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r: float = float(diameter) * 0.5 - 1.0
	var c: Vector2 = Vector2(float(diameter) * 0.5, float(diameter) * 0.5)
	for y in range(diameter):
		for x in range(diameter):
			var d: float = Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(c)
			if d <= r:
				var shade: float = clampf(1.0 - (d / r) * 0.35, 0.5, 1.0)
				img.set_pixel(x, y, Color(0.86 * shade, 0.14 * shade, 0.16 * shade, 1.0))
			elif d <= r + 1.2:
				img.set_pixel(x, y, Color(0.42, 0.05, 0.08, 0.7))
			else:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
	return ImageTexture.create_from_image(img)


func _make_label(
	text: String,
	pos: Vector2,
	sz: Vector2,
	font_size: int,
	color: Color
) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.size = sz
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	return lbl
