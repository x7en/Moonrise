extends Node2D
## RED MOON (Bounce Back) — Main Game Controller
##
## Design decisions documented per specification:
## 1. House starts Day 1 at 36 HP (= HOUSE_HP - ACT1_PLANKS_PER_DAY * PLANK_HEAL), matching
##    the story ("the king's army destroyed your home") so all 8 Day-1 planks heal it to 100.
## 2. Fences are inactive in Act 1 so zombies walk directly to the house. On entering Act 2
##    (and F4 debug jump), all 6 fence slots activate with 4 worn wooden fences (16 HP) and
##    2 ruined slots (0 HP) so the player can immediately test both repairing and rebuilding.
## 3. Structure uses setup_house / setup_fence instance methods instead of inner subclasses
##    extending the outer class_name, avoiding Godot 4.3 cyclic inheritance restrictions.
## 4. Repair range (40 px) is measured to each structure's nearest footprint edge so the 96x90
##    House can be repaired comfortably from its front door and all four sides.
## 5. Enemy spawns use a jittered (+/-20%) timer accumulator scheduled across
##    (night_len - travel_lead) so perimeter enemies arrive in time to threaten the base.
## 6. Swing cooldown (0.4 s) starts on swing (0.3 s active hitbox + 0.1 s recovery), giving
##    responsive pacing during multi-directional Blood Moon waves.
## 7. House damage overlay uses a pre-baked silhouette ImageTexture matching house.png alpha
##    so there are no rectangular artifacts around the roof on GL Compatibility or WebGL.

enum Phase { TITLE, STORY, DAY, DUSK, NIGHT, DAWN, LOST, WON }

@export var world_seed: int = 1337
@export var scenery_seed: int = 4242
@export var act1_start_house_hp: int = 36

var phase: Phase = Phase.TITLE
var act: int = 1
var current_night: int = 1
var story_index: int = 0
var phase_timer: float = 0.0

var bag: int = 0
var stockpile: int = 0
var total_planks_dropped: int = 0
var god_mode: bool = false

var dusk_snapshot: Dictionary = {}

var _canvas_modulate: CanvasModulate = null
var _ground: Sprite2D = null
var _decals: Node2D = null
var _entities: Node2D = null
var _effects: Node2D = null
var _camera: Camera2D = null
var _hud: HUD = null
var _story_card: StoryCard = null
var _sfx: Sfx = null

var _house: Structure = null
var _fences: Array[Structure] = []
var _structures: Array[Structure] = []
var _player: Player = null
var _solid_rects: Array[Rect2] = []

var _tint_tween: Tween = null
var _spawn_queue: Array[String] = []
var _spawn_timer: float = 0.0
var _spawn_base_interval: float = 1.0
var _fences_standing_at_night_start: int = 0
var _raider_warned_this_dusk: bool = false


func _ready() -> void:
	randomize()
	_setup_input_map()
	_build_scene_tree()
	_enter_title()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute", false):
		get_viewport().set_input_as_handled()
		if _sfx != null:
			var is_muted: bool = _sfx.toggle_mute()
			if _is_gameplay_phase():
				_hud.show_banner("Sound OFF" if is_muted else "Sound ON", Color(0.85, 0.9, 1.0), 1.5)
		return

	if OS.is_debug_build() and event is InputEventKey:
		var key_ev: InputEventKey = event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			var code: Key = key_ev.physical_keycode
			if code == KEY_NONE:
				code = key_ev.keycode
			match code:
				KEY_F1:
					_debug_skip_phase()
				KEY_F2:
					god_mode = not god_mode
					_hud.show_banner(
						"DEBUG: God Mode ON" if god_mode else "DEBUG: God Mode OFF",
						Color(1.0, 0.9, 0.4),
						2.0
					)
				KEY_F3:
					Engine.time_scale = 4.0 if Engine.time_scale < 2.0 else 1.0
					_hud.show_banner(
						"DEBUG: Speed %.0fx" % Engine.time_scale,
						Color(0.65, 0.95, 1.0),
						2.0
					)
				KEY_F4:
					_debug_jump_act2()


