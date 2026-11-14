class_name UpgradeUI
extends CanvasLayer
## T1.6 / T2.2 / T3.3 / T3.4: Clean modal overlays for Inventory (I), Structure Context
## Menus (House / Fence / Ring 3 Foundation), Pause Menu, Controls, Settings, Achievements, Credits.

signal action_triggered(action_id: String, payload: Dictionary)
signal menu_closed()

var active_panel: String = ""  # "", "inventory", "structure", "pause", "info"
var current_structure: Structure = null

var _dimmer: ColorRect = null
var _panel: PanelContainer = null
var _title_lbl: Label = null
var _subtitle_lbl: Label = null
var _list_box: VBoxContainer = null
var _footer_lbl: Label = null
var _buttons: Array[Button] = []
var _selected_idx: int = 0


func _ready() -> void:
	layer = 32
	visible = false
	_build_shell()


func is_open() -> bool:
	return not active_panel.is_empty()


func close_all() -> void:
	if not is_open():
		return
	active_panel = ""
	current_structure = null
	visible = false
	_buttons.clear()
	menu_closed.emit()


## Opens Inventory panel (I) showing Bag + Stockpile + Upgrades + Trap counts (T1.6A).
func open_inventory(
	bag: Inventory,
	stockpile: Inventory,
	player: Player,
	upgrades: Dictionary
) -> void:
	active_panel = "inventory"
	current_structure = null
	visible = true
	_title_lbl.text = "INVENTORY & GEAR"
	_subtitle_lbl.text = (
		"Bag (%d/%d)   |   House Stockpile (Unlimited)"
		% [bag.used_capacity(), bag.capacity]
	)
	_clear_list()

	_add_info_row(
		"Planks",
		"Bag: %d   |   Stockpile: %d" % [bag.count("plank"), stockpile.count("plank")]
	)
	_add_info_row(
		"Scrap",
		"Bag: %d   |   Stockpile: %d" % [bag.count("scrap"), stockpile.count("scrap")]
	)
	_add_info_row(
		"Hunting Bow",
		"Loaded: %d/%d   |   Reserve: %d/%d"
		% [player.mag, player.mag_max, bag.count("arrow"), player.reserve_max]
	)
	_add_info_row(
		"Traps Ready",
		"Spike: %d   Snare: %d   Lure: %d"
		% [bag.count("trap_spike"), bag.count("trap_snare"), bag.count("trap_lure")]
	)

	var up_names: Array[String] = []
	for k in upgrades.keys():
		if bool(upgrades[k]):
			up_names.append(String(k).replace("_", " ").capitalize())
	_add_info_row("Workshop", ", ".join(up_names) if not up_names.is_empty() else "None yet")

	_add_button("Close [I / Esc]", "close", {}, true)
	_footer_lbl.text = "Press I or Esc to return."
	_focus_index(0)


## Opens context upgrade/repair menu for House or Fence (T1.6C / T2.2).
func open_structure_menu(
	st: Structure,
	bag: Inventory,
	stockpile: Inventory,
	act: int,
	upgrades: Dictionary,
	ring_stats: Dictionary,
	watchtower_count: int
) -> void:
	active_panel = "structure"
	current_structure = st
	visible = true
	_clear_list()

	if st.kind == Structure.Kind.HOUSE:
		_build_house_menu(st, bag, stockpile, act, upgrades, watchtower_count)
	else:
		_build_fence_menu(st, bag, stockpile, ring_stats)

	_add_button("Close [Esc]", "close", {}, true)
	_footer_lbl.text = "Up/Down + Enter or Click. Costs draw from Bag + Stockpile."
	_focus_index(0)


## Opens Pause menu (T3.3).
func open_pause_menu() -> void:
	active_panel = "pause"
	current_structure = null
	visible = true
	_title_lbl.text = "PAUSED"
	_subtitle_lbl.text = "Take a breath — the horde waits."
	_clear_list()
	_add_button("Resume", "resume", {}, true)
	_add_button("Controls", "show_controls", {}, true)
	_add_button("Settings", "show_settings", {}, true)
	_add_button("Achievements", "show_achievements", {}, true)
	_add_button("Restart Day", "restart_day", {}, true)
	_add_button("Main Menu", "main_menu", {}, true)
	_footer_lbl.text = "[Esc] Resume"
	_focus_index(0)


