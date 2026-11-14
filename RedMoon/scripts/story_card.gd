class_name StoryCard
extends CanvasLayer
## Full-screen overlay for Title, Story Cards 1-5, Lose Screen, Ending, and Pause Menu.
## Uses PROCESS_MODE_ALWAYS so the Pause Menu remains responsive while the game tree is paused.

signal advance_requested()
signal retry_requested()
signal restart_run_requested()
signal resume_requested()
signal mute_requested()

enum Mode { NONE, TITLE, STORY, LOST, WON, PAUSED }

var mode: Mode = Mode.NONE

var _root: Control = null
var _solid_bg: ColorRect = null
var _dim_bg: ColorRect = null

# Story / Title / Lose widgets
var _card_container: Control = null
var _diorama_border: ColorRect = null
var _diorama: Control = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _story_label: Label = null
var _prompt_label: Label = null
var _credits_label: Label = null
var _lost_buttons: HBoxContainer = null

# Pause Menu widgets
var _pause_panel: ColorRect = null
var _pause_retry_btn: Button = null
var _pause_mute_btn: Button = null

var _input_lock: float = 0.0
var _blink_time: float = 0.0
var _can_retry_in_pause: bool = false


## Builds the reusable story card and pause menu layouts under one shared pixel-font Theme.
func _ready() -> void:
	name = "StoryCard"
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root = Control.new()
	_root.name = "Root"
	_root.position = Vector2.ZERO
	_root.size = Config.VIEW_SIZE
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = SpriteFactory.get_game_theme(Config.PIXEL_FONT_PATH)
	add_child(_root)

	# Solid black backdrop for Title and Story Cards.
	_solid_bg = ColorRect.new()
	_solid_bg.position = Vector2.ZERO
	_solid_bg.size = Config.VIEW_SIZE
	_solid_bg.color = Color(0.02, 0.02, 0.03, 1.0)
	_root.add_child(_solid_bg)

	# Translucent backdrop for the Pause Menu so you can still see the frozen world behind it.
	_dim_bg = ColorRect.new()
	_dim_bg.position = Vector2.ZERO
	_dim_bg.size = Config.VIEW_SIZE
	_dim_bg.color = Color(0.02, 0.02, 0.04, 0.72)
	_dim_bg.visible = false
	_root.add_child(_dim_bg)

	_build_card_widgets()
	_build_pause_widgets()
	hide_card()


## Pulses the "Press any key" prompt and ticks the short anti-skip input lock.
func _process(delta: float) -> void:
	if not visible:
		return

	var real_dt: float = delta / maxf(Engine.time_scale, 0.01)
	if _input_lock > 0.0:
		_input_lock = maxf(0.0, _input_lock - real_dt)

	_blink_time += real_dt
	var pulse: float = 0.55 + 0.45 * sin(_blink_time * 4.2)
	_prompt_label.modulate.a = pulse


## Routes keyboard shortcuts depending on whether Title, Story, Lose, or Pause is showing.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or mode == Mode.NONE or _input_lock > 0.0 or not (event is InputEventKey):
		return

	var key_ev: InputEventKey = event as InputEventKey
	if not key_ev.pressed or key_ev.echo:
		return

	var code: Key = key_ev.physical_keycode
	if code == KEY_NONE:
		code = key_ev.keycode

	# Ignore pure modifier keys and debug F1-F4 keys so they pass through cleanly.
	if code in [
		KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK,
		KEY_F1, KEY_F2, KEY_F3, KEY_F4
	]:
		return

	if mode == Mode.PAUSED:
		_handle_pause_key(code)
	elif code == KEY_M or code == KEY_ESCAPE:
		# Let M toggle mute, and ignore Esc outside gameplay so it never skips cards.
		return
	elif mode == Mode.LOST:
		if code in [KEY_R, KEY_ENTER, KEY_KP_ENTER]:
			get_viewport().set_input_as_handled()
			retry_requested.emit()
		elif code == KEY_N:
			get_viewport().set_input_as_handled()
			restart_run_requested.emit()
	else:
		# Any other key advances Title, Story Cards 1-4, or Ending Card 5.
		get_viewport().set_input_as_handled()
		advance_requested.emit()


