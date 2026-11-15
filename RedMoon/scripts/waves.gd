class_name Waves
extends RefCounted

# builds night spawn queues, picks map edges, and formats the hud state dictionary

const DOG_SCENE: PackedScene = preload("res://scenes/dog.tscn")
const GHOST_SCENE: PackedScene = preload("res://scenes/ghost.tscn")


func build_night_wave_queue(day: int, act: int) -> Array[Dictionary]:
	var queue: Array[Dictionary] = []
	var info = Config.NIGHTS.get(day, Config.NIGHTS[7])
	var zombies = int(info["zombies"])
	var raiders = int(info["raiders"])
	var total = zombies + raiders
	var night_dur = maxf(10.0, Config.night_length(day) - 6.0)
	var avg_gap = night_dur / float(maxi(1, total))

	var sides: Array[String] = ["north", "south", "east", "west"]
	var pool: Array[String] = []
	for _z in range(zombies):
		pool.append("zombie")
	for _r in range(raiders):
		pool.append("raider")
	pool.shuffle()

	var idx = 0
	while idx < pool.size():
		var group_n = randi_range(Config.WAVE_GROUP_MIN, Config.WAVE_GROUP_MAX)
		var side = sides[randi() % sides.size()]
		for m in range(group_n):
			if idx >= pool.size():
				break
			var etype = pool[idx]
			var use_side = Config.RAIDER_SIDE if etype == "raider" else side
			var pos = _pick_spawn_edge_pos(use_side, act)
			var gap = maxf(0.9, avg_gap * float(group_n))
			var delay = Config.WAVE_MEMBER_DELAY if (m < group_n - 1) else gap
			queue.append({"type": etype, "pos": pos, "delay": delay})
			idx += 1
	return queue


