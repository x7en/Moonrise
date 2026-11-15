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


func save_day(
	act: int,
	day: int,
	player: Player,
	bag: Bag,
	stockpile: Bag,
	upgrades: Dictionary,
	house: Structure,
	fences: Array[Structure]
) -> Dictionary:
	var f_snaps: Array[Dictionary] = []
	for f in fences:
		f_snaps.append(f.save_state())
	return {
		"act": act,
		"day": day,
		"hp": player.hp,
		"bag": bag.to_dict(),
		"stockpile": stockpile.to_dict(),
		"upgrades": upgrades.duplicate(true),
		"house": house.save_state() if house != null else {},
		"fences": f_snaps,
	}


func load_day(
	snap: Dictionary,
	bag: Bag,
	stockpile: Bag,
	player: Player,
	house: Structure,
	fences: Array[Structure]
) -> Dictionary:
	bag.from_dict(snap["bag"])
	stockpile.from_dict(snap["stockpile"])
	var up = snap["upgrades"].duplicate(true)
	player.reset_for_new_game(Config.HOUSE_DOOR)
	player.hp = int(snap["hp"])
	player.apply_upgrade_stats(up)
	if house != null:
		house.load_state(snap["house"])
	var f_snaps: Array = snap["fences"]
	for i in range(mini(fences.size(), f_snaps.size())):
		fences[i].load_state(f_snaps[i])
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
	stockpile: Bag,
	traps: Array,
	structures: Array
) -> Dictionary:
	if player.inside_house or player.dead:
		return {"ok": false, "reason": "Step outside to place traps."}
	if traps.size() >= Config.MAX_TRAPS:
		return {"ok": false, "reason": "Max %d traps reached!" % Config.MAX_TRAPS}
	if bag.count(t_key) <= 0:
		var cost = (Config.TRAPS[t_key])["cost"]
		if not bag.can_afford(cost, stockpile):
			return {"ok": false, "reason": "Need %s." % Bag.format_cost(cost)}
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
func try_place_trap_at(
	t_key: String, place_pos: Vector2, main_node: Node
) -> bool:
	var player = main_node.get("_player")
	var bag = main_node.get("bag")
	var stockpile = main_node.get("stockpile")
	var traps: Array = main_node.get("traps")
	var structures: Array = main_node.get("structures")
	var entities_layer = main_node.get("_entities_layer")
	var hud = main_node.get("_hud")
	var sfx = main_node.get("_sfx")
	var effects = main_node.get("_effects")

	var check = can_place_trap_at(
		t_key, place_pos, player, bag, stockpile, traps, structures
	)
	if not bool(check["ok"]):
		hud.show_message(String(check["reason"]), 1.6, Color(1.0, 0.55, 0.45))
		return false

	if bag.count(t_key) > 0:
		bag.remove(t_key, 1)
	else:
		var cost = (Config.TRAPS[t_key])["cost"]
		if not bag.spend(cost, stockpile):
			return false

	var trap = Trap.new()
	trap.setup(t_key, place_pos)
	trap.triggered.connect(func(tr: Trap, en: Node) -> void:
		sfx.play("trap_trigger", -7.0)
		if is_instance_valid(en):
			var ep = en.position
			if tr.trap_type == "trap_snare":
				effects.spawn_sparks(ep, Color(0.95, 0.85, 0.35, 1.0), 8)
				effects.spawn_floating_text(ep, "SNARED!", Color(1.0, 0.88, 0.38))
			else:
				effects.spawn_sparks(ep, Color(0.96, 0.32, 0.28, 1.0), 6)
	)
	entities_layer.add_child(trap)
	traps.append(trap)
	sfx.play("fence_rebuilt", -8.0)
	effects.spawn_sparks(place_pos, Color(0.86, 0.82, 0.64, 1.0), 5)
	var t_label = String((Config.TRAPS[t_key])["label"])
	effects.spawn_floating_text(place_pos, "%s Set!" % t_label, Color(0.62, 0.96, 0.68))
	return true


func compute_trap_place_pos(trap_mode_active: bool, main_node: Node) -> Vector2:
	var player = main_node.get("_player")
	if trap_mode_active and DisplayServer.get_name() != "headless":
		var mw = main_node.get_global_mouse_position()
		var delta_v = mw - player.position
		if delta_v.length() > Config.TRAP_PLACE_RANGE:
			mw = player.position + delta_v.normalized() * Config.TRAP_PLACE_RANGE
		return mw.round()
	return (player.position + player.facing_vec.normalized() * 16.0).round()


func update_trap_preview(
	trap_mode_active: bool, selected_idx: int, main_node: Node
) -> void:
	var effects = main_node.get("_effects")
	var player = main_node.get("_player")
	var upgrade_ui = main_node.get("_upgrade_ui")
	if not trap_mode_active or upgrade_ui.is_open() or player.inside_house:
		effects.set_trap_preview(false)
		return
	var keys: Array[String] = ["trap_spike", "trap_snare", "trap_lure"]
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
	effects.set_trap_preview(
		true,
		place_pos,
		float(info.get("radius", 13.0)),
		float(info.get("attract_radius", 0.0)),
		bool(check["ok"]),
		t_key
	)


func grant_prop_loot(
	prop: Dictionary,
	world_builder: MapGen,
	player: Player,
	bag: Bag,
	stockpile: Bag,
	sfx: Sfx,
	effects: Fx
) -> void:
	world_builder.mark_prop_searched(int(prop["id"]))
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
	effects.spawn_floating_text(
		player.position, "+%d Scrap +%d Plank" % [sg, pg], Color(0.98, 0.84, 0.46)
	)


func handle_settings_action(
	action_id: String, settings: SaveData, upgrade_ui: Menus
) -> bool:
	match action_id:
		"show_controls":
			upgrade_ui.open_info_panel("controls", settings)
		"show_settings":
			upgrade_ui.open_info_panel("settings", settings)
		"show_achievements":
			upgrade_ui.open_info_panel("achievements", settings)
		"toggle_fullscreen":
			settings.fullscreen = not settings.fullscreen
			settings.save_settings()
			settings.apply_display_and_audio()
			upgrade_ui.open_info_panel("settings", settings)
		"cycle_volume":
			settings.master_volume = fmod(settings.master_volume + 0.25, 1.25)
			if settings.master_volume > 1.05:
				settings.master_volume = 0.0
			settings.save_settings()
			settings.apply_display_and_audio()
			upgrade_ui.open_info_panel("settings", settings)
		"toggle_shake":
			settings.screen_shake = not settings.screen_shake
			settings.save_settings()
			upgrade_ui.open_info_panel("settings", settings)
		"toggle_intro":
			settings.play_intro = not settings.play_intro
			settings.save_settings()
			upgrade_ui.open_info_panel("settings", settings)
		_:
			return false
	return true
