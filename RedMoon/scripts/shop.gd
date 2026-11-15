class_name Shop
extends RefCounted

# upgrades, trap placement checks, and saving/reloading the start of a day


func compute_ring_stats(fences: Array[Structure]) -> Dictionary:
	var stats = {}
	for r in [1, 2, 3]:
		stats[r] = {
			"built": false,
			"level": 1,
			"spiked": false,
			"hp": 0,
			"max_hp": 0,
			"repair_planks": 0,
		}
	for f in fences:
		var d = stats[f.ring]
		if f.is_built:
			d["built"] = true
			d["level"] = maxi(int(d["level"]), f.level)
			if f.spiked:
				d["spiked"] = true
			d["hp"] = int(d["hp"]) + f.hp
			d["max_hp"] = int(d["max_hp"]) + f.max_hp
	for r in [1, 2, 3]:
		var d = stats[r]
		if bool(d["built"]):
			var missing = int(d["max_hp"]) - int(d["hp"])
			if missing > 0:
				d["repair_planks"] = clampi(ceili(float(missing) / 16.0), 1, 10)
	return stats


# returns { sfx, message, achievement, spawn_watchtower } for whichever upgrade button was clicked
func execute_action(
	action_id: String,
	data: Dictionary,
	bag: Bag,
	stockpile: Bag,
	house: Structure,
	fences: Array[Structure],
	player: Player,
	upgrades: Dictionary,
	act: int,
	watchtower_count: int
) -> Dictionary:
	var res = {"sfx": "", "message": "", "achievement": "", "spawn_watchtower": false}
	var cost = data.get("cost", {})

	match action_id:
		"house_rebuild":
			var rb_cost = (
				Config.COST_HOUSE_REBUILD_ACT1 if act == 1 else Config.COST_HOUSE_REBUILD
			)
			if bag.spend(rb_cost, stockpile):
				house.rebuild_house()
				res["sfx"] = "fence_rebuilt"
				res["message"] = "House rebuilt at 40% HP!"
		"house_repair":
			if bag.spend(cost, stockpile):
				house.set_hp(house.max_hp)
				res["sfx"] = "fence_rebuilt"
				res["message"] = "House repaired to full HP."
		"house_upgrade":
			if bag.spend(cost, stockpile):
				var lv = int(data["level"])
				house.set_level(lv, true)
				res["sfx"] = "upgrade"
				res["message"] = "House upgraded to Level %d!" % lv
				if lv >= 3:
					res["achievement"] = "house_level_3"
		"unlock_fence_layer":
			if bag.spend(cost, stockpile):
				var r_unlock = int(data["ring"])
				for f in fences:
					if f.ring == r_unlock and not f.is_built:
						f.build_from_foundation()
				res["sfx"] = "fence_rebuilt"
				res["message"] = "Fence Layer %d unlocked & built (with gate)!" % r_unlock
		"upgrade_gear":
			if bag.spend(cost, stockpile):
				var next_tier = int(data["tier"])
				upgrades["gear_tier"] = next_tier
				player.apply_upgrade_stats(upgrades)
				player.mag = player.mag_max
				res["sfx"] = "upgrade"
				res["message"] = "Weapons & Gear upgraded to Tier %d!" % next_tier
		"buy_arrows":
			if bag.spend(cost, stockpile):
				var space = maxi(0, player.reserve_max - bag.count("arrow"))
				bag.add("arrow", mini(Config.BUY_ARROWS_AMOUNT, space))
				res["sfx"] = "pickup"
				res["message"] = "+%d Arrows added to quiver." % mini(Config.BUY_ARROWS_AMOUNT, space)
		"craft_trap":
			if bag.spend(cost, stockpile):
				var t_key = String(data["trap_key"])
				var qty = int(data.get("qty", 1))
				bag.add(t_key, qty)
				var t_lbl = String((Config.TRAPS[t_key])["label"])
				res["sfx"] = "pickup"
				res["message"] = "Crafted +%d %s!" % [qty, t_lbl]
		"build_watchtower":
			if watchtower_count < Config.WATCHTOWER_MAX and bag.spend(cost, stockpile):
				res["spawn_watchtower"] = true
				res["sfx"] = "upgrade"
				res["message"] = "Watchtower constructed!"
		"fence_repair_ring":
			if bag.spend(cost, stockpile):
				var r_rep = int(data["ring"])
				for f in fences:
					if f.ring == r_rep and f.is_built:
						f.set_hp(f.max_hp)
				res["sfx"] = "fence_rebuilt"
				res["message"] = "Entire Fence Ring %d repaired!" % r_rep
		"fence_upgrade_ring":
			if bag.spend(cost, stockpile):
				var r_u = int(data["ring"])
				var lv_all = int(data["level"])
				for f in fences:
					if f.ring == r_u and f.is_built:
						f.set_level(lv_all, true)
				res["sfx"] = "upgrade"
				res["message"] = "Entire Fence Ring %d upgraded to Level %d!" % [r_u, lv_all]
				res["achievement"] = "metal_fences" if lv_all >= 3 else "fence_upgraded"
		"fence_spike_ring":
			if bag.spend(cost, stockpile):
				var r_sp = int(data["ring"])
				for f in fences:
					if f.ring == r_sp and f.is_built:
						f.spiked = true
						f.refresh_visuals()
				res["sfx"] = "upgrade"
				res["message"] = "Spikes installed across entire Ring %d!" % r_sp
	return res


