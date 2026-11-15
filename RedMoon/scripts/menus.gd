class_name Menus
extends CanvasLayer

# popup menus: backpack, house/fence upgrades, pause, settings, controls, achievements

signal action_triggered(action_id: String, data: Dictionary)
signal menu_closed()

var active_panel: String = ""  # "", "inventory", "structure", "pause", "info"
var current_structure: Structure

var _dimmer: ColorRect
var _panel: PanelContainer
var _title_lbl: Label
var _subtitle_lbl: Label
var _list_box: VBoxContainer
var _footer_lbl: Label
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


func open_inventory(
	bag: Bag,
	stockpile: Bag,
	player: Player,
	upgrades: Dictionary
) -> void:
	active_panel = "inventory"
	current_structure = null
	visible = true
	_set_panel_size(380.0, 212.0)
	_title_lbl.text = "INVENTORY"
	_subtitle_lbl.text = (
		"Bag (%d/%d)   |   Stockpile (Unlimited)" % [bag.used_capacity(), bag.capacity]
	)
	_clear_list()

	_add_info_row(
		"Planks", "Bag: %d   |   Stock: %d" % [bag.count("plank"), stockpile.count("plank")]
	)
	_add_info_row(
		"Scrap", "Bag: %d   |   Stock: %d" % [bag.count("scrap"), stockpile.count("scrap")]
	)
	_add_info_row(
		"Hunting Bow",
		"Loaded: %d/%d   |   Reserve: %d/%d"
		% [player.mag, player.mag_max, bag.count("arrow"), player.reserve_max]
	)
	_add_info_row(
		"Traps Owned",
		"Bear: %d   Spike: %d   Lure: %d"
		% [bag.count("trap_snare"), bag.count("trap_spike"), bag.count("trap_lure")]
	)
	_add_info_row("Gear Tier", "Tier %d / 3" % int(upgrades.get("gear_tier", 1)))

	_add_button("Close [I / Esc]", "close", {}, true)
	_footer_lbl.text = "Tip: Press 1-3 or click trap slots to place; craft more at House [U]!"
	_focus_index(0)


func open_structure_menu(
	st: Structure,
	bag: Bag,
	stockpile: Bag,
	act: int,
	upgrades: Dictionary,
	ring_stats: Dictionary,
	watchtower_count: int
) -> void:
	active_panel = "structure"
	current_structure = st
	visible = true
	_set_panel_size(396.0, 268.0)
	_clear_list()

	if st.kind == Structure.Kind.HOUSE:
		_build_house_menu(st, bag, stockpile, act, upgrades, ring_stats, watchtower_count)
	else:
		_build_fence_menu(st, bag, stockpile, ring_stats)

	_add_button("Close [Esc]", "close", {}, true)
	_footer_lbl.text = "Up/Down + Enter or Click   |   Draws from Bag + Stockpile"
	_focus_index(0)


func open_pause_menu() -> void:
	active_panel = "pause"
	current_structure = null
	visible = true
	_set_panel_size(300.0, 248.0)
	_title_lbl.text = "PAUSED"
	_subtitle_lbl.text = "Paused."
	_clear_list()
	_add_button("Resume", "resume", {}, true)
	_add_button("Tutorial", "show_tutorial", {}, true)
	_add_button("Controls", "show_controls", {}, true)
	_add_button("Settings", "show_settings", {}, true)
	_add_button("Achievements", "show_achievements", {}, true)
	_add_button("Restart Day", "restart_day", {}, true)
	_add_button("Main Menu", "main_menu", {}, true)
	_footer_lbl.text = "[Esc] Resume"
	_focus_index(0)


