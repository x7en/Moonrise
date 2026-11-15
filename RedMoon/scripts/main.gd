extends Node2D

# main game loop and glue between world, player, enemies, and ui

enum GameState { TITLE, STORY, DAY, MOONRISE, NIGHT, PAUSED, GAME_OVER, VICTORY }

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

var state: GameState = GameState.TITLE
var act: int = 1
var day: int = 1
var phase_timer: float = 0.0
var is_blood_moon: bool = false
var is_even_moon: bool = false
var is_dusk_warned: bool = false

var house: Structure
var fences: Array[Structure] = []
var structures: Array = []
var enemies: Array[Enemy] = []
var ghosts: Array[Ghost] = []
var arrows: Array[Arrow] = []
var boomerangs: Array[Boomerang] = []
var traps: Array[Trap] = []
var watchtowers: Array[Watchtower] = []
var dogs: Array[Dog] = []

var bag: Bag
var stockpile: Bag
var settings: SaveData
var upgrades: Dictionary = {}

var _ground_layer: Node2D
var _decals_layer: Node2D
var _entities_layer: Node2D
var _fx: Fx
var _tint: CanvasModulate
var _camera: Camera2D
var _player: Player
var _map: MapGen
var _hud: Hud
var _intro: IntroCards
var _night_intro: NightIntro
var _menus: Menus
var _popups: Popups
var _sfx: Sfx
var _shop: Shop = Shop.new()
var _waves: Waves = Waves.new()

var _wave_queue: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _ghost_spawn_timer: float = 0.0
var _bounce_cd: float = 0.0
var _shockwave_cd: float = 0.0
var _hit_stop: float = 0.0
var _shake_timer: float = 0.0
var _shake_amp: float = 0.0
var _selected_trap_idx: int = 1
var _trap_mode_active: bool = false
var _intruders_inside: int = 0
var _intruder_dmg_accum: float = 0.0
var _intruder_player_timer: float = 0.0
var _night_damage_taken: bool = false
var _night_had_intruder: bool = false
var _kills_total: int = 0
var _hovered_struct: Structure
var _search_key: String = ""
var _search_timer: float = 0.0
var _search_progress: float = 0.0
var _pending_story_cb: Callable = Callable()
var _day_save: Dictionary = {}
var _pre_pause_state: GameState = GameState.DAY
var _info_return_to_title: bool = false
var _tutorial_overlay_open: bool = false


func _ready() -> void:
	settings = SaveData.new()
	settings.load_all()
	settings.apply_display_and_audio()

	_set_trap_mode(false)
	bag = Bag.new(Config.BAG_CAPACITY)
	stockpile = Bag.new(-1)

	_build_scene_tree()
	_connect_ui_signals()
	_rebuild_world_and_structures(1337)
	if settings.should_auto_play_story():
		state = GameState.STORY
		_hud.hide_all_screens()
		_pending_story_cb = func() -> void:
			settings.mark_intro_completed()
			_return_to_title()
		_intro.show_cards(IntroCards.get_opening_cards(), true, false)
	else:
		_hud.show_title_screen(false)


