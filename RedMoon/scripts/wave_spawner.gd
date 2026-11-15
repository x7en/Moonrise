class_name WaveSpawner
extends RefCounted

# builds night spawn queues, picks map edges, and formats the hud state dictionary


func build_night_wave_queue(day: int, act: int) -> Array[Dictionary]:
	var queue: Array[Dictionary] = []
	var spec: Dictionary = Config.NIGHTS.get(day, Config.NIGHTS[7]) as Dictionary
	var zombies: int = int(spec["zombies"])
	var raiders: int = int(spec["raiders"])
	var total: int = zombies + raiders
	var night_dur: float = maxf(10.0, Config.night_length(day) - 6.0)
	var avg_gap: float = night_dur / float(maxi(1, total))

	var sides: Array[String] = ["north", "south", "east", "west"]
	var pool: Array[String] = []
	for _z in range(zombies):
		pool.append("zombie")
	for _r in range(raiders):
		pool.append("raider")
	pool.shuffle()

	var idx: int = 0
	while idx < pool.size():
		var group_n: int = randi_range(Config.WAVE_GROUP_MIN, Config.WAVE_GROUP_MAX)
		var side: String = sides[randi() % sides.size()]
		for m in range(group_n):
			if idx >= pool.size():
				break
			var etype: String = pool[idx]
			var use_side: String = Config.RAIDER_SIDE if etype == "raider" else side
			var pos: Vector2 = pick_spawn_edge_pos(use_side, act)
			var gap: float = maxf(0.9, avg_gap * float(group_n))
			var delay: float = Config.WAVE_MEMBER_DELAY if (m < group_n - 1) else gap
			queue.append({"type": etype, "pos": pos, "delay": delay})
			idx += 1
	return queue


func pick_spawn_edge_pos(side: String, act: int) -> Vector2:
	var r: Rect2 = (
		Config.ACT1_RECT.grow(-18.0)
		if act == 1
		else Rect2(Config.HOUSE_CENTER - Vector2(420.0, 270.0), Vector2(840.0, 540.0))
	)
	match side:
		"north":
			return Vector2(randf_range(r.position.x, r.end.x), r.position.y)
		"south":
			return Vector2(randf_range(r.position.x, r.end.x), r.end.y)
		"west":
			return Vector2(r.position.x, randf_range(r.position.y, r.end.y))
		_:
			return Vector2(r.end.x, randf_range(r.position.y, r.end.y))


func build_objective_text(
	is_night: bool,
	is_blood_moon: bool,
	act: int,
	day: int,
	_total_planks: int
) -> String:
	if is_night:
		return "BLOOD MOON! Hold!" if is_blood_moon else "Hold out until dawn!"
	if act == 1:
		var left: int = maxi(0, Config.WORLD_EXPAND_NIGHT - day)
		if left == 0:
			return "Blood Moon TONIGHT!"
		return "Blood Moon in %d night%s" % [left, "" if left == 1 else "s"]
	var left2: int = maxi(0, 7 - day)
	if left2 == 0:
		return "FINAL BLOOD MOON!"
	return "Final Blood Moon: %d nights" % left2


