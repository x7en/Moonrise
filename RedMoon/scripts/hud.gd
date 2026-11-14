class_name Hud
extends CanvasLayer
## 640x360 pixel HUD (T0.1b / T0.B / T0.2 / T1.1 / T1.2 / T1.5 / T2.3 / T3.1 / T3.3 / T3.4).
## No persistent sky moon icon (T1.1). Main Menu reuses MoonSky live sky (T3.4).

signal play_requested(continue_run: bool)
signal menu_panel_requested(panel_kind: String)
signal quit_requested()
signal retry_day_requested()
signal new_game_requested()
signal return_to_menu_requested()

var _root: Control = null
var _hud_layer: Control = null

# Top-left status cluster
var _hp_fill: ColorRect = null
var _hp_lbl: Label = null
var _house_lbl: Label = null
var _house_icon: TextureRect = null
var _bag_lbl: Label = null
var _stock_lbl: Label = null
var _bow_lbl: Label = null

# Top-center clock & persistent objective strip (T0.2)
var _day_lbl: Label = null
var _timer_lbl: Label = null
var _objective_lbl: Label = null

# Top-right bounce & quick-hints
var _bounce_lbl: Label = null
var _hint_lbl: Label = null
var _status_lbl: Label = null
var _trap_slots: Array[PanelContainer] = []
var _trap_slot_labels: Array[Label] = []

# Center banners, search bar, tooltip, home arrow
var _header_panel: PanelContainer = null
var _header_title: Label = null
var _header_sub: Label = null
var _header_timer: float = 0.0
var _toast_lbl: Label = null
var _toast_timer: float = 0.0
var _prompt_lbl: Label = null
var _tooltip_lbl: Label = null
var _search_bar_bg: ColorRect = null
var _search_bar_fill: ColorRect = null
var _home_arrow: Label = null
var _vignette: ColorRect = null

# Main menu (T3.4) & End screen
var _title_screen: Control = null
var _menu_sky: MoonSky = null
var _menu_buttons: Array[Button] = []
var _menu_continue_btn: Button = null
var _menu_idx: int = 0
var _end_screen: Control = null
var _end_title: Label = null
var _end_body: Label = null
var _end_retry_btn: Button = null
var _end_buttons: Array[Button] = []
var _end_idx: int = 0


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.position = Vector2.ZERO
	_root.size = Config.VIEW_SIZE
	_root.theme = SpriteFactory.get_game_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_hud()
	_build_title_screen()
	_build_end_screen()
	show_title_screen(false)


func _process(delta: float) -> void:
	if _title_screen != null and _title_screen.visible and _menu_sky != null:
		_menu_sky.update_sky(delta)

	if _header_timer > 0.0 and _header_panel != null:
		_header_timer = maxf(0.0, _header_timer - delta)
		_header_panel.modulate.a = clampf(_header_timer / 0.45, 0.0, 1.0)
		if _header_timer <= 0.0:
			_header_panel.visible = false

	if _toast_timer > 0.0 and _toast_lbl != null:
		_toast_timer = maxf(0.0, _toast_timer - delta)
		_toast_lbl.modulate.a = clampf(_toast_timer / 0.35, 0.0, 1.0)
		if _toast_timer <= 0.0:
			_toast_lbl.visible = false


func show_title_screen(has_continue: bool) -> void:
	_title_screen.visible = true
	_hud_layer.visible = false
	_end_screen.visible = false
	_menu_sky.configure_for_night(3, true, false)
	_menu_sky.moon_progress = 0.88
	_menu_sky.red_blend = 0.92
	_menu_continue_btn.visible = has_continue
	_menu_idx = 1 if has_continue else 0
	_focus_menu_button(_menu_idx)


func show_gameplay_hud() -> void:
	_title_screen.visible = false
	_end_screen.visible = false
	_hud_layer.visible = true


