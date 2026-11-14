class_name HUD
extends CanvasLayer
## Heads-up display: hearts, house HP bar, day/night timer, plank counters, Bounce bar, banner.

const HEART_COUNT := 5

var _root: Control = null
var _hearts: Array[TextureRect] = []
var _house_bar_fill: ColorRect = null
var _house_hp_label: Label = null
var _phase_label: Label = null
var _plank_icon: TextureRect = null
var _plank_label: Label = null
var _bounce_bar_fill: ColorRect = null
var _bounce_status_label: Label = null
var _prompt_label: Label = null
var _controls_label: Label = null

var _banner_panel: ColorRect = null
var _banner_label: Label = null
var _banner_tween: Tween = null


func _ready() -> void:
	name = "HUD"
	layer = 5

	_root = Control.new()
	_root.name = "Root"
	_root.position = Vector2.ZERO
	_root.size = Config.VIEW_SIZE
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_top_left()
	_build_top_right()
	_build_bottom_left()
	_build_bottom_bar()
	_build_banner()


func set_hud_visible(is_visible: bool) -> void:
	visible = is_visible


func update_state(data: Dictionary) -> void:
	var player_hp: int = int(data.get("player_hp", Config.PLAYER_HP))
	var house_hp: int = int(data.get("house_hp", Config.HOUSE_HP))
	var house_max: int = int(data.get("house_max_hp", Config.HOUSE_HP))
	var phase_title: String = String(data.get("phase_title", "Day 1"))
	var time_left: float = float(data.get("time_left", 0.0))
	var is_blood: bool = bool(data.get("is_blood_moon", false))
	var is_dusk: bool = bool(data.get("is_dusk", false))
	var act: int = int(data.get("act", 1))
	var bag: int = int(data.get("bag", 0))
	var stockpile: int = int(data.get("stockpile", 0))
	var bounce_cd: float = float(data.get("bounce_cd", 0.0))
	var bounce_cd_max: float = maxf(0.1, float(data.get("bounce_cd_max", Config.BOUNCE_CD_ACT1)))
	var bounce_stun: float = float(data.get("bounce_stun", 0.0))
	var bounce_bonuses: int = int(data.get("bounce_bonuses", 0))
	var muted: bool = bool(data.get("muted", false))
	var god_mode: bool = bool(data.get("god_mode", false))
	var repair_prompt: String = String(data.get("repair_prompt", ""))

	# 1. Player hearts (each heart = 10 HP, half = 5 HP).
	var tex_full: Texture2D = SpriteFactory.tex("ui/heart_full")
	var tex_half: Texture2D = SpriteFactory.tex("ui/heart_half")
	var tex_empty: Texture2D = SpriteFactory.tex("ui/heart_empty")
	for i in range(HEART_COUNT):
		var rem: int = player_hp - i * 10
		if rem >= 10:
			_hearts[i].texture = tex_full
		elif rem >= 5 or (rem > 0 and bounce_stun > 0.0):
			_hearts[i].texture = tex_half
		else:
			_hearts[i].texture = tex_empty

	# 2. House HP bar + numeric label.
	var frac: float = clampf(float(house_hp) / float(maxi(1, house_max)), 0.0, 1.0)
	_house_bar_fill.size.x = floorf(70.0 * frac) if house_hp > 0 else 0.0
	if god_mode:
		_house_hp_label.text = "%d/%d [GOD]" % [house_hp, house_max]
	else:
		_house_hp_label.text = "%d/%d" % [house_hp, house_max]

	# 3. Top-right phase title + timer.
	var secs: int = maxi(0, ceili(time_left))
	var mins: int = floori(float(secs) / 60.0)
	var rem_secs: int = secs % 60
	_phase_label.text = "%s  %d:%02d" % [phase_title, mins, rem_secs]
	if is_blood:
		_phase_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42))
	elif is_dusk:
		_phase_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.56))
	else:
		_phase_label.add_theme_color_override("font_color", Color.WHITE)

	# 4. Plank counters (Bag in Act 1; Bag + Stock in Act 2).
	if act == 1:
		_plank_label.text = "Bag: %d" % bag
		_plank_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.85))
	else:
		_plank_label.text = "Bag: %d   Stock: %d" % [bag, stockpile]
		if is_dusk and Config.LOSE_BAG_AT_DUSK and bag > 0:
			_plank_label.add_theme_color_override("font_color", Color(1.0, 0.58, 0.36))
		else:
			_plank_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.85))

	# 5. Bounce Back cooldown bar.
	var bonus_tag: String = ""
	if bounce_bonuses > 0:
		var pct: int = int(round(float(bounce_bonuses) * Config.SWING_GROWTH_PER_BOUNCE * 100.0))
		bonus_tag = "  +%d%%" % pct

	if bounce_stun > 0.0:
		var heal_frac: float = 1.0 - clampf(bounce_stun / maxf(Config.BOUNCE_STUN, 0.1), 0.0, 1.0)
		_bounce_bar_fill.size.x = maxf(1.0, floorf(44.0 * heal_frac))
		_bounce_bar_fill.color = Color(0.35, 0.92, 0.72, 1.0)
		_bounce_status_label.text = "HEAL %.1fs%s" % [bounce_stun, bonus_tag]
	elif bounce_cd > 0.0:
		var ready_frac: float = 1.0 - clampf(bounce_cd / bounce_cd_max, 0.0, 1.0)
		_bounce_bar_fill.size.x = floorf(44.0 * ready_frac)
		_bounce_bar_fill.color = Color(0.45, 0.62, 0.82, 1.0)
		_bounce_status_label.text = "%ds%s" % [ceili(bounce_cd), bonus_tag]
	else:
		_bounce_bar_fill.size.x = 44.0
		_bounce_bar_fill.color = Color(0.35, 0.86, 1.0, 1.0)
		_bounce_status_label.text = "READY%s" % bonus_tag

	# 6. Context repair prompt + controls line.
	_prompt_label.text = repair_prompt
	_prompt_label.visible = not repair_prompt.is_empty()

	var ctrl_base: String = (
		"Arrows/WASD: Move   Space: Punch   B: Bounce Back   M: Mute"
		if act == 1
		else "Arrows/WASD: Move   Space: Punch   B: Bounce   E: Repair   M: Mute"
	)
	if muted:
		ctrl_base += "  [MUTED]"
	_controls_label.text = ctrl_base