func save_day(main_node: Node) -> Dictionary:
	var house = main_node.get("house")
	var fences: Array = main_node.get("fences")
	var traps: Array = main_node.get("traps")
	var watchtowers: Array = main_node.get("watchtowers")
	var dogs: Array = main_node.get("dogs")
	var fence_saves: Array[Dictionary] = []
	for f in fences:
		fence_saves.append(f.save_state())
	var trap_saves: Array[Dictionary] = []
	for t in traps:
		if is_instance_valid(t) and t.is_active():
			trap_saves.append({
				"type": t.trap_type,
				"pos": t.position,
				"triggers": t.triggers_left,
				"hp": t.hp,
			})
	var tower_saves: Array[Dictionary] = []
	for wt in watchtowers:
		if is_instance_valid(wt) and wt.is_standing():
			tower_saves.append({"pos": wt.position, "hp": wt.hp})
	var dog_saves: Array[Dictionary] = []
	for d in dogs:
		if is_instance_valid(d) and d.mode != Dog.Mode.STRAY and d.is_alive():
			dog_saves.append({"pos": d.position, "mode": int(d.mode), "hp": d.hp})
	var p_ref = main_node.get("_player")
	return {
		"act": int(main_node.get("act")),
		"day": int(main_node.get("day")),
		"hp": p_ref.hp,
		"active_weapon": p_ref.active_weapon,
		"unlocked_weapons": p_ref.unlocked_weapons.duplicate(),
		"bag": main_node.get("bag").to_dict(),
		"stockpile": main_node.get("stockpile").to_dict(),
		"upgrades": main_node.get("upgrades").duplicate(true),
		"house": house.save_state() if house != null else {},
		"fences": fence_saves,
		"traps": trap_saves,
		"watchtowers": tower_saves,
		"dogs": dog_saves,
	}


func load_day(saved: Dictionary, main_node: Node) -> Dictionary:
	var bag = main_node.get("bag")
	var stockpile = main_node.get("stockpile")
	var player = main_node.get("_player")
	var house = main_node.get("house")
	var fences: Array = main_node.get("fences")
	bag.from_dict(saved["bag"])
	stockpile.from_dict(saved["stockpile"])
	var up = saved["upgrades"].duplicate(true)
	player.reset_for_new_game(Config.HOUSE_DOOR)
	player.hp = int(saved["hp"])
	var saved_weapons: Array = saved.get("unlocked_weapons", [])
	for w_id in saved_weapons:
		player.unlock_weapon(String(w_id))
	player.equip_weapon(String(saved.get("active_weapon", "bow")))
	player.apply_upgrade_stats(up)
	if house != null:
		house.load_state(saved["house"])
	var fence_saves: Array = saved["fences"]
	for i in range(mini(fences.size(), fence_saves.size())):
		fences[i].load_state(fence_saves[i])
	for td in saved.get("traps", []):
		var tr = spawn_trap_node(String(td["type"]), td["pos"], main_node)
		tr.triggers_left = int(td.get("triggers", tr.triggers_left))
		tr.hp = int(td.get("hp", tr.hp))
	for wd in saved.get("watchtowers", []):
		main_node.call("_spawn_watchtower", wd["pos"], int(wd.get("hp", Config.WATCHTOWER_HP)))
	var waves = main_node.get("_waves")
	for dd in saved.get("dogs", []):
		waves.spawn_dog_for(
			main_node,
			dd["pos"],
			int(dd.get("mode", Dog.Mode.FOLLOW)),
			int(dd.get("hp", Config.DOG_HP))
		)
	return up