func show_end_screen(victory: bool, title_txt: String, body_txt: String, can_retry: bool) -> void:
	_title_screen.visible = false
	_hud_layer.visible = false
	_end_screen.visible = true
	_end_title.text = title_txt
	SpriteFactory.style_label(
		_end_title,
		"display",
		16,
		Color(0.56, 0.96, 0.62) if victory else Color(1.0, 0.38, 0.34)
	)
	_end_body.text = body_txt
	_end_retry_btn.visible = can_retry
	_end_idx = 0 if can_retry else 1
	if _end_idx < _end_buttons.size() and _end_buttons[_end_idx].visible:
		_end_buttons[_end_idx].grab_focus()


## T0.2: Big centered day/night header banner (e.g., "DAY 1 - ACT 1", "NIGHT 3 - BLOOD MOON!").
func show_header_banner(
	title_txt: String,
	subtitle_txt: String,
	accent: Color,
	dur: float = 2.6
) -> void:
	_header_title.text = title_txt
	SpriteFactory.style_label(_header_title, "display", 16, accent)
	_header_sub.text = subtitle_txt
	_header_panel.modulate.a = 1.0
	_header_panel.visible = true
	_header_timer = dur


func show_message(text: String, duration: float = 2.0, col: Color = Color(1.0, 0.92, 0.68)) -> void:
	_toast_lbl.text = text
	SpriteFactory.style_label(_toast_lbl, "bold", 8, col)
	_toast_lbl.modulate.a = 1.0
	_toast_lbl.visible = true
	_toast_timer = duration


