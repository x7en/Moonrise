extends Node2D
## Root controller for Red Moon (Godot 4.7). Wires T0-T3 cleanly across modular scripts.

enum GameState { TITLE, STORY, DAY, MOONRISE, NIGHT, PAUSED, GAME_OVER, VICTORY }

var state: GameState = GameState.TITLE
var act: int = 1
var day: int = 1
var phase_timer: float = 0.0
var is_blood_moon: bool = false
var is_dusk_warned: bool = false

var house: Structure = null
var fences: Array[Structure] = []
var structures: Array = []
var enemies: Array[Enemy] = []
var arrows: Array[Arrow] = []
var traps: Array[Trap] = []
var watchtowers: Array[Watchtower] = []
var dogs: Array[Dog] = []

var bag: Inventory = null
var stockpile: Inventory = null
var settings: SettingsStore = null
var upgrades: Dictionary = {}

var _ground_layer: Node2D = null
var _decals_layer: Node2D = null
var _entities_layer: Node2D = null
var _effects: WorldEffects = null
var _tint: CanvasModulate = null
var _camera: Camera2D = null
var _player: Player = null
var _world_builder: WorldBuilder = null
var _hud: Hud = null
var _story: StoryCard = null
var _moonrise: MoonriseCutscene = null
var _upgrade_ui: UpgradeUI = null
var _toasts: ToastLayer = null
var _sfx: Sfx = null
var _smoke: SmokeRunner = null
var _economy: EconomyController = EconomyController.new()
var _spawner: WaveSpawner = WaveSpawner.new()

var _wave_queue: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _bounce_cd: float = 0.0
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
var _hovered_struct: Structure = null
var _search_prop_id: int = -1
var _search_timer: float = 0.0
var _meteor_pending: int = 0
var _meteor_cd: float = 0.0
var _meteor_day_active: bool = false
var _meteor_hit_player: bool = false
var _pending_story_cb: Callable = Callable()
var _day_snapshot: Dictionary = {}
var _pre_pause_state: GameState = GameState.DAY
var _info_return_to_title: bool = false


func _ready() -> void:
	settings = SettingsStore.new()
	settings.load_all()
	settings.apply_display_and_audio()
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(
			SpriteFactory.get_icon_texture("cursor"), Input.CURSOR_ARROW, Vector2(1.0, 1.0)
		)
	bag = Inventory.new(Config.BAG_CAPACITY)
	stockpile = Inventory.new(-1)
	_build_scene_tree()
	_connect_ui_signals()
	_rebuild_world_and_structures(1337)
	_hud.show_title_screen(false)

	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	if "--smoke" in all_args:
		_smoke = SmokeRunner.new()
		_smoke.start(self)


