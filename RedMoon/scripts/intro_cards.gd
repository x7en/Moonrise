class_name IntroCards
extends CanvasLayer

signal sequence_finished(was_skipped: bool)

var active: bool = false

var _root: Control
var _title_lbl: Label
var _body_lbl: Label
var _prompt_lbl: Label
var _skip_lbl: Label
var _art_holder: Control

var _cards: Array[Dictionary] = []
var _index: int = 0
var _allow_skip_all: bool = true
var _ready_timer: float = 0.0
var _blink_timer: float = 0.0


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

	if _cards.is_empty():
		sequence_finished.emit(false)
		return

	active = true
	visible = true
	if _skip_lbl != null:
		_skip_lbl.visible = allow_skip_all

	_render_current()

	if instant_skip:
		_finish_all(true)


func _process(delta: float) -> void:
	if not active:
		return

	if _ready_timer > 0.0:
		_ready_timer = maxf(0.0, _ready_timer - delta)

	_blink_timer += delta
	if _prompt_lbl != null:
		_prompt_lbl.visible = (_ready_timer <= 0.0) and (int(_blink_timer * 2.5) % 2 == 0)


func _input(event: InputEvent) -> void:
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
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			if _ready_timer <= 0.0:
				_advance()
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			get_viewport().set_input_as_handled()
			if _ready_timer <= 0.0:
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
	# tiny input lock so mashing space doesnt skip two cards by accident
	_ready_timer = 0.25

	var card := _cards[_index]
	var accent = card.get("accent", Color(0.95, 0.90, 0.85))

	_title_lbl.text = String(card.get("title", ""))
	Art.style_label(_title_lbl, "display", 16, accent)
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

	var tex_rect := TextureRect.new()
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_rect.position = Vector2(272.0, 68.0)
	tex_rect.size = Vector2(96.0, 96.0)

	match art_kind:
		"blood_moon":
			tex_rect.texture = Art.tex("sky/blood_moon")
		"house":
			tex_rect.texture = Art.get_shaded_house_texture(1, false)
		"rubble":
			tex_rect.texture = Art.tex("props/rubble")
		"bow":
			tex_rect.texture = Art.get_icon_texture("bow")
		"boomerang":
			tex_rect.texture = Art.get_icon_texture("boomerang")
		"trap_snare":
			tex_rect.texture = Art.get_icon_texture("trap_snare")
		"dog":
			var dog_sheet := Art.tex("dog/idle_right")
			if dog_sheet.get_width() >= 48:
				var atlas := AtlasTexture.new()
				atlas.atlas = dog_sheet
				atlas.region = Rect2(0.0, 0.0, 48.0, float(dog_sheet.get_height()))
				tex_rect.texture = atlas
			else:
				tex_rect.texture = Art.get_icon_texture("trophy")
		_:
			tex_rect.texture = Art.tex("sky/moon")
			tex_rect.modulate = Config.EVEN_MOON_COLOR

	_art_holder.add_child(tex_rect)


func _build_ui() -> void:
	_root = get_node("Root") as Control
	_root.theme = Art.get_game_theme()

	_art_holder = get_node("Root/ArtHolder") as Control

	_title_lbl = get_node("Root/TitleLabel") as Label
	Art.style_label(_title_lbl, "display", 16, Color(0.98, 0.88, 0.78))

	_body_lbl = get_node("Root/BodyLabel") as Label
	Art.style_label(_body_lbl, "body", 8, Color(0.92, 0.90, 0.94))

	_prompt_lbl = get_node("Root/PromptLabel") as Label
	Art.style_label(_prompt_lbl, "bold", 8, Color(1.0, 0.86, 0.48))

	_skip_lbl = get_node("Root/SkipLabel") as Label
	Art.style_label(_skip_lbl, "body", 8, Color(0.68, 0.66, 0.74))