# dumps your bag into the stockpile when you walk close to the house, and vacuums nearby pickups
func step_piles_and_deposit(
	tree: SceneTree,
	player: Player,
	house: Structure,
	bag: Bag,
	stockpile: Bag,
	sfx: Sfx,
	effects: Fx
) -> bool:
	var picked_plank = false
	if house != null and not house.is_fallen and bag.used_capacity() > 0:
		if house.distance_from_point(player.position) <= 24.0 or player.inside_house:
			var moved = bag.transfer_resources_to(stockpile)
			var total_m = int(moved["plank"]) + int(moved["scrap"])
			if total_m > 0:
				sfx.play("dropoff", -8.0)
				effects.spawn_floating_text(
					Config.HOUSE_DOOR_STEP, "+%d Stored" % total_m, Color(0.62, 0.96, 0.68)
				)
	if player.inside_house:
		return false
	for node in tree.get_nodes_in_group("piles"):
		if not is_instance_valid(node) or not (node is Pile):
			continue
		var pile = node
		var room = (
			player.reserve_max - bag.count("arrow")
			if pile.item_type == "arrow"
			else bag.remaining_capacity()
		)
		var taken = pile.try_pickup(player.position, room)
		if taken > 0:
			bag.add(pile.item_type, taken)
			sfx.play("pickup", -8.0)
			var lbl = "+%d %s" % [taken, pile.item_type.capitalize()]
			effects.spawn_floating_text(player.position, lbl, Color(1.0, 0.92, 0.56))
			if pile.item_type == "plank":
				picked_plank = true
	return picked_plank


func can_place_trap_at(
	t_key: String,
	place_pos: Vector2,
	player: Player,
	bag: Bag,
	_stockpile: Bag,
	traps: Array,
	structures: Array
) -> Dictionary:
	if player.inside_house or player.dead:
		return {"ok": false, "reason": "Step outside to place traps."}
	if traps.size() >= Config.MAX_TRAPS:
		return {"ok": false, "reason": "Max %d traps placed!" % Config.MAX_TRAPS}
	if bag.count(t_key) <= 0:
		var lbl = String((Config.TRAPS[t_key])["label"])
		var cost = (Config.TRAPS[t_key])["cost"]
		return {
			"ok": false,
			"reason": "No %ss left! Press [C] to craft (%s)." % [lbl, Bag.format_cost(cost)],
		}
	for s in structures:
		if not is_instance_valid(s) or not (s is Structure):
			continue
		var st = s
		if st.is_standing() and st.footprint_rect.grow(3.0).has_point(place_pos):
			return {"ok": false, "reason": "Blocked by structure."}
	for ex in traps:
		if is_instance_valid(ex) and ex.position.distance_to(place_pos) < Config.TRAP_MIN_SPACING:
			return {"ok": false, "reason": "Too close to another trap."}
	return {"ok": true, "reason": ""}


# spends a trap from the bag first, otherwise crafts one right out of the stockpile
func spawn_trap_node(
	t_key: String, place_pos: Vector2, main_node: Node
) -> Trap:
	var traps: Array = main_node.get("traps")
	var entities_layer = main_node.get("_entities_layer")
	var sfx = main_node.get("_sfx")
	var fx = main_node.get("_fx")

	var trap = Trap.new()
	trap.setup(t_key, place_pos)
	trap.triggered.connect(func(tr: Trap, en: Node2D) -> void:
		sfx.play("trap_trigger", -7.0)
		if is_instance_valid(en):
			var ep := en.position
			if tr.trap_type == "trap_snare":
				fx.spawn_sparks(ep, Color(0.95, 0.85, 0.35, 1.0), 8)
				fx.spawn_floating_text(ep, "SNARED!", Color(1.0, 0.88, 0.38))
			else:
				fx.spawn_sparks(ep, Color(0.96, 0.32, 0.28, 1.0), 6)
	)
	entities_layer.add_child(trap)
	traps.append(trap)
	return trap