func update_hud(data: Dictionary) -> void:
	var hp: int = int(data.get("hp", 50))
	var max_hp: int = maxi(1, int(data.get("max_hp", 50)))
	_hp_fill.size.x = floorf(78.0 * clampf(float(hp) / float(max_hp), 0.0, 1.0))
	_hp_lbl.text = "HP %d/%d" % [hp, max_hp]

	var house_fallen: bool = bool(data.get("house_fallen", false))
	var house_hp: int = int(data.get("house_hp", 100))
	var house_max: int = int(data.get("house_max", 100))
	var door_open: bool = bool(data.get("door_open", false))
	var intruders: int = int(data.get("intruders", 0))
	if house_fallen:
		_house_lbl.text = "HOUSE FALLEN! (No Shelter)"
		SpriteFactory.style_label(_house_lbl, "bold", 8, Color(1.0, 0.42, 0.36))
		_house_icon.texture = SpriteFactory.get_icon_texture("broken_house")
		_house_icon.visible = true
	else:
		var door_tag: String = "OPEN" if door_open else "CLOSED"
		_house_lbl.text = "House %d/%d  Door:%s" % [house_hp, house_max, door_tag]
		SpriteFactory.style_label(
			_house_lbl,
			"bold",
			8,
			Color(1.0, 0.72, 0.35) if door_open else Color(0.84, 0.92, 0.86)
		)
		_house_icon.visible = false

	_bag_lbl.text = "Bag %d/%d (P:%d S:%d) | Stock P:%d S:%d" % [
		int(data.get("bag_used", 0)),
		int(data.get("bag_cap", 16)),
		int(data.get("bag_planks", 0)),
		int(data.get("bag_scrap", 0)),
		int(data.get("stock_planks", 0)),
		int(data.get("stock_scrap", 0)),
	]
	_stock_lbl.visible = false

	var reloading: bool = bool(data.get("reloading", false))
	if reloading:
		_bow_lbl.text = "Bow: Reloading... (%d)" % int(data.get("arrows", 0))
		SpriteFactory.style_label(_bow_lbl, "bold", 8, Color(1.0, 0.82, 0.40))
	else:
		_bow_lbl.text = "Bow %d/%d (%d) [F/R]" % [
			int(data.get("mag", 6)),
			int(data.get("mag_max", 6)),
			int(data.get("arrows", 0)),
		]
		SpriteFactory.style_label(_bow_lbl, "bold", 8, Color(0.92, 0.94, 1.0))

	var secs: int = maxi(0, ceili(float(data.get("time_left", 0.0))))
	var clk: String = "%d:%02d" % [int(floorf(float(secs) / 60.0)), secs % 60]
	_day_lbl.text = "%s   %s" % [String(data.get("phase_label", "DAY 1")), clk]
	_timer_lbl.visible = false
	_objective_lbl.text = String(data.get("objective", ""))

	var b_cd: float = float(data.get("bounce_cd", 0.0))
	_bounce_lbl.text = (
		"[Q] Shockwave READY" if b_cd <= 0.0 else "[Q] Shockwave %.0fs" % ceilf(b_cd)
	)
	SpriteFactory.style_label(
		_bounce_lbl, "bold", 8, Color(0.62, 0.94, 1.0) if b_cd <= 0.0 else Color(0.66, 0.66, 0.72)
	)

	_update_trap_hotbar(
		int(data.get("selected_trap", 1)),
		bool(data.get("trap_mode_active", false)),
		int(data.get("trap_spike", 0)),
		int(data.get("trap_snare", 0)),
		int(data.get("trap_lure", 0))
	)

	var extras: Array[String] = []
	if bool(data.get("inside_house", false)):
		extras.append("INDOORS (Safe - Shoot w/ F, E Exit)")
	if intruders > 0:
		extras.append("INTRUDERS INSIDE: %d! [Space] Clear" % intruders)
	if bool(data.get("muted", false)):
		extras.append("MUTED [M]")
	_status_lbl.text = "  |  ".join(extras)
	_status_lbl.visible = not extras.is_empty()

	var prompt_txt: String = String(data.get("prompt", ""))
	_prompt_lbl.text = prompt_txt
	_prompt_lbl.visible = not prompt_txt.is_empty()

	var tip_txt: String = String(data.get("tooltip", ""))
	_tooltip_lbl.text = tip_txt
	_tooltip_lbl.visible = not tip_txt.is_empty()

	var search_frac: float = float(data.get("search_progress", 0.0))
	_search_bar_bg.visible = search_frac > 0.0
	_search_bar_fill.size.x = floorf(84.0 * clampf(search_frac, 0.0, 1.0))

	# Off-screen home arrow when far from farmhouse in Act 2 (T3.1).
	var home_dir: Vector2 = data.get("home_arrow_dir", Vector2.ZERO) as Vector2
	if home_dir.length_squared() > 0.01:
		_home_arrow.visible = true
		var edge: Vector2 = Config.VIEW_SIZE * 0.5 + home_dir.normalized() * Vector2(270.0, 130.0)
		_home_arrow.position = Vector2(
			clampf(edge.x - 28.0, 12.0, Config.VIEW_SIZE.x - 68.0),
			clampf(edge.y - 8.0, 56.0, Config.VIEW_SIZE.y - 32.0)
		)
	else:
		_home_arrow.visible = false

	# Subtle red border danger flash on low HP or active intruders (T1.5).
	if intruders > 0 or (hp > 0 and hp <= 15):
		_vignette.visible = true
		_vignette.color = Color(0.75, 0.08, 0.08, 0.16)
	else:
		_vignette.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke: InputEventKey = event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	if _title_screen.visible:
		_handle_menu_nav(ke, _menu_buttons, true)
	elif _end_screen.visible:
		_handle_menu_nav(ke, _end_buttons, false)


func _handle_menu_nav(ke: InputEventKey, btns: Array[Button], is_title: bool) -> void:
	var visible_btns: Array[Button] = []
	for b in btns:
		if b.visible:
			visible_btns.append(b)
	if visible_btns.is_empty():
		return
	var idx: int = _menu_idx if is_title else _end_idx
	idx = clampi(idx, 0, visible_btns.size() - 1)
	if ke.keycode in [KEY_UP, KEY_W]:
		get_viewport().set_input_as_handled()
		idx = (idx - 1 + visible_btns.size()) % visible_btns.size()
	elif ke.keycode in [KEY_DOWN, KEY_S]:
		get_viewport().set_input_as_handled()
		idx = (idx + 1) % visible_btns.size()
	elif ke.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		visible_btns[idx].pressed.emit()
		return
	else:
		return
	if is_title:
		_menu_idx = idx
	else:
		_end_idx = idx
	visible_btns[idx].grab_focus()