func show_banner(text: String, color: Color = Color.WHITE, duration: float = 3.0) -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()

	_banner_label.text = text
	_banner_label.add_theme_color_override("font_color", color)
	_banner_panel.visible = true
	_banner_panel.modulate.a = 1.0

	var hold: float = maxf(0.3, duration - 0.6)
	_banner_tween = create_tween()
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(_banner_panel, "modulate:a", 0.0, 0.6)
	_banner_tween.tween_callback(_hide_banner)


func clear_banner() -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_hide_banner()


func _hide_banner() -> void:
	if _banner_panel != null:
		_banner_panel.visible = false
		_banner_panel.modulate.a = 0.0


func _build_top_left() -> void:
	_hearts.clear()
	for i in range(HEART_COUNT):
		var heart: TextureRect = TextureRect.new()
		heart.texture = SpriteFactory.tex("ui/heart_full")
		heart.position = Vector2(8.0 + float(i * 15), 6.0)
		heart.size = Vector2(13.0, 12.0)
		heart.stretch_mode = TextureRect.STRETCH_KEEP
		heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_root.add_child(heart)
		_hearts.append(heart)

	var house_tag: Label = _make_label(
		"HOUSE",
		Vector2(8.0, 21.0),
		Vector2(36.0, 12.0),
		8,
		Color(0.95, 0.85, 0.85)
	)
	_root.add_child(house_tag)

	var bar_bg: ColorRect = ColorRect.new()
	bar_bg.position = Vector2(42.0, 22.0)
	bar_bg.size = Vector2(72.0, 8.0)
	bar_bg.color = Color(0.11, 0.07, 0.08, 0.9)
	_root.add_child(bar_bg)

	_house_bar_fill = ColorRect.new()
	_house_bar_fill.position = Vector2(43.0, 23.0)
	_house_bar_fill.size = Vector2(70.0, 6.0)
	_house_bar_fill.color = Color(0.84, 0.18, 0.2, 1.0)
	_root.add_child(_house_bar_fill)

	_house_hp_label = _make_label(
		"100/100",
		Vector2(118.0, 21.0),
		Vector2(74.0, 12.0),
		8,
		Color.WHITE
	)
	_root.add_child(_house_hp_label)


