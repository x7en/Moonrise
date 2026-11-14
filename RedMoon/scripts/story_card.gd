class_name StoryCard
extends CanvasLayer
## Full-screen retro story cards (640x360), T0.2 Blood Moon deadline card, T1.7 skippable intro
## (Esc skips all remaining cards and marks intro seen), and T1.8 World Expanded reveal.

signal sequence_finished(was_skipped: bool)

var active: bool = false

var _root: Control = null
var _title_lbl: Label = null
var _body_lbl: Label = null
var _prompt_lbl: Label = null
var _skip_lbl: Label = null
var _art_holder: Control = null

var _cards: Array[Dictionary] = []
var _index: int = 0
var _allow_skip_all: bool = true
var _ready_timer: float = 0.0
var _blink_timer: float = 0.0
var _auto_skip: bool = false


func _ready() -> void:
	layer = 35
	visible = false
	_build_ui()


func show_cards(
	cards: Array[Dictionary],
	allow_skip_all: bool = true,
	instant_skip: bool = false
) -> void:
	_cards = cards
	_index = 0
	_allow_skip_all = allow_skip_all
	_auto_skip = instant_skip
	if _cards.is_empty():
		sequence_finished.emit(false)
		return
	active = true
	visible = true
	if _skip_lbl != null:
		_skip_lbl.visible = allow_skip_all
	_render_current()
	if _auto_skip:
		_finish_all(true)


func _process(delta: float) -> void:
	if not active:
		return
	if _ready_timer > 0.0:
		_ready_timer = maxf(0.0, _ready_timer - delta)
	_blink_timer += delta
	if _prompt_lbl != null:
		_prompt_lbl.visible = (_ready_timer <= 0.0) and (int(_blink_timer * 2.5) % 2 == 0)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if not ke.pressed or ke.echo:
			return
		if ke.keycode == KEY_ESCAPE and _allow_skip_all:
			get_viewport().set_input_as_handled()
			_finish_all(true)
			return
		if ke.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and _ready_timer <= 0.0:
			get_viewport().set_input_as_handled()
			_advance()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and _ready_timer <= 0.0:
			get_viewport().set_input_as_handled()
			_advance()


func _advance() -> void:
	_index += 1
	if _index >= _cards.size():
		_finish_all(false)
	else:
		_render_current()


func _finish_all(skipped: bool) -> void:
	active = false
	visible = false
	_cards.clear()
	sequence_finished.emit(skipped)


func _render_current() -> void:
	_ready_timer = 0.25
	var card: Dictionary = _cards[_index]
	var accent: Color = card.get("accent", Color(0.95, 0.90, 0.85)) as Color
	_title_lbl.text = String(card.get("title", ""))
	SpriteFactory.style_label(_title_lbl, "display", 16, accent)
	_body_lbl.text = String(card.get("body", ""))
	_prompt_lbl.text = (
		"[Space / Enter] Continue (%d/%d)" % [_index + 1, _cards.size()]
		if _index < _cards.size() - 1
		else "[Space / Enter] Begin"
	)
	_render_card_art(String(card.get("art", "moon")))


func _render_card_art(art_kind: String) -> void:
	for child in _art_holder.get_children():
		child.queue_free()
	var tex_rect: TextureRect = TextureRect.new()
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_rect.position = Vector2(272.0, 62.0)
	tex_rect.size = Vector2(96.0, 96.0)
	match art_kind:
		"blood_moon":
			tex_rect.texture = SpriteFactory.tex("moon/moon_02_red")
		"house":
			tex_rect.texture = SpriteFactory.get_shaded_house_texture(1, false)
		"world":
			tex_rect.texture = SpriteFactory.tex("moon/moon_00_white")
		"rubble":
			tex_rect.texture = SpriteFactory.tex("structures/ruins/gray-brick_debris")
		_:
			tex_rect.texture = SpriteFactory.tex("moon/moon_01")
	_art_holder.add_child(tex_rect)