func build_context_prompt(
	player: Player,
	house: Structure,
	world_builder: WorldBuilder,
	nearest_struct: Structure,
	nearest_gate: Structure,
	trap_mode_active: bool,
	selected_trap_idx: int
) -> String:
	var out: String = ""
	if trap_mode_active:
		var keys: Array[String] = ["trap_spike", "trap_snare", "trap_lure"]
		var tk: String = keys[clampi(selected_trap_idx - 1, 0, 2)]
		var lbl: String = String((Config.TRAPS[tk] as Dictionary)["label"])
		out = "PLACING %s: [Click / T] Set Trap   |   [Right-Click / Esc] Cancel" % lbl.to_upper()
	elif player.inside_house:
		out = "[E] Step Outside   |   [F] Shoot Bow   |   [U] House Menu"
	elif house != null and house.is_standing() and minf(
		player.position.distance_to(Config.HOUSE_DOOR_STEP),
		player.position.distance_to(Config.HOUSE_DOOR)
	) <= Config.DOOR_INTERACT_REACH:
		out = (
			"[E] Enter House / Close Door   |   [U] House Menu"
			if house.is_door_open()
			else "[E] Open House Door   |   [U] House Menu"
		)
	elif nearest_gate != null and nearest_gate.is_standing():
		var act_verb: String = "Close" if nearest_gate.gate_open else "Open"
		out = "[E] %s Layer %d Gate   |   [U] Upgrade Layer %d" % [
			act_verb, nearest_gate.ring, nearest_gate.ring
		]
	else:
		var prop: Dictionary = world_builder.find_nearest_searchable(player.position, 32.0)
		if not prop.is_empty():
			out = "[Hold E] Search %s" % String(prop["name"])
		elif nearest_struct != null and nearest_struct.is_built:
			out = "[U] %s" % nearest_struct.get_tooltip_text()
	return out


func spawn_pile(
	entities_layer: Node2D, pos: Vector2, amount: int, tier: String, item_type: String
) -> void:
	var pile: Pile = Pile.new()
	pile.setup(pos, amount, tier, item_type)
	entities_layer.add_child(pile)


func spawn_day_pickups(
	world_builder: WorldBuilder, entities_layer: Node2D, act: int, day: int
) -> void:
	if act == 1:
		var pts: Array[Vector2] = world_builder.build_act1_plank_positions(
			Config.ACT1_PLANKS_PER_DAY, day * 97 + 11
		)
		for p in pts:
			spawn_pile(entities_layer, p, 1, "single", "plank")
	else:
		for s in world_builder.build_act2_pile_specs(day * 131 + 29):
			spawn_pile(
				entities_layer,
				s["pos"] as Vector2,
				int(s["amount"]),
				String(s["tier"]),
				String(s["type"])
			)


func read_move_vector() -> Vector2:
	var x: float = float(int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(
		Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
	))
	var y: float = float(int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - int(
		Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	))
	return Vector2(x, y)


func find_nearest_structure(
	structures: Array, world_pos: Vector2, max_d: float
) -> Structure:
	var best: Structure = null
	var best_d: float = max_d
	for s in structures:
		if is_instance_valid(s):
			var st: Structure = s as Structure
			if not st.is_built:
				continue
			var d: float = st.distance_from_point(world_pos)
			if d <= best_d:
				best_d = d
				best = st
	return best


func find_nearest_gate(
	fences: Array, world_pos: Vector2, max_d: float
) -> Structure:
	var best: Structure = null
	var best_d: float = max_d
	for f in fences:
		if is_instance_valid(f) and f is Structure:
			var st: Structure = f as Structure
			if st.is_gate and st.is_standing():
				var d: float = st.distance_from_point(world_pos)
				if d <= best_d:
					best_d = d
					best = st
	return best


func has_open_fence_gate(fences: Array) -> bool:
	for f in fences:
		if is_instance_valid(f):
			var st: Structure = f as Structure
			if st.is_gate and st.is_standing() and st.gate_open:
				return true
	return false


func clear_piles_in_tree(tree: SceneTree) -> void:
	for p in tree.get_nodes_in_group("piles"):
		if is_instance_valid(p):
			p.remove_from_group("piles")
			if p.get_parent() != null:
				p.get_parent().remove_child(p)
			p.queue_free()


func prune_invalid_arrays(lists: Array) -> void:
	for arr in lists:
		var typed_list: Array = arr as Array
		var i: int = typed_list.size() - 1
		while i >= 0:
			if not is_instance_valid(typed_list[i]):
				typed_list.remove_at(i)
			i -= 1


func clear_group_or_list(items: Array) -> void:
	for item in items:
		if is_instance_valid(item):
			var n: Node = item as Node
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	items.clear()


