class_name Hud
extends CanvasLayer

# 640x360 pixel hud, title screen, trap bar, and game over / victory screen

signal play_requested(continue_run: bool)
signal menu_panel_requested(panel_kind: String)
signal trap_slot_clicked(slot_idx: int)
signal tame_dog_requested()
signal quit_requested()
signal retry_day_requested()
signal new_game_requested()
signal return_to_menu_requested()

var _root: Control
var _hud_layer: Control

# top-left bars
var _hp_fill: ColorRect
var _hp_lbl: Label
var _house_lbl: Label
var _house_icon: TextureRect
var _bag_lbl: Label
var _bow_lbl: Label

# top-center clock & objective
var _day_lbl: Label
var _objective_lbl: Label

# top-right & bottom trap hotbar
var _bounce_lbl: Label
var _hint_lbl: Label
var _status_lbl: Label
var _trap_slots: Array[PanelContainer] = []
var _trap_slot_labels: Array[Label] = []
var _trap_count_lbl: Label
var _slot_box_normal: StyleBox
var _slot_box_active: StyleBox
var _slot_active_state: Array[bool] = [false, false, false]
var _slot_has_stock: Array[bool] = [true, true, true]

# popups & overlays
var _header_panel: PanelContainer
var _header_title: Label
var _header_sub: Label
var _header_timer: float = 0.0
var _toast_lbl: Label
var _toast_timer: float = 0.0
var _prompt_lbl: Label
var _tooltip_lbl: Label
var _tame_btn: Button
var _search_bar_bg: ColorRect
var _search_bar_fill: ColorRect
var _home_arrow_holder: Node2D
var _home_arrow_poly: Polygon2D
var _home_arrow: Label
var _vignette: ColorRect

# title & end screen
var _title_screen: Control
var _menu_sky: MoonSky
var _menu_buttons: Array[Button] = []
var _menu_continue_btn: Button
var _menu_idx: int = 0
var _end_screen: Control
var _end_title: Label
var _end_body: Label
var _end_retry_btn: Button
var _end_buttons: Array[Button] = []
var _end_idx: int = 0


func _ready() -> void:
	layer = 20
	_root = get_node("Root") as Control
	_root.theme = Art.get_game_theme()

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
	_menu_sky.moon_progress = 0.96
	_menu_sky.red_blend = 0.92
	_menu_continue_btn.visible = has_continue
	_menu_idx = 1 if has_continue else 0
	_focus_menu_button(_menu_idx)


func show_gameplay_hud() -> void:
	_title_screen.visible = false
	_end_screen.visible = false
	_hud_layer.visible = true


func hide_all_screens() -> void:
	_title_screen.visible = false
	_hud_layer.visible = false
	_end_screen.visible = false