func _focus_menu_button(idx: int) -> void:
	var vis: Array[Button] = []
	for b in _menu_buttons:
		if b.visible:
			vis.append(b)
	if not vis.is_empty():
		_menu_idx = clampi(idx, 0, vis.size() - 1)
		vis[_menu_idx].grab_focus()


func _build_hud() -> void:
	_hud_layer = Control.new()
	_hud_layer.position = Vector2.ZERO
	_hud_layer.size = Config.VIEW_SIZE
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud_layer)

	_vignette = ColorRect.new()
	_vignette.position = Vector2.ZERO
	_vignette.size = Config.VIEW_SIZE
	_vignette.color = Color(0.75, 0.08, 0.08, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	_hud_layer.add_child(_vignette)

	# Top bar translucent backdrop (compact 44 px height on 640x360 viewport).
	var top_bar: ColorRect = ColorRect.new()
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(Config.VIEW_SIZE.x, 44.0)
	top_bar.color = Color(0.05, 0.04, 0.09, 0.62)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(top_bar)

	# Left cluster: HP bar, House status, Bag & Stockpile, Bow ammo.
	var hp_bg: ColorRect = ColorRect.new()
	hp_bg.position = Vector2(8.0, 5.0)
	hp_bg.size = Vector2(80.0, 9.0)
	hp_bg.color = Color(0.14, 0.08, 0.12, 0.95)
	_hud_layer.add_child(hp_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.position = Vector2(9.0, 6.0)
	_hp_fill.size = Vector2(78.0, 7.0)
	_hp_fill.color = Color(0.86, 0.24, 0.26, 1.0)
	_hud_layer.add_child(_hp_fill)

	_hp_lbl = _mk_lbl(Vector2(92.0, 4.0), Vector2(84.0, 12.0), "bold", 8, Color.WHITE)
	_house_icon = TextureRect.new()
	_house_icon.position = Vector2(8.0, 16.0)
	_house_icon.size = Vector2(12.0, 12.0)
	_house_icon.visible = false
	_hud_layer.add_child(_house_icon)
	_house_lbl = _mk_lbl(
		Vector2(22.0, 17.0), Vector2(194.0, 12.0), "bold", 8, Color(0.86, 0.94, 0.86)
	)
	_bag_lbl = _mk_lbl(Vector2(8.0, 29.0), Vector2(310.0, 12.0), "body", 8, Color(0.95, 0.86, 0.62))
	_stock_lbl = _mk_lbl(Vector2(8.0, 29.0), Vector2(10.0, 10.0), "body", 8, Color.WHITE)
	_stock_lbl.visible = false

	# Center cluster: Day + Clock on row 1, short crisp Objective on row 2 (zero overlap!).
	_day_lbl = _mk_lbl(
		Vector2(186.0, 4.0), Vector2(268.0, 12.0), "bold", 8, Color(1.0, 0.90, 0.64)
	)
	_day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_lbl = _mk_lbl(Vector2(236.0, 16.0), Vector2(10.0, 10.0), "bold", 8, Color.WHITE)
	_timer_lbl.visible = false
	_objective_lbl = _mk_lbl(
		Vector2(218.0, 17.0), Vector2(216.0, 12.0), "body", 8, Color(0.98, 0.92, 0.72)
	)
	_objective_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Right cluster: Bow, Shockwave Q, clean quick-key strip.
	_bow_lbl = _mk_lbl(
		Vector2(458.0, 4.0), Vector2(174.0, 12.0), "bold", 8, Color(0.92, 0.94, 1.0)
	)
	_bow_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bounce_lbl = _mk_lbl(
		Vector2(440.0, 17.0), Vector2(192.0, 12.0), "bold", 8, Color(0.62, 0.94, 1.0)
	)
	_bounce_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_lbl = _mk_lbl(
		Vector2(326.0, 29.0), Vector2(306.0, 12.0), "body", 8, Color(0.80, 0.84, 0.92)
	)
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_lbl.text = "[E] Door/Gate  [U] Upgrade  [I] Bag  [Esc] Pause"

	# Status strip just below top bar (Indoors / Intruders / Muted).
	_status_lbl = _mk_lbl(
		Vector2(110.0, 46.0), Vector2(420.0, 12.0), "bold", 8, Color(1.0, 0.78, 0.42)
	)
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.visible = false

	# Dedicated clean Bottom Trap Hotbar ([1] Spike, [2] Snare, [3] Lure).
	_build_trap_hotbar()

	# Big Day/Night Header Banner (T0.2).
	_header_panel = PanelContainer.new()
	_header_panel.position = Vector2(140.0, 80.0)
	_header_panel.size = Vector2(360.0, 56.0)
	_header_panel.visible = false
	_header_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hstyle: StyleBoxFlat = StyleBoxFlat.new()
	hstyle.bg_color = Color(0.08, 0.06, 0.12, 0.90)
	hstyle.border_color = Color(0.86, 0.34, 0.32, 0.95)
	hstyle.set_border_width_all(1)
	_header_panel.add_theme_stylebox_override("panel", hstyle)
	_hud_layer.add_child(_header_panel)

	var hvbox: VBoxContainer = VBoxContainer.new()
	hvbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_header_panel.add_child(hvbox)
	_header_title = Label.new()
	_header_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SpriteFactory.style_label(_header_title, "display", 16, Color(1.0, 0.88, 0.56))
	hvbox.add_child(_header_title)
	_header_sub = Label.new()
	_header_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SpriteFactory.style_label(_header_sub, "body", 8, Color(0.92, 0.90, 0.94))
	hvbox.add_child(_header_sub)

	# Bottom prompts, search hold bar, hover tooltip, and transient message (clean vertical stack).
	_toast_lbl = _mk_lbl(
		Vector2(90.0, Config.VIEW_SIZE.y - 64.0), Vector2(460.0, 12.0), "bold", 8, Color.WHITE
	)
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_lbl.visible = false

	_search_bar_bg = ColorRect.new()
	_search_bar_bg.position = Vector2(277.0, Config.VIEW_SIZE.y - 50.0)
	_search_bar_bg.size = Vector2(86.0, 7.0)
	_search_bar_bg.color = Color(0.08, 0.06, 0.12, 0.92)
	_search_bar_bg.visible = false
	_hud_layer.add_child(_search_bar_bg)
	_search_bar_fill = ColorRect.new()
	_search_bar_fill.position = Vector2(1.0, 1.0)
	_search_bar_fill.size = Vector2(0.0, 5.0)
	_search_bar_fill.color = Color(0.96, 0.78, 0.32, 1.0)
	_search_bar_bg.add_child(_search_bar_fill)

	_prompt_lbl = _mk_lbl(
		Vector2(40.0, Config.VIEW_SIZE.y - 40.0),
		Vector2(560.0, 12.0),
		"bold",
		8,
		Color(1.0, 0.92, 0.56)
	)
	_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_lbl.visible = false

	_tooltip_lbl = _mk_lbl(
		Vector2(8.0, Config.VIEW_SIZE.y - 11.0),
		Vector2(624.0, 10.0),
		"body",
		8,
		Color(0.84, 0.88, 0.94)
	)
	_tooltip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip_lbl.visible = false

	_home_arrow = _mk_lbl(Vector2.ZERO, Vector2(56.0, 14.0), "bold", 8, Color(1.0, 0.88, 0.40))
	_home_arrow.text = "HOME >>"
	_home_arrow.visible = false


func _build_title_screen() -> void:
	_title_screen = Control.new()
	_title_screen.position = Vector2.ZERO
	_title_screen.size = Config.VIEW_SIZE
	_root.add_child(_title_screen)

	_menu_sky = MoonSky.new()
	_title_screen.add_child(_menu_sky)
	_menu_sky.build(Config.VIEW_SIZE)

	var title_lbl: Label = Label.new()
	title_lbl.position = Vector2(0.0, 26.0)
	title_lbl.size = Vector2(Config.VIEW_SIZE.x, 40.0)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.text = "RED MOON"
	SpriteFactory.style_label(title_lbl, "display", 32, Color(1.0, 0.34, 0.30))
	_title_screen.add_child(title_lbl)

	var sub_lbl: Label = Label.new()
	sub_lbl.position = Vector2(0.0, 68.0)
	sub_lbl.size = Vector2(Config.VIEW_SIZE.x, 14.0)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.text = "Gather by day. Hold the rings by night."
	SpriteFactory.style_label(sub_lbl, "bold", 8, Color(0.95, 0.88, 0.84))
	_title_screen.add_child(sub_lbl)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.position = Vector2(236.0, 166.0)
	vbox.size = Vector2(168.0, 174.0)
	vbox.add_theme_constant_override("separation", 4)
	_title_screen.add_child(vbox)

	_menu_buttons.clear()
	_menu_continue_btn = _mk_menu_btn(vbox, "Continue", func() -> void: play_requested.emit(true))
	_menu_continue_btn.visible = false
	_mk_menu_btn(vbox, "Play", func() -> void: play_requested.emit(false))
	_mk_menu_btn(vbox, "Controls", func() -> void: menu_panel_requested.emit("controls"))
	_mk_menu_btn(vbox, "Settings", func() -> void: menu_panel_requested.emit("settings"))
	_mk_menu_btn(vbox, "Achievements", func() -> void: menu_panel_requested.emit("achievements"))
	_mk_menu_btn(vbox, "Credits", func() -> void: menu_panel_requested.emit("credits"))
	if not OS.has_feature("web"):
		_mk_menu_btn(vbox, "Quit", func() -> void: quit_requested.emit())

	var ver_lbl: Label = Label.new()
	ver_lbl.position = Vector2(8.0, Config.VIEW_SIZE.y - 14.0)
	ver_lbl.size = Vector2(300.0, 12.0)
	ver_lbl.text = "Red Moon v2.0 (Godot 4.7)  |  F11 Fullscreen"
	SpriteFactory.style_label(ver_lbl, "body", 8, Color(0.72, 0.68, 0.78))
	_title_screen.add_child(ver_lbl)


func _build_end_screen() -> void:
	_end_screen = Control.new()
	_end_screen.position = Vector2.ZERO
	_end_screen.size = Config.VIEW_SIZE
	_end_screen.visible = false
	_root.add_child(_end_screen)

	var bg: ColorRect = ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Config.VIEW_SIZE
	bg.color = Color(0.05, 0.04, 0.08, 0.90)
	_end_screen.add_child(bg)

	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(130.0, 56.0)
	panel.size = Vector2(380.0, 248.0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.07, 0.13, 0.96)
	style.border_color = Color(0.86, 0.34, 0.32, 1.0)
	style.set_border_width_all(2)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)
	_end_screen.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_end_title = Label.new()
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SpriteFactory.style_label(_end_title, "display", 16, Color(1.0, 0.38, 0.34))
	vbox.add_child(_end_title)

	_end_body = Label.new()
	_end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	SpriteFactory.style_label(_end_body, "body", 8, Color(0.92, 0.90, 0.94))
	vbox.add_child(_end_body)

	_end_buttons.clear()
	_end_retry_btn = Button.new()
	_end_retry_btn.text = "Retry Day"
	_end_retry_btn.pressed.connect(func() -> void: retry_day_requested.emit())
	vbox.add_child(_end_retry_btn)
	_end_buttons.append(_end_retry_btn)

	var b_new: Button = Button.new()
	b_new.text = "New Run"
	b_new.pressed.connect(func() -> void: new_game_requested.emit())
	vbox.add_child(b_new)
	_end_buttons.append(b_new)

	var b_menu: Button = Button.new()
	b_menu.text = "Main Menu"
	b_menu.pressed.connect(func() -> void: return_to_menu_requested.emit())
	vbox.add_child(b_menu)
	_end_buttons.append(b_menu)


func _build_trap_hotbar() -> void:
	_trap_slots.clear()
	_trap_slot_labels.clear()
	var bar_w: float = 342.0
	var start_x: float = floorf((Config.VIEW_SIZE.x - bar_w) * 0.5)
	var bar_y: float = Config.VIEW_SIZE.y - 27.0
	var icons: Array[String] = ["trap_spike", "trap_snare", "trap_lure"]
	for i in range(3):
		var slot: PanelContainer = PanelContainer.new()
		slot.position = Vector2(start_x + float(i) * 116.0, bar_y)
		slot.size = Vector2(110.0, 15.0)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("panel", _make_slot_box(false))
		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 3)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic: TextureRect = TextureRect.new()
		ic.texture = SpriteFactory.get_icon_texture(icons[i])
		ic.custom_minimum_size = Vector2(11.0, 11.0)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(ic)
		var lbl: Label = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		SpriteFactory.style_label(lbl, "body", 8, Color(0.92, 0.90, 0.94))
		hbox.add_child(lbl)
		slot.add_child(hbox)
		_hud_layer.add_child(slot)
		_trap_slots.append(slot)
		_trap_slot_labels.append(lbl)