func _pick_spawn_edge_pos(side: String, act: int) -> Vector2:
	var r = (
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


func _build_objective_text(
	is_night: bool,
	is_blood_moon: bool,
	is_even_moon: bool,
	act: int,
	day: int,
	_total_planks: int
) -> String:
	if is_night:
		var night_msg = "Survive until dawn!"
		if is_blood_moon:
			night_msg = "BLOOD MOON! Hold!"
		elif is_even_moon:
			night_msg = "EVEN MOON! Hold until dawn!"
		return night_msg
	if act == 1:
		var left = maxi(0, Config.WORLD_EXPAND_NIGHT - day)
		return (
			"Blood Moon TONIGHT!" if left == 0
			else "Blood Moon in %d night%s" % [left, "" if left == 1 else "s"]
		)
	var left2 = maxi(0, 7 - day)
	return "FINAL BLOOD MOON!" if left2 == 0 else "Final Blood Moon: %d nights" % left2


func _build_context_prompt(
	player: Player,
	house: Structure,
	map: MapGen,
	nearest_struct: Structure,
	nearest_gate: Structure,
	dogs: Array,
	trap_mode_active: bool,
	selected_trap_idx: int
) -> String:
	var out = ""
	if trap_mode_active:
		var keys: Array[String] = ["trap_snare", "trap_spike", "trap_lure"]
		var tk = keys[clampi(selected_trap_idx - 1, 0, 2)]
		var lbl = String((Config.TRAPS[tk])["label"])
		out = "PLACING %s: [Click / T] Set Trap   |   [Right-Click / Esc] Cancel" % lbl.to_upper()
	elif player.inside_house:
		out = "[E] Step Outside   |   [Click / F] Shoot Bow   |   [U] House Menu"
	else:
		var d_door = 9999.0
		if house != null and house.is_standing():
			d_door = minf(
				player.position.distance_to(Config.HOUSE_DOOR_STEP),
				player.position.distance_to(Config.HOUSE_DOOR)
			)
		var d_gate = (
			nearest_gate.distance_from_point(player.position)
			if nearest_gate != null and nearest_gate.is_standing()
			else 9999.0
		)
		if d_gate <= 34.0 and d_gate <= d_door:
			var act_verb = "Close" if nearest_gate.gate_open else "Open"
			out = "[E] %s Layer %d Gate   |   [U] Upgrade Layer %d" % [
				act_verb, nearest_gate.ring, nearest_gate.ring
			]
		elif d_door <= Config.DOOR_INTERACT_REACH:
			out = (
				"[E] Enter House / Close Door   |   [U] House Menu"
				if house.is_door_open()
				else "[E] Open House Door   |   [U] House Menu"
			)
		else:
			var near_tameable = (
				count_tamed_dogs(dogs) < Config.DOG_MAX_TAMED
				and find_nearest_stray_dog(dogs, player.position, Config.DOG_TAME_RANGE) != null
			)
			if near_tameable:
				out = "Tameable Wild Dog nearby - Click [Tame] button"
			else:
				var prop = map.find_nearest_searchable(player.position, 32.0)
				if not prop.is_empty():
					out = "[Hold E] Search %s" % String(prop["name"])
				else:
					var tree_rec = map.find_nearest_tree(player.position, 26.0)
					if not tree_rec.is_empty():
						out = "[Hold E] Chop Tree (Axe)"
					elif nearest_struct != null and nearest_struct.is_built:
						out = "[U] %s" % nearest_struct.get_tooltip_text()
	return out


func _spawn_pile(
	entities_layer: Node2D, pos: Vector2, amount: int, tier: String, item_type: String
) -> void:
	var pile = Pile.new()
	pile.setup(pos, amount, tier, item_type)
	entities_layer.add_child(pile)


func spawn_day_pickups(
	map: MapGen, entities_layer: Node2D, act: int, day: int
) -> void:
	if act == 1:
		var pts: Array[Vector2] = map.build_act1_plank_positions(
			Config.ACT1_PLANKS_PER_DAY, day * 97 + 11
		)
		for p in pts:
			_spawn_pile(entities_layer, p, 1, "single", "plank")
	else:
		for s in map.make_act2_piles(day * 131 + 29):
			_spawn_pile(
				entities_layer,
				s["pos"],
				int(s["amount"]),
				String(s["tier"]),
				String(s["type"])
			)


func read_move_vector() -> Vector2:
	var x = float(int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(
		Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
	))
	var y = float(int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - int(
		Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	))
	return Vector2(x, y)


func find_nearest_structure(
	structures: Array, world_pos: Vector2, max_d: float
) -> Structure:
	var best = null
	var best_d = max_d
	for s in structures:
		if is_instance_valid(s):
			var st = s
			if not st.is_built:
				continue
			var d = st.distance_from_point(world_pos)
			if d <= best_d:
				best_d = d
				best = st
	return best


func find_nearest_gate(
	fences: Array, world_pos: Vector2, max_d: float
) -> Structure:
	var best = null
	var best_d = max_d
	for f in fences:
		if is_instance_valid(f) and f is Structure:
			var st = f
			if st.is_gate and st.is_standing():
				var d = st.distance_from_point(world_pos)
				if d <= best_d:
					best_d = d
					best = st
	return best


func count_tamed_dogs(dogs: Array) -> int:
	var n = 0
	for d in dogs:
		if is_instance_valid(d) and d.is_tamed() and d.is_alive():
			n += 1
	return n


func find_nearest_stray_dog(dogs: Array, world_pos: Vector2, max_d: float) -> Dog:
	var best = null
	var best_d = max_d
	for d in dogs:
		if is_instance_valid(d) and d.can_be_tamed():
			var dist = d.position.distance_to(world_pos)
			if dist <= best_d:
				best_d = dist
				best = d
	return best


func _roll_stray_tameable(dogs: Array) -> bool:
	var tameable_strays := 0
	var untameable_strays := 0
	for d in dogs:
		if is_instance_valid(d) and d.mode == Dog.Mode.STRAY:
			if d.is_tameable:
				tameable_strays += 1
			else:
				untameable_strays += 1
	if tameable_strays == 0 and untameable_strays > 0:
		return true
	if untameable_strays == 0 and tameable_strays > 0:
		return false
	return randf() < Config.DOG_TAMEABLE_CHANCE


func get_all_hostiles(enemies: Array, ghosts: Array) -> Array:
	var out: Array = []
	for e in enemies:
		if is_instance_valid(e):
			out.append(e)
	for g in ghosts:
		if is_instance_valid(g):
			out.append(g)
	return out


func _pick_ghost_spawn_pos(player_pos: Vector2) -> Vector2:
	var ang := randf_range(0.0, TAU)
	var dist := randf_range(Config.GHOST_SPAWN_MIN_DIST, Config.GHOST_SPAWN_MAX_DIST)
	return (player_pos + Vector2(cos(ang), sin(ang)) * dist).clamp(
		Vector2(60.0, 60.0), Config.WORLD_SIZE - Vector2(60.0, 60.0)
	)


func next_ghost_interval(is_night: bool) -> float:
	if is_night:
		return randf_range(Config.GHOST_NIGHT_INTERVAL_MIN, Config.GHOST_NIGHT_INTERVAL_MAX)
	return randf_range(Config.GHOST_DAY_INTERVAL_MIN, Config.GHOST_DAY_INTERVAL_MAX)


func spawn_ghost_for(main_node: Node) -> Ghost:
	var act = int(main_node.get("act"))
	var day = int(main_node.get("day"))
	if act < 2 or day < Config.GHOST_MIN_DAY:
		return null
	var ghosts: Array = main_node.get("ghosts")
	if ghosts.size() >= Config.GHOST_MAX_ALIVE:
		return null
	var player: Player = main_node.get("_player") as Player
	if player == null or player.dead:
		return null
	var pos := _pick_ghost_spawn_pos(player.position)
	var variant := "scythe" if randf() < 0.65 else "lunge"
	var g: Ghost = GHOST_SCENE.instantiate() as Ghost
	g.setup(pos, variant)
	g.player_damaged.connect(func(dmg: int, _ghost: Node) -> void:
		main_node.call("_on_ghost_player_damaged", dmg)
	)
	g.damaged_feedback.connect(func(hit_pos: Vector2, is_kill: bool) -> void:
		main_node.call("_on_enemy_hit_feedback", hit_pos, is_kill)
	)
	g.killed.connect(func(_ghost: Node, was_bow: bool) -> void:
		main_node.call("_on_hostile_killed", was_bow)
	)
	var entities_layer = main_node.get("_entities_layer")
	var sfx = main_node.get("_sfx")
	var fx = main_node.get("_fx")
	var hud = main_node.get("_hud")
	entities_layer.add_child(g)
	ghosts.append(g)
	sfx.play("ghost_appear", -7.0)
	fx.spawn_ring(pos, 34.0, Color(0.68, 0.90, 1.0, 0.72))
	fx.spawn_sparks(pos, Color(0.75, 0.92, 1.0, 0.85), 6)
	hud.show_message("A cold chill passes nearby...", 1.8, Color(0.76, 0.90, 1.0))
	return g


func spawn_dog_for(
	main_node: Node,
	pos: Vector2,
	start_mode: int = Dog.Mode.STRAY,
	start_hp: int = -1,
	allow_tame: bool = false
) -> Dog:
	var d: Dog = DOG_SCENE.instantiate() as Dog
	if not d.setup(pos, allow_tame):
		d.free()
		return null
	d.restore_state(start_mode, start_hp, pos)
	var sfx = main_node.get("_sfx")
	var fx = main_node.get("_fx")
	var hud = main_node.get("_hud")
	d.tamed.connect(func(_dog: Dog) -> void:
		sfx.play("dog_bark", -6.0)
		main_node.call("_unlock_achievement", "tamed_dog")
		hud.show_message("Dog tamed! Press G for Follow / Guard.", 2.6, Color(0.62, 0.96, 0.68))
	)
	d.attacked_enemy.connect(func(en: Node2D) -> void:
		sfx.play("dog_bark", -12.0)
		if is_instance_valid(en):
			fx.spawn_sparks(en.position, Color(1.0, 0.42, 0.34, 1.0), 5)
	)
	d.died.connect(func(fallen: Dog) -> void:
		sfx.play("player_hit", -8.0)
		fx.spawn_sparks(fallen.position, Color(1.0, 0.32, 0.28, 1.0), 8)
		hud.show_message("Your companion dog fell in battle!", 2.4, Color(1.0, 0.42, 0.38))
	)
	main_node.get("_entities_layer").add_child(d)
	var dogs: Array = main_node.get("dogs")
	dogs.append(d)
	return d


func maybe_spawn_stray_dogs_for(main_node: Node) -> void:
	var act = int(main_node.get("act"))
	var day = int(main_node.get("day"))
	if act < 2 or day < Config.GHOST_MIN_DAY:
		return
	var dogs: Array = main_node.get("dogs")
	var to_add = mini(2, Config.DOG_MAX - dogs.size())
	for _i in range(to_add):
		var allow_tame := _roll_stray_tameable(dogs)
		var pos := Config.HOUSE_CENTER + Vector2(
			randf_range(-420.0, 420.0), randf_range(160.0, 260.0)
		)
		spawn_dog_for(main_node, pos, Dog.Mode.STRAY, -1, allow_tame)


func get_night_banner_info(day: int, is_blood: bool, is_even: bool) -> Dictionary:
	if is_blood:
		return {
			"title": "NIGHT %d - BLOOD MOON!" % day,
			"sub": "Hold every ring! They are swarming from all sides!",
			"color": Color(1.0, 0.34, 0.24),
		}
	if is_even:
		return {
			"title": "NIGHT %d - EVEN MOON" % day,
			"sub": "The crimson Even Moon watches. Defend until dawn.",
			"color": Config.EVEN_MOON_BANNER,
		}
	return {
		"title": "NIGHT %d" % day,
		"sub": "Night has fallen. Defend the farmhouse until dawn.",
		"color": Color(0.86, 0.90, 1.0),
	}


func spawn_boomerang_for(
	main_node: Node, origin: Vector2, aim_dir: Vector2, dmg: int
) -> Boomerang:
	var player = main_node.get("_player")
	var sfx = main_node.get("_sfx")
	var fx = main_node.get("_fx")
	var boomerangs: Array = main_node.get("boomerangs")

	var b := Boomerang.new()
	b.setup(player, origin, aim_dir, dmg, Config.BOOMERANG_RANGE, true)
	b.hit_target.connect(func(target: Node2D, boom: Boomerang, _is_ret: bool) -> void:
		if is_instance_valid(target) and target.has_method("take_hit"):
			var hit_dir := (
				boom.velocity.normalized() if boom.velocity.length_squared() > 0.01 else Vector2.RIGHT
			)
			target.call("take_hit", boom.damage, hit_dir, false)
	)
	b.bounced.connect(func(pos: Vector2, hit_enemy: bool) -> void:
		if hit_enemy:
			fx.spawn_sparks(pos, Color(0.95, 0.90, 0.50, 1.0), 6)
	)
	b.caught.connect(func(_boom: Boomerang) -> void:
		if is_instance_valid(player):
			player.on_boomerang_caught()
		sfx.play("boomerang_catch", -9.0)
	)
	main_node.get("_entities_layer").add_child(b)
	boomerangs.append(b)
	sfx.play("boomerang_throw", -8.0)
	return b


func has_open_fence_gate(fences: Array) -> bool:
	for f in fences:
		if is_instance_valid(f):
			var st = f
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
		var typed_list: Array = arr
		var i = typed_list.size() - 1
		while i >= 0:
			if not is_instance_valid(typed_list[i]):
				typed_list.remove_at(i)
			i -= 1


func clear_group_or_list(items: Array) -> void:
	for item in items:
		if is_instance_valid(item):
			var n = item
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	items.clear()


func pick_wanderer_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var count = randi_range(Config.DAY_WANDERER_MIN, Config.DAY_WANDERER_MAX)
	for _i in range(count):
		var ang = randf_range(0.0, TAU)
		var dist = randf_range(340.0, 920.0)
		var pos = (Config.HOUSE_CENTER + Vector2(cos(ang), sin(ang)) * dist).clamp(
			Vector2(60.0, 60.0), Config.WORLD_SIZE - Vector2(60.0, 60.0)
		)
		out.append(pos)
	return out


# packs everything Hud.update_hud needs into one dict so main.gd stays somewhat readable
func make_hud_data(
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
	var is_blood = bool(main_node.get("is_blood_moon"))
	var is_even = bool(main_node.get("is_even_moon"))
	var act = int(main_node.get("act"))
	var day = int(main_node.get("day"))
	var phase_timer = float(main_node.get("phase_timer"))
	var trap_mode_active = bool(main_node.get("_trap_mode_active"))
	var player = main_node.get("_player")
	var house = main_node.get("house")
	var fences: Array = main_node.get("fences")
	var bag = main_node.get("bag")
	var stockpile = main_node.get("stockpile")
	var map = main_node.get("_map")
	var dogs: Array = main_node.get("dogs")
	var traps: Array = main_node.get("traps")
	var near_gate = find_nearest_gate(fences, player.position, 34.0)
	var obj = _build_objective_text(
		is_night, is_blood, is_even, act, day, bag.count("plank") + stockpile.count("plank")
	)
	var prompt = _build_context_prompt(
		player, house, map, nearest_struct, near_gate, dogs, trap_mode_active, selected_trap_idx
	)
	var tooltip = (
		hovered_struct.get_tooltip_text()
		if is_instance_valid(hovered_struct) and hovered_struct.is_built
		else ""
	)
	var home_arrow = Vector2.ZERO
	var home_dist = 0
	if not player.inside_house:
		var to_home = Config.HOUSE_CENTER - player.position
		var dist = to_home.length()
		if dist >= Config.BASE_TRACKER_MIN_PX and dist <= Config.BASE_TRACKER_MAX_PX:
			home_arrow = to_home / dist
			home_dist = int(roundf(dist / 16.0))
	var can_tame_dog = (
		not player.inside_house
		and count_tamed_dogs(dogs) < Config.DOG_MAX_TAMED
		and find_nearest_stray_dog(dogs, player.position, Config.DOG_TAME_RANGE) != null
	)
	var phase_label = "DAY %d" % day
	if is_night:
		if is_blood:
			phase_label = "NIGHT %d (BLOOD MOON)" % day
		elif is_even:
			phase_label = "NIGHT %d (EVEN MOON)" % day
		else:
			phase_label = "NIGHT %d" % day
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
		"bow_cd": player.bow_cd,
		"boomerang_cd": player.boomerang_cd,
		"boomerang_flying": player.boomerang_in_flight,
		"reloading": player.is_reloading(),
		"active_weapon": player.active_weapon,
		"phase_label": phase_label,
		"time_left": phase_timer,
		"objective": obj,
		"bounce_cd": bounce_cd,
		"selected_trap": selected_trap_idx,
		"trap_mode_active": trap_mode_active,
		"trap_snare": bag.count("trap_snare"),
		"trap_spike": bag.count("trap_spike"),
		"trap_lure": bag.count("trap_lure"),
		"traps_placed": traps.size(),
		"traps_max": Config.MAX_TRAPS,
		"muted": muted,
		"prompt": prompt,
		"tooltip": tooltip,
		"search_progress": search_progress,
		"home_arrow_dir": home_arrow,
		"home_dist": home_dist,
		"can_tame_dog": can_tame_dog,
	}