## Opens Controls / Settings / Achievements / Credits sub-panels (shared by Main Menu & Pause).
func open_info_panel(kind: String, settings: SettingsStore) -> void:
	active_panel = "info"
	current_structure = null
	visible = true
	_clear_list()

	if kind == "controls":
		_title_lbl.text = "CONTROLS"
		_subtitle_lbl.text = "Keyboard-first (Mouse optional)"
		for row in [
			["Move", "WASD / Arrow Keys"],
			["Spear Melee", "Space"],
			["Hunting Bow (Auto-Aim)", "F or Left Click  |  R Reload"],
			["Door / Interact / Search", "E (Hold E on ruins/cars)"],
			["Structure Upgrade Menu", "U or Click House/Fence"],
			["Inventory / Bounce", "I Inventory  |  Q Shockwave"],
			["Traps (Select / Place)", "1 Spike  2 Snare  3 Lure  |  T Place"],
			["Display / Audio / Pause", "F11 Fullscreen  |  M Mute  |  Esc Pause"],
		]:
			_add_info_row(String(row[0]), String(row[1]))
	elif kind == "settings":
		_title_lbl.text = "SETTINGS"
		_subtitle_lbl.text = "Saved automatically to user://settings.cfg"
		var fs_txt: String = "ON" if settings.fullscreen else "OFF"
		var vol_pct: int = roundi(settings.master_volume * 100.0)
		var shake_txt: String = "ON" if settings.screen_shake else "OFF"
		var intro_txt: String = "ON" if settings.play_intro else "OFF"
		_add_button("Fullscreen: %s" % fs_txt, "toggle_fullscreen", {}, true)
		_add_button("Master Volume: %d%% (Cycle)" % vol_pct, "cycle_volume", {}, true)
		_add_button("Screen Shake: %s" % shake_txt, "toggle_shake", {}, true)
		_add_button("Play Story Intro: %s" % intro_txt, "toggle_intro", {}, true)
	elif kind == "achievements":
		_title_lbl.text = "ACHIEVEMENTS (%d/%d)" % [
			settings.get_unlocked_count(), SettingsStore.ACHIEVEMENT_DEFS.size()
		]
		_subtitle_lbl.text = "Unlocked milestones persist across runs."
		for ach_id in SettingsStore.ACHIEVEMENT_DEFS.keys():
			var d: Dictionary = SettingsStore.ACHIEVEMENT_DEFS[ach_id] as Dictionary
			var done: bool = settings.is_unlocked(String(ach_id))
			var prefix: String = "[X] " if done else "[ ] "
			_add_info_row(prefix + String(d["title"]), String(d["desc"]), done)
	elif kind == "credits":
		_title_lbl.text = "CREDITS"
		_subtitle_lbl.text = "Red Moon (Godot 4.7)"
		_add_info_row("World & Sprites", "TheLazyStone (Post-Apocalyptic Pixel Pack)")
		_add_info_row("Moon Art", "Owner-supplied v2 moon sprites & lunar tiles")
		_add_info_row("Body Font", "Pixel Operator (CC0) by Jayvee Enaguas")
		_add_info_row("Display Font", "KiwiSoda (check license before public release)")
		_add_info_row("Audio & Shaders", "Procedural 8-bit SFX & 2D pixel skies")

	_add_button("Back [Esc]", "close", {}, true)
	_footer_lbl.text = "Up/Down + Enter or Esc to return."
	_focus_index(0)