func _process(delta: float) -> void:
	if _camera != null and _player != null:
		_camera.position = _player.position.round()

	if not _is_gameplay_phase():
		return

	_player.is_night_context = (phase == Phase.NIGHT)

	_check_pile_pickups()
	_check_house_dropoff()

	if act == 2 and (phase == Phase.DAY or phase == Phase.DUSK):
		if Input.is_action_just_pressed("repair"):
			_try_repair_nearest()

	match phase:
		Phase.DAWN:
			phase_timer -= delta
			if phase_timer <= 0.0:
				_start_day(current_night)
		Phase.DAY:
			phase_timer -= delta
			if act == 2 and phase_timer <= Config.ACT2_DUSK_TIME:
				_enter_dusk()
			elif act == 1 and phase_timer <= 0.0:
				_clear_piles()
				_start_night(current_night, false)
		Phase.DUSK:
			phase_timer -= delta
			if current_night >= 5 and not _raider_warned_this_dusk and phase_timer <= 5.0:
				_raider_warned_this_dusk = true
				_hud.show_banner("Raiders from the east!", Color(1.0, 0.62, 0.42), 3.0)
			if phase_timer <= 0.0:
				_clear_piles()
				_start_night(current_night, false)
		Phase.NIGHT:
			_step_night(delta)

	_refresh_hud()


func _setup_input_map() -> void:
	_bind_action(&"move_left", [KEY_LEFT, KEY_A])
	_bind_action(&"move_right", [KEY_RIGHT, KEY_D])
	_bind_action(&"move_up", [KEY_UP, KEY_W])
	_bind_action(&"move_down", [KEY_DOWN, KEY_S])
	_bind_action(&"swing", [KEY_SPACE])
	_bind_action(&"bounce", [KEY_B])
	_bind_action(&"repair", [KEY_E])
	_bind_action(&"confirm", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_R])
	_bind_action(&"mute", [KEY_M])