func try_place_trap_at(
	t_key: String, place_pos: Vector2, main_node: Node
) -> bool:
	var player = main_node.get("_player")
	var bag = main_node.get("bag")
	var stockpile = main_node.get("stockpile")
	var traps: Array = main_node.get("traps")
	var structures: Array = main_node.get("structures")
	var hud = main_node.get("_hud")
	var sfx = main_node.get("_sfx")
	var fx = main_node.get("_fx")

	var check = can_place_trap_at(
		t_key, place_pos, player, bag, stockpile, traps, structures
	)
	if not bool(check["ok"]):
		hud.show_message(String(check["reason"]), 1.6, Color(1.0, 0.55, 0.45))
		return false

	if bag.count(t_key) <= 0:
		return false
	bag.remove(t_key, 1)

	spawn_trap_node(t_key, place_pos, main_node)
	sfx.play("fence_rebuilt", -8.0)
	fx.spawn_sparks(place_pos, Color(0.86, 0.82, 0.64, 1.0), 5)
	var t_label = String((Config.TRAPS[t_key])["label"])
	var left_n = bag.count(t_key)
	fx.spawn_floating_text(place_pos, "%s (%d left)" % [t_label, left_n], Color(0.62, 0.96, 0.68))
	return true


func compute_trap_place_pos(trap_mode_active: bool, main_node: Node2D) -> Vector2:
	var player = main_node.get("_player")
	if trap_mode_active and DisplayServer.get_name() != "headless":
		var mw = main_node.get_global_mouse_position()
		var delta_v = mw - player.position
		if delta_v.length() > Config.TRAP_PLACE_RANGE:
			mw = player.position + delta_v.normalized() * Config.TRAP_PLACE_RANGE
		return mw.round()
	return (player.position + player.facing_vec.normalized() * 16.0).round()


func update_trap_preview(
	trap_mode_active: bool, selected_idx: int, main_node: Node2D
) -> void:
	var fx = main_node.get("_fx")
	var player = main_node.get("_player")
	var menus = main_node.get("_menus")
	if not trap_mode_active or menus.is_open() or player.inside_house:
		fx.set_trap_preview(false)
		return
	var keys: Array[String] = ["trap_snare", "trap_spike", "trap_lure"]
	var t_key = keys[clampi(selected_idx - 1, 0, 2)]
	var info = Config.TRAPS[t_key]
	var place_pos = compute_trap_place_pos(trap_mode_active, main_node)
	var check = can_place_trap_at(
		t_key,
		place_pos,
		player,
		main_node.get("bag"),
		main_node.get("stockpile"),
		main_node.get("traps"),
		main_node.get("structures")
	)
	fx.set_trap_preview(
		true,
		place_pos,
		float(info.get("radius", 13.0)),
		float(info.get("attract_radius", 0.0)),
		bool(check["ok"]),
		t_key
	)


func grant_prop_loot(
	prop: Dictionary,
	map: MapGen,
	player: Player,
	bag: Bag,
	stockpile: Bag,
	sfx: Sfx,
	fx: Fx
) -> void:
	map.mark_prop_searched(int(prop["id"]))
	var sg = int(prop["loot_scrap"])
	var pg = int(prop["loot_plank"])
	var sa = bag.add("scrap", sg)
	var pa = bag.add("plank", pg)
	if sa < sg:
		stockpile.add("scrap", sg - sa)
	if pa < pg:
		stockpile.add("plank", pg - pa)
	if randf() < 0.45:
		bag.add("arrow", 4)
	sfx.play("pickup", -7.0)
	fx.spawn_floating_text(
		player.position, "+%d Scrap +%d Plank" % [sg, pg], Color(0.98, 0.84, 0.46)
	)


func grant_tree_chop_loot(
	tree_rec: Dictionary,
	map: MapGen,
	player: Player,
	bag: Bag,
	stockpile: Bag,
	sfx: Sfx,
	fx: Fx
) -> void:
	if not map.mark_tree_chopped(int(tree_rec["id"])):
		return
	var pa = bag.add("plank", 1)
	if pa < 1:
		stockpile.add("plank", 1)
	sfx.play("wood_chop", -6.0)
	fx.spawn_sparks(tree_rec["pos"], Color(0.76, 0.54, 0.30, 1.0), 8)
	fx.spawn_floating_text(player.position, "+1 Plank (Chopped)", Color(0.98, 0.86, 0.48))