func open_info_panel(kind: String, settings: SaveData) -> void:
	active_panel = "info"
	current_structure = null
	visible = true
	_set_panel_size(456.0, 278.0)
	_clear_list()

	if kind == "tutorial":
		_title_lbl.text = "HOW TO PLAY"
		_subtitle_lbl.text = "Survive 7 nights and hold the farmhouse"
		for step in [
			["1. Morning Gather", "Exit the open south gate; pick up planks & hold E on wrecks."],
			["2. Store & Upgrade", "Walk by the house to store loot. Press U to upgrade/craft."],
			["3. Spear & Bow", "Space swings spear. Click/Tap or F auto-aims bow (1.5s CD)."],
			["4. Bear Traps", "Press 1-3 or click slot, then click/T. Craft at House [U]."],
			["5. Bounce Back", "Press B anytime to teleport home and start healing!"],
			["6. Night Shelter", "Close fence gates [E] at dusk & enter the front door [E]."],
			["7. Dogs & Arrow", "Follow the BASE arrow home. Hold E on strays (G Follow/Guard)."],
		]:
			_add_info_row(String(step[0]), String(step[1]))
	elif kind == "controls":
		_title_lbl.text = "CONTROLS"
		_subtitle_lbl.text = "Keyboard + Mouse"
		for row in [
			["Move", "WASD / Arrow Keys"],
			["Spear / Bow / Reload", "Space Melee  |  Click or F Bow (1.5s)  |  R Reload"],
			["Door / Fence Gate / Search", "E Open-Close Door or Gate  |  Hold E Search/Tame"],
			["Place Traps", "1 Bear  2 Spike  3 Lure (or Click Slot)  |  Click/T Place"],
			["Bounce Back / Shockwave", "B Recall Home & Heal  |  Q Shockwave"],
			["Upgrade House / Ring", "U or Right-Click House / Fence"],
			["Bag / Dog / Pause", "I Bag  |  G Dog Mode  |  F11 Fullscreen  |  Esc Pause"],
		]:
			_add_info_row(String(row[0]), String(row[1]))
	elif kind == "settings":
		_title_lbl.text = "SETTINGS"
		_subtitle_lbl.text = "Saved automatically"
		var fs_txt = "ON" if settings.fullscreen else "OFF"
		var vol_pct = roundi(settings.master_volume * 100.0)
		var shake_txt = "ON" if settings.screen_shake else "OFF"
		var intro_txt = "ON" if settings.play_intro else "OFF"
		_add_button("Fullscreen: %s" % fs_txt, "toggle_fullscreen", {}, true)
		_add_button("Master Volume: %d%%" % vol_pct, "cycle_volume", {}, true)
		_add_button("Screen Shake: %s" % shake_txt, "toggle_shake", {}, true)
		_add_button("Play Story Intro: %s" % intro_txt, "toggle_intro", {}, true)
	elif kind == "achievements":
		_title_lbl.text = "ACHIEVEMENTS (%d/%d)" % [
			settings.get_unlocked_count(), SaveData.ACHIEVEMENT_DEFS.size()
		]
		_subtitle_lbl.text = "Persisted across runs"
		for ach_id in SaveData.ACHIEVEMENT_DEFS.keys():
			var d = SaveData.ACHIEVEMENT_DEFS[ach_id]
			var done = settings.is_unlocked(String(ach_id))
			_add_info_row(("[X] " if done else "[ ] ") + String(d["title"]), String(d["desc"]), done)
	elif kind == "credits":
		_title_lbl.text = "CREDITS"
		_subtitle_lbl.text = "Moonrise (Godot 4.7)"
		_add_info_row("Game Designer & Lead Developer", "Abdul Haseeb", true)
		_add_info_row("Secondary Designer", "Waseem Qadir", true)
		_add_info_row("Helper", "Bilal", true)
		_add_info_row("World & Sprites", "TheLazyStone + Custom 3/4 Cottage")
		_add_info_row("Fonts", "Pixel Operator (CC0) & KiwiSoda")
		_add_info_row("Audio", "Procedural 8-bit Web-safe SFX")

	_add_button("Back [Esc]", "close", {}, true)
	_footer_lbl.text = "[Esc] Back"
	_focus_index(0)


