class_name EconomyController
extends RefCounted
## Handles all House/Fence/Workshop/Trap/Watchtower purchases, ring-wide calculations,
## and day-start snapshot serialization (T1.6 / T2.1 / T2.2 / T2.3).


func compute_ring_stats(fences: Array[Structure]) -> Dictionary:
	var stats: Dictionary = {}
	for r in [1, 2, 3]:
		stats[r] = {"unbuilt": 0, "repair_planks": 0, "lv1_count": 0}
	for f in fences:
		var d: Dictionary = stats[f.ring] as Dictionary
		if not f.is_built:
			d["unbuilt"] = int(d["unbuilt"]) + 1
		else:
			if f.hp < f.max_hp:
				var need: int = maxi(1, ceili(float(f.max_hp - f.hp) / float(Config.PLANK_HEAL)))
				d["repair_planks"] = int(d["repair_planks"]) + need
			if f.level == 1:
				d["lv1_count"] = int(d["lv1_count"]) + 1
	return stats


## Executes one structure/workshop economy action and returns a result dictionary:
## {"sfx": String, "message": String, "achievement": String, "spawn_watchtower": bool}
func execute_action(
	action_id: String,
	payload: Dictionary,
	bag: Inventory,
	stockpile: Inventory,
	house: Structure,
	fences: Array[Structure],
	player: Player,
	upgrades: Dictionary,
	act: int,
	watchtower_count: int
) -> Dictionary:
	var res: Dictionary = {"sfx": "", "message": "", "achievement": "", "spawn_watchtower": false}
	var cost: Dictionary = payload.get("cost", {}) as Dictionary

	match action_id:
		"deposit_bag":
			bag.transfer_resources_to(stockpile)
			res["sfx"] = "dropoff"
		"house_rebuild":
			var rb_cost: Dictionary = (
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
		"house_upgrade":
			if bag.spend(cost, stockpile):
				var lv: int = int(payload["level"])
				house.set_level(lv, true)
				res["sfx"] = "upgrade"
				if lv >= 3:
					res["achievement"] = "house_level_3"
		"buy_arrows":
			if bag.spend(cost, stockpile):
				var space: int = maxi(0, player.reserve_max - bag.count("arrow"))
				bag.add("arrow", mini(Config.BUY_ARROWS_AMOUNT, space))
				res["sfx"] = "pickup"
		"buy_upgrade":
			if bag.spend(cost, stockpile):
				upgrades[String(payload["id"])] = true
				player.apply_upgrade_stats(upgrades)
				res["sfx"] = "upgrade"
		"build_watchtower":
			if watchtower_count < Config.WATCHTOWER_MAX and bag.spend(cost, stockpile):
				res["spawn_watchtower"] = true
				res["sfx"] = "upgrade"
		"craft_trap":
			if bag.spend(cost, stockpile):
				bag.add(String(payload["trap_type"]), 1)
				res["sfx"] = "pickup"
		"fence_build_seg":
			if bag.spend(cost, stockpile):
				(payload["seg"] as Structure).build_from_foundation()
				res["sfx"] = "fence_rebuilt"
		"fence_build_ring":
			if bag.spend(cost, stockpile):
				var r_b: int = int(payload["ring"])
				for f in fences:
					if f.ring == r_b and not f.is_built:
						f.build_from_foundation()
				res["sfx"] = "fence_rebuilt"
		"fence_repair_seg":
			if bag.spend(cost, stockpile):
				var seg_r: Structure = payload["seg"] as Structure
				seg_r.set_hp(seg_r.max_hp)
				res["sfx"] = "fence_rebuilt"
		"fence_repair_ring":
			if bag.spend(cost, stockpile):
				var r_rep: int = int(payload["ring"])
				for f in fences:
					if f.ring == r_rep and f.is_built:
						f.set_hp(f.max_hp)
				res["sfx"] = "fence_rebuilt"
		"fence_upgrade_seg":
			if bag.spend(cost, stockpile):
				var seg_u: Structure = payload["seg"] as Structure
				var lv_u: int = int(payload["level"])
				seg_u.set_level(lv_u, true)
				res["sfx"] = "upgrade"
				res["achievement"] = "metal_fences" if lv_u >= 3 else "fence_upgraded"
		"fence_upgrade_ring":
			if bag.spend(cost, stockpile):
				var r_u: int = int(payload["ring"])
				var lv_all: int = int(payload["level"])
				for f in fences:
					if f.ring == r_u and f.is_built and f.level < lv_all:
						f.set_level(lv_all, true)
				res["sfx"] = "upgrade"
				res["achievement"] = "fence_upgraded"
		"fence_spike_seg":
			if bag.spend(cost, stockpile):
				var seg_s: Structure = payload["seg"] as Structure
				seg_s.spiked = true
				seg_s.refresh_visuals()
				res["sfx"] = "upgrade"
	return res


func make_day_snapshot(
	act: int,
	day: int,
	player: Player,
	bag: Inventory,
	stockpile: Inventory,
	upgrades: Dictionary,
	house: Structure,
	fences: Array[Structure]
) -> Dictionary:
	var f_snaps: Array[Dictionary] = []
	for f in fences:
		f_snaps.append(f.to_snapshot())
	return {
		"act": act,
		"day": day,
		"hp": player.hp,
		"bag": bag.to_dict(),
		"stockpile": stockpile.to_dict(),
		"upgrades": upgrades.duplicate(true),
		"house": house.to_snapshot() if house != null else {},
		"fences": f_snaps,
	}


func apply_day_snapshot(
	snap: Dictionary,
	bag: Inventory,
	stockpile: Inventory,
	player: Player,
	house: Structure,
	fences: Array[Structure]
) -> Dictionary:
	bag.from_dict(snap["bag"] as Dictionary)
	stockpile.from_dict(snap["stockpile"] as Dictionary)
	var up: Dictionary = (snap["upgrades"] as Dictionary).duplicate(true)
	player.reset_for_new_game(Config.HOUSE_DOOR)
	player.hp = int(snap["hp"])
	player.apply_upgrade_stats(up)
	if house != null:
		house.apply_snapshot(snap["house"] as Dictionary)
	var f_snaps: Array = snap["fences"] as Array
	for i in range(mini(fences.size(), f_snaps.size())):
		fences[i].apply_snapshot(f_snaps[i] as Dictionary)
	return up


## Handles auto-deposit near the farmhouse and ground pickup collection into bag.
func step_piles_and_deposit(
	tree: SceneTree,
	player: Player,
	house: Structure,
	bag: Inventory,
	stockpile: Inventory,
	sfx: Sfx,
	effects: WorldEffects
) -> bool:
	var picked_plank: bool = false
	if house != null and not house.is_fallen and bag.used_capacity() > 0:
		if house.distance_from_point(player.position) <= 22.0 or player.inside_house:
			var moved: Dictionary = bag.transfer_resources_to(stockpile)
			var total_m: int = int(moved["plank"]) + int(moved["scrap"])
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
		var pile: Pile = node as Pile
		var room: int = (
			player.reserve_max - bag.count("arrow")
			if pile.item_type == "arrow"
			else bag.remaining_capacity()
		)
		var taken: int = pile.try_pickup(player.position, room)
		if taken > 0:
			bag.add(pile.item_type, taken)
			sfx.play("pickup", -8.0)
			var lbl: String = "+%d %s" % [taken, pile.item_type.capitalize()]
			effects.spawn_floating_text(player.position, lbl, Color(1.0, 0.92, 0.56))
			if pile.item_type == "plank":
				picked_plank = true
	return picked_plank


## Places the selected trap in front of the player, consuming from bag or stockpile.
func try_place_trap(
	selected_idx: int,
	player: Player,
	bag: Inventory,
	stockpile: Inventory,
	traps: Array[Trap],
	entities_layer: Node2D,
	hud: Hud,
	sfx: Sfx
) -> void:
	if player.inside_house or player.dead:
		return
	var keys: Array[String] = ["trap_spike", "trap_snare", "trap_lure"]
	var t_key: String = keys[clampi(selected_idx - 1, 0, 2)]
	if traps.size() >= Config.MAX_TRAPS:
		hud.show_message("Max %d traps reached!" % Config.MAX_TRAPS, 1.8, Color(1.0, 0.55, 0.45))
		return
	if bag.count(t_key) <= 0:
		var cost: Dictionary = (Config.TRAPS[t_key] as Dictionary)["cost"] as Dictionary
		if not bag.spend(cost, stockpile):
			hud.show_message("Need %s to place trap." % Inventory.format_cost(cost), 1.8)
			return
	else:
		bag.remove(t_key, 1)

	var place_pos: Vector2 = (player.position + player.facing_vec.normalized() * 14.0).round()
	for ex in traps:
		if is_instance_valid(ex) and ex.position.distance_to(place_pos) < Config.TRAP_MIN_SPACING:
			hud.show_message("Too close to another trap.", 1.4)
			bag.add(t_key, 1)
			return
	var trap: Trap = Trap.new()
	trap.setup(t_key, place_pos)
	trap.triggered.connect(func(_t: Trap, _e: Node) -> void: sfx.play("trap_trigger", -8.0))
	entities_layer.add_child(trap)
	traps.append(trap)
	sfx.play("fence_rebuilt", -9.0)


## Completes a hold-E search on a POI prop, rewarding scrap, planks, and occasional arrows.
func grant_prop_loot(
	prop: Dictionary,
	world_builder: WorldBuilder,
	player: Player,
	bag: Inventory,
	stockpile: Inventory,
	sfx: Sfx,
	effects: WorldEffects
) -> void:
	world_builder.mark_prop_searched(int(prop["id"]))
	var sg: int = int(prop["loot_scrap"])
	var pg: int = int(prop["loot_plank"])
	var sa: int = bag.add("scrap", sg)
	var pa: int = bag.add("plank", pg)
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


## Applies Settings menu toggles/cycles cleanly and refreshes the settings panel.
func handle_settings_action(
	action_id: String, settings: SettingsStore, upgrade_ui: UpgradeUI
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