func reset_hold_gather(main_node: Node) -> void:
	main_node.set("_search_key", "")
	main_node.set("_search_timer", 0.0)
	main_node.set("_search_progress", 0.0)


func step_hold_gather(delta: float, main_node: Node) -> void:
	var player = main_node.get("_player")
	var map = main_node.get("_map")
	var holding_e = (not player.inside_house) and (not player.dead) and Input.is_key_pressed(KEY_E)
	if not holding_e:
		reset_hold_gather(main_node)
		return
	var prop: Dictionary = map.find_nearest_searchable(player.position, 32.0)
	var tree_rec: Dictionary = (
		{} if not prop.is_empty() else map.find_nearest_tree(player.position, 26.0)
	)
	if prop.is_empty() and tree_rec.is_empty():
		reset_hold_gather(main_node)
		return
	var is_prop: bool = not prop.is_empty()
	var target_key: String = (
		("p:%d" % int(prop["id"])) if is_prop else ("t:%d" % int(tree_rec["id"]))
	)
	var needed: float = Config.SEARCH_HOLD_TIME if is_prop else Config.CHOP_HOLD_TIME
	var same_target: bool = String(main_node.get("_search_key")) == target_key
	var timer: float = (float(main_node.get("_search_timer")) if same_target else 0.0) + delta
	main_node.set("_search_key", target_key)
	main_node.set("_search_timer", timer)
	main_node.set("_search_progress", clampf(timer / maxf(0.1, needed), 0.0, 1.0))
	if timer >= needed:
		reset_hold_gather(main_node)
		var bag = main_node.get("bag")
		var stockpile = main_node.get("stockpile")
		var sfx = main_node.get("_sfx")
		var fx = main_node.get("_fx")
		if is_prop:
			grant_prop_loot(prop, map, player, bag, stockpile, sfx, fx)
		else:
			grant_tree_chop_loot(tree_rec, map, player, bag, stockpile, sfx, fx)


func handle_settings_action(
	action_id: String, settings: SaveData, menus: Menus
) -> bool:
	match action_id:
		"show_controls":
			menus.open_info_panel("controls", settings)
		"show_settings":
			menus.open_info_panel("settings", settings)
		"show_achievements":
			menus.open_info_panel("achievements", settings)
		"toggle_fullscreen":
			settings.fullscreen = not settings.fullscreen
			settings.save_settings()
			settings.apply_display_and_audio()
			menus.open_info_panel("settings", settings)
		"cycle_volume":
			settings.master_volume = fmod(settings.master_volume + 0.25, 1.25)
			if settings.master_volume > 1.05:
				settings.master_volume = 0.0
			settings.save_settings()
			settings.apply_display_and_audio()
			menus.open_info_panel("settings", settings)
		"toggle_shake":
			settings.screen_shake = not settings.screen_shake
			settings.save_settings()
			menus.open_info_panel("settings", settings)
		"toggle_intro":
			settings.dev_always_play_intro = not settings.dev_always_play_intro
			settings.save_settings()
			menus.open_info_panel("settings", settings)
		_:
			return false
	return true


func handle_inventory_action(action_id: String, data: Dictionary, main_node: Node) -> bool:
	var menus = main_node.get("_menus")
	var bag = main_node.get("bag")
	var stockpile = main_node.get("stockpile")
	var player = main_node.get("_player")
	if action_id == "equip_weapon":
		var w_id := String(data.get("weapon_id", ""))
		if player.equip_weapon(w_id):
			main_node.get("_sfx").play("pickup", -8.0)
			var w_def: Dictionary = Config.WEAPON_DEFS.get(w_id, {})
			var w_lbl: String = String(w_def.get("label", w_id))
			main_node.get("_hud").show_message("Equipped %s!" % w_lbl, 1.8, Color(0.62, 0.96, 0.68))
			menus.open_inventory(bag, stockpile, player, main_node.get("upgrades"))
		return true
	if action_id == "open_crafting":
		menus.open_crafting_menu(bag, stockpile)
		return true
	if action_id == "open_inventory":
		menus.open_inventory(bag, stockpile, player, main_node.get("upgrades"))
		return true
	return false