static func get_opening_cards() -> Array[Dictionary]:
	return [
		{
			"title": "THE NIGHT THE SKY CHANGED",
			"body": "Three weeks after the outbreak, the crimson Even Moon rose over the valley.\n"
			+ "Only the old hilltop farmhouse still has walls worth holding.",
			"art": "moon",
			"accent": Config.EVEN_MOON_BANNER,
		},
		{
			"title": "HOLD THE YARD",
			"body": "A weathered timber ring surrounds the house.\n"
			+ "Gather planks by day, patch the gaps, and unlock outer fence rings.",
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
			"body": "The Blood Moon struck two nights early - and you survived it.\n"
			+ "The road out of the yard is open! Explore the full 2400x1350 valley\n"
			+ "for scrap, ruins, traps, and stronger walls.\n\n"
			+ "The real Blood Moon arrives on Night 7.",
			"art": "world",
			"accent": Color(0.55, 0.96, 0.62),
		},
		{
			"title": "NEW: TAMING WILD DOGS",
			"body": "Wild dogs now roam the valley! Only SOME stray dogs can be tamed.\n"
			+ "Walk beside a friendly wild dog and click the [Tame] button.\n"
			+ "Tamed dogs follow you (press G for Follow / Guard) and attack zombies,\n"
			+ "but have low health - keep them backed up!",
			"art": "dog",
			"accent": Color(0.98, 0.88, 0.50),
		},
	]


# spoiler-free step-by-step tutorial (skippable with Esc, replayable from Title & Pause menus)
static func get_tutorial_cards() -> Array[Dictionary]:
	return [
		{
			"title": "1. MOVE & MORNING GATHER",
			"body": "Move with WASD or Arrow Keys.\n"
			+ "Every morning your fence gate opens automatically (house door stays shut).\n"
			+ "Step outside to grab planks, chop trees [Hold E] with your axe,\n"
			+ "and search wrecks [Hold E]. Walk near the house to store loot.",
			"art": "house",
			"accent": Color(1.0, 0.88, 0.56),
		},
		{
			"title": "2. ATTACKING & BOW",
			"body": "Click or tap to attack with your currently equipped weapon.\n"
			+ "Spear [Space] thrusts at nearby enemies with knockback.\n"
			+ "Hunting Bow [F] auto-aims at nearby threats using limited arrows\n"
			+ "with a short cooldown between shots. Press [R] to reload.",
			"art": "bow",
			"accent": Color(0.86, 0.94, 1.0),
		},
		{
			"title": "3. BOOMERANG",
			"body": "Equip the Boomerang to throw a spinning blade that auto-aims\n"
			+ "at the closest foe (or throws forward if none are nearby).\n"
			+ "It bounces back after its first hit, damaging foes on both legs,\n"
			+ "then starts a short cooldown once you catch it.",
			"art": "boomerang",
			"accent": Color(0.68, 0.96, 0.82),
		},
		{
			"title": "4. INVENTORY [I] & CRAFTING [C]",
			"body": "Press [I] to pause and open Inventory: view weapons, ammo, and traps,\n"
			+ "and switch weapons by clicking or pressing number keys [1-3].\n"
			+ "Press [C] to pause and craft Bear Traps, Spike Traps, Lures,\n"
			+ "and Arrows from your gathered resources.",
			"art": "trap_snare",
			"accent": Color(0.98, 0.84, 0.48),
		},
		{
			"title": "5. BEAR TRAPS & RECALL [B]",
			"body": "Press [1-3] (or click a bottom trap slot) and click ground to place.\n"
			+ "Bear Traps deal damage and briefly immobilize zombies.\n"
			+ "Press [B] anytime to teleport straight home and start healing!\n"
			+ "Press [U] near your house or fences to repair and upgrade.",
			"art": "trap_snare",
			"accent": Color(0.62, 0.96, 0.68),
		},
		{
			"title": "6. NIGHT SHELTER & BASE TRACKER",
			"body": "Before dusk, shut your fence gate and house door with [E].\n"
			+ "Watch the sky for the crimson Even Moon as night falls.\n"
			+ "Whenever you explore within 50m of home, a yellow BASE arrow\n"
			+ "shows the direction and distance back to safety.",
			"art": "moon",
			"accent": Config.EVEN_MOON_BANNER,
		},
	]
