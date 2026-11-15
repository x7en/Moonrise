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
var _weapon_hotkey_ids: Array[String] = []
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
	_set_panel_size(448.0, 278.0)
	_title_lbl.text = "INVENTORY & WEAPONS"
	_subtitle_lbl.text = (
		"Bag (%d/%d)   |   Stockpile (Unlimited)   |   Gear Tier %d/3"
		% [bag.used_capacity(), bag.capacity, int(upgrades.get("gear_tier", 1))]
	)
	_clear_list()

	_add_info_row(
		"Resources",
		"Bag P:%d S:%d   |   Stock P:%d S:%d" % [
			bag.count("plank"),
			bag.count("scrap"),
			stockpile.count("plank"),
			stockpile.count("scrap"),
		]
	)
	_add_info_row(
		"Traps Owned",
		"Bear: %d   Spike: %d   Lure: %d"
		% [bag.count("trap_snare"), bag.count("trap_spike"), bag.count("trap_lure")]
	)

	_add_info_row("WEAPONS", "Click or press [1-3] to switch equipped weapon", true)
	var slot_num := 1
	for w_id in player.unlocked_weapons:
		var def: Dictionary = Config.WEAPON_DEFS.get(w_id, {})
		if def.is_empty():
			continue
		var is_eq := (player.active_weapon == w_id)
		var badge := "[EQUIPPED] " if is_eq else ""
		var stat_txt := _format_weapon_status(w_id, player, bag)
		var lbl_txt := "[%d] %s%s (%s)" % [
			slot_num, badge, String(def.get("label", w_id)), stat_txt
		]
		var btn = _add_button(lbl_txt, "equip_weapon", {"weapon_id": w_id}, true)
		var icon_key := String(def.get("icon", ""))
		if not icon_key.is_empty():
			btn.icon = Art.get_icon_texture(icon_key)
		_weapon_hotkey_ids.append(w_id)
		slot_num += 1

	_add_button("Open Trap Crafting [C]", "open_crafting", {}, true)
	_add_button("Close [I / Esc]", "close", {}, true)
	_footer_lbl.text = "Press [1-3] or Click to switch  |  Craft [C]  |  [I / Esc] Resume"
	_focus_index(0)


func _format_weapon_status(w_id: String, player: Player, bag: Bag) -> String:
	if w_id == "bow":
		return "Loaded %d/%d, Reserve %d" % [player.mag, player.mag_max, bag.count("arrow")]
	if w_id == "boomerang":
		if player.boomerang_in_flight:
			return "In flight"
		if player.boomerang_cd > 0.05:
			return "CD %.1fs" % player.boomerang_cd
		return "Ready - 1.8s CD"
	return "Melee, no ammo"


func open_crafting_menu(
	bag: Bag,
	stockpile: Bag
) -> void:
	active_panel = "crafting"
	current_structure = null
	visible = true
	_set_panel_size(432.0, 264.0)
	var tot_p := bag.count("plank") + stockpile.count("plank")
	var tot_s := bag.count("scrap") + stockpile.count("scrap")
	_title_lbl.text = "TRAP CRAFTING"
	_subtitle_lbl.text = (
		"Resources: %d Planks, %d Scrap  (Draws from Bag + Stockpile)" % [tot_p, tot_s]
	)
	_clear_list()

	for recipe in Config.CRAFT_RECIPES:
		var action_id := String(recipe["action"])
		var item_key := String(recipe["item"])
		var cost: Dictionary = recipe["cost"]
		var owned_key := "arrow" if item_key == "arrows" else item_key
		var owned := bag.count(owned_key)
		var label_txt := "%s  (Owned: %d)" % [String(recipe["label"]), owned]
		var data := {"cost": cost}
		if action_id == "craft_trap":
			data["trap_key"] = item_key
			data["qty"] = int(recipe["amount"])
		var btn = _add_cost_button(label_txt, action_id, data, cost, bag, stockpile)
		var icon_key := "arrow" if item_key == "arrows" else item_key
		btn.icon = Art.get_icon_texture(icon_key)
		var desc_lbl := Label.new()
		desc_lbl.text = "   " + String(recipe["desc"])
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		Art.style_label(desc_lbl, "body", 8, Color(0.76, 0.80, 0.88))
		_list_box.add_child(desc_lbl)

	_add_button("Open Weapons / Inventory [I]", "open_inventory", {}, true)
	_add_button("Close [C / Esc]", "close", {}, true)
	_footer_lbl.text = "Craft traps anytime [C]  |  Select with keys 1-3 & click ground to place"
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
		_subtitle_lbl.text = "Gather by day, fortify your yard, and hold the farmhouse"
		for step in [
			["1. Morning Gather", "Gate opens at dawn. Grab planks, hold E on trees & wrecks."],
			["2. Store & Upgrade", "Walk near the house to store loot. Press U to upgrade."],
			["3. Weapons [I]", "Press I to switch Bow/Spear/Boomerang (click or 1-3)."],
			["4. Craft Traps [C]", "Press C to craft traps. Pick slots 1-3 & click to place."],
			["5. Bounce Back", "Press B anytime to recall home and start healing."],
			["6. Night Shelter", "Watch the Even Moon. Shut gates/door [E] before dusk."],
			["7. Dogs & Tracker", "Some strays can be tamed (G Follow/Guard). BASE <50m."],
		]:
			_add_info_row(String(step[0]), String(step[1]))
	elif kind == "controls":
		_title_lbl.text = "CONTROLS"
		_subtitle_lbl.text = "Keyboard + Mouse"
		for row in [
			["Move", "WASD / Arrow Keys"],
			["Weapons & Attack", "Click Equipped (Bow/Spear/Boomerang) | Space Spear | F Bow"],
			["Inventory / Craft", "I Weapons (Click or 1-3) & Bag  |  C Craft Traps & Arrows"],
			["Door / Trees / Dogs", "E Door/Gate | Hold E Chop Tree/Search | Tame Btn / G Dog"],
			["Place Traps", "1 Bear  2 Spike  3 Lure (or Click Slot)  |  Click/T Place"],
			["Bounce / Shockwave", "B Recall Home & Heal  |  Q Shockwave  |  R Reload Bow"],
			["Upgrades & Pause", "U or Right-Click House/Fence  |  F11 Full  |  Esc Pause"],
		]:
			_add_info_row(String(row[0]), String(row[1]))
	elif kind == "settings":
		_title_lbl.text = "SETTINGS"
		_subtitle_lbl.text = "Saved automatically"
		var fs_txt = "ON" if settings.fullscreen else "OFF"
		var vol_pct = roundi(settings.master_volume * 100.0)
		var shake_txt = "ON" if settings.screen_shake else "OFF"
		var dev_intro_txt = (
			"ON (Every Launch)" if settings.dev_always_play_intro else "OFF (First Launch Only)"
		)
		_add_button("Fullscreen: %s" % fs_txt, "toggle_fullscreen", {}, true)
		_add_button("Master Volume: %d%%" % vol_pct, "cycle_volume", {}, true)
		_add_button("Screen Shake: %s" % shake_txt, "toggle_shake", {}, true)
		_add_button("[DEV] Story Intro on Launch: %s" % dev_intro_txt, "toggle_intro", {}, true)
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
		_subtitle_lbl.text = "Moonrise"
		for line in [
			"Game Designer & Lead Developer: Vaseem",
			"Secondary Designer: Vaseem Qadir",
			"Helper: Bilal",
			"Weapon art: Jestan (The Ultimate Weapons Pack)",
		]:
			var lbl := Label.new()
			lbl.text = line
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.custom_minimum_size = Vector2(0.0, 20.0)
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			Art.style_label(lbl, "bold", 8, Color(1.0, 0.90, 0.52))
			_list_box.add_child(lbl)

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
) -> Button:
	var can_pay = bag.can_afford(cost, stockpile)
	var suffix = "  [%s]" % Bag.format_cost(cost)
	return _add_button(label_txt + suffix, action_id, data, can_pay)