func _bind_action(action: StringName, keys: Array[Key]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for k in keys:
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _build_scene_tree() -> void:
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.name = "CanvasModulate"
	_canvas_modulate.color = Config.TINT_DAY
	add_child(_canvas_modulate)

	_ground = Sprite2D.new()
	_ground.name = "Ground"
	_ground.centered = false
	_ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ground.texture = WorldBuilder.build_ground_texture(
		Config.WORLD_SIZE,
		Config.HOUSE_CENTER,
		world_seed
	)
	add_child(_ground)

	_decals = Node2D.new()
	_decals.name = "Decals"
	add_child(_decals)

	_entities = Node2D.new()
	_entities.name = "Entities"
	_entities.y_sort_enabled = true
	add_child(_entities)

	_effects = Node2D.new()
	_effects.name = "Effects"
	_effects.z_index = 20
	add_child(_effects)

	# Create House and the 6 perimeter Fences.
	_house = Structure.new()
	_entities.add_child(_house)
	_house.setup_house()
	_house.destroyed.connect(_on_structure_destroyed)
	_structures.append(_house)

	_fences.clear()
	for i in range(Config.FENCE_SLOTS.size()):
		var slot: Dictionary = Config.FENCE_SLOTS[i] as Dictionary
		var fence: Structure = Structure.new()
		_entities.add_child(fence)
		fence.setup_fence(i, slot, _decals)
		fence.destroyed.connect(_on_structure_destroyed)
		_fences.append(fence)
		_structures.append(fence)

	# Seeded trees, containers, cars, and ground details.
	_solid_rects = WorldBuilder.populate_scenery(
		_entities,
		_structures,
		Config.WORLD_SIZE,
		Config.HOUSE_CENTER,
		Config.ACT1_RECT,
		scenery_seed
	)

	# Player
	_player = Player.new()
	_player.swung.connect(_on_player_swung)
	_player.bounced.connect(_on_player_bounced)
	_player.took_damage.connect(_on_player_took_damage)
	_entities.add_child(_player)

	# Camera (follows player with smoothing disabled)
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.position_smoothing_enabled = false
	_camera.enabled = true
	add_child(_camera)
	_set_camera_limits(Config.ACT1_RECT)

	# HUD and StoryCard CanvasLayers (unaffected by CanvasModulate)
	_hud = HUD.new()
	add_child(_hud)

	_story_card = StoryCard.new()
	_story_card.advance_requested.connect(_on_story_advance)
	_story_card.retry_requested.connect(_on_retry_requested)
	add_child(_story_card)

	# Procedural SFX
	_sfx = Sfx.new()
	_sfx.name = "Sfx"
	add_child(_sfx)


func _is_gameplay_phase() -> bool:
	return phase in [Phase.DAY, Phase.DUSK, Phase.NIGHT, Phase.DAWN]


func _enter_title() -> void:
	phase = Phase.TITLE
	story_index = 0
	_clear_enemies()
	_clear_piles()
	_set_tint(Config.TINT_DAY, true)
	_set_camera_limits(Config.ACT1_RECT)
	_player.controls_enabled = false
	_player.reset_state(Config.HOUSE_DOOR, Config.ACT1_RECT, Config.BOUNCE_CD_ACT1)
	_camera.position = _player.position.round()
	_hud.clear_banner()
	_hud.set_hud_visible(false)
	_story_card.show_title()


func _on_story_advance() -> void:
	_sfx.play("ui_blip")
	match phase:
		Phase.TITLE:
			phase = Phase.STORY
			story_index = 1
			_story_card.show_story(1)
		Phase.STORY:
			if story_index < 3:
				story_index += 1
				_story_card.show_story(story_index)
			elif story_index == 3:
				_start_act1()
			elif story_index == 4:
				_start_act2(false)
		Phase.WON:
			_enter_title()


func _start_act1() -> void:
	act = 1
	current_night = 1
	bag = 0
	stockpile = 0
	total_planks_dropped = 0
	_clear_enemies()
	_clear_piles()

	_house.set_active(true)
	_house.set_hp(act1_start_house_hp)
	for f in _fences:
		f.set_active(false)
		f.set_hp(0)

	_set_camera_limits(Config.ACT1_RECT)
	_player.reset_state(Config.HOUSE_DOOR, Config.ACT1_RECT, Config.BOUNCE_CD_ACT1)
	_player.controls_enabled = true
	_camera.position = _player.position.round()

	_story_card.hide_card()
	_hud.set_hud_visible(true)
	_set_tint(Config.TINT_DAY, true)
	_start_day(1)


func _start_act2(from_debug: bool) -> void:
	act = 2
	current_night = 4
	bag = 0
	stockpile = Config.ACT2_START_STOCKPILE
	_clear_enemies()
	_clear_piles()

	_house.set_active(true)
	if from_debug:
		_house.set_hp(60)
	elif _house.hp <= 0:
		_house.set_hp(30)

	# Activate all 6 fences: 4 worn wooden fences (16 HP) and 2 ruined slots (0 HP).
	var initial_fence_hps: Array[int] = [16, 16, 0, 16, 16, 0]
	for i in range(_fences.size()):
		_fences[i].set_active(true)
		_fences[i].set_hp(initial_fence_hps[i])

	_set_camera_limits(Config.WORLD_RECT)
	_player.reset_state(Config.HOUSE_DOOR, Config.WORLD_RECT, Config.BOUNCE_CD_ACT2)
	_player.controls_enabled = true
	_camera.position = _player.position.round()

	_story_card.hide_card()
	_hud.set_hud_visible(true)
	_start_dawn(4, true)


func _start_dawn(day_num: int, is_act2_opening: bool = false) -> void:
	phase = Phase.DAWN
	current_night = day_num
	phase_timer = 3.0
	_set_tint(Config.TINT_DAY, is_act2_opening)

	# Free dawn repair for standing structures.
	if is_act2_opening:
		_house.heal(Config.DAWN_FREE_REPAIR)
		_hud.show_banner("The road is open! Gather planks and rebuild.", Color(0.88, 0.96, 1.0), 3.0)
	else:
		var standing_now: int = _count_standing_fences()
		var fell: int = maxi(0, _fences_standing_at_night_start - standing_now)
		for s in _structures:
			if s.is_standing():
				s.heal(Config.DAWN_FREE_REPAIR)
		var report: String = "Nothing fell."
		if fell == 1:
			report = "1 fence fell."
		elif fell > 1:
			report = "%d fences fell." % fell
		_hud.show_banner("Dawn. %s" % report, Color(1.0, 0.94, 0.72), 3.0)

	_scatter_act2_piles()
	_refresh_hud()


func _start_day(day_num: int) -> void:
	phase = Phase.DAY
	current_night = day_num
	_raider_warned_this_dusk = false
	_set_tint(Config.TINT_DAY, day_num == 1)

	if act == 1:
		phase_timer = Config.ACT1_DAY_TIME
		_scatter_act1_planks()
		_hud.show_banner("Day %d. Blood Moon: night 5." % day_num, Color.WHITE, 3.0)
	else:
		phase_timer = Config.ACT2_DAY_TIME
		if _get_pile_count() == 0:
			_scatter_act2_piles()
		_hud.show_banner(
			"Day %d. Blood Moon: night 7. This time it's true." % day_num,
			Color(1.0, 0.95, 0.85),
			3.0
		)

	_refresh_hud()


func _enter_dusk() -> void:
	phase = Phase.DUSK
	_set_tint(Config.TINT_DUSK, false)
	_hud.show_banner("Dusk. Head home.", Color(1.0, 0.78, 0.52), 3.0)


func _start_night(night_num: int, from_retry: bool) -> void:
	phase = Phase.NIGHT
	current_night = night_num
	_player.bounce_bonuses = 0

	if not from_retry:
		if act == 2 and Config.LOSE_BAG_AT_DUSK and bag > 0:
			_spawn_floating_text(
				_player.position + Vector2(0.0, -18.0),
				"Lost %d planks!" % bag,
				Color(1.0, 0.45, 0.35)
			)
			bag = 0
		_take_dusk_snapshot()
		_fences_standing_at_night_start = _count_standing_fences()

	var cfg: Dictionary = Config.NIGHTS.get(night_num, Config.NIGHTS[1]) as Dictionary
	phase_timer = float(cfg["len"])
	var zombies: int = int(cfg["zombies"])
	var raiders: int = int(cfg["raiders"])

	if night_num == 3:
		zombies += int(floor(float(total_planks_dropped) / 2.0))
	elif night_num == 7:
		zombies += int(floor(float(stockpile) / 2.0))

	_build_spawn_queue(zombies, raiders)

	var is_blood: bool = (night_num == 3 or night_num == 7)
	_set_tint(Config.TINT_BLOOD if is_blood else Config.TINT_NIGHT, from_retry)

	if is_blood:
		_sfx.play("blood_moon", -6.0)
		if night_num == 3:
			_hud.show_banner("The Blood Moon rises early!", Color(1.0, 0.34, 0.34), 3.5)
		else:
			_hud.show_banner("The Final Blood Moon! Raiders from the east!", Color(1.0, 0.34, 0.34), 3.5)
	elif raiders > 0:
		_hud.show_banner("Raiders from the east!", Color(1.0, 0.65, 0.45), 3.0)
	else:
		_hud.show_banner("Night %d" % night_num, Color(0.76, 0.84, 1.0), 2.5)

	_refresh_hud()


func _step_night(delta: float) -> void:
	phase_timer -= delta

	# Spawn wave using jittered timer accumulator.
	if not _spawn_queue.is_empty():
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			var next_type: String = _spawn_queue.pop_back()
			_spawn_enemy(next_type)
			if not _spawn_queue.is_empty():
				_spawn_timer = _spawn_base_interval * randf_range(0.8, 1.2)

	# Step all enemies and resolve geometry combat.
	var swing_active: bool = _player.is_swing_active()
	var swing_rect: Rect2 = _player.get_swing_rect() if swing_active else Rect2()
	var player_hurtbox: Rect2 = _player.get_hurtbox()

	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	for node in enemies:
		var e: Enemy = node as Enemy
		if e == null or not is_instance_valid(e):
			continue
		e.step(delta, _structures)
		if phase != Phase.NIGHT:
			return
		if not is_instance_valid(e) or not e.is_active_threat():
			continue

		var e_box: Rect2 = e.get_hurtbox()
		if swing_active and not _player.has_hit_enemy(e.get_instance_id()):
			if swing_rect.intersects(e_box):
				_player.mark_enemy_hit(e.get_instance_id())
				var was_killed: bool = e.apply_hit(_player.position)
				_sfx.play("hit", -7.0 if was_killed else -9.0)
				continue

		if not _player.is_dying and _player.invuln_timer <= 0.0:
			if player_hurtbox.intersects(e_box):
				_player.take_contact_damage(e.player_dmg)

	if phase == Phase.NIGHT and phase_timer <= 0.0 and _house.hp > 0:
		_complete_night()


func _complete_night() -> void:
	_dissolve_all_enemies()
	_player.is_night_context = false

	if current_night == 3:
		phase = Phase.STORY
		story_index = 4
		_player.controls_enabled = false
		_hud.clear_banner()
		_hud.set_hud_visible(false)
		_story_card.show_story(4)
		return

	if current_night == 7:
		phase = Phase.WON
		_player.controls_enabled = false
		_hud.clear_banner()
		_hud.set_hud_visible(false)
		_story_card.show_story(5)
		return

	current_night += 1
	if act == 1:
		_start_day(current_night)
	else:
		_start_dawn(current_night, false)


func _trigger_game_over() -> void:
	if phase == Phase.LOST:
		return
	phase = Phase.LOST
	_spawn_queue.clear()
	_clear_enemies()
	_player.controls_enabled = false
	_hud.clear_banner()
	_hud.set_hud_visible(false)
	_story_card.show_lost(current_night)


func _on_retry_requested() -> void:
	_sfx.play("bounce")
	_clear_enemies()
	_clear_piles()

	if dusk_snapshot.is_empty():
		_start_act1()
		return

	act = int(dusk_snapshot["act"])
	current_night = int(dusk_snapshot["night"])
	stockpile = int(dusk_snapshot["stockpile"])
	total_planks_dropped = int(dusk_snapshot["total_planks_dropped"])
	bag = 0

	_house.set_active(true)
	_house.set_hp(int(dusk_snapshot["house_hp"]))

	var saved_fences: Array = dusk_snapshot["fence_hps"] as Array
	for i in range(_fences.size()):
		_fences[i].set_active(act == 2)
		var f_hp: int = int(saved_fences[i]) if i < saved_fences.size() else 0
		_fences[i].set_hp(f_hp)

	_fences_standing_at_night_start = _count_standing_fences()

	var rect: Rect2 = Config.ACT1_RECT if act == 1 else Config.WORLD_RECT
	var cd_max: float = Config.BOUNCE_CD_ACT1 if act == 1 else Config.BOUNCE_CD_ACT2
	_set_camera_limits(rect)
	_player.reset_state(Config.HOUSE_DOOR, rect, cd_max)
	_player.controls_enabled = true
	_camera.position = _player.position.round()

	_story_card.hide_card()
	_hud.set_hud_visible(true)
	_start_night(current_night, true)


func _take_dusk_snapshot() -> void:
	var fence_hps: Array[int] = []
	for f in _fences:
		fence_hps.append(f.hp)
	dusk_snapshot = {
		"night": current_night,
		"act": act,
		"house_hp": _house.hp,
		"stockpile": stockpile,
		"fence_hps": fence_hps,
		"total_planks_dropped": total_planks_dropped,
	}


func _build_spawn_queue(zombies: int, raiders: int) -> void:
	_spawn_queue.clear()
	for _i in range(zombies):
		_spawn_queue.append("zombie")
	for _i in range(raiders):
		_spawn_queue.append("raider")
	if Config.BRUTE_ENABLED and current_night >= 6:
		_spawn_queue.append("brute")
	_spawn_queue.shuffle()

	var total: int = maxi(1, _spawn_queue.size())
	# Lead time ensures enemies spawned on the world perimeter reach the base before sunrise.
	var travel_lead: float = 6.0 if act == 1 else 16.0
	var spawn_window: float = maxf(phase_timer * 0.6, phase_timer - travel_lead)
	_spawn_base_interval = spawn_window / float(total)
	_spawn_timer = minf(0.6, _spawn_base_interval * 0.5)


func _spawn_enemy(enemy_type: String) -> void:
	var spawn_pos: Vector2 = _pick_spawn_position(enemy_type)
	var enemy: Enemy = Enemy.new()
	_entities.add_child(enemy)
	enemy.setup(enemy_type, spawn_pos, _structures)
	enemy.struck_structure.connect(_on_enemy_struck_structure)


func _pick_spawn_position(enemy_type: String) -> Vector2:
	var area: Rect2 = Config.ACT1_RECT if act == 1 else Config.WORLD_RECT
	var margin: float = 14.0

	if enemy_type == "raider" and Config.RAIDER_SIDE == "east":
		return Vector2(
			area.end.x + margin,
			randf_range(area.position.y + 70.0, area.end.y - 70.0)
		)

	var side: int = randi() % 4
	match side:
		0:  # North
			return Vector2(randf_range(area.position.x + 24.0, area.end.x - 24.0), area.position.y - margin)
		1:  # South
			return Vector2(randf_range(area.position.x + 24.0, area.end.x - 24.0), area.end.y + margin)
		2:  # West
			return Vector2(area.position.x - margin, randf_range(area.position.y + 24.0, area.end.y - 24.0))
		_:  # East
			return Vector2(area.end.x + margin, randf_range(area.position.y + 24.0, area.end.y - 24.0))


func _scatter_act1_planks() -> void:
	_clear_piles()
	var placed: Array[Vector2] = []
	var area: Rect2 = Config.ACT1_RECT.grow(-24.0)
	for _i in range(Config.ACT1_PLANKS_PER_DAY):
		var pos: Vector2 = _find_valid_plank_pos(area, 80.0, 260.0, placed)
		placed.append(pos)
		var pile: Pile = Pile.new()
		_decals.add_child(pile)
		pile.setup(pos, 1, "single")


func _scatter_act2_piles() -> void:
	_clear_piles()
	var placed: Array[Vector2] = []
	var area: Rect2 = Config.WORLD_RECT.grow(-24.0)
	var tiers: Array[String] = ["near", "middle", "far"]

	for ring_idx in range(Config.PILES.size()):
		var ring: Dictionary = Config.PILES[ring_idx] as Dictionary
		var count: int = int(ring["count"])
		var planks_val: int = int(ring["planks"])
		var r_min: float = float(ring["r_min"])
		var r_max: float = float(ring["r_max"])
		var tier_name: String = tiers[mini(ring_idx, tiers.size() - 1)]

		for _j in range(count):
			var pos: Vector2 = _find_valid_ring_pos(area, r_min, r_max, placed)
			placed.append(pos)
			var pile: Pile = Pile.new()
			_decals.add_child(pile)
			pile.setup(pos, planks_val, tier_name)


func _find_valid_plank_pos(
	bounds: Rect2,
	min_dist_from_house: float,
	max_dist_from_house: float,
	existing: Array[Vector2]
) -> Vector2:
	for _attempt in range(50):
		var candidate: Vector2 = Vector2(
			randf_range(bounds.position.x, bounds.end.x),
			randf_range(bounds.position.y, bounds.end.y)
		).round()
		var d: float = candidate.distance_to(Config.HOUSE_CENTER)
		if d < min_dist_from_house or d > max_dist_from_house:
			continue
		if _is_pos_blocked_for_pile(candidate, existing):
			continue
		return candidate
	return (Config.HOUSE_CENTER + Vector2(110.0, 0.0)).round()


func _find_valid_ring_pos(
	bounds: Rect2,
	r_min: float,
	r_max: float,
	existing: Array[Vector2]
) -> Vector2:
	for _attempt in range(60):
		var angle: float = randf_range(0.0, TAU)
		var radius: float = randf_range(r_min, r_max)
		var candidate: Vector2 = Config.HOUSE_CENTER + Vector2(cos(angle), sin(angle)) * radius
		candidate.x = clampf(candidate.x, bounds.position.x, bounds.end.x)
		candidate.y = clampf(candidate.y, bounds.position.y, bounds.end.y)
		candidate = candidate.round()
		if _is_pos_blocked_for_pile(candidate, existing):
			continue
		return candidate
	return Vector2(
		clampf(Config.HOUSE_CENTER.x + r_min, bounds.position.x, bounds.end.x),
		Config.HOUSE_CENTER.y
	).round()


func _is_pos_blocked_for_pile(pos: Vector2, existing: Array[Vector2]) -> bool:
	for s in _structures:
		if s.footprint_rect.grow(14.0).has_point(pos):
			return true
	for col in _solid_rects:
		if col.grow(10.0).has_point(pos):
			return true
	for prev in existing:
		if prev.distance_squared_to(pos) < 576.0:  # 24 px spacing
			return true
	return false


func _check_pile_pickups() -> void:
	var piles: Array[Node] = get_tree().get_nodes_in_group("piles")
	for node in piles:
		var p: Pile = node as Pile
		if p == null or not is_instance_valid(p):
			continue
		var gained: int = p.check_pickup(_player.position)
		if gained > 0:
			bag += gained
			_sfx.play("pickup")
			_spawn_floating_text(p.position + Vector2(0.0, -10.0), "+%d" % gained, Color(1.0, 0.92, 0.55))


func _check_house_dropoff() -> void:
	if bag <= 0:
		return
	if not _house.footprint_rect.grow(6.0).has_point(_player.position):
		return

	var dropped: int = bag
	bag = 0
	_sfx.play("dropoff")

	if act == 1:
		total_planks_dropped += dropped
		var healed: int = _house.heal(dropped * Config.PLANK_HEAL)
		var msg: String = "+%d HP" % healed if healed > 0 else "House full"
		_spawn_floating_text(Config.HOUSE_DOOR + Vector2(0.0, -16.0), msg, Color(0.55, 1.0, 0.55))
	else:
		stockpile += dropped
		_spawn_floating_text(
			Config.HOUSE_DOOR + Vector2(0.0, -16.0),
			"+%d Stock" % dropped,
			Color(1.0, 0.9, 0.5)
		)


func _find_nearest_repairable_structure() -> Structure:
	var best: Structure = null
	var best_dist: float = 40.0
	for s in _structures:
		if not s.active_in_game or s.hp >= s.max_hp:
			continue
		var d: float = s.distance_from_point(_player.position)
		if d <= best_dist:
			best_dist = d
			best = s
	return best


func _try_repair_nearest() -> void:
	var target: Structure = _find_nearest_repairable_structure()
	if target == null:
		return
	if stockpile <= 0:
		_hud.show_banner("No planks", Color(1.0, 0.55, 0.45), 2.0)
		_sfx.play("ui_blip")
		return

	var missing: int = target.max_hp - target.hp
	var needed: int = int(ceili(float(missing) / float(Config.PLANK_HEAL)))
	var spend: int = mini(stockpile, needed)
	if spend <= 0:
		return

	var was_ruined: bool = (target.hp <= 0)
	stockpile -= spend
	var healed: int = target.heal(spend * Config.PLANK_HEAL)

	if was_ruined:
		_sfx.play("fence_rebuilt")
		_spawn_floating_text(
			target.get_target_point() + Vector2(0.0, -14.0),
			"Rebuilt!",
			Color(0.55, 1.0, 0.65)
		)
	else:
		_sfx.play("dropoff")
		_spawn_floating_text(
			target.get_target_point() + Vector2(0.0, -14.0),
			"+%d HP" % healed,
			Color(0.55, 1.0, 0.65)
		)


func _on_player_swung() -> void:
	_sfx.play("swing", -9.0)


func _on_player_took_damage(_amount: int) -> void:
	_sfx.play("player_hit", -7.0)


func _on_player_bounced(_was_death: bool) -> void:
	_sfx.play("bounce", -6.0)
	if act == 2 and bag > 0:
		var deposited: int = bag
		bag = 0
		stockpile += deposited
		_spawn_floating_text(
			Config.HOUSE_DOOR + Vector2(0.0, -24.0),
			"+%d Stock" % deposited,
			Color(1.0, 0.9, 0.5)
		)
	if phase == Phase.NIGHT and _player.bounce_bonuses > 0:
		var pct: int = int(round(float(_player.bounce_bonuses) * Config.SWING_GROWTH_PER_BOUNCE * 100.0))
		_spawn_floating_text(
			Config.HOUSE_DOOR + Vector2(0.0, -14.0),
			"+%d%% Swing!" % pct,
			Color(0.45, 0.92, 1.0)
		)


func _on_enemy_struck_structure(_enemy: Enemy, structure: Structure, damage: int) -> void:
	if structure == null or not is_instance_valid(structure):
		return
	if god_mode and structure == _house:
		return
	structure.take_damage(damage)
	_sfx.play("struct_hit", -7.0)


func _on_structure_destroyed(structure: Structure) -> void:
	if structure == _house:
		_trigger_game_over()


func _refresh_hud() -> void:
	var phase_title: String = ""
	match phase:
		Phase.DAWN:
			phase_title = "Dawn %d" % current_night
		Phase.DAY:
			phase_title = "Day %d" % current_night
		Phase.DUSK:
			phase_title = "Dusk %d" % current_night
		Phase.NIGHT:
			phase_title = "Night %d" % current_night
		_:
			phase_title = ""

	var repair_prompt: String = ""
	if act == 2 and (phase == Phase.DAY or phase == Phase.DUSK):
		var near_s: Structure = _find_nearest_repairable_structure()
		if near_s != null:
			var needed: int = int(ceili(float(near_s.max_hp - near_s.hp) / float(Config.PLANK_HEAL)))
			var verb: String = "Rebuild" if near_s.hp <= 0 else "Repair"
			var label_name: String = "House" if near_s == _house else "Fence"
			repair_prompt = "[E] %s %s (%d)" % [verb, label_name, needed]

	_hud.update_state({
		"player_hp": _player.hp,
		"house_hp": _house.hp,
		"house_max_hp": _house.max_hp,
		"phase_title": phase_title,
		"time_left": phase_timer,
		"is_blood_moon": phase == Phase.NIGHT and (current_night == 3 or current_night == 7),
		"is_dusk": phase == Phase.DUSK,
		"act": act,
		"bag": bag,
		"stockpile": stockpile,
		"bounce_cd": _player.bounce_cd_timer,
		"bounce_cd_max": _player.bounce_cd_max,
		"bounce_stun": _player.bounce_stun_timer,
		"bounce_bonuses": _player.bounce_bonuses,
		"muted": _sfx.muted,
		"god_mode": god_mode,
		"repair_prompt": repair_prompt,
	})


func _set_camera_limits(rect: Rect2) -> void:
	_camera.limit_left = int(rect.position.x)
	_camera.limit_right = int(rect.end.x)
	_camera.limit_top = int(rect.position.y)
	_camera.limit_bottom = int(rect.end.y)


func _set_tint(target_color: Color, instant: bool) -> void:
	if _tint_tween != null and _tint_tween.is_valid():
		_tint_tween.kill()
	if instant:
		_canvas_modulate.color = target_color
		return
	_tint_tween = create_tween()
	_tint_tween.tween_property(_canvas_modulate, "color", target_color, 2.0)


func _count_standing_fences() -> int:
	var count: int = 0
	for f in _fences:
		if f.is_standing():
			count += 1
	return count


func _get_pile_count() -> int:
	return get_tree().get_nodes_in_group("piles").size()


func _clear_piles() -> void:
	for node in get_tree().get_nodes_in_group("piles"):
		if is_instance_valid(node):
			node.queue_free()


func _clear_enemies() -> void:
	_spawn_queue.clear()
	for node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node):
			node.queue_free()