func _process(delta: float) -> void:
	if _hit_stop > 0.0:
		_hit_stop = maxf(0.0, _hit_stop - delta)
		return
	_shake_timer = maxf(0.0, _shake_timer - delta)
	_update_camera()
	if state == GameState.DAY or state == GameState.NIGHT:
		_step_gameplay(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _intro.active or _night_intro.active:
		return
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if ke.pressed and not ke.echo:
			_handle_key_press(ke)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			if _trap_mode_active:
				_set_trap_mode(false)
			else:
				_try_right_click_structure()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_handle_left_click()


func _handle_key_press(ke: InputEventKey) -> void:
	if ke.keycode == KEY_F11 or (ke.keycode == KEY_ENTER and ke.alt_pressed):
		_toggle_fullscreen()
		return
	if ke.keycode == KEY_M:
		_sfx.toggle_mute()
		return
	if ke.keycode == KEY_F8:
		_fx.show_debug_colliders = not _fx.show_debug_colliders
		_fx.queue_redraw()
		return
	if _menus.is_open() or (state != GameState.DAY and state != GameState.NIGHT):
		return

	match ke.keycode:
		KEY_ESCAPE:
			if _trap_mode_active:
				_set_trap_mode(false)
				return
			_enter_menu_pause()
			_menus.open_pause_menu()
		KEY_I:
			_enter_menu_pause()
			_menus.open_inventory(bag, stockpile, _player, upgrades)
		KEY_C:
			_enter_menu_pause()
			_menus.open_crafting_menu(bag, stockpile)
		KEY_SPACE:
			_trigger_melee_or_clear_intruders()
		KEY_F:
			_player.try_fire_bow(_waves.get_all_hostiles(enemies, ghosts), bag)
		KEY_R:
			if _player.start_reload(bag):
				_sfx.play("bow_reload", -10.0)
		KEY_B:
			_try_bounce_back()
		KEY_Q:
			_try_shockwave()
		KEY_E:
			_handle_interact_press()
		KEY_U:
			_set_trap_mode(false)
			_try_open_nearby_structure_menu()
		KEY_1, KEY_2, KEY_3:
			_toggle_trap_slot(int(ke.keycode - KEY_1) + 1)
		KEY_T:
			_place_selected_trap()
		KEY_G:
			_toggle_dogs_mode()


func _enter_menu_pause() -> void:
	_set_trap_mode(false)
	_shop.reset_hold_gather(self)
	_pre_pause_state = state
	state = GameState.PAUSED
	_info_return_to_title = false


func _toggle_trap_slot(idx: int) -> void:
	var turn_on = not (_trap_mode_active and _selected_trap_idx == idx)
	_selected_trap_idx = idx
	_set_trap_mode(turn_on)


func _set_trap_mode(active: bool) -> void:
	_trap_mode_active = active
	if not active and _fx != null:
		_fx.set_trap_preview(false)

	# swap mouse cursor to crosshair while placing traps
	if DisplayServer.get_name() != "headless":
		var icon_id := "cursor_crosshair" if active else "cursor"
		var hot := Vector2(8.0, 8.0) if active else Vector2(1.0, 1.0)
		Input.set_custom_mouse_cursor(Art.get_icon_texture(icon_id), Input.CURSOR_ARROW, hot)


func _place_selected_trap() -> void:
	var keys: Array[String] = ["trap_snare", "trap_spike", "trap_lure"]
	var t_key := keys[clampi(_selected_trap_idx - 1, 0, 2)]
	var pos := _shop.compute_trap_place_pos(_trap_mode_active, self)
	_shop.try_place_trap_at(t_key, pos, self)


func _handle_left_click() -> void:
	if _menus.is_open() or (state != GameState.DAY and state != GameState.NIGHT):
		return
	if _trap_mode_active:
		_place_selected_trap()
		return
	if _player.active_weapon == "spear":
		_trigger_melee_or_clear_intruders()
	elif _player.active_weapon == "boomerang" and _player.inside_house:
		if _intruders_inside > 0:
			_trigger_melee_or_clear_intruders()
		else:
			_hud.show_message("Step outside to throw Boomerang (or press F for Bow).", 1.8)
	else:
		_player.use_active_weapon(_waves.get_all_hostiles(enemies, ghosts), bag)


func _try_right_click_structure() -> void:
	if _menus.is_open() or (state != GameState.DAY and state != GameState.NIGHT):
		return
	var st := _hovered_struct
	if st != null and st.is_built:
		if st.distance_from_point(_player.position) <= Config.STRUCTURE_MENU_REACH:
			_open_structure_menu(st)


func _step_gameplay(delta: float) -> void:
	var bounds := Config.ACT1_RECT if act == 1 else Config.WORLD_RECT
	_player.step_player(delta, _waves.read_move_vector(), bounds, not _menus.is_open(), bag)
	_player.set_night_lantern(state == GameState.NIGHT)

	_bounce_cd = maxf(0.0, _bounce_cd - delta)
	_shockwave_cd = maxf(0.0, _shockwave_cd - delta)

	_waves.prune_invalid_arrays([enemies, ghosts, arrows, boomerangs, traps, watchtowers, dogs])
	var hostiles := _waves.get_all_hostiles(enemies, ghosts)
	_step_hover_target()
	_shop.update_trap_preview(_trap_mode_active, _selected_trap_idx, self)
	if _shop.step_piles_and_deposit(get_tree(), _player, house, bag, stockpile, _sfx, _fx):
		_unlock_achievement("first_plank")
	_shop.step_hold_gather(delta, self)

	for a in arrows:
		if is_instance_valid(a):
			a.step_arrow(delta, hostiles, bounds)
	for b in boomerangs:
		if is_instance_valid(b):
			b.step_boomerang(delta, hostiles, bounds)
	for t in traps:
		if is_instance_valid(t):
			t.step_trap(delta, enemies)
	for wt in watchtowers:
		if is_instance_valid(wt):
			wt.step_tower(delta, hostiles)
	for d in dogs:
		if is_instance_valid(d):
			d.step_dog(
				delta, _player.position, enemies, bounds, _player.facing_vec, _player.inside_house
			)
	for e in enemies:
		if is_instance_valid(e):
			e.step_enemy(
				delta, structures, watchtowers, traps, _player.position,
				_player.inside_house, house, enemies, bounds, dogs
			)
	for g in ghosts:
		if is_instance_valid(g):
			g.step_ghost(delta, _player.position, _player.inside_house, bounds)
	_step_intruders(delta)

	if act >= 2 and day >= Config.GHOST_MIN_DAY:
		_ghost_spawn_timer -= delta
		if _ghost_spawn_timer <= 0.0:
			_ghost_spawn_timer = _waves.next_ghost_interval(state == GameState.NIGHT)
			_waves.spawn_ghost_for(self)

	if state == GameState.DAY:
		_step_day_phase(delta)
	elif state == GameState.NIGHT:
		phase_timer -= delta
		if not _wave_queue.is_empty():
			_spawn_timer -= delta
			if _spawn_timer <= 0.0:
				var next_e = _wave_queue.pop_front()
				_spawn_enemy(String(next_e["type"]), next_e["pos"], false)
				_spawn_timer = float(next_e["delay"])
		if phase_timer <= 0.0 and _wave_queue.is_empty():
			_finish_night()

	_update_lighting_and_tint()
	_update_hud()


func _step_day_phase(delta: float) -> void:
	phase_timer -= delta
	var dusk_thresh = Config.ACT1_DUSK_TIME if act == 1 else Config.ACT2_DUSK_TIME
	if not is_dusk_warned and phase_timer <= dusk_thresh:
		is_dusk_warned = true
		var msg = (
			"Dusk: close your fence gate [E] & get inside!"
			if _waves.has_open_fence_gate(fences)
			else ("Dusk: get inside and close the door!" if act == 1 else "Dusk. Head home.")
		)
		_hud.show_message(msg, 3.0, Color(1.0, 0.72, 0.40))
	if phase_timer <= 0.0:
		_begin_night_sequence()


func _begin_new_run() -> void:
	act = 1
	day = 1
	is_blood_moon = false
	is_even_moon = false
	_kills_total = 0
	_intruders_inside = 0
	_bounce_cd = 0.0
	_shockwave_cd = 0.0
	_set_trap_mode(false)
	_day_save.clear()
	upgrades = {"gear_tier": 1}
	bag.clear()
	stockpile.clear()
	stockpile.add("plank", Config.ACT1_START_STOCKPILE)
	bag.add("arrow", 18)
	bag.add("trap_snare", Config.START_BEAR_TRAPS)
	bag.add("trap_spike", Config.START_SPIKE_TRAPS)

	_clear_dynamic_world()
	_rebuild_world_and_structures(1337 + randi() % 1000)
	_player.reset_for_new_game(Config.HOUSE_DOOR)
	_player.apply_upgrade_stats(upgrades)
	_map.set_act1_fog_visible(true)
	_apply_camera_limits()
	_hud.show_gameplay_hud()
	_start_day(1)


func _start_day(day_num: int, is_retry: bool = false) -> void:
	day = day_num
	state = GameState.DAY
	is_blood_moon = false
	is_even_moon = false
	is_dusk_warned = false
	_intruders_inside = 0
	phase_timer = Config.day_length()
	_ghost_spawn_timer = _waves.next_ghost_interval(false)
	_shop.reset_hold_gather(self)

	if _player.inside_house:
		_player.set_inside_house(false, Config.HOUSE_DOOR)
	if house != null and house.is_standing():
		house.toggle_door(true)
	# open built fence gates each morning from Day 1 so the player is never trapped inside
	for f in fences:
		if f.is_gate and f.is_standing() and not f.gate_open:
			f.toggle_door(false)
	if day > 1 and not is_retry:
		if house != null and house.is_standing():
			house.heal(Config.DAWN_FREE_REPAIR)
		for f in fences:
			if f.is_standing():
				f.heal(Config.DAWN_FREE_REPAIR)
		for d in dogs:
			if is_instance_valid(d):
				d.heal_for_new_day()

	_clear_dynamic_world()
	_waves.spawn_day_pickups(_map, _entities_layer, act, day)
	if act == 2:
		for wp in _waves.pick_wanderer_positions():
			_spawn_enemy("zombie", wp, true)
		_waves.maybe_spawn_stray_dogs_for(self)

	_day_save = _shop.save_day(self)
	var sub = (
		"Gather planks, set traps [1-3], & close your fence gate [E] before dusk!"
		if act == 1 else "Explore the valley, scavenge scrap, and unlock outer fence layers!"
	)
	var col = Color(1.0, 0.90, 0.56) if act == 1 else Color(0.62, 0.96, 0.68)
	_hud.show_header_banner("DAY %d" % day, sub, col, 2.8)


func _begin_night_sequence() -> void:
	_shop.reset_hold_gather(self)
	# wipe leftover pickups before dusk flips over
	_waves.clear_piles_in_tree(get_tree())
	if OS.is_debug_build():
		assert(get_tree().get_nodes_in_group("piles").is_empty(), "leftover piles still around at night")
	if act == 2 and Config.LOSE_BAG_AT_DUSK_ACT2 and not _player.inside_house:
		if bag.used_capacity() > 0:
			bag.remove("plank", bag.count("plank"))
			bag.remove("scrap", bag.count("scrap"))
			_hud.show_message(
				"Night fell outside! Unbanked bag resources lost.", 2.6, Color(1.0, 0.45, 0.40)
			)

	is_blood_moon = (day == Config.WORLD_EXPAND_NIGHT or day == 7)
	is_even_moon = (not is_blood_moon and (day % 2 == 0))
	state = GameState.MOONRISE
	if is_blood_moon:
		_sfx.play("blood_moon", -6.0)
	_night_intro.start_moonrise(day, is_blood_moon, false, is_even_moon)


func _start_night_combat() -> void:
	state = GameState.NIGHT
	phase_timer = Config.night_length(day)
	_ghost_spawn_timer = _waves.next_ghost_interval(true)
	_night_damage_taken = false
	_night_had_intruder = false
	_clear_dynamic_world()
	_wave_queue = _waves.build_night_wave_queue(day, act)
	_spawn_timer = 0.8
	var bn := _waves.get_night_banner_info(day, is_blood_moon, is_even_moon)
	_hud.show_header_banner(String(bn["title"]), String(bn["sub"]), bn["color"], 2.5)


func _finish_night() -> void:
	for e in enemies:
		if is_instance_valid(e) and e.is_alive():
			e.start_dissolve()
	for g in ghosts:
		if is_instance_valid(g) and g.is_alive():
			g.start_dissolve()
	_waves.clear_group_or_list(arrows)
	_waves.clear_group_or_list(boomerangs)
	_player.boomerang_in_flight = false
	if day == 1:
		_unlock_achievement("first_night")
	if not _night_damage_taken:
		_unlock_achievement("perfect_night")
	if _night_had_intruder:
		_unlock_achievement("intruder_alert")

	if day == Config.WORLD_EXPAND_NIGHT and act == 1:
		_unlock_achievement("blood_moon_survivor")
		_expand_to_act2()
		return
	if day >= 7:
		_unlock_achievement("final_blood_moon")
		if house != null and house.is_fallen:
			_unlock_achievement("homeless_survivor")
		state = GameState.VICTORY
		var fallen := house != null and house.is_fallen
		var h_status := "Fallen (Homeless Victory!)" if fallen else "%d/%d HP" % [house.hp, house.max_hp]
		var ach_txt := "%d/%d" % [settings.get_unlocked_count(), SaveData.ACHIEVEMENT_DEFS.size()]
		var end_txt := "You outlasted the Final Blood Moon on Night 7!\n\n" + (
			"Enemies Defeated: %d\nHouse Status: %s\nAchievements Unlocked: %s"
			% [_kills_total, h_status, ach_txt]
		)
		_hud.show_end_screen(true, "DAWN BREAKS - YOU SURVIVED!", end_txt, false)
		return
	_start_day(day + 1)


func _expand_to_act2() -> void:
	act = 2
	_map.set_act1_fog_visible(false)
	_apply_camera_limits()
	stockpile.add("plank", Config.ACT2_START_STOCKPILE)
	_unlock_achievement("world_expanded")
	state = GameState.STORY
	_pending_story_cb = func() -> void: _start_day(day + 1)
	_intro.show_cards(IntroCards.get_world_expanded_cards(), true, false)


func _spawn_enemy(etype: String, pos: Vector2, is_wanderer: bool) -> Enemy:
	var e: Enemy = ENEMY_SCENE.instantiate() as Enemy
	e.setup(etype, pos, is_wanderer)
	e.structure_damaged.connect(_on_enemy_structure_damaged)
	e.player_damaged.connect(_on_enemy_player_damaged)
	e.entered_house.connect(_on_enemy_entered_house)
	e.killed.connect(func(_en: Enemy, was_bow: bool) -> void: _on_hostile_killed(was_bow))
	e.damaged_feedback.connect(_on_enemy_hit_feedback)
	_entities_layer.add_child(e)
	enemies.append(e)
	return e


func _trigger_melee_or_clear_intruders() -> void:
	if _player.inside_house:
		if _intruders_inside > 0:
			_intruders_inside -= 1
			_kills_total += 1
			_sfx.play("hit", -6.0)
			_fx.spawn_floating_text(
				Config.HOUSE_CENTER, "Intruder cleared!", Color(0.55, 0.96, 0.60)
			)
		return
	if _player.try_swing():
		_sfx.play("swing", -9.0)


func _try_bounce_back() -> void:
	if _player.dead:
		return
	if _bounce_cd > 0.0:
		_hud.show_message("Bounce Back in %.0fs" % ceilf(_bounce_cd), 1.4, Color(1.0, 0.72, 0.42))
		return
	var from_pos = _player.position
	var base_cd = Config.BOUNCE_CD_ACT1 if act == 1 else Config.BOUNCE_CD_ACT2
	_bounce_cd = base_cd * _player.bounce_cd_mult
	_set_trap_mode(false)
	if _player.inside_house:
		_player.set_inside_house(false, Config.HOUSE_DOOR)
	else:
		_player.position = Config.HOUSE_DOOR
		_player.velocity = Vector2.ZERO
	_player.start_recall_heal()
	_sfx.play("bounce", -6.0)
	_fx.spawn_ring(from_pos, 56.0, Color(0.52, 0.94, 1.0, 0.90))
	_fx.spawn_ring(Config.HOUSE_DOOR, 68.0, Color(0.48, 0.98, 0.68, 0.95))
	_fx.spawn_sparks(Config.HOUSE_DOOR, Color(0.48, 0.98, 0.68, 1.0), 10)
	_fx.spawn_floating_text(Config.HOUSE_DOOR, "Home! Healing...", Color(0.55, 0.98, 0.68))
	# briefly push/stun any hostile camping the doorstep so recalling is safe
	for e in _waves.get_all_hostiles(enemies, ghosts):
		if e.is_alive() and e.position.distance_to(Config.HOUSE_DOOR) <= 44.0:
			e.apply_stun(2.0)


func _try_shockwave() -> void:
	if _shockwave_cd > 0.0 or _player.dead or _player.inside_house:
		return
	var base_cd = Config.BOUNCE_CD_ACT1 if act == 1 else Config.BOUNCE_CD_ACT2
	_shockwave_cd = base_cd * _player.bounce_cd_mult
	_player.bounce_bonus_count = mini(Config.MAX_BOUNCE_BONUSES, _player.bounce_bonus_count + 1)
	_sfx.play("bounce", -6.0)
	_fx.spawn_ring(_player.position, 92.0, Color(0.55, 0.92, 1.0, 0.95))
	for e in _waves.get_all_hostiles(enemies, ghosts):
		if e.is_alive() and e.position.distance_to(_player.position) <= 92.0:
			e.apply_stun(Config.BOUNCE_STUN)
			e.take_hit(1, (e.position - _player.position).normalized(), false)


func _handle_interact_press() -> void:
	if _player.inside_house:
		_player.set_inside_house(false, Config.HOUSE_DOOR)
		_sfx.play("door_creak", -8.0)
		return

	# interact with whichever of fence gate or house door is closer so gates never get blocked
	var d_door = 9999.0
	if house != null and house.is_standing():
		d_door = minf(
			_player.position.distance_to(Config.HOUSE_DOOR_STEP),
			_player.position.distance_to(Config.HOUSE_DOOR)
		)
	var near_gate := _waves.find_nearest_gate(fences, _player.position, 34.0)
	var d_gate = near_gate.distance_from_point(_player.position) if near_gate != null else 9999.0
	if near_gate != null and d_gate <= 34.0 and d_gate <= d_door:
		near_gate.toggle_door(false)
		_sfx.play("door_creak", -8.0)
		var g_msg := (
			"Ring %d gate OPEN!" % near_gate.ring
			if near_gate.gate_open else "Ring %d gate shut." % near_gate.ring
		)
		var g_col := Color(1.0, 0.78, 0.40) if near_gate.gate_open else Color(0.60, 0.95, 0.65)
		_hud.show_message(g_msg, 2.0, g_col)
		return

	if house != null and house.is_standing() and d_door <= Config.DOOR_INTERACT_REACH:
		if house.is_door_open() and _player.position.distance_to(Config.HOUSE_DOOR_STEP) <= 18.0:
			_player.set_inside_house(true)
			house.toggle_door(true)
			_sfx.play("door_creak", -8.0)
			_hud.show_message("Safe inside. Door shut.", 1.8, Color(0.60, 0.95, 0.65))
		else:
			house.toggle_door(false)
			_sfx.play("door_creak", -8.0)
			if house.is_door_open():
				_hud.show_message("Door open! Press E at step to enter, or E to close.", 1.8)
		return
	if not _map.find_nearest_searchable(_player.position, 32.0).is_empty():
		return
	if not _map.find_nearest_tree(_player.position, 26.0).is_empty():
		return
	_try_open_nearby_structure_menu()


func _try_open_nearby_structure_menu() -> void:
	var best = _waves.find_nearest_structure(structures, _player.position, Config.STRUCTURE_MENU_REACH)
	if best != null:
		_open_structure_menu(best)


func _open_structure_menu(st: Structure) -> void:
	_enter_menu_pause()
	_menus.open_structure_menu(
		st, bag, stockpile, act, upgrades, _shop.compute_ring_stats(fences), watchtowers.size()
	)


func _toggle_dogs_mode() -> void:
	for d in dogs:
		if is_instance_valid(d) and d.mode != Dog.Mode.STRAY:
			var msg = d.toggle_guard_mode(_player.position)
			if not msg.is_empty():
				_hud.show_message(msg, 1.6, Color(0.82, 0.96, 0.72))
				_sfx.play("dog_bark", -10.0)


func _on_tame_dog_clicked() -> void:
	if _menus.is_open() or _player.inside_house or _player.dead:
		return
	if _waves.count_tamed_dogs(dogs) >= Config.DOG_MAX_TAMED:
		return
	var stray = _waves.find_nearest_stray_dog(dogs, _player.position, Config.DOG_TAME_RANGE)
	if stray != null and stray.tame_now():
		_fx.spawn_sparks(stray.position, Color(0.55, 0.96, 0.62, 1.0), 8)


func _step_hover_target() -> void:
	var mouse_world = get_global_mouse_position()
	var found = null
	for s in structures:
		if is_instance_valid(s) and s.is_built and s.visual_rect.has_point(mouse_world):
			found = s
			break
	if found != _hovered_struct:
		if is_instance_valid(_hovered_struct):
			_hovered_struct.set_hovered(false)
		_hovered_struct = found
		if is_instance_valid(_hovered_struct):
			_hovered_struct.set_hovered(true)


func _step_intruders(delta: float) -> void:
	if _intruders_inside <= 0 or house == null or house.is_fallen:
		return
	_intruder_dmg_accum += Config.INTRUDER_HOUSE_DPS * float(_intruders_inside) * delta
	if _intruder_dmg_accum >= 1.0:
		var whole = int(_intruder_dmg_accum)
		_intruder_dmg_accum -= float(whole)
		house.take_damage(whole)
		_night_damage_taken = true
	if _player.inside_house:
		_intruder_player_timer += delta
		if _intruder_player_timer >= Config.INTRUDER_PLAYER_INTERVAL:
			_intruder_player_timer = 0.0
			if _player.take_damage(Config.INTRUDER_PLAYER_DMG):
				_sfx.play("player_hit", -6.0)
				_add_shake(0.16, 2.5)


func _on_player_spear_swung(hitbox: Rect2, facing_dir: Vector2, damage: int) -> void:
	for e in _waves.get_all_hostiles(enemies, ghosts):
		if e.is_alive() and hitbox.intersects(e.get_hurtbox_rect()):
			e.take_hit(damage, facing_dir, false)


func _on_player_bow_fired(origin: Vector2, dir: Vector2, dmg: int, pierce: int) -> void:
	_sfx.play("bow_shoot", -8.0)
	_spawn_arrow(origin, dir, dmg, Config.BOW_RANGE, pierce, true)


func _on_player_boomerang_thrown(origin: Vector2, dir: Vector2, dmg: int) -> void:
	_waves.spawn_boomerang_for(self, origin, dir, dmg)


func _on_watchtower_fire(origin: Vector2, target: Node2D) -> void:
	if is_instance_valid(target):
		var dir = (target.position + Vector2(0.0, -8.0) - origin).normalized()
		_sfx.play("bow_shoot", -12.0)
		_spawn_arrow(origin, dir, 1, Config.WATCHTOWER_RANGE + 20.0, 0, false)


func _spawn_arrow(
	origin: Vector2, dir: Vector2, dmg: int, max_range: float, pierce: int, from_player: bool
) -> void:
	var arr = Arrow.new()
	arr.setup(origin, dir, Config.ARROW_SPEED, dmg, max_range, pierce, from_player)
	arr.hit_enemy.connect(func(e: Node2D, a: Arrow, fp: bool) -> void:
		if is_instance_valid(e) and e.has_method("take_hit"):
			e.call("take_hit", a.damage, a.velocity.normalized(), fp)
	)
	_entities_layer.add_child(arr)
	arrows.append(arr)


func _on_enemy_hit_feedback(pos: Vector2, is_kill: bool) -> void:
	_sfx.play("hit", -7.0 if is_kill else -9.0)
	_fx.spawn_sparks(pos, Color(0.95, 0.28, 0.24, 1.0), 8 if is_kill else 5)
	_hit_stop = 0.04
	if is_kill:
		_add_shake(0.10, 1.8)


func _on_enemy_structure_damaged(target: Node, damage: int, _enemy: Enemy) -> void:
	_night_damage_taken = true
	if target is Structure:
		var st: Structure = target as Structure
		st.take_damage(damage)
		_sfx.play("struct_hit", -9.0)
		_fx.spawn_sparks(st.target_center, Color(0.76, 0.56, 0.34, 1.0), 5)
	elif target is Watchtower:
		(target as Watchtower).take_damage(damage)
		_sfx.play("struct_hit", -9.0)


func _on_enemy_player_damaged(damage: int, _enemy: Enemy) -> void:
	if _player.take_damage(damage):
		_sfx.play("player_hit", -6.0)
		_add_shake(0.18, 2.8)


func _on_ghost_player_damaged(damage: int) -> void:
	_sfx.play("ghost_slash", -8.0)
	if _player.take_damage(damage):
		_sfx.play("player_hit", -8.0)
		_add_shake(0.14, 2.0)


func _on_hostile_killed(was_bow: bool) -> void:
	_kills_total += 1
	if was_bow:
		_unlock_achievement("first_bow_kill")


func _on_enemy_entered_house(_enemy: Enemy) -> void:
	_intruders_inside += 1
	_night_had_intruder = true
	_sfx.play("door_bump", -5.0)
	_hud.show_message("AN ENEMY ENTERED THE HOUSE! Close the door!", 2.8, Color(1.0, 0.30, 0.28))


func _on_house_crumbled(_st: Structure) -> void:
	_sfx.play("crumble", -4.0)
	_add_shake(0.65, 5.0)
	_intruders_inside = 0
	if _player.inside_house:
		_player.set_inside_house(false, Config.HOUSE_DOOR)
	_unlock_achievement("house_fell")
	var sub = "No shelter left! Rebuild from the rubble when you can."
	_hud.show_header_banner("THE HOUSE HAS FALLEN!", sub, Color(1.0, 0.34, 0.30), 3.4)


func _on_player_died() -> void:
	state = GameState.GAME_OVER
	var fallen = house != null and house.is_fallen
	var reason = "You fell in the ruins without shelter." if fallen else (
		"The horde overwhelmed you on Day %d." % day
	)
	var body = "%s\n\nEnemies Defeated: %d\nReached: Day %d" % [reason, _kills_total, day]
	_hud.show_end_screen(false, "YOU FELL", body, not _day_save.is_empty())


func _on_upgrade_action(action_id: String, data: Dictionary) -> void:
	if action_id == "show_tutorial":
		_open_tutorial_cards(false)
		return
	if _shop.handle_settings_action(action_id, settings, _menus):
		return
	if _shop.handle_inventory_action(action_id, data, self):
		return
	if action_id == "restart_day":
		_menus.close_all()
		_retry_day()
		return
	if action_id == "main_menu":
		_menus.close_all()
		_return_to_title()
		return

	var res = _shop.execute_action(
		action_id, data, bag, stockpile, house, fences, _player, upgrades, act, watchtowers.size()
	)
	if not String(res["sfx"]).is_empty():
		_sfx.play(String(res["sfx"]), -7.0)
	if not String(res["message"]).is_empty():
		_hud.show_message(String(res["message"]), 2.4, Color(0.62, 0.96, 0.68))
	if not String(res["achievement"]).is_empty():
		_unlock_achievement(String(res["achievement"]))
	if bool(res["spawn_watchtower"]):
		var off = Vector2(-88.0, -54.0) if watchtowers.is_empty() else Vector2(88.0, -54.0)
		_spawn_watchtower(Config.HOUSE_CENTER + off)
	var cur = _menus.current_structure
	if is_instance_valid(cur) and _menus.active_panel == "structure":
		var rs = _shop.compute_ring_stats(fences)
		_menus.open_structure_menu(cur, bag, stockpile, act, upgrades, rs, watchtowers.size())
	elif _menus.active_panel == "crafting":
		_menus.open_crafting_menu(bag, stockpile)


func _spawn_watchtower(world_pos: Vector2, start_hp: int = -1) -> Watchtower:
	var wt = Watchtower.new()
	wt.setup(world_pos)
	if start_hp > 0:
		wt.hp = mini(start_hp, wt.max_hp)
	wt.fire_requested.connect(_on_watchtower_fire)
	_entities_layer.add_child(wt)
	watchtowers.append(wt)
	return wt


func _update_lighting_and_tint() -> void:
	var target_tint = Config.TINT_DAY
	if state == GameState.NIGHT:
		target_tint = (
			Config.TINT_BLOOD if is_blood_moon
			else (Config.TINT_EVEN_MOON if is_even_moon else Config.TINT_NIGHT)
		)
	elif state == GameState.DAY and is_dusk_warned:
		target_tint = Config.TINT_DUSK
	elif house != null and house.is_fallen:
		target_tint = Config.TINT_HOPELESS
	_tint.color = _tint.color.lerp(target_tint, 0.08)
	if house != null:
		var dusk := state == GameState.DAY and is_dusk_warned
		house.update_lighting(state == GameState.NIGHT, dusk, is_blood_moon, _intruders_inside)


func _update_hud() -> void:
	var near_st = _waves.find_nearest_structure(structures, _player.position, 28.0)
	_hud.update_hud(_waves.make_hud_data(
		self, state == GameState.NIGHT, near_st, _hovered_struct,
		_intruders_inside, _bounce_cd, _selected_trap_idx, _sfx.muted, _search_progress
	))


func _unlock_achievement(ach_id: String) -> void:
	var u_def = settings.unlock(ach_id)
	if not u_def.is_empty():
		_sfx.play("toast", -8.0)
		var icon_name = String(u_def.get("icon", "trophy"))
		_popups.enqueue("Achievement: " + String(u_def["title"]), String(u_def["desc"]), icon_name)


func _toggle_fullscreen() -> void:
	settings.fullscreen = not settings.fullscreen
	settings.save_settings()
	settings.apply_display_and_audio()


func _return_to_title() -> void:
	state = GameState.TITLE
	_set_trap_mode(false)
	_shop.reset_hold_gather(self)
	_tint.color = Config.TINT_DAY
	_clear_dynamic_world()
	_hud.show_title_screen(not _day_save.is_empty())


func _retry_day() -> void:
	if _day_save.is_empty():
		_begin_new_run()
		return
	_set_trap_mode(false)
	for arr in [traps, watchtowers, dogs]:
		_waves.clear_group_or_list(arr)
	_fx.clear_all()
	act = int(_day_save["act"])
	day = int(_day_save["day"])
	upgrades = _shop.load_day(_day_save, self)
	_map.set_act1_fog_visible(act == 1)
	_apply_camera_limits()
	_hud.show_gameplay_hud()
	_start_day(day, true)


func _rebuild_world_and_structures(seed_val: int) -> void:
	for layer_node in [_ground_layer, _decals_layer, _entities_layer]:
		for child in layer_node.get_children():
			if child != _player:
				child.queue_free()
	for arr in [fences, structures, enemies, ghosts, arrows, boomerangs, traps, watchtowers, dogs]:
		arr.clear()
	_player.boomerang_in_flight = false
	_fx.clear_all()
	_map = MapGen.new()
	_map.build_world(_ground_layer, _decals_layer, _entities_layer, seed_val)
	var built = _map.spawn_base_buildings(_decals_layer, _entities_layer, _on_house_crumbled)
	house = built["house"]
	fences.assign(built["fences"])
	structures.assign(built["structures"])
	if _player.get_parent() != _entities_layer:
		_entities_layer.add_child(_player)
	_fx.set_debug_refs(structures, _player, enemies)


func _build_scene_tree() -> void:
	_ground_layer = get_node("World/GroundLayer") as Node2D
	_decals_layer = get_node("World/DecalsLayer") as Node2D
	_entities_layer = get_node("Entities") as Node2D
	_fx = get_node("Effects") as Fx
	_tint = get_node("DayNightTint") as CanvasModulate
	_tint.color = Config.TINT_DAY
	_camera = get_node("Camera2D") as Camera2D
	_camera.enabled = true
	_sfx = get_node("Audio") as Sfx
	_hud = get_node("UI") as Hud
	_menus = get_node("Menus") as Menus
	_night_intro = get_node("NightIntro") as NightIntro
	_intro = get_node("IntroCards") as IntroCards
	_popups = get_node("Popups") as Popups
	_player = get_node("Entities/Player") as Player
	_player.spear_swung.connect(_on_player_spear_swung)
	_player.bow_fired.connect(_on_player_bow_fired)
	_player.boomerang_thrown.connect(_on_player_boomerang_thrown)
	_player.bow_empty_clicked.connect(func() -> void: _sfx.play("bow_empty", -8.0))
	_player.bow_reloaded.connect(func() -> void: _sfx.play("bow_reload", -10.0))
	_player.died.connect(_on_player_died)


func _open_tutorial_cards(from_title: bool) -> void:
	if from_title:
		_hud.hide_all_screens()
		_pending_story_cb = func() -> void: _hud.show_title_screen(not _day_save.is_empty())
	else:
		_tutorial_overlay_open = true
		_menus.close_all()
		_pending_story_cb = func() -> void:
			_tutorial_overlay_open = false
			_menus.open_pause_menu()
	_intro.show_cards(IntroCards.get_tutorial_cards(), true, false)


func _connect_ui_signals() -> void:
	_hud.play_requested.connect(func(cont: bool) -> void:
		if cont and not _day_save.is_empty():
			_retry_day()
		else:
			_begin_new_run()
	)
	_hud.menu_panel_requested.connect(func(kind: String) -> void:
		if kind == "tutorial":
			_open_tutorial_cards(true)
			return
		_info_return_to_title = true
		_menus.open_info_panel(kind, settings)
	)
	_hud.trap_slot_clicked.connect(_toggle_trap_slot)
	_hud.tame_dog_requested.connect(_on_tame_dog_clicked)
	_hud.quit_requested.connect(func() -> void: get_tree().quit(0))
	_hud.retry_day_requested.connect(_retry_day)
	_hud.new_game_requested.connect(_begin_new_run)
	_hud.return_to_menu_requested.connect(_return_to_title)
	_intro.sequence_finished.connect(func(_s: bool) -> void:
		var cb: Callable = _pending_story_cb
		_pending_story_cb = Callable()
		if cb.is_valid():
			cb.call()
	)
	_night_intro.finished.connect(_start_night_combat)
	_menus.action_triggered.connect(_on_upgrade_action)
	_menus.menu_closed.connect(func() -> void:
		if _tutorial_overlay_open:
			return
		if _info_return_to_title:
			_info_return_to_title = false
		elif state == GameState.PAUSED:
			state = _pre_pause_state
	)


func _apply_camera_limits() -> void:
	var r = Config.ACT1_RECT if act == 1 else Config.WORLD_RECT
	_camera.limit_left = int(r.position.x)
	_camera.limit_top = int(r.position.y)
	_camera.limit_right = int(r.end.x)
	_camera.limit_bottom = int(r.end.y)


func _update_camera() -> void:
	var target = Config.HOUSE_CENTER if _player.inside_house else _player.position
	if _shake_timer > 0.0 and settings.screen_shake:
		target += Vector2(randf_range(-_shake_amp, _shake_amp), randf_range(-_shake_amp, _shake_amp))
	_camera.position = target.round()


func _add_shake(duration: float, amp: float) -> void:
	if settings.screen_shake:
		_shake_timer = maxf(_shake_timer, duration)
		_shake_amp = maxf(_shake_amp, amp)


func _clear_dynamic_world() -> void:
	_waves.clear_piles_in_tree(get_tree())
	for arr in [enemies, ghosts, arrows, boomerangs]:
		_waves.clear_group_or_list(arr)
	_player.boomerang_in_flight = false