## Hides all overlays and clears the active modal mode.
func hide_card() -> void:
	visible = false
	mode = Mode.NONE


## Displays the Title screen with a Red Moon diorama and asset pack credit line.
func show_title() -> void:
	mode = Mode.TITLE
	_input_lock = 0.25
	_blink_time = 0.0
	_show_card_layout()

	_title_label.text = "RED MOON"
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.2, 0.22))
	_title_label.visible = true

	_subtitle_label.text = "Bounce Back"
	_subtitle_label.visible = true

	_story_label.visible = false
	_lost_buttons.visible = false
	_prompt_label.text = "Press any key to start"
	_prompt_label.visible = true
	_credits_label.visible = true

	_build_diorama_title()


## Displays one of the 5 story cards (1-3 intro, 4 Act-2 transition, 5 victory ending).
func show_story(card_id: int) -> void:
	mode = Mode.WON if card_id == 5 else Mode.STORY
	_input_lock = 0.28
	_blink_time = 0.0
	_show_card_layout()

	_title_label.visible = (card_id == 3 or card_id == 5)
	if card_id == 3:
		_title_label.text = "RED MOON - Bounce Back"
		_title_label.add_theme_font_size_override("font_size", 16)
		_title_label.add_theme_color_override("font_color", Color(0.9, 0.32, 0.28))
	elif card_id == 5:
		_title_label.text = "VICTORY"
		_title_label.add_theme_font_size_override("font_size", 16)
		_title_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.44))

	_subtitle_label.visible = false
	_story_label.visible = true
	_lost_buttons.visible = false
	_prompt_label.visible = true
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


## Displays the Lose Screen with BOTH Retry Night (R/Enter) and Restart Entire Run (N).
func show_lost(night_num: int) -> void:
	mode = Mode.LOST
	_input_lock = 0.35
	_blink_time = 0.0
	_show_card_layout()

	_title_label.text = "The house fell. Bounce back."
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.26, 0.26))
	_title_label.visible = true

	_subtitle_label.visible = false
	_story_label.visible = true
	_story_label.text = "Night %d failed. Retry from dusk or start a brand new run." % night_num
	_prompt_label.text = "R / Enter: Retry Night %d    |    N: Restart Entire Run" % night_num
	_prompt_label.visible = true
	_lost_buttons.visible = true
	_credits_label.visible = false

	_build_diorama_lost()


## Displays the lightweight Pause Menu over the frozen world.
func show_pause(can_retry_night: bool, is_muted: bool) -> void:
	mode = Mode.PAUSED
	_can_retry_in_pause = can_retry_night
	_input_lock = 0.15
	visible = true

	_solid_bg.visible = false
	_card_container.visible = false
	_dim_bg.visible = true
	_pause_panel.visible = true

	_pause_retry_btn.disabled = not can_retry_night
	_pause_retry_btn.text = "Retry This Night (R)" if can_retry_night else "Retry Night (Night Only)"
	_update_pause_mute_text(is_muted)


## Updates the mute button label inside the Pause Menu immediately after toggling sound.
func update_pause_mute_label(is_muted: bool) -> void:
	_update_pause_mute_text(is_muted)


func _update_pause_mute_text(is_muted: bool) -> void:
	if _pause_mute_btn != null:
		_pause_mute_btn.text = "Sound: OFF (M)" if is_muted else "Sound: ON (M)"


func _handle_pause_key(code: Key) -> void:
	if code == KEY_ESCAPE or code == KEY_ENTER or code == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		resume_requested.emit()
	elif code == KEY_R and _can_retry_in_pause:
		get_viewport().set_input_as_handled()
		retry_requested.emit()
	elif code == KEY_N:
		get_viewport().set_input_as_handled()
		restart_run_requested.emit()
	elif code == KEY_M:
		get_viewport().set_input_as_handled()
		mute_requested.emit()