func _build_house_menu(
	house: Structure,
	bag: Inventory,
	stockpile: Inventory,
	act: int,
	upgrades: Dictionary,
	watchtower_count: int
) -> void:
	if house.is_fallen:
		_title_lbl.text = "HOUSE RUBBLE (FALLEN)"
		_subtitle_lbl.text = "Rebuild the house to restore indoor shelter."
		var cost: Dictionary = (
			Config.COST_HOUSE_REBUILD_ACT1 if act == 1 else Config.COST_HOUSE_REBUILD
		)
		var can_rb: bool = bag.can_afford(cost, stockpile)
		_add_button(
			"Rebuild House (40%% HP) - %s" % Inventory.format_cost(cost),
			"house_rebuild",
			{},
			can_rb
		)
		return

	_title_lbl.text = "FARMHOUSE (Lv %d - %d/%d HP)" % [house.level, house.hp, house.max_hp]
	_subtitle_lbl.text = (
		"Stockpile: %d planks, %d scrap  |  Bag: %d planks, %d scrap"
		% [stockpile.count("plank"), stockpile.count("scrap"), bag.count("plank"), bag.count("scrap")]
	)

	if bag.used_capacity() > 0:
		_add_button("Deposit Bag to Stockpile", "deposit_bag", {}, true)

	if house.hp < house.max_hp:
		var missing_hp: int = house.max_hp - house.hp
		var planks_need: int = maxi(1, ceili(float(missing_hp) / float(Config.PLANK_HEAL)))
		var rep_cost: Dictionary = {"plank": planks_need}
		_add_button(
			"Repair House (+%d HP) - %s" % [missing_hp, Inventory.format_cost(rep_cost)],
			"house_repair",
			{"cost": rep_cost},
			bag.can_afford(rep_cost, stockpile)
		)

	if house.level == 1:
		_add_cost_button(
			"Upgrade House -> Lv 2 (160 HP)",
			"house_upgrade",
			{"level": 2, "cost": Config.COST_HOUSE_LV2},
			Config.COST_HOUSE_LV2,
			bag,
			stockpile
		)
	elif house.level == 2:
		_add_cost_button(
			"Upgrade House -> Lv 3 (240 HP)",
			"house_upgrade",
			{"level": 3, "cost": Config.COST_HOUSE_LV3},
			Config.COST_HOUSE_LV3,
			bag,
			stockpile
		)

	# Workshop / Bow / Traps / Watchtower upgrades (T1.2 / T2.2 / T2.3).
	_add_cost_button(
		"Craft +%d Arrows" % Config.BUY_ARROWS_AMOUNT,
		"buy_arrows",
		{"cost": Config.COST_BUY_ARROWS},
		Config.COST_BUY_ARROWS,
		bag,
		stockpile
	)
	if not bool(upgrades.get("bigger_quiver", false)):
		_add_cost_button(
			"Bigger Quiver (Mag 12 / Res 50)",
			"buy_upgrade",
			{"id": "bigger_quiver", "cost": Config.COST_BIGGER_QUIVER},
			Config.COST_BIGGER_QUIVER,
			bag,
			stockpile
		)
	if not bool(upgrades.get("quick_hands", false)):
		_add_cost_button(
			"Quick Hands (Reload 1.4s)",
			"buy_upgrade",
			{"id": "quick_hands", "cost": Config.COST_QUICK_HANDS},
			Config.COST_QUICK_HANDS,
			bag,
			stockpile
		)
	if not bool(upgrades.get("barbed_arrows", false)):
		_add_cost_button(
			"Barbed Arrows (Pierce +1)",
			"buy_upgrade",
			{"id": "barbed_arrows", "cost": Config.COST_BARBED_ARROWS},
			Config.COST_BARBED_ARROWS,
			bag,
			stockpile
		)
	if not bool(upgrades.get("heavy_bat", false)):
		_add_cost_button(
			"Heavy Spear (Melee 2 dmg)",
			"buy_upgrade",
			{"id": "heavy_bat", "cost": Config.COST_HEAVY_BAT},
			Config.COST_HEAVY_BAT,
			bag,
			stockpile
		)
	if not bool(upgrades.get("swift_boots", false)):
		_add_cost_button(
			"Swift Boots (+15% Speed)",
			"buy_upgrade",
			{"id": "swift_boots", "cost": Config.COST_SWIFT_BOOTS},
			Config.COST_SWIFT_BOOTS,
			bag,
			stockpile
		)
	if not bool(upgrades.get("quick_bounce", false)):
		_add_cost_button(
			"Quick Shockwave (-30% Q CD)",
			"buy_upgrade",
			{"id": "quick_bounce", "cost": Config.COST_QUICK_BOUNCE},
			Config.COST_QUICK_BOUNCE,
			bag,
			stockpile
		)
	if watchtower_count < Config.WATCHTOWER_MAX:
		_add_cost_button(
			"Build Watchtower (%d/%d)" % [watchtower_count, Config.WATCHTOWER_MAX],
			"build_watchtower",
			{"cost": Config.COST_WATCHTOWER},
			Config.COST_WATCHTOWER,
			bag,
			stockpile
		)

	# Craftable traps (stored in bag, placed with 1/2/3 + T).
	for t_key in ["trap_spike", "trap_snare", "trap_lure"]:
		var t_spec: Dictionary = Config.TRAPS[t_key] as Dictionary
		var t_cost: Dictionary = t_spec["cost"] as Dictionary
		_add_cost_button(
			"Craft %s (Owned: %d)" % [String(t_spec["label"]), bag.count(t_key)],
			"craft_trap",
			{"trap_type": t_key, "cost": t_cost},
			t_cost,
			bag,
			stockpile
		)