func _add_button(label_txt: String, action_id: String, data: Dictionary, enabled: bool) -> Button:
	var btn = Button.new()
	btn.text = label_txt
	btn.disabled = not enabled
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0.0, 20.0)
	btn.pressed.connect(_on_btn_pressed.bind(action_id, data))
	_list_box.add_child(btn)
	_buttons.append(btn)
	return btn


func _add_info_row(left_txt: String, right_txt: String, highlight: bool = false) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l_lbl = Label.new()
	l_lbl.text = left_txt
	l_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_lbl.size_flags_stretch_ratio = 0.36
	l_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Art.style_label(
		l_lbl, "bold", 8, Color(1.0, 0.88, 0.45) if highlight else Color(0.95, 0.92, 0.88)
	)
	row.add_child(l_lbl)

	var r_lbl = Label.new()
	r_lbl.text = right_txt
	r_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_lbl.size_flags_stretch_ratio = 0.64
	r_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	var toggle_close = (
		ke.keycode == KEY_ESCAPE
		or (active_panel == "inventory" and ke.keycode == KEY_I)
		or (active_panel == "crafting" and ke.keycode == KEY_C)
	)
	if toggle_close:
		get_viewport().set_input_as_handled()
		close_all()
		return
	if active_panel == "inventory" and ke.keycode >= KEY_1 and ke.keycode <= KEY_9:
		var w_idx := int(ke.keycode - KEY_1)
		if w_idx < _weapon_hotkey_ids.size():
			get_viewport().set_input_as_handled()
			action_triggered.emit("equip_weapon", {"weapon_id": _weapon_hotkey_ids[w_idx]})
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
	_weapon_hotkey_ids.clear()
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
	_dimmer = get_node("Dimmer") as ColorRect

	_panel = get_node("Panel") as PanelContainer
	_set_panel_size(388.0, 224.0)
	_panel.theme = Art.get_game_theme()
	_panel.add_theme_stylebox_override(
		"panel",
		Art.make_panel_style("res://assets/ui/panel.png", 10.0, 12.0, 10.0)
	)

	_title_lbl = get_node("Panel/VBox/TitleLabel") as Label
	Art.style_label(_title_lbl, "display", 16, Color(1.0, 0.88, 0.56))

	_subtitle_lbl = get_node("Panel/VBox/SubtitleLabel") as Label
	Art.style_label(_subtitle_lbl, "body", 8, Color(0.80, 0.82, 0.88))

	_list_box = get_node("Panel/VBox/Scroll/ListBox") as VBoxContainer

	_footer_lbl = get_node("Panel/VBox/FooterLabel") as Label
	Art.style_label(_footer_lbl, "body", 8, Color(0.68, 0.66, 0.74))