func pick_wanderer_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var count: int = randi_range(Config.DAY_WANDERER_MIN, Config.DAY_WANDERER_MAX)
	for _i in range(count):
		var ang: float = randf_range(0.0, TAU)
		var dist: float = randf_range(340.0, 920.0)
		var pos: Vector2 = (Config.HOUSE_CENTER + Vector2(cos(ang), sin(ang)) * dist).clamp(
			Vector2(60.0, 60.0), Config.WORLD_SIZE - Vector2(60.0, 60.0)
		)
		out.append(pos)
	return out


# packs everything Hud.update_hud needs into one dict so main.gd stays somewhat readable
func build_hud_payload(
	main_node: Node,
	is_night: bool,
	nearest_struct: Structure,
	hovered_struct: Structure,
	intruders_inside: int,
	bounce_cd: float,
	selected_trap_idx: int,
	muted: bool,
	search_progress: float
) -> Dictionary:
	var is_blood: bool = bool(main_node.get("is_blood_moon"))
	var act: int = int(main_node.get("act"))
	var day: int = int(main_node.get("day"))
	var phase_timer: float = float(main_node.get("phase_timer"))
	var trap_mode_active: bool = bool(main_node.get("_trap_mode_active"))
	var player: Player = main_node.get("_player") as Player
	var house: Structure = main_node.get("house") as Structure
	var fences: Array = main_node.get("fences") as Array
	var bag: Inventory = main_node.get("bag") as Inventory
	var stockpile: Inventory = main_node.get("stockpile") as Inventory
	var wb: WorldBuilder = main_node.get("_world_builder") as WorldBuilder
	var near_gate: Structure = find_nearest_gate(fences, player.position, 28.0)
	var obj: String = build_objective_text(
		is_night, is_blood, act, day, bag.count("plank") + stockpile.count("plank")
	)
	var prompt: String = build_context_prompt(
		player, house, wb, nearest_struct, near_gate, trap_mode_active, selected_trap_idx
	)
	var tooltip: String = (
		hovered_struct.get_tooltip_text()
		if is_instance_valid(hovered_struct) and hovered_struct.is_built
		else ""
	)
	var home_arrow: Vector2 = Vector2.ZERO
	if act == 2 and not player.inside_house:
		var to_home: Vector2 = Config.HOUSE_CENTER - player.position
		if to_home.length() > 260.0:
			home_arrow = to_home.normalized()
	return {
		"hp": player.hp,
		"max_hp": player.max_hp,
		"house_fallen": house.is_fallen if house != null else false,
		"house_hp": house.hp if house != null else 0,
		"house_max": house.max_hp if house != null else 100,
		"door_open": house.is_door_open() if house != null else false,
		"intruders": intruders_inside,
		"inside_house": player.inside_house,
		"bag_used": bag.used_capacity(),
		"bag_cap": bag.capacity,
		"bag_planks": bag.count("plank"),
		"bag_scrap": bag.count("scrap"),
		"stock_planks": stockpile.count("plank"),
		"stock_scrap": stockpile.count("scrap"),
		"mag": player.mag,
		"mag_max": player.mag_max,
		"arrows": bag.count("arrow"),
		"reloading": player.is_reloading(),
		"phase_label": "%s %d (ACT %d)" % ["NIGHT" if is_night else "DAY", day, act],
		"time_left": phase_timer,
		"objective": obj,
		"bounce_cd": bounce_cd,
		"selected_trap": selected_trap_idx,
		"trap_mode_active": trap_mode_active,
		"trap_spike": bag.count("trap_spike"),
		"trap_snare": bag.count("trap_snare"),
		"trap_lure": bag.count("trap_lure"),
		"muted": muted,
		"prompt": prompt,
		"tooltip": tooltip,
		"search_progress": search_progress,
		"home_arrow_dir": home_arrow,
	}