func _build_fence_menu(
	seg: Structure,
	bag: Inventory,
	stockpile: Inventory,
	ring_stats: Dictionary
) -> void:
	var r: int = seg.ring
	var r_info: Dictionary = ring_stats.get(r, {}) as Dictionary

	if not seg.is_built:
		_title_lbl.text = "RING %d FOUNDATION (UNBUILT)" % r
		_subtitle_lbl.text = "Build a 3rd outer ring to buy more time on late nights."
		_add_cost_button(
			"Build This Segment (50 HP)",
			"fence_build_seg",
			{"seg": seg, "cost": Config.COST_BUILD_RING3_SEG},
			Config.COST_BUILD_RING3_SEG,
			bag,
			stockpile
		)
		var unbuilt_n: int = int(r_info.get("unbuilt", 0))
		if unbuilt_n > 1:
			var ring_cost: Dictionary = {
				"plank": int(Config.COST_BUILD_RING3_SEG["plank"]) * unbuilt_n
			}
			_add_cost_button(
				"Build Entire Ring %d (%d segs)" % [r, unbuilt_n],
				"fence_build_ring",
				{"ring": r, "cost": ring_cost},
				ring_cost,
				bag,
				stockpile
			)
		return

	_title_lbl.text = "FENCE RING %d (Lv %d - %d/%d HP)" % [r, seg.level, seg.hp, seg.max_hp]
	_subtitle_lbl.text = (
		"Stockpile: %d planks, %d scrap  |  Bag: %d planks, %d scrap"
		% [stockpile.count("plank"), stockpile.count("scrap"), bag.count("plank"), bag.count("scrap")]
	)

	if seg.hp < seg.max_hp:
		var need_hp: int = seg.max_hp - seg.hp
		var rep_p: int = maxi(1, ceili(float(need_hp) / float(Config.PLANK_HEAL)))
		var rep_cost: Dictionary = {"plank": rep_p}
		_add_cost_button(
			"Repair Segment (+%d HP)" % need_hp,
			"fence_repair_seg",
			{"seg": seg, "cost": rep_cost},
			rep_cost,
			bag,
			stockpile
		)

	var ring_rep_planks: int = int(r_info.get("repair_planks", 0))
	if ring_rep_planks > 0:
		var r_rep_cost: Dictionary = {"plank": ring_rep_planks}
		_add_cost_button(
			"Repair Entire Ring %d" % r,
			"fence_repair_ring",
			{"ring": r, "cost": r_rep_cost},
			r_rep_cost,
			bag,
			stockpile
		)

	if seg.level == 1:
		_add_cost_button(
			"Upgrade Segment -> Lv 2 (90 HP)",
			"fence_upgrade_seg",
			{"seg": seg, "level": 2, "cost": Config.COST_FENCE_LV2_SEG},
			Config.COST_FENCE_LV2_SEG,
			bag,
			stockpile
		)
	elif seg.level == 2:
		_add_cost_button(
			"Upgrade Segment -> Metal Lv 3 (140 HP)",
			"fence_upgrade_seg",
			{"seg": seg, "level": 3, "cost": Config.COST_FENCE_LV3_SEG},
			Config.COST_FENCE_LV3_SEG,
			bag,
			stockpile
		)

	var lv1_n: int = int(r_info.get("lv1_count", 0))
	if lv1_n > 0:
		var all_lv2: Dictionary = {"plank": int(Config.COST_FENCE_LV2_SEG["plank"]) * lv1_n}
		_add_cost_button(
			"Upgrade All Ring %d -> Lv 2 (%d segs)" % [r, lv1_n],
			"fence_upgrade_ring",
			{"ring": r, "level": 2, "cost": all_lv2},
			all_lv2,
			bag,
			stockpile
		)

	if not seg.spiked:
		_add_cost_button(
			"Add Fence Spikes (Hurts attackers)",
			"fence_spike_seg",
			{"seg": seg, "cost": Config.COST_FENCE_SPIKES_SEG},
			Config.COST_FENCE_SPIKES_SEG,
			bag,
			stockpile
		)