func _show_card_layout() -> void:
	visible = true
	_solid_bg.visible = true
	_card_container.visible = true
	_dim_bg.visible = false
	_pause_panel.visible = false


func _build_card_widgets() -> void:
	_card_container = Control.new()
	_card_container.position = Vector2.ZERO
	_card_container.size = Config.VIEW_SIZE
	_root.add_child(_card_container)

	_diorama_border = ColorRect.new()
	_diorama_border.position = Vector2(109.0, 39.0)
	_diorama_border.size = Vector2(262.0, 128.0)
	_diorama_border.color = Color(0.28, 0.22, 0.24, 1.0)
	_card_container.add_child(_diorama_border)

	_diorama = Control.new()
	_diorama.position = Vector2(110.0, 40.0)
	_diorama.size = Vector2(260.0, 126.0)
	_diorama.clip_contents = true
	_card_container.add_child(_diorama)

	_title_label = _make_label(
		"",
		Vector2(0.0, 10.0),
		Vector2(480.0, 26.0),
		16,
		Color(0.92, 0.22, 0.22)
	)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_container.add_child(_title_label)

	_subtitle_label = _make_label(
		"",
		Vector2(0.0, 174.0),
		Vector2(480.0, 16.0),
		8,
		Color(0.88, 0.88, 0.92)
	)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_container.add_child(_subtitle_label)

	_story_label = _make_label(
		"",
		Vector2(24.0, 174.0),
		Vector2(432.0, 34.0),
		8,
		Color(0.96, 0.94, 0.9)
	)
	_story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_container.add_child(_story_label)

	# Clickable Retry Night and Restart Entire Run buttons for the Lose screen.
	_lost_buttons = HBoxContainer.new()
	_lost_buttons.position = Vector2(100.0, 206.0)
	_lost_buttons.size = Vector2(280.0, 22.0)
	_lost_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_lost_buttons.add_theme_constant_override("separation", 12)
	_lost_buttons.visible = false
	_card_container.add_child(_lost_buttons)

	var retry_btn: Button = Button.new()
	retry_btn.text = "Retry Night (R)"
	retry_btn.focus_mode = Control.FOCUS_NONE
	retry_btn.pressed.connect(func() -> void: retry_requested.emit())
	_lost_buttons.add_child(retry_btn)

	var restart_btn: Button = Button.new()
	restart_btn.text = "Restart Run (N)"
	restart_btn.focus_mode = Control.FOCUS_NONE
	restart_btn.pressed.connect(func() -> void: restart_run_requested.emit())
	_lost_buttons.add_child(restart_btn)

	_prompt_label = _make_label(
		"",
		Vector2(0.0, 234.0),
		Vector2(480.0, 14.0),
		8,
		Color(0.82, 0.84, 0.9)
	)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_container.add_child(_prompt_label)

	_credits_label = _make_label(
		"Art: Post-Apocalyptic Pixel Art Asset Pack by TheLazyStone",
		Vector2(0.0, 252.0),
		Vector2(480.0, 14.0),
		8,
		Color(0.58, 0.58, 0.64)
	)
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_container.add_child(_credits_label)