func _process(delta: float) -> void:
	if _smoke != null and _smoke.active:
		_smoke.step(delta)
		if state != GameState.DAY and state != GameState.NIGHT:
			return
	if _hit_stop > 0.0:
		_hit_stop = maxf(0.0, _hit_stop - delta)
		return
	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - delta)
	_update_camera()
	if state == GameState.DAY or state == GameState.NIGHT:
		_step_gameplay(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _story.active or _moonrise.active:
		return
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if ke.pressed and not ke.echo:
			_handle_key_press(ke)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and _trap_mode_active:
			_trap_mode_active = false
			_effects.set_trap_preview(false)


func _handle_key_press(ke: InputEventKey) -> void:
	if ke.keycode == KEY_F11 or (ke.keycode == KEY_ENTER and ke.alt_pressed):
		_toggle_fullscreen()
		return
	if ke.keycode == KEY_M:
		_sfx.toggle_mute()
		return
	if ke.keycode == KEY_F8:
		_effects.show_debug_colliders = not _effects.show_debug_colliders
		_effects.queue_redraw()
		return
	if ke.keycode == KEY_F7 and (state == GameState.DAY or state == GameState.NIGHT):
		_trigger_meteor_shower(6)
		return
	if _upgrade_ui.is_open() or (state != GameState.DAY and state != GameState.NIGHT):
		return

	match ke.keycode:
		KEY_ESCAPE:
			if _trap_mode_active:
				_trap_mode_active = false
				_effects.set_trap_preview(false)
				return
			_pre_pause_state = state
			state = GameState.PAUSED
			_info_return_to_title = false
			_upgrade_ui.open_pause_menu()
		KEY_I:
			_trap_mode_active = false
			_effects.set_trap_preview(false)
			_pre_pause_state = state
			state = GameState.PAUSED
			_upgrade_ui.open_inventory(bag, stockpile, _player, upgrades)
		KEY_SPACE:
			_trigger_melee_or_clear_intruders()
		KEY_F:
			_player.try_fire_bow(enemies, bag)
		KEY_R:
			if _player.start_reload(bag):
				_sfx.play("bow_reload", -10.0)
		KEY_Q:
			_try_shockwave()
		KEY_E:
			_handle_interact_press()
		KEY_U:
			_trap_mode_active = false
			_effects.set_trap_preview(false)
			_try_open_nearby_structure_menu()
		KEY_1:
			_toggle_trap_slot(1)
		KEY_2:
			_toggle_trap_slot(2)
		KEY_3:
			_toggle_trap_slot(3)
		KEY_T:
			_place_selected_trap()
		KEY_G:
			_toggle_dogs_mode()


func _toggle_trap_slot(idx: int) -> void:
	if _trap_mode_active and _selected_trap_idx == idx:
		_trap_mode_active = false
		_effects.set_trap_preview(false)
	else:
		_selected_trap_idx = idx
		_trap_mode_active = true


func _place_selected_trap() -> void:
	var keys: Array[String] = ["trap_spike", "trap_snare", "trap_lure"]
	var t_key: String = keys[clampi(_selected_trap_idx - 1, 0, 2)]
	var pos: Vector2 = _economy.compute_trap_place_pos(_trap_mode_active, self)
	_economy.try_place_trap_at(t_key, pos, self)


func _handle_left_click() -> void:
	if _upgrade_ui.is_open() or (state != GameState.DAY and state != GameState.NIGHT):
		return
	if _trap_mode_active:
		_place_selected_trap()
		return
	var in_reach: bool = (
		_hovered_struct != null
		and _hovered_struct.is_built
		and _hovered_struct.distance_from_point(_player.position) <= Config.STRUCTURE_MENU_REACH
	)
	if in_reach:
		_open_structure_menu(_hovered_struct)
		return
	_player.try_fire_bow(enemies, bag)


func _step_gameplay(delta: float) -> void:
	var bounds: Rect2 = Config.ACT1_RECT if act == 1 else Config.WORLD_RECT
	_player.step_player(
		delta, _spawner.read_move_vector(), bounds, not _upgrade_ui.is_open(), bag
	)
	_player.set_night_lantern(state == GameState.NIGHT)
	if _bounce_cd > 0.0:
		_bounce_cd = maxf(0.0, _bounce_cd - delta)

	_spawner.prune_invalid_arrays([enemies, arrows, traps, watchtowers, dogs])
	_step_hover_target()
	_economy.update_trap_preview(_trap_mode_active, _selected_trap_idx, self)
	if _economy.step_piles_and_deposit(
		get_tree(), _player, house, bag, stockpile, _sfx, _effects
	):
		_unlock_achievement("first_plank")
	_step_hold_search_and_tame(delta)
	for a in arrows:
		if is_instance_valid(a):
			a.step_arrow(delta, enemies, bounds)
	for t in traps:
		if is_instance_valid(t):
			t.step_trap(delta, enemies)
	for wt in watchtowers:
		if is_instance_valid(wt):
			wt.step_tower(delta, enemies)
	for d in dogs:
		if is_instance_valid(d):
			d.step_dog(delta, _player.position, enemies, bounds)
	for e in enemies:
		if is_instance_valid(e):
			e.step_enemy(
				delta, structures, watchtowers, traps, _player.position,
				_player.inside_house, house, enemies, bounds
			)
	_step_intruders(delta)

	if state == GameState.DAY:
		_step_day_phase(delta)
	elif state == GameState.NIGHT:
		phase_timer -= delta
		if not _wave_queue.is_empty():
			_spawn_timer -= delta
			if _spawn_timer <= 0.0:
				var next_e: Dictionary = _wave_queue.pop_front() as Dictionary
				_spawn_enemy(String(next_e["type"]), next_e["pos"] as Vector2, false)
				_spawn_timer = float(next_e["delay"])
		if phase_timer <= 0.0 and _wave_queue.is_empty():
			_finish_night()

	_update_lighting_and_tint()
	_push_hud_snapshot()


func _step_day_phase(delta: float) -> void:
	phase_timer -= delta
	var dusk_thresh: float = Config.ACT1_DUSK_TIME if act == 1 else Config.ACT2_DUSK_TIME
	if not is_dusk_warned and phase_timer <= dusk_thresh:
		is_dusk_warned = true
		var msg: String = (
			"Dusk: close your fence gate [E] & get inside!"
			if _spawner.has_open_fence_gate(fences)
			else ("Dusk: get inside and close the door!" if act == 1 else "Dusk. Head home.")
		)
		_hud.show_message(msg, 3.0, Color(1.0, 0.72, 0.40))
	if _meteor_day_active and _meteor_pending > 0:
		_meteor_cd -= delta
		if _meteor_cd <= 0.0:
			_meteor_cd = randf_range(2.2, 4.2)
			_meteor_pending -= 1
			var mp: Vector2 = (_player.position + Vector2(
				randf_range(-190.0, 190.0), randf_range(-120.0, 120.0)
			)).clamp(Vector2(64.0, 64.0), Config.WORLD_SIZE - Vector2(64.0, 64.0))
			_effects.schedule_meteor(mp)
	if phase_timer <= 0.0:
		_begin_night_sequence()


func _begin_new_run(from_smoke: bool = false) -> void:
	act = 1
	day = 1
	is_blood_moon = false
	_kills_total = 0
	_intruders_inside = 0
	_trap_mode_active = false
	_day_snapshot.clear()
	upgrades = {"gear_tier": 1}
	bag.clear()
	stockpile.clear()
	stockpile.add("plank", Config.ACT1_START_STOCKPILE)
	bag.add("arrow", 18)
	bag.add("trap_spike", Config.START_SPIKE_TRAPS)

	_clear_dynamic_world()
	_rebuild_world_and_structures(1337 + randi() % 1000)
	_player.reset_for_new_game(Config.HOUSE_DOOR)
	_player.apply_upgrade_stats(upgrades)
	_world_builder.set_act1_fog_visible(true)
	_apply_camera_limits()
	_hud.show_gameplay_hud()

	var play_story: bool = (not from_smoke) and ((not settings.intro_seen) or settings.play_intro)
	if play_story:
		state = GameState.STORY
		_pending_story_cb = func() -> void:
			settings.mark_intro_completed()
			_start_day(1)
		_story.show_cards(StoryCard.get_opening_cards(), true, false)
	else:
		_start_day(1)


func _start_day(day_num: int) -> void:
	day = day_num
	state = GameState.DAY
	is_blood_moon = false
	is_dusk_warned = false
	_intruders_inside = 0
	_meteor_day_active = false
	_meteor_pending = 0
	_meteor_hit_player = false
	phase_timer = Config.day_length()

	if _player.inside_house:
		_player.set_inside_house(false, Config.HOUSE_DOOR)
	if house != null and house.is_standing():
		house.toggle_door(true)
	if day > 1:
		if house != null and house.is_standing():
			house.heal(Config.DAWN_FREE_REPAIR)
		for f in fences:
			if f.is_standing():
				f.heal(Config.DAWN_FREE_REPAIR)

	_clear_dynamic_world()
	_spawner.spawn_day_pickups(_world_builder, _entities_layer, act, day)
	if act == 2:
		for wp in _spawner.pick_wanderer_positions():
			_spawn_enemy("zombie", wp, true)
		if day in Config.METEOR_DAYS:
			_trigger_meteor_shower(Config.METEOR_COUNT_DAY4 if day == 4 else Config.METEOR_COUNT_DAY6)
		_maybe_spawn_stray_dogs()

	_day_snapshot = _economy.make_day_snapshot(
		act, day, _player, bag, stockpile, upgrades, house, fences
	)
	var sub: String = (
		"Gather planks, set traps [1-3], & close your fence gate [E] before dusk!"
		if act == 1 else "Explore the valley, scavenge scrap, and unlock outer fence layers!"
	)
	var col: Color = Color(1.0, 0.90, 0.56) if act == 1 else Color(0.62, 0.96, 0.68)
	_hud.show_header_banner("DAY %d - ACT %d" % [day, act], sub, col, 2.8)


func _begin_night_sequence() -> void:
	# T0.3: Destroy every surviving pickup pile cleanly before night starts.
	_spawner.clear_piles_in_tree(get_tree())
	if OS.is_debug_build():
		assert(get_tree().get_nodes_in_group("piles").is_empty(), "T0.3: piles leaked into night!")
	if act == 2 and Config.LOSE_BAG_AT_DUSK_ACT2 and not _player.inside_house:
		if bag.used_capacity() > 0:
			bag.remove("plank", bag.count("plank"))
			bag.remove("scrap", bag.count("scrap"))
			_hud.show_message(
				"Night fell outside! Unbanked bag resources lost.", 2.6, Color(1.0, 0.45, 0.40)
			)
	if _meteor_day_active and not _meteor_hit_player:
		_unlock_achievement("meteor_survivor")

	is_blood_moon = (day == Config.WORLD_EXPAND_NIGHT or day == 7)
	state = GameState.MOONRISE
	if is_blood_moon:
		_sfx.play("blood_moon", -6.0)
	_moonrise.start_moonrise(day, is_blood_moon, _smoke != null and _smoke.active)


func _start_night_combat() -> void:
	state = GameState.NIGHT
	phase_timer = Config.night_length(day)
	_night_damage_taken = false
	_night_had_intruder = false
	_spawner.clear_group_or_list(enemies)
	_wave_queue = _spawner.build_night_wave_queue(day, act)
	_spawn_timer = 0.8
	var title: String = "NIGHT %d - BLOOD MOON!" % day if is_blood_moon else "NIGHT %d" % day
	var sub: String = (
		"Hold every ring! They are swarming from all sides!"
		if is_blood_moon else "Defend the rings and house until dawn."
	)
	_hud.show_header_banner(
		title, sub, Color(1.0, 0.34, 0.30) if is_blood_moon else Color(0.84, 0.88, 1.0), 2.5
	)


func _finish_night() -> void:
	for e in enemies:
		if is_instance_valid(e) and e.is_alive():
			e.start_dissolve()
	_spawner.clear_group_or_list(arrows)
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
		var h_status: String = (
			"Fallen (Homeless Victory!)" if house.is_fallen else "%d/%d HP" % [house.hp, house.max_hp]
		)
		var end_txt: String = (
			"You outlasted the Final Blood Moon on Night 7!\n\n"
			+ "Enemies Defeated: %d\nHouse Status: %s\nAchievements Unlocked: %d/%d"
			% [_kills_total, h_status, settings.get_unlocked_count(), SettingsStore.ACHIEVEMENT_DEFS.size()]
		)
		_hud.show_end_screen(true, "DAWN BREAKS - YOU SURVIVED!", end_txt, false)
		return
	_start_day(day + 1)


func _expand_to_act2() -> void:
	act = 2
	_world_builder.set_act1_fog_visible(false)
	_apply_camera_limits()
	stockpile.add("plank", Config.ACT2_START_STOCKPILE)
	_unlock_achievement("world_expanded")
	state = GameState.STORY
	_pending_story_cb = func() -> void: _start_day(day + 1)
	_story.show_cards(StoryCard.get_world_expanded_cards(), true, _smoke != null and _smoke.active)


func _spawn_enemy(etype: String, pos: Vector2, is_wanderer: bool) -> Enemy:
	var e: Enemy = Enemy.new()
	e.setup(etype, pos, is_wanderer)
	e.structure_damaged.connect(_on_enemy_structure_damaged)
	e.player_damaged.connect(_on_enemy_player_damaged)
	e.entered_house.connect(_on_enemy_entered_house)
	e.killed.connect(func(_en: Enemy, was_bow: bool) -> void:
		_kills_total += 1
		if was_bow:
			_unlock_achievement("first_bow_kill")
	)
	e.damaged_feedback.connect(_on_enemy_hit_feedback)
	_entities_layer.add_child(e)
	enemies.append(e)
	return e


func _maybe_spawn_stray_dogs() -> void:
	if Dog.assets_available() and dogs.size() < Config.DOG_MAX:
		var d: Dog = Dog.new()
		if d.setup(Config.HOUSE_CENTER + Vector2(randf_range(-420.0, 420.0), 220.0)):
			d.tamed.connect(func(_dog: Dog) -> void:
				_sfx.play("dog_bark", -6.0)
				_unlock_achievement("tamed_dog")
				_hud.show_message(
					"Dog tamed! Press G to toggle Follow / Guard.", 2.6, Color(0.62, 0.96, 0.68)
				)
			)
			_entities_layer.add_child(d)
			dogs.append(d)


func _trigger_meteor_shower(count: int) -> void:
	_meteor_day_active = true
	_meteor_pending += count
	_meteor_cd = 0.8
	_hud.show_message("METEOR SHOWER! Watch the sky shadows!", 3.0, Color(1.0, 0.54, 0.28))


func _on_meteor_impacted(pos: Vector2) -> void:
	_sfx.play("meteor_impact", -7.0)
	_add_shake(0.24, 3.5)
	_world_builder.spawn_crater_decal(pos)
	_spawner.spawn_pile(
		_entities_layer, pos + Vector2(8.0, 4.0), randi_range(2, 3), "meteor", "scrap"
	)
	if not _player.inside_house and _player.position.distance_to(pos) <= Config.METEOR_RADIUS:
		_meteor_hit_player = true
		_player.take_damage(Config.METEOR_PLAYER_DMG)
		_sfx.play("player_hit", -6.0)
	for s in structures:
		if is_instance_valid(s) and (s as Structure).is_standing():
			if (s as Structure).distance_from_point(pos) <= Config.METEOR_RADIUS:
				(s as Structure).take_damage(Config.METEOR_STRUCT_DMG)


func _trigger_melee_or_clear_intruders() -> void:
	if _player.inside_house:
		if _intruders_inside > 0:
			_intruders_inside -= 1
			_kills_total += 1
			_sfx.play("hit", -6.0)
			_effects.spawn_floating_text(
				Config.HOUSE_CENTER, "Intruder cleared!", Color(0.55, 0.96, 0.60)
			)
		return
	if _player.try_swing():
		_sfx.play("swing", -9.0)


func _try_shockwave() -> void:
	if _bounce_cd > 0.0 or _player.dead or _player.inside_house:
		return
	var base_cd: float = Config.BOUNCE_CD_ACT1 if act == 1 else Config.BOUNCE_CD_ACT2
	_bounce_cd = base_cd * _player.bounce_cd_mult
	_player.bounce_bonus_count = mini(Config.MAX_BOUNCE_BONUSES, _player.bounce_bonus_count + 1)
	_sfx.play("bounce", -6.0)
	_effects.spawn_ring(_player.position, 92.0, Color(0.55, 0.92, 1.0, 0.95))
	for e in enemies:
		if is_instance_valid(e) and e.is_alive() and e.position.distance_to(_player.position) <= 92.0:
			e.apply_stun(Config.BOUNCE_STUN)
			e.take_hit(1, (e.position - _player.position).normalized(), false)


func _handle_interact_press() -> void:
	if _player.inside_house:
		_player.set_inside_house(false, Config.HOUSE_DOOR)
		_sfx.play("door_creak", -8.0)
		return
	if house != null and house.is_standing():
		var d_door: float = minf(
			_player.position.distance_to(Config.HOUSE_DOOR_STEP),
			_player.position.distance_to(Config.HOUSE_DOOR)
		)
		if d_door <= Config.DOOR_INTERACT_REACH:
			if house.is_door_open() and _player.position.distance_to(Config.HOUSE_DOOR_STEP) <= 18.0:
				_player.set_inside_house(true)
				house.toggle_door(true)
				_sfx.play("door_creak", -8.0)
				_hud.show_message("Sheltered indoors & door closed.", 1.8, Color(0.60, 0.95, 0.65))
			else:
				house.toggle_door(false)
				_sfx.play("door_creak", -8.0)
				if house.is_door_open():
					_hud.show_message("Door open! Press E at step to enter, or E to close.", 1.8)
			return
	var near_gate: Structure = _spawner.find_nearest_gate(fences, _player.position, 28.0)
	if near_gate != null and near_gate.is_standing():
		near_gate.toggle_door(false)
		_sfx.play("door_creak", -8.0)
		var g_msg: String = (
			"Layer %d Gate OPEN (close before night!)" % near_gate.ring
			if near_gate.gate_open else "Layer %d Gate CLOSED (blocks zombies!)" % near_gate.ring
		)
		_hud.show_message(
			g_msg, 2.0, Color(1.0, 0.78, 0.40) if near_gate.gate_open else Color(0.60, 0.95, 0.65)
		)
		return
	_try_open_nearby_structure_menu()


func _try_open_nearby_structure_menu() -> void:
	var best: Structure = _spawner.find_nearest_structure(
		structures, _player.position, Config.STRUCTURE_MENU_REACH
	)
	if best != null:
		_open_structure_menu(best)


func _open_structure_menu(st: Structure) -> void:
	_pre_pause_state = state
	state = GameState.PAUSED
	_upgrade_ui.open_structure_menu(
		st, bag, stockpile, act, upgrades, _economy.compute_ring_stats(fences), watchtowers.size()
	)


func _toggle_dogs_mode() -> void:
	for d in dogs:
		if is_instance_valid(d) and d.mode != Dog.Mode.STRAY:
			var msg: String = d.toggle_guard_mode(_player.position)
			if not msg.is_empty():
				_hud.show_message(msg, 1.6, Color(0.82, 0.96, 0.72))
				_sfx.play("dog_bark", -10.0)


func _step_hold_search_and_tame(delta: float) -> void:
	if _player.inside_house or not Input.is_key_pressed(KEY_E):
		_search_prop_id = -1
		_search_timer = 0.0
		return
	for d in dogs:
		if not is_instance_valid(d) or d.mode != Dog.Mode.STRAY:
			continue
		if d.position.distance_to(_player.position) <= 24.0:
			d.advance_tame(delta, true)
			return
	var prop: Dictionary = _world_builder.find_nearest_searchable(_player.position, 32.0)
	if prop.is_empty():
		_search_prop_id = -1
		_search_timer = 0.0
		return
	var pid: int = int(prop["id"])
	if _search_prop_id != pid:
		_search_prop_id = pid
		_search_timer = 0.0
	_search_timer += delta
	if _search_timer >= Config.SEARCH_HOLD_TIME:
		_search_prop_id = -1
		_search_timer = 0.0
		_economy.grant_prop_loot(prop, _world_builder, _player, bag, stockpile, _sfx, _effects)


func _step_hover_target() -> void:
	var mouse_world: Vector2 = get_global_mouse_position()
	var found: Structure = null
	for s in structures:
		if is_instance_valid(s) and (s as Structure).is_built:
			if (s as Structure).visual_rect.has_point(mouse_world):
				found = s as Structure
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
		var whole: int = int(_intruder_dmg_accum)
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
	for e in enemies:
		if is_instance_valid(e) and e.is_alive() and hitbox.intersects(e.get_hurtbox_rect()):
			e.take_hit(damage, facing_dir, false)


func _on_player_bow_fired(origin: Vector2, dir: Vector2, dmg: int, pierce: int) -> void:
	_sfx.play("bow_shoot", -8.0)
	_spawn_arrow(origin, dir, dmg, Config.BOW_RANGE, pierce, true)


func _on_watchtower_fire(origin: Vector2, target: Node) -> void:
	if is_instance_valid(target):
		var dir: Vector2 = ((target as Node2D).position + Vector2(0.0, -8.0) - origin).normalized()
		_sfx.play("bow_shoot", -12.0)
		_spawn_arrow(origin, dir, 1, Config.WATCHTOWER_RANGE + 20.0, 0, false)


func _spawn_arrow(
	origin: Vector2, dir: Vector2, dmg: int, max_range: float, pierce: int, from_player: bool
) -> void:
	var arr: Arrow = Arrow.new()
	arr.setup(origin, dir, Config.ARROW_SPEED, dmg, max_range, pierce, from_player)
	arr.hit_enemy.connect(func(e: Node, a: Arrow, fp: bool) -> void:
		if is_instance_valid(e) and e is Enemy:
			(e as Enemy).take_hit(a.damage, a.velocity.normalized(), fp)
	)
	_entities_layer.add_child(arr)
	arrows.append(arr)


func _on_enemy_hit_feedback(pos: Vector2, is_kill: bool) -> void:
	_sfx.play("hit", -7.0 if is_kill else -9.0)
	_effects.spawn_sparks(pos, Color(0.95, 0.28, 0.24, 1.0), 8 if is_kill else 5)
	if _smoke == null or not _smoke.active:
		_hit_stop = 0.04
	if is_kill:
		_add_shake(0.10, 1.8)


func _on_enemy_structure_damaged(target: Node, damage: int, _enemy: Enemy) -> void:
	_night_damage_taken = true
	if target is Structure:
		var st: Structure = target as Structure
		st.take_damage(damage)
		_sfx.play("struct_hit", -9.0)
		_effects.spawn_sparks(st.target_center, Color(0.76, 0.56, 0.34, 1.0), 5)
	elif target is Watchtower:
		(target as Watchtower).take_damage(damage)
		_sfx.play("struct_hit", -9.0)


func _on_enemy_player_damaged(damage: int, _enemy: Enemy) -> void:
	if _player.take_damage(damage):
		_sfx.play("player_hit", -6.0)
		_add_shake(0.18, 2.8)


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
	_hud.show_header_banner(
		"THE HOUSE HAS FALLEN!",
		"No shelter left! Rebuild from the rubble when you can.", Color(1.0, 0.34, 0.30), 3.4
	)


func _on_player_died() -> void:
	state = GameState.GAME_OVER
	var reason: String = (
		"You fell in the ruins without shelter."
		if (house != null and house.is_fallen) else "The horde overwhelmed you on Day %d." % day
	)
	var body: String = "%s\n\nEnemies Defeated: %d\nReached: Day %d (Act %d)" % [
		reason, _kills_total, day, act
	]
	_hud.show_end_screen(false, "YOU FELL", body, not _day_snapshot.is_empty())


func _on_upgrade_action(action_id: String, payload: Dictionary) -> void:
	if _economy.handle_settings_action(action_id, settings, _upgrade_ui):
		return
	if action_id == "restart_day":
		_upgrade_ui.close_all()
		_restore_day_snapshot()
		return
	if action_id == "main_menu":
		_upgrade_ui.close_all()
		_return_to_title()
		return

	var res: Dictionary = _economy.execute_action(
		action_id, payload, bag, stockpile, house, fences, _player, upgrades, act, watchtowers.size()
	)
	if not String(res["sfx"]).is_empty():
		_sfx.play(String(res["sfx"]), -7.0)
	if not String(res["message"]).is_empty():
		_hud.show_message(String(res["message"]), 2.4, Color(0.62, 0.96, 0.68))
	if not String(res["achievement"]).is_empty():
		_unlock_achievement(String(res["achievement"]))
	if bool(res["spawn_watchtower"]):
		var off: Vector2 = (
			Vector2(-64.0, -56.0) if watchtowers.is_empty() else Vector2(64.0, -56.0)
		)
		var wt: Watchtower = Watchtower.new()
		wt.setup(Config.HOUSE_CENTER + off)
		wt.fire_requested.connect(_on_watchtower_fire)
		_entities_layer.add_child(wt)
		watchtowers.append(wt)
	var cur: Structure = _upgrade_ui.current_structure
	if is_instance_valid(cur) and _upgrade_ui.active_panel == "structure":
		var rs: Dictionary = _economy.compute_ring_stats(fences)
		_upgrade_ui.open_structure_menu(cur, bag, stockpile, act, upgrades, rs, watchtowers.size())


func _update_lighting_and_tint() -> void:
	var target_tint: Color = Config.TINT_DAY
	if state == GameState.NIGHT:
		target_tint = Config.TINT_BLOOD if is_blood_moon else Config.TINT_NIGHT
	elif state == GameState.DAY and is_dusk_warned:
		target_tint = Config.TINT_DUSK
	elif house != null and house.is_fallen:
		target_tint = Config.TINT_HOPELESS
	_tint.color = _tint.color.lerp(target_tint, 0.08)
	if house != null:
		house.update_lighting(
			state == GameState.NIGHT,
			state == GameState.DAY and is_dusk_warned,
			is_blood_moon,
			_intruders_inside
		)


func _push_hud_snapshot() -> void:
	var s_prog: float = _search_timer / Config.SEARCH_HOLD_TIME if _search_prop_id >= 0 else 0.0
	var near_st: Structure = _spawner.find_nearest_structure(structures, _player.position, 28.0)
	_hud.update_hud(_spawner.build_hud_payload(
		self, state == GameState.NIGHT, near_st, _hovered_struct,
		_intruders_inside, _bounce_cd, _selected_trap_idx, _sfx.muted, s_prog
	))


func _unlock_achievement(ach_id: String) -> void:
	var u_def: Dictionary = settings.unlock(ach_id)
	if not u_def.is_empty():
		_sfx.play("toast", -8.0)
		_toasts.enqueue(
			"Achievement: " + String(u_def["title"]),
			String(u_def["desc"]),
			String(u_def.get("icon", "trophy"))
		)


func _toggle_fullscreen() -> void:
	settings.fullscreen = not settings.fullscreen
	settings.save_settings()
	settings.apply_display_and_audio()


func _return_to_title() -> void:
	state = GameState.TITLE
	_spawner.clear_group_or_list(enemies)
	_spawner.clear_group_or_list(arrows)
	_hud.show_title_screen(not _day_snapshot.is_empty())


func _restore_day_snapshot() -> void:
	if _day_snapshot.is_empty():
		_begin_new_run()
		return
	act = int(_day_snapshot["act"])
	day = int(_day_snapshot["day"])
	upgrades = _economy.apply_day_snapshot(
		_day_snapshot, bag, stockpile, _player, house, fences
	)
	_world_builder.set_act1_fog_visible(act == 1)
	_apply_camera_limits()
	_hud.show_gameplay_hud()
	_start_day(day)


func _rebuild_world_and_structures(seed_val: int) -> void:
	for layer_node in [_ground_layer, _decals_layer, _entities_layer]:
		for child in layer_node.get_children():
			if child != _player:
				child.queue_free()
	for arr in [fences, structures, enemies, arrows, traps, watchtowers, dogs]:
		(arr as Array).clear()
	_effects.clear_all()
	_world_builder = WorldBuilder.new()
	_world_builder.build_world(_ground_layer, _decals_layer, _entities_layer, seed_val)
	var built: Dictionary = _world_builder.spawn_homestead_structures(
		_decals_layer, _entities_layer, _on_house_crumbled
	)
	house = built["house"] as Structure
	for s in built["fences"] as Array:
		fences.append(s as Structure)
	for s in built["structures"] as Array:
		structures.append(s as Structure)
	if _player.get_parent() != _entities_layer:
		_entities_layer.add_child(_player)
	_effects.set_debug_refs(structures, _player, enemies)


func _build_scene_tree() -> void:
	_ground_layer = Node2D.new()
	_decals_layer = Node2D.new()
	_entities_layer = Node2D.new()
	_entities_layer.y_sort_enabled = true
	_effects = WorldEffects.new()
	_effects.z_index = 15
	_effects.meteor_impacted.connect(_on_meteor_impacted)
	_tint = CanvasModulate.new()
	_tint.color = Config.TINT_DAY
	_camera = Camera2D.new()
	_camera.enabled = true
	_sfx = Sfx.new()
	_hud = Hud.new()
	_story = StoryCard.new()
	_moonrise = MoonriseCutscene.new()
	_upgrade_ui = UpgradeUI.new()
	_toasts = ToastLayer.new()
	for child_n in [
		_ground_layer, _decals_layer, _entities_layer, _effects, _tint,
		_camera, _sfx, _hud, _story, _moonrise, _upgrade_ui, _toasts
	]:
		add_child(child_n)
	_player = Player.new()
	_player.spear_swung.connect(_on_player_spear_swung)
	_player.bow_fired.connect(_on_player_bow_fired)
	_player.bow_empty_clicked.connect(func() -> void: _sfx.play("bow_empty", -8.0))
	_player.bow_reloaded.connect(func() -> void: _sfx.play("pickup", -11.0))
	_player.died.connect(_on_player_died)
	_entities_layer.add_child(_player)


func _connect_ui_signals() -> void:
	_hud.play_requested.connect(func(cont: bool) -> void:
		if cont and not _day_snapshot.is_empty():
			_restore_day_snapshot()
		else:
			_begin_new_run(false)
	)
	_hud.menu_panel_requested.connect(func(kind: String) -> void:
		_info_return_to_title = true
		_upgrade_ui.open_info_panel(kind, settings)
	)
	_hud.quit_requested.connect(func() -> void: get_tree().quit(0))
	_hud.retry_day_requested.connect(_restore_day_snapshot)
	_hud.new_game_requested.connect(func() -> void: _begin_new_run(false))
	_hud.return_to_menu_requested.connect(_return_to_title)
	_story.sequence_finished.connect(func(_s: bool) -> void:
		if _pending_story_cb.is_valid():
			var cb: Callable = _pending_story_cb
			_pending_story_cb = Callable()
			cb.call()
	)
	_moonrise.finished.connect(_start_night_combat)
	_upgrade_ui.action_triggered.connect(_on_upgrade_action)
	_upgrade_ui.menu_closed.connect(func() -> void:
		if _info_return_to_title:
			_info_return_to_title = false
		elif state == GameState.PAUSED:
			state = _pre_pause_state
	)


func _apply_camera_limits() -> void:
	var r: Rect2 = Config.ACT1_RECT if act == 1 else Config.WORLD_RECT
	_camera.limit_left = int(r.position.x)
	_camera.limit_top = int(r.position.y)
	_camera.limit_right = int(r.end.x)
	_camera.limit_bottom = int(r.end.y)


func _update_camera() -> void:
	var target: Vector2 = Config.HOUSE_CENTER if _player.inside_house else _player.position
	if _shake_timer > 0.0 and settings.screen_shake:
		target += Vector2(randf_range(-_shake_amp, _shake_amp), randf_range(-_shake_amp, _shake_amp))
	_camera.position = target.round()


func _add_shake(duration: float, amp: float) -> void:
	if settings.screen_shake:
		_shake_timer = maxf(_shake_timer, duration)
		_shake_amp = maxf(_shake_amp, amp)


func _clear_dynamic_world() -> void:
	_spawner.clear_piles_in_tree(get_tree())
	_spawner.clear_group_or_list(enemies)
	_spawner.clear_group_or_list(arrows)


# --- Headless --smoke hooks (T0.0) ---
func smoke_start_run() -> void:
	_begin_new_run(true)


func smoke_get_state() -> String:
	return String(GameState.keys()[state])


func smoke_skip_overlay() -> void:
	if _story.active:
		_story.show_cards([], true, true)
	if _moonrise.active:
		_moonrise.skip_now()


func smoke_fast_forward_day() -> void:
	stockpile.add("plank", 10)
	phase_timer = 0.01


func smoke_defend_step(delta: float) -> void:
	_player.hp = _player.max_hp
	if house != null and house.hp < 50:
		house.set_hp(house.max_hp)
	_player.try_fire_bow(enemies, bag)
	phase_timer -= delta * 18.0
	if phase_timer <= 0.0:
		_wave_queue.clear()
		_finish_night()