func _build_house_menu(
	house: Structure,
	bag: Bag,
	stockpile: Bag,
	act: int,
	upgrades: Dictionary,
	ring_stats: Dictionary,
	watchtower_count: int
) -> void:
	var tot_p = bag.count("plank") + stockpile.count("plank")
	var tot_s = bag.count("scrap") + stockpile.count("scrap")

	if house.is_fallen:
		_title_lbl.text = "HOUSE RUBBLE"
		_subtitle_lbl.text = "Planks: %d  |  Scrap: %d" % [tot_p, tot_s]
		var rb_cost = (
			Config.COST_HOUSE_REBUILD_ACT1 if act == 1 else Config.COST_HOUSE_REBUILD
		)
		_add_cost_button("Rebuild House (40%% HP)", "house_rebuild", {}, rb_cost, bag, stockpile)
		return

	_title_lbl.text = "FARMHOUSE (Lv %d - %d/%d HP)" % [house.level, house.hp, house.max_hp]
	_subtitle_lbl.text = "Available: %d planks, %d scrap" % [tot_p, tot_s]

	if house.hp < house.max_hp:
		var missing_hp = house.max_hp - house.hp
		var planks_need = maxi(1, ceili(float(missing_hp) / float(Config.PLANK_HEAL)))
		var rep_cost = {"plank": planks_need}
		_add_cost_button(
			"Repair House (+%d HP)" % missing_hp,
			"house_repair",
			{"cost": rep_cost},
			rep_cost,
			bag,
			stockpile
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

	# outer fence rings (ring 2 then ring 3, each comes with its own gate)
	var r2_built = bool((ring_stats.get(2, {})).get("built", false))
	var r3_built = bool((ring_stats.get(3, {})).get("built", false))
	if not r2_built:
		_add_cost_button(
			"Unlock Fence Layer 2 (Whole Ring + Gate)",
			"unlock_fence_layer",
			{"ring": 2, "cost": Config.COST_UNLOCK_RING2},
			Config.COST_UNLOCK_RING2,
			bag,
			stockpile
		)
	elif not r3_built:
		_add_cost_button(
			"Unlock Fence Layer 3 (Whole Ring + Gate)",
			"unlock_fence_layer",
			{"ring": 3, "cost": Config.COST_UNLOCK_RING3},
			Config.COST_UNLOCK_RING3,
			bag,
			stockpile
		)

	# bundled weapon + gear upgrade instead of cluttering the menu with 6 separate rows
	var g_tier = int(upgrades.get("gear_tier", 1))
	if g_tier == 1:
		_add_cost_button(
			"Upgrade Gear -> Tier 2 (Pierce Bow, +DMG, +Spd)",
			"upgrade_gear",
			{"tier": 2, "cost": Config.COST_GEAR_TIER2},
			Config.COST_GEAR_TIER2,
			bag,
			stockpile
		)
	elif g_tier == 2:
		_add_cost_button(
			"Upgrade Gear -> Tier 3 (2x Bow DMG, Fast Reload)",
			"upgrade_gear",
			{"tier": 3, "cost": Config.COST_GEAR_TIER3},
			Config.COST_GEAR_TIER3,
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

	_add_cost_button(
		"Restock +%d Arrows" % Config.BUY_ARROWS_AMOUNT,
		"buy_arrows",
		{"cost": Config.COST_BUY_ARROWS},
		Config.COST_BUY_ARROWS,
		bag,
		stockpile
	)

	var bear_cost = (Config.TRAPS["trap_snare"])["cost"]
	_add_cost_button(
		"Craft +2 Bear Traps (Owned: %d)" % bag.count("trap_snare"),
		"craft_trap",
		{"trap_key": "trap_snare", "qty": 2, "cost": bear_cost},
		bear_cost,
		bag,
		stockpile
	)
	var spike_cost = (Config.TRAPS["trap_spike"])["cost"]
	_add_cost_button(
		"Craft +2 Spike Traps (Owned: %d)" % bag.count("trap_spike"),
		"craft_trap",
		{"trap_key": "trap_spike", "qty": 2, "cost": spike_cost},
		spike_cost,
		bag,
		stockpile
	)
	var lure_cost = (Config.TRAPS["trap_lure"])["cost"]
	_add_cost_button(
		"Craft +1 Decoy Lure (Owned: %d)" % bag.count("trap_lure"),
		"craft_trap",
		{"trap_key": "trap_lure", "qty": 1, "cost": lure_cost},
		lure_cost,
		bag,
		stockpile
	)


# upgrades apply to the whole ring at once, per-segment clicking was way too tedious
func _build_fence_menu(
	seg: Structure,
	bag: Bag,
	stockpile: Bag,
	ring_stats: Dictionary
) -> void:
	var r = seg.ring
	var r_info = ring_stats.get(r, {})
	var r_lv = int(r_info.get("level", seg.level))
	var r_hp = int(r_info.get("hp", seg.hp))
	var r_max = int(r_info.get("max_hp", seg.max_hp))
	var r_spiked = bool(r_info.get("spiked", seg.spiked))
	var tot_p = bag.count("plank") + stockpile.count("plank")
	var tot_s = bag.count("scrap") + stockpile.count("scrap")

	_title_lbl.text = "FENCE LAYER %d (Lv %d)" % [r, r_lv]
	_subtitle_lbl.text = (
		"Whole Ring HP: %d/%d   |   Planks: %d, Scrap: %d" % [r_hp, r_max, tot_p, tot_s]
	)

	var ring_rep_planks = int(r_info.get("repair_planks", 0))
	if ring_rep_planks > 0:
		var rep_cost = {"plank": ring_rep_planks}
		_add_cost_button(
			"Repair Entire Layer %d" % r,
			"fence_repair_ring",
			{"ring": r, "cost": rep_cost},
			rep_cost,
			bag,
			stockpile
		)

	if r_lv == 1:
		var lv2_cost = Config.COST_RING_LV2[r]
		_add_cost_button(
			"Upgrade Whole Layer %d -> Lv 2 (90 HP)" % r,
			"fence_upgrade_ring",
			{"ring": r, "level": 2, "cost": lv2_cost},
			lv2_cost,
			bag,
			stockpile
		)
	elif r_lv == 2:
		var lv3_cost = Config.COST_RING_LV3[r]
		_add_cost_button(
			"Upgrade Whole Layer %d -> Lv 3 Steel (140 HP)" % r,
			"fence_upgrade_ring",
			{"ring": r, "level": 3, "cost": lv3_cost},
			lv3_cost,
			bag,
			stockpile
		)

	if not r_spiked:
		var spk_cost = Config.COST_RING_SPIKES[r]
		_add_cost_button(
			"Add Spikes to Whole Layer %d (Hurts attackers)" % r,
			"fence_spike_ring",
			{"ring": r, "cost": spk_cost},
			spk_cost,
			bag,
			stockpile
		)

	var r2_built = bool((ring_stats.get(2, {})).get("built", false))
	var r3_built = bool((ring_stats.get(3, {})).get("built", false))
	if r == 1 and not r2_built:
		_add_cost_button(
			"Unlock Fence Layer 2 (Whole Ring + Gate)",
			"unlock_fence_layer",
			{"ring": 2, "cost": Config.COST_UNLOCK_RING2},
			Config.COST_UNLOCK_RING2,
			bag,
			stockpile
		)
	elif r == 2 and not r3_built:
		_add_cost_button(
			"Unlock Fence Layer 3 (Whole Ring + Gate)",
			"unlock_fence_layer",
			{"ring": 3, "cost": Config.COST_UNLOCK_RING3},
			Config.COST_UNLOCK_RING3,
			bag,
			stockpile
		)


func _add_cost_button(
	label_txt: String,
	action_id: String,
	data: Dictionary,
	cost: Dictionary,
	bag: Bag,
	stockpile: Bag
) -> void:
	var can_pay = bag.can_afford(cost, stockpile)
	var suffix = "  [%s]" % Bag.format_cost(cost)
	_add_button(label_txt + suffix, action_id, data, can_pay)


func _add_button(label_txt: String, action_id: String, data: Dictionary, enabled: bool) -> void:
	var btn = Button.new()
	btn.text = label_txt
	btn.disabled = not enabled
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0.0, 20.0)
	btn.pressed.connect(_on_btn_pressed.bind(action_id, data))
	_list_box.add_child(btn)
	_buttons.append(btn)


func _add_info_row(left_txt: String, right_txt: String, highlight: bool = false) -> void:
	var row = HBoxContainer.new()
	var l_lbl = Label.new()
	l_lbl.text = left_txt
	l_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Art.style_label(
		l_lbl, "bold", 8, Color(1.0, 0.88, 0.45) if highlight else Color(0.95, 0.92, 0.88)
	)
	row.add_child(l_lbl)

	var r_lbl = Label.new()
	r_lbl.text = right_txt
	r_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Art.style_label(r_lbl, "body", 8, Color(0.80, 0.84, 0.90))
	row.add_child(r_lbl)
	_list_box.add_child(row)


func _on_btn_pressed(action_id: String, data: Dictionary) -> void:
	if action_id == "close" or action_id == "resume":
		close_all()
		return
	action_triggered.emit(action_id, data)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not (event is InputEventKey):
		return
	var ke = event
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
		var btn = _buttons[_selected_idx]
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


func _set_panel_size(w: float, h: float) -> void:
	if _panel == null:
		return
	_panel.size = Vector2(w, h)
	_panel.position = Vector2(
		floorf((Config.VIEW_SIZE.x - w) * 0.5),
		floorf((Config.VIEW_SIZE.y - h) * 0.5)
	)


func _build_shell() -> void:
	_dimmer = ColorRect.new()
	_dimmer.position = Vector2.ZERO
	_dimmer.size = Config.VIEW_SIZE
	_dimmer.color = Color(0.03, 0.02, 0.06, 0.65)
	add_child(_dimmer)

	_panel = PanelContainer.new()
	_set_panel_size(388.0, 224.0)
	_panel.theme = Art.get_game_theme()
	_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_panel.add_theme_stylebox_override(
		"panel",
		Art.make_panel_style("res://assets/ui/panel.png", 10.0, 12.0, 10.0)
	)
	add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_panel.add_child(vbox)

	_title_lbl = Label.new()
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Art.style_label(_title_lbl, "display", 16, Color(1.0, 0.88, 0.56))
	vbox.add_child(_title_lbl)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Art.style_label(_subtitle_lbl, "body", 8, Color(0.80, 0.82, 0.88))
	vbox.add_child(_subtitle_lbl)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_list_box)

	_footer_lbl = Label.new()
	_footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Art.style_label(_footer_lbl, "body", 8, Color(0.68, 0.66, 0.74))
	vbox.add_child(_footer_lbl)