## Builds the centered Pause Menu box with Resume, Retry Night, Restart Run, and Mute buttons.
func _build_pause_widgets() -> void:
	_pause_panel = ColorRect.new()
	_pause_panel.position = Vector2(140.0, 54.0)
	_pause_panel.size = Vector2(200.0, 158.0)
	_pause_panel.color = Color(0.08, 0.06, 0.09, 0.96)
	_pause_panel.visible = false
	_root.add_child(_pause_panel)

	var border_top: ColorRect = ColorRect.new()
	border_top.position = Vector2.ZERO
	border_top.size = Vector2(200.0, 2.0)
	border_top.color = Color(0.75, 0.22, 0.24, 1.0)
	_pause_panel.add_child(border_top)

	var pause_title: Label = _make_label(
		"PAUSED",
		Vector2(0.0, 12.0),
		Vector2(200.0, 22.0),
		16,
		Color(0.95, 0.3, 0.28)
	)
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_panel.add_child(pause_title)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.position = Vector2(18.0, 42.0)
	vbox.size = Vector2(164.0, 106.0)
	vbox.add_theme_constant_override("separation", 6)
	_pause_panel.add_child(vbox)

	var resume_btn: Button = Button.new()
	resume_btn.text = "Resume (Esc)"
	resume_btn.focus_mode = Control.FOCUS_NONE
	resume_btn.pressed.connect(func() -> void: resume_requested.emit())
	vbox.add_child(resume_btn)

	_pause_retry_btn = Button.new()
	_pause_retry_btn.text = "Retry This Night (R)"
	_pause_retry_btn.focus_mode = Control.FOCUS_NONE
	_pause_retry_btn.pressed.connect(func() -> void: retry_requested.emit())
	vbox.add_child(_pause_retry_btn)

	var restart_btn: Button = Button.new()
	restart_btn.text = "Restart Entire Run (N)"
	restart_btn.focus_mode = Control.FOCUS_NONE
	restart_btn.pressed.connect(func() -> void: restart_run_requested.emit())
	vbox.add_child(restart_btn)

	_pause_mute_btn = Button.new()
	_pause_mute_btn.text = "Sound: ON (M)"
	_pause_mute_btn.focus_mode = Control.FOCUS_NONE
	_pause_mute_btn.pressed.connect(func() -> void: mute_requested.emit())
	vbox.add_child(_pause_mute_btn)


func _clear_diorama() -> void:
	for child in _diorama.get_children():
		child.queue_free()


func _add_rect(pos: Vector2, sz: Vector2, color: Color) -> ColorRect:
	var rect_node: ColorRect = ColorRect.new()
	rect_node.position = pos
	rect_node.size = sz
	rect_node.color = color
	_diorama.add_child(rect_node)
	return rect_node


func _add_ground_strip(
	tile_key: String,
	y_start: float,
	rows: int,
	tint: Color = Color.WHITE
) -> void:
	var tile_tex: Texture2D = SpriteFactory.tex(tile_key)
	for row in range(rows):
		for col in range(17):
			var tr: TextureRect = TextureRect.new()
			tr.texture = tile_tex
			tr.position = Vector2(float(col * 16), y_start + float(row * 16))
			tr.size = Vector2(16.0, 16.0)
			tr.stretch_mode = TextureRect.STRETCH_KEEP
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.modulate = tint
			_diorama.add_child(tr)


func _add_sprite(key: String, pos: Vector2, tint: Color = Color.WHITE) -> TextureRect:
	var loaded_tex: Texture2D = SpriteFactory.tex(key)
	var tr: TextureRect = TextureRect.new()
	tr.texture = loaded_tex
	tr.position = pos
	tr.size = Vector2(float(loaded_tex.get_width()), float(loaded_tex.get_height()))
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
	var frame_w: int = int(info[1])
	var frame_h: int = int(info[2])
	var strip: Texture2D = SpriteFactory.tex(key)
	var tex_to_use: Texture2D = strip

	if strip.get_width() >= (frame_idx + 1) * frame_w and strip.get_height() >= frame_h:
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = strip
		atlas.region = Rect2(float(frame_idx * frame_w), 0.0, float(frame_w), float(frame_h))
		tex_to_use = atlas

	var tr: TextureRect = TextureRect.new()
	tr.texture = tex_to_use
	tr.position = pos
	tr.size = Vector2(float(frame_w), float(frame_h))
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.modulate = tint
	_diorama.add_child(tr)
	return tr


func _add_red_moon(pos: Vector2) -> void:
	var moon_tex: Texture2D = SpriteFactory.get_moon_texture(36, true)
	var tr: TextureRect = TextureRect.new()
	tr.texture = moon_tex
	tr.position = pos
	tr.size = Vector2(float(moon_tex.get_width()), float(moon_tex.get_height()))
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
	return lbl