func _dissolve_all_enemies() -> void:
	_spawn_queue.clear()
	for node in get_tree().get_nodes_in_group("enemies"):
		var e: Enemy = node as Enemy
		if e != null and is_instance_valid(e):
			e.dissolve()


func _spawn_floating_text(world_pos: Vector2, text: String, color: Color) -> void:
	var holder: Node2D = Node2D.new()
	holder.position = world_pos.round()

	var lbl: Label = Label.new()
	lbl.text = text
	lbl.position = Vector2(-36.0, -8.0)
	lbl.size = Vector2(72.0, 12.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	holder.add_child(lbl)
	_effects.add_child(holder)

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(holder, "position:y", holder.position.y - 14.0, 0.85)
	tw.tween_property(holder, "modulate:a", 0.0, 0.85)
	tw.chain().tween_callback(holder.queue_free)


func _debug_skip_phase() -> void:
	match phase:
		Phase.TITLE, Phase.STORY, Phase.WON:
			_on_story_advance()
		Phase.DAWN:
			_start_day(current_night)
		Phase.DAY:
			if act == 2:
				phase_timer = Config.ACT2_DUSK_TIME
				_enter_dusk()
			else:
				_clear_piles()
				_start_night(current_night, false)
		Phase.DUSK:
			_clear_piles()
			_start_night(current_night, false)
		Phase.NIGHT:
			_complete_night()
		Phase.LOST:
			_on_retry_requested()


func _debug_jump_act2() -> void:
	_start_act2(true)
	_start_day(4)
	_hud.show_banner("DEBUG: Jumped to Act 2 Day 4", Color(0.65, 0.95, 1.0), 2.5)