func _add_cost_button(
	label_txt: String,
	action_id: String,
	payload: Dictionary,
	cost: Dictionary,
	bag: Inventory,
	stockpile: Inventory
) -> void:
	var can_pay: bool = bag.can_afford(cost, stockpile)
	var suffix: String = " - " + Inventory.format_cost(cost)
	if not can_pay:
		var miss: Dictionary = bag.missing_for(cost, stockpile)
		suffix += " (Need %s)" % Inventory.format_cost(miss)
	_add_button(label_txt + suffix, action_id, payload, can_pay)


func _add_button(label_txt: String, action_id: String, payload: Dictionary, enabled: bool) -> void:
	var btn: Button = Button.new()
	btn.text = label_txt
	btn.disabled = not enabled
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0.0, 18.0)
	btn.pressed.connect(_on_btn_pressed.bind(action_id, payload))
	_list_box.add_child(btn)
	_buttons.append(btn)


func _add_info_row(left_txt: String, right_txt: String, highlight: bool = false) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	var l_lbl: Label = Label.new()
	l_lbl.text = left_txt
	l_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	SpriteFactory.style_label(
		l_lbl, "bold", 8, Color(1.0, 0.88, 0.45) if highlight else Color(0.95, 0.92, 0.88)
	)
	row.add_child(l_lbl)

	var r_lbl: Label = Label.new()
	r_lbl.text = right_txt
	r_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	SpriteFactory.style_label(r_lbl, "body", 8, Color(0.80, 0.84, 0.90))
	row.add_child(r_lbl)
	_list_box.add_child(row)


func _on_btn_pressed(action_id: String, payload: Dictionary) -> void:
	if action_id == "close" or action_id == "resume":
		close_all()
		return
	action_triggered.emit(action_id, payload)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not (event is InputEventKey):
		return
	var ke: InputEventKey = event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	if ke.keycode == KEY_ESCAPE or (active_panel == "inventory" and ke.keycode == KEY_I):
		get_viewport().set_input_as_handled()
		close_all()
		return
	if _buttons.is_empty():
		return
	if ke.keycode in [KEY_UP, KEY_W]:
		get_viewport().set_input_as_handled()
		_focus_index((_selected_idx - 1 + _buttons.size()) % _buttons.size())
	elif ke.keycode in [KEY_DOWN, KEY_S]:
		get_viewport().set_input_as_handled()
		_focus_index((_selected_idx + 1) % _buttons.size())
	elif ke.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		var btn: Button = _buttons[_selected_idx]
		if not btn.disabled:
			btn.pressed.emit()


func _focus_index(idx: int) -> void:
	if _buttons.is_empty():
		return
	_selected_idx = clampi(idx, 0, _buttons.size() - 1)
	_buttons[_selected_idx].grab_focus()


func _clear_list() -> void:
	_buttons.clear()
	for child in _list_box.get_children():
		child.queue_free()


func _build_shell() -> void:
	_dimmer = ColorRect.new()
	_dimmer.position = Vector2.ZERO
	_dimmer.size = Config.VIEW_SIZE
	_dimmer.color = Color(0.03, 0.02, 0.06, 0.68)
	add_child(_dimmer)

	_panel = PanelContainer.new()
	_panel.position = Vector2(96.0, 26.0)
	_panel.size = Vector2(Config.VIEW_SIZE.x - 192.0, Config.VIEW_SIZE.y - 52.0)
	_panel.theme = SpriteFactory.get_game_theme()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.07, 0.13, 0.97)
	style.border_color = Color(0.84, 0.36, 0.34, 1.0)
	style.set_border_width_all(2)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_panel.add_child(vbox)

	_title_lbl = Label.new()
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SpriteFactory.style_label(_title_lbl, "display", 16, Color(1.0, 0.88, 0.56))
	vbox.add_child(_title_lbl)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SpriteFactory.style_label(_subtitle_lbl, "body", 8, Color(0.80, 0.82, 0.88))
	vbox.add_child(_subtitle_lbl)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_list_box)

	_footer_lbl = Label.new()
	_footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SpriteFactory.style_label(_footer_lbl, "body", 8, Color(0.68, 0.66, 0.74))
	vbox.add_child(_footer_lbl)