func show_end_screen(victory: bool, title_txt: String, body_txt: String, can_retry: bool) -> void:
	_title_screen.visible = false
	_hud_layer.visible = false
	_end_screen.visible = true
	_end_title.text = title_txt
	Art.style_label(
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


func show_header_banner(
	title_txt: String,
	subtitle_txt: String,
	accent: Color,
	dur: float = 2.6
) -> void:
	_header_title.text = title_txt
	Art.style_label(_header_title, "display", 16, accent)
	_header_sub.text = subtitle_txt
	_header_panel.modulate.a = 1.0
	_header_panel.visible = true
	_header_timer = dur


func show_message(text: String, duration: float = 2.0, col: Color = Color(1.0, 0.92, 0.68)) -> void:
	_toast_lbl.text = text
	Art.style_label(_toast_lbl, "bold", 8, col)
	_toast_lbl.modulate.a = 1.0
	_toast_lbl.visible = true
	_toast_timer = duration


func update_hud(data: Dictionary) -> void:
	var hp = int(data.get("hp", 50))
	var max_hp = maxi(1, int(data.get("max_hp", 50)))
	_hp_fill.size.x = floorf(78.0 * clampf(float(hp) / float(max_hp), 0.0, 1.0))
	_hp_lbl.text = "HP %d/%d" % [hp, max_hp]

	var house_fallen = bool(data.get("house_fallen", false))
	var house_hp = int(data.get("house_hp", 100))
	var house_max = int(data.get("house_max", 100))
	var door_open = bool(data.get("door_open", false))
	var intruders = int(data.get("intruders", 0))
	if house_fallen:
		_house_lbl.text = "HOUSE FALLEN!"
		Art.style_label(_house_lbl, "bold", 8, Color(1.0, 0.42, 0.36))
		_house_icon.texture = Art.get_icon_texture("broken_house")
		_house_icon.visible = true
	else:
		var door_tag = "OPEN!" if door_open else "Shut"
		_house_lbl.text = "House %d/%d (%s)" % [house_hp, house_max, door_tag]
		Art.style_label(
			_house_lbl,
			"bold",
			8,
			Color(1.0, 0.72, 0.35) if door_open else Color(0.84, 0.92, 0.86)
		)
		_house_icon.texture = Art.get_icon_texture(
			"broken_house" if intruders > 0 else "house_icon"
		)
		_house_icon.visible = true

	_bag_lbl.text = "Bag %d/%d P:%d S:%d | Stock P:%d S:%d" % [
		int(data.get("bag_used", 0)),
		int(data.get("bag_cap", 16)),
		int(data.get("bag_planks", 0)),
		int(data.get("bag_scrap", 0)),
		int(data.get("stock_planks", 0)),
		int(data.get("stock_scrap", 0)),
	]

	var reloading = bool(data.get("reloading", false))
	var mag_n = int(data.get("mag", Config.BOW_MAG))
	var mag_max_n = int(data.get("mag_max", Config.BOW_MAG))
	var arrows_n = int(data.get("arrows", 0))
	var bow_cd = float(data.get("bow_cd", 0.0))
	var rang_cd = float(data.get("boomerang_cd", 0.0))
	var rang_flying = bool(data.get("boomerang_flying", false))
	var active_w = String(data.get("active_weapon", "bow"))
	var w_def: Dictionary = Config.WEAPON_DEFS.get(active_w, {})
	var w_tag = String(w_def.get("short_label", active_w.capitalize()))
	if active_w == "boomerang":
		if rang_flying:
			_bow_lbl.text = "Boomerang: IN FLIGHT"
			Art.style_label(_bow_lbl, "bold", 8, Color(0.56, 0.96, 1.0))
		elif rang_cd > 0.05:
			_bow_lbl.text = "Boomerang: CD %.1fs" % rang_cd
			Art.style_label(_bow_lbl, "bold", 8, Color(1.0, 0.82, 0.42))
		else:
			_bow_lbl.text = "Boomerang: READY [Click]"
			Art.style_label(_bow_lbl, "bold", 8, Color(0.62, 0.96, 0.68))
	elif active_w != "bow":
		var extra_cd := " | R %.1fs" % rang_cd if rang_cd > 0.05 else " (%d)" % arrows_n
		_bow_lbl.text = "%s | Bow %d/%d%s" % [w_tag, mag_n, mag_max_n, extra_cd]
		Art.style_label(_bow_lbl, "bold", 8, Color(0.95, 0.86, 0.56))
	elif reloading:
		_bow_lbl.text = "Bow: Reloading... (%d)" % arrows_n
		Art.style_label(_bow_lbl, "bold", 8, Color(1.0, 0.82, 0.40))
	elif mag_n <= 0 and arrows_n <= 0:
		_bow_lbl.text = "Bow: 0/0 (OUT!)"
		Art.style_label(_bow_lbl, "bold", 8, Color(1.0, 0.42, 0.36))
	elif bow_cd > 0.05:
		_bow_lbl.text = "Bow %d/%d (%d) %.1fs" % [mag_n, mag_max_n, arrows_n, bow_cd]
		Art.style_label(_bow_lbl, "bold", 8, Color(1.0, 0.86, 0.56))
	else:
		_bow_lbl.text = "Bow %d/%d (%d) [Click]" % [mag_n, mag_max_n, arrows_n]
		Art.style_label(_bow_lbl, "bold", 8, Color(0.92, 0.94, 1.0))

	var secs = maxi(0, ceili(float(data.get("time_left", 0.0))))
	var clk = "%d:%02d" % [int(floorf(float(secs) / 60.0)), secs % 60]
	_day_lbl.text = "%s   %s" % [String(data.get("phase_label", "DAY 1")), clk]
	_objective_lbl.text = String(data.get("objective", ""))

	var b_cd = float(data.get("bounce_cd", 0.0))
	_bounce_lbl.text = (
		"[B] Bounce Home READY" if b_cd <= 0.0 else "[B] Bounce Home %.0fs" % ceilf(b_cd)
	)
	Art.style_label(
		_bounce_lbl, "bold", 8, Color(0.62, 0.94, 1.0) if b_cd <= 0.0 else Color(0.66, 0.66, 0.72)
	)

	var n_snare = int(data.get("trap_snare", 0))
	var n_spike = int(data.get("trap_spike", 0))
	var n_lure = int(data.get("trap_lure", 0))
	_update_trap_hotbar(
		int(data.get("selected_trap", 1)),
		bool(data.get("trap_mode_active", false)),
		n_snare,
		n_spike,
		n_lure,
		int(data.get("traps_placed", 0)),
		int(data.get("traps_max", Config.MAX_TRAPS))
	)

	var extras: Array[String] = []
	if bool(data.get("inside_house", false)):
		extras.append("INDOORS (Safe - Shoot w/ F, E Exit)")
	if intruders > 0:
		extras.append("ZOMBIES INSIDE: %d! [Space] Clear" % intruders)
	if bool(data.get("muted", false)):
		extras.append("MUTED [M]")
	_status_lbl.text = "  |  ".join(extras)
	_status_lbl.visible = not extras.is_empty()

	var prompt_txt = String(data.get("prompt", ""))
	_prompt_lbl.text = prompt_txt
	_prompt_lbl.visible = not prompt_txt.is_empty()

	var tip_txt = String(data.get("tooltip", ""))
	_tooltip_lbl.text = tip_txt
	_tooltip_lbl.visible = not tip_txt.is_empty()

	if _tame_btn != null:
		_tame_btn.visible = bool(data.get("can_tame_dog", false))

	var search_frac = float(data.get("search_progress", 0.0))
	_search_bar_bg.visible = search_frac > 0.0
	_search_bar_fill.size.x = floorf(84.0 * clampf(search_frac, 0.0, 1.0))

	# points back toward the farmhouse base only when player is within 50m
	var home_dir = data.get("home_arrow_dir", Vector2.ZERO)
	if home_dir.length_squared() > 0.01:
		var dir_n = home_dir.normalized()
		var edge = Config.VIEW_SIZE * 0.5 + dir_n * Vector2(276.0, 120.0)
		var pos = Vector2(
			clampf(edge.x, 24.0, Config.VIEW_SIZE.x - 24.0),
			clampf(edge.y, 60.0, Config.VIEW_SIZE.y - 74.0)
		).round()
		_home_arrow_holder.visible = true
		_home_arrow_holder.position = pos
		_home_arrow_poly.rotation = dir_n.angle()
		_home_arrow.visible = true
		_home_arrow.text = "BASE %dm" % int(data.get("home_dist", 0))
		_home_arrow.position = Vector2(
			clampf(pos.x - 29.0, 4.0, Config.VIEW_SIZE.x - 62.0),
			pos.y + (10.0 if pos.y < Config.VIEW_SIZE.y - 92.0 else -19.0)
		).round()
	else:
		_home_arrow_holder.visible = false
		_home_arrow.visible = false

	# red screen tint when hp is critical or zombies got inside
	if intruders > 0 or (hp > 0 and hp <= 15):
		_vignette.visible = true
		_vignette.color = Color(0.75, 0.08, 0.08, 0.16)
	else:
		_vignette.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke = event
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
	var idx = _menu_idx if is_title else _end_idx
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
	_hud_layer = get_node("Root/HudLayer") as Control
	_vignette = get_node("Root/HudLayer/Vignette") as ColorRect
	_hp_fill = get_node("Root/HudLayer/HpFill") as ColorRect

	_hp_lbl = _bind_lbl("Root/HudLayer/HpLabel", "bold", 8, Color.WHITE)
	_house_icon = get_node("Root/HudLayer/HouseIcon") as TextureRect
	_house_lbl = _bind_lbl("Root/HudLayer/HouseLabel", "bold", 8, Color(0.86, 0.94, 0.86))
	_bag_lbl = _bind_lbl("Root/HudLayer/BagLabel", "body", 8, Color(0.95, 0.86, 0.62))

	_day_lbl = _bind_lbl("Root/HudLayer/DayLabel", "bold", 8, Color(1.0, 0.90, 0.64))
	_objective_lbl = _bind_lbl("Root/HudLayer/ObjectiveLabel", "body", 8, Color(0.98, 0.92, 0.72))

	_bow_lbl = _bind_lbl("Root/HudLayer/BowLabel", "bold", 8, Color(0.92, 0.94, 1.0))
	_bounce_lbl = _bind_lbl("Root/HudLayer/BounceLabel", "bold", 8, Color(0.62, 0.94, 1.0))
	_hint_lbl = _bind_lbl("Root/HudLayer/HintLabel", "body", 8, Color(0.80, 0.84, 0.92))
	_status_lbl = _bind_lbl("Root/HudLayer/StatusLabel", "bold", 8, Color(1.0, 0.78, 0.42))

	_build_trap_hotbar()

	_header_panel = get_node("Root/HudLayer/HeaderPanel") as PanelContainer
	_header_panel.add_theme_stylebox_override(
		"panel",
		Art.make_panel_style("res://assets/ui/panel.png", 10.0, 10.0, 6.0)
	)
	_header_title = _bind_lbl(
		"Root/HudLayer/HeaderPanel/VBox/HeaderTitle", "display", 16, Color(1.0, 0.88, 0.56)
	)
	_header_sub = _bind_lbl(
		"Root/HudLayer/HeaderPanel/VBox/HeaderSub", "body", 8, Color(0.92, 0.90, 0.94)
	)

	_tame_btn = get_node("Root/HudLayer/TameButton") as Button
	_tame_btn.pressed.connect(func() -> void: tame_dog_requested.emit())

	_toast_lbl = _bind_lbl("Root/HudLayer/ToastLabel", "bold", 8, Color.WHITE)
	_search_bar_bg = get_node("Root/HudLayer/SearchBarBg") as ColorRect
	_search_bar_fill = get_node("Root/HudLayer/SearchBarBg/SearchBarFill") as ColorRect
	_prompt_lbl = _bind_lbl("Root/HudLayer/PromptLabel", "bold", 8, Color(1.0, 0.92, 0.56))
	_tooltip_lbl = _bind_lbl("Root/HudLayer/TooltipLabel", "body", 8, Color(0.84, 0.88, 0.94))

	_home_arrow_holder = get_node("Root/HudLayer/HomeArrowHolder") as Node2D
	_home_arrow_poly = get_node("Root/HudLayer/HomeArrowHolder/ArrowPoly") as Polygon2D
	_home_arrow = _bind_lbl("Root/HudLayer/HomeArrowLabel", "bold", 8, Color(1.0, 0.90, 0.42))


func _build_title_screen() -> void:
	_title_screen = get_node("Root/TitleScreen") as Control

	_menu_sky = get_node("Root/TitleScreen/MenuSky") as MoonSky
	_menu_sky.build(Config.VIEW_SIZE)

	_bind_lbl("Root/TitleScreen/TitleLabel", "display", 32, Color(1.0, 0.34, 0.30))
	_bind_lbl("Root/TitleScreen/SubtitleLabel", "bold", 8, Color(0.95, 0.88, 0.84))

	_menu_buttons.clear()
	_menu_continue_btn = _wire_menu_btn(
		"Root/TitleScreen/Buttons/ContinueButton", func() -> void: play_requested.emit(true)
	)
	_menu_continue_btn.visible = false
	_wire_menu_btn(
		"Root/TitleScreen/Buttons/PlayButton", func() -> void: play_requested.emit(false)
	)
	_wire_menu_btn(
		"Root/TitleScreen/Buttons/TutorialButton",
		func() -> void: menu_panel_requested.emit("tutorial")
	)
	_wire_menu_btn(
		"Root/TitleScreen/Buttons/ControlsButton",
		func() -> void: menu_panel_requested.emit("controls")
	)
	_wire_menu_btn(
		"Root/TitleScreen/Buttons/SettingsButton",
		func() -> void: menu_panel_requested.emit("settings")
	)
	_wire_menu_btn(
		"Root/TitleScreen/Buttons/AchievementsButton",
		func() -> void: menu_panel_requested.emit("achievements")
	)
	_wire_menu_btn(
		"Root/TitleScreen/Buttons/CreditsButton",
		func() -> void: menu_panel_requested.emit("credits")
	)
	var b_quit := get_node("Root/TitleScreen/Buttons/QuitButton") as Button
	if OS.has_feature("web"):
		b_quit.visible = false
	else:
		_wire_menu_btn(
			"Root/TitleScreen/Buttons/QuitButton", func() -> void: quit_requested.emit()
		)

	_bind_lbl("Root/TitleScreen/VersionLabel", "body", 8, Color(0.72, 0.68, 0.78))


func _build_end_screen() -> void:
	_end_screen = get_node("Root/EndScreen") as Control

	var panel := get_node("Root/EndScreen/Panel") as PanelContainer
	panel.add_theme_stylebox_override(
		"panel",
		Art.make_panel_style("res://assets/ui/panel.png", 10.0, 14.0, 12.0)
	)

	_end_title = _bind_lbl(
		"Root/EndScreen/Panel/VBox/EndTitle", "display", 16, Color(1.0, 0.38, 0.34)
	)
	_end_body = _bind_lbl(
		"Root/EndScreen/Panel/VBox/EndBody", "body", 8, Color(0.92, 0.90, 0.94)
	)

	_end_buttons.clear()
	_end_retry_btn = get_node("Root/EndScreen/Panel/VBox/RetryButton") as Button
	_end_retry_btn.pressed.connect(func() -> void: retry_day_requested.emit())
	_end_buttons.append(_end_retry_btn)

	var b_new := get_node("Root/EndScreen/Panel/VBox/NewRunButton") as Button
	b_new.pressed.connect(func() -> void: new_game_requested.emit())
	_end_buttons.append(b_new)

	var b_menu := get_node("Root/EndScreen/Panel/VBox/MainMenuButton") as Button
	b_menu.pressed.connect(func() -> void: return_to_menu_requested.emit())
	_end_buttons.append(b_menu)


func _build_trap_hotbar() -> void:
	_trap_slots.clear()
	_trap_slot_labels.clear()
	_slot_box_normal = _make_slot_box(false)
	_slot_box_active = _make_slot_box(true)
	_slot_active_state = [false, false, false]

	_trap_count_lbl = _bind_lbl(
		"Root/HudLayer/TrapCountLabel", "body", 8, Color(0.92, 0.88, 0.72)
	)

	var icons: Array[String] = ["trap_snare", "trap_spike", "trap_lure"]
	var slot_paths: Array[String] = [
		"Root/HudLayer/TrapSlot1",
		"Root/HudLayer/TrapSlot2",
		"Root/HudLayer/TrapSlot3",
	]
	for i in range(3):
		var slot_idx := i + 1
		var slot := get_node(slot_paths[i]) as PanelContainer
		slot.add_theme_stylebox_override("panel", _slot_box_normal)
		slot.gui_input.connect(func(ev: InputEvent) -> void:
			var is_click := false
			if ev is InputEventMouseButton:
				var mb: InputEventMouseButton = ev as InputEventMouseButton
				is_click = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
			var is_tap := false
			if ev is InputEventScreenTouch:
				is_tap = (ev as InputEventScreenTouch).pressed
			if is_click or is_tap:
				get_viewport().set_input_as_handled()
				trap_slot_clicked.emit(slot_idx)
		)
		var ic := slot.get_node("HBox/Icon") as TextureRect
		ic.texture = Art.get_icon_texture(icons[i])
		var lbl := slot.get_node("HBox/Label") as Label
		Art.style_label(lbl, "body", 8, Color(0.88, 0.88, 0.94))
		_trap_slots.append(slot)
		_trap_slot_labels.append(lbl)


func _update_trap_hotbar(
	sel_idx: int,
	trap_mode: bool,
	n_snare: int,
	n_spike: int,
	n_lure: int,
	placed: int,
	max_placed: int
) -> void:
	var counts: Array[int] = [n_snare, n_spike, n_lure]
	var texts: Array[String] = [
		"[1]Bear x%d" % n_snare,
		"[2]Spike x%d" % n_spike,
		"[3]Lure x%d" % n_lure,
	]
	if _trap_count_lbl != null:
		var total_left = n_snare + n_spike + n_lure
		_trap_count_lbl.text = (
			"Traps Left: %d  |  Placed: %d/%d  |  Craft [C]"
			% [total_left, placed, max_placed]
		)
	for i in range(mini(3, _trap_slots.size())):
		var active = trap_mode and (sel_idx == i + 1)
		var has_stock = counts[i] > 0
		if _trap_slot_labels[i].text != texts[i]:
			_trap_slot_labels[i].text = texts[i]
		if _slot_active_state[i] != active or _slot_has_stock[i] != has_stock:
			_slot_active_state[i] = active
			_slot_has_stock[i] = has_stock
			_trap_slots[i].add_theme_stylebox_override(
				"panel", _slot_box_active if active else _slot_box_normal
			)
			var col = (
				Color(1.0, 0.92, 0.45) if active
				else (Color(0.88, 0.88, 0.94) if has_stock else Color(0.75, 0.46, 0.46))
			)
			Art.style_label(_trap_slot_labels[i], "bold" if active else "body", 8, col)


func _make_slot_box(active: bool) -> StyleBox:
	var path := "res://assets/ui/slot_active.png" if active else "res://assets/ui/slot.png"
	return Art.make_panel_style(
		path,
		4.0,
		4.0,
		1.0,
		Color(0.24, 0.16, 0.12, 0.94) if active else Color(0.06, 0.05, 0.10, 0.78),
		Color(1.0, 0.84, 0.34, 1.0) if active else Color(0.36, 0.32, 0.42, 0.85)
	)


func _wire_menu_btn(node_path: String, cb: Callable) -> Button:
	var btn := get_node(node_path) as Button
	btn.pressed.connect(cb)
	_menu_buttons.append(btn)
	return btn


func _bind_lbl(node_path: String, style: String, font_px: int, col: Color) -> Label:
	var lbl := get_node(node_path) as Label
	Art.style_label(lbl, style, font_px, col)
	return lbl