func _update_trap_hotbar(
	sel_idx: int, trap_mode: bool, n_spike: int, n_snare: int, n_lure: int
) -> void:
	var texts: Array[String] = [
		"[1]Spike %s" % ("x%d" % n_spike if n_spike > 0 else "2P"),
		"[2]Snare %s" % ("x%d" % n_snare if n_snare > 0 else "2P 1S"),
		"[3]Lure %s" % ("x%d" % n_lure if n_lure > 0 else "2P"),
	]
	for i in range(mini(3, _trap_slots.size())):
		var active: bool = trap_mode and (sel_idx == i + 1)
		_trap_slots[i].add_theme_stylebox_override("panel", _make_slot_box(active))
		_trap_slot_labels[i].text = texts[i]
		SpriteFactory.style_label(
			_trap_slot_labels[i],
			"bold" if active else "body",
			8,
			Color(1.0, 0.92, 0.45) if active else Color(0.88, 0.88, 0.94)
		)


func _make_slot_box(active: bool) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = (
		Color(0.24, 0.16, 0.12, 0.94) if active else Color(0.06, 0.05, 0.10, 0.78)
	)
	box.border_color = (
		Color(1.0, 0.84, 0.34, 1.0) if active else Color(0.36, 0.32, 0.42, 0.85)
	)
	box.set_border_width_all(1)
	box.content_margin_left = 4.0
	box.content_margin_right = 4.0
	box.content_margin_top = 1.0
	box.content_margin_bottom = 1.0
	return box


func _mk_menu_btn(parent: VBoxContainer, label: String, cb: Callable) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0.0, 19.0)
	btn.pressed.connect(cb)
	parent.add_child(btn)
	_menu_buttons.append(btn)
	return btn


func _mk_lbl(pos: Vector2, sz: Vector2, style: String, font_px: int, col: Color) -> Label:
	var lbl: Label = Label.new()
	lbl.position = pos
	lbl.size = sz
	SpriteFactory.style_label(lbl, style, font_px, col)
	_hud_layer.add_child(lbl)
	return lbl