func _build_ui() -> void:
	_root = Control.new()
	_root.position = Vector2.ZERO
	_root.size = Config.VIEW_SIZE
	_root.theme = SpriteFactory.get_game_theme()
	add_child(_root)

	var bg: ColorRect = ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Config.VIEW_SIZE
	bg.color = Color(0.05, 0.04, 0.08, 0.96)
	_root.add_child(bg)

	var frame: PanelContainer = PanelContainer.new()
	frame.position = Vector2(64.0, 28.0)
	frame.size = Vector2(Config.VIEW_SIZE.x - 128.0, Config.VIEW_SIZE.y - 56.0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.07, 0.13, 0.96)
	style.border_color = Color(0.55, 0.30, 0.34, 1.0)
	style.set_border_width_all(2)
	frame.add_theme_stylebox_override("panel", style)
	_root.add_child(frame)

	_art_holder = Control.new()
	_art_holder.position = Vector2.ZERO
	_art_holder.size = Config.VIEW_SIZE
	_art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_art_holder)

	_title_lbl = Label.new()
	_title_lbl.position = Vector2(84.0, 36.0)
	_title_lbl.size = Vector2(Config.VIEW_SIZE.x - 168.0, 28.0)
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SpriteFactory.style_label(_title_lbl, "display", 16, Color(0.98, 0.88, 0.78))
	_root.add_child(_title_lbl)

	_body_lbl = Label.new()
	_body_lbl.position = Vector2(96.0, 174.0)
	_body_lbl.size = Vector2(Config.VIEW_SIZE.x - 192.0, 110.0)
	_body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	SpriteFactory.style_label(_body_lbl, "body", 8, Color(0.92, 0.90, 0.94))
	_root.add_child(_body_lbl)

	_prompt_lbl = Label.new()
	_prompt_lbl.position = Vector2(84.0, Config.VIEW_SIZE.y - 56.0)
	_prompt_lbl.size = Vector2(Config.VIEW_SIZE.x - 168.0, 16.0)
	_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SpriteFactory.style_label(_prompt_lbl, "bold", 8, Color(1.0, 0.86, 0.48))
	_root.add_child(_prompt_lbl)

	_skip_lbl = Label.new()
	_skip_lbl.position = Vector2(Config.VIEW_SIZE.x - 180.0, Config.VIEW_SIZE.y - 24.0)
	_skip_lbl.size = Vector2(170.0, 14.0)
	_skip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_lbl.text = "[Esc] Skip Intro"
	SpriteFactory.style_label(_skip_lbl, "body", 8, Color(0.68, 0.66, 0.74))
	_root.add_child(_skip_lbl)


## T0.2 + T1.7: Opening story cards, explicitly establishing the Act 1 Night 5 false deadline.
static func get_opening_cards() -> Array[Dictionary]:
	return [
		{
			"title": "THE NIGHT THE SKY CHANGED",
			"body": "Three weeks after the outbreak, the valley fell silent.\n"
			+ "Only the old hilltop farmhouse still has walls worth holding.",
			"art": "moon",
			"accent": Color(0.92, 0.94, 1.0),
		},
		{
			"title": "THE TWO RINGS",
			"body": "Two weathered rings of timber surround the house.\n"
			+ "Gather planks by day, mend the gaps, and fortify the outer line.",
			"art": "house",
			"accent": Color(1.0, 0.88, 0.64),
		},
		{
			"title": "THE BLOOD MOON",
			"body": "Old radio logs warn of one thing above all else:\n"
			+ "The Blood Moon rises on Night 5.\n"
			+ "Scavenge fast. Close the door before dusk.",
			"art": "blood_moon",
			"accent": Color(1.0, 0.40, 0.36),
		},
	]


static func get_world_expanded_cards() -> Array[Dictionary]:
	return [
		{
			"title": "WORLD EXPANDED!",
			"body": "The Blood Moon struck two nights early — and you survived it.\n"
			+ "The road out of the yard is open! Explore the full 2400x1350 valley\n"
			+ "for scrap, ruins, traps, and stronger walls.\n\n"
			+ "The real Blood Moon arrives on Night 7.",
			"art": "world",
			"accent": Color(0.55, 0.96, 0.62),
		},
	]