func _build_top_right() -> void:
	_phase_label = _make_label(
		"Day 1  0:20",
		Vector2(276.0, 6.0),
		Vector2(196.0, 12.0),
		8,
		Color.WHITE
	)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_phase_label)

	_plank_icon = TextureRect.new()
	_plank_icon.texture = SpriteFactory.tex("pickups_planks/pallet_2")
	_plank_icon.position = Vector2(342.0, 19.0)
	_plank_icon.size = Vector2(14.0, 10.0)
	_plank_icon.stretch_mode = TextureRect.STRETCH_KEEP
	_plank_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_root.add_child(_plank_icon)

	_plank_label = _make_label(
		"Bag: 0",
		Vector2(358.0, 19.0),
		Vector2(114.0, 12.0),
		8,
		Color(1.0, 0.96, 0.85)
	)
	_plank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_plank_label)


func _build_bottom_left() -> void:
	var b_tag: Label = _make_label(
		"B",
		Vector2(8.0, 240.0),
		Vector2(10.0, 12.0),
		8,
		Color(0.7, 0.94, 1.0)
	)
	_root.add_child(b_tag)

	var bg: ColorRect = ColorRect.new()
	bg.position = Vector2(18.0, 242.0)
	bg.size = Vector2(46.0, 7.0)
	bg.color = Color(0.08, 0.1, 0.14, 0.9)
	_root.add_child(bg)

	_bounce_bar_fill = ColorRect.new()
	_bounce_bar_fill.position = Vector2(19.0, 243.0)
	_bounce_bar_fill.size = Vector2(44.0, 5.0)
	_bounce_bar_fill.color = Color(0.35, 0.86, 1.0, 1.0)
	_root.add_child(_bounce_bar_fill)

	_bounce_status_label = _make_label(
		"READY",
		Vector2(68.0, 240.0),
		Vector2(116.0, 12.0),
		8,
		Color(0.85, 0.95, 1.0)
	)
	_root.add_child(_bounce_status_label)


func _build_bottom_bar() -> void:
	_prompt_label = _make_label(
		"",
		Vector2(230.0, 240.0),
		Vector2(242.0, 12.0),
		8,
		Color(1.0, 0.93, 0.56)
	)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt_label.visible = false
	_root.add_child(_prompt_label)

	var ctrl_bg: ColorRect = ColorRect.new()
	ctrl_bg.position = Vector2(0.0, 255.0)
	ctrl_bg.size = Vector2(Config.VIEW_SIZE.x, 15.0)
	ctrl_bg.color = Color(0.0, 0.0, 0.0, 0.45)
	_root.add_child(ctrl_bg)

	_controls_label = _make_label(
		"",
		Vector2(0.0, 257.0),
		Vector2(Config.VIEW_SIZE.x, 12.0),
		8,
		Color(0.92, 0.92, 0.92)
	)
	_controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_controls_label)


func _build_banner() -> void:
	_banner_panel = ColorRect.new()
	_banner_panel.position = Vector2(60.0, 44.0)
	_banner_panel.size = Vector2(360.0, 22.0)
	_banner_panel.color = Color(0.04, 0.03, 0.05, 0.68)
	_banner_panel.visible = false
	_root.add_child(_banner_panel)

	_banner_label = _make_label("", Vector2(0.0, 4.0), Vector2(360.0, 16.0), 10, Color.WHITE)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_panel.add_child(_banner_label)


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
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	return lbl
