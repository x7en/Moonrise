extends Node2D
## RED MOON (Bounce Back) — Main Game Controller (Godot 4.7 / GDScript 2.0)
##
## DESIGN DECISIONS:
## 1. Solid House Fix (Part A): The house has a full 96x86 StaticBody2D for the player AND a
##    padded enemy blocker rect. Enemies attack at the house's outer edge using HOUSE_REACH and
##    are clamped outside the house on every walk and knockback tick, so they never overlap it.
## 2. Retry Night vs. Restart Entire Run (Part A):
##    - Lose Screen: R or Enter retries ONLY the failed night from its dusk snapshot; N restarts
##      the entire run from Act 1, Day 1 (both also have clickable buttons).
##    - Pause Menu (Esc during gameplay): pauses the scene tree and offers Resume (Esc), Retry
##      This Night (R during Night), Restart Entire Run (N), and Sound toggle (M).
## 3. Balance & Spear Upgrade (Part B): Raised PLAYER_SPEED to 85, raised ACT1_DAY_TIME to 60s
##    and ACT2_DAY_TIME to 100s, cut zombie counts ~30%, and spawn nights in small bursts of 2-3
##    enemies from one side at a time with breathing pauses. Space thrusts a longer, wider Spear.
## 4. Farmhouse Compound (Part C): Visible wooden yard fence around the house with a clear south
##    front DOOR gap centered on HOUSE_DOOR (720, 468). Act 2 swaps the 6 slot fills for Fences.
## 5. Richer 1440x810 World (Part D): More seeded trees, bushes, rocks, containers, cars, and 18
##    randomized daily plank piles across 3 rings (far piles 490-680 px away, ~6-10s at 85px/s).
## 6. Cosmetics (Part E): Shared pixel-font Theme in SpriteFactory loads res://assets/fonts/
##    pixel_font.ttf (or KiwiSoda.ttf / dogicapixel.ttf); HUD shows a sky moon turning red on
##    Blood Moon nights. All Image allocations use Image.create_empty for Godot 4.7 cleanliness.
##
## WHAT WAS CUT TO KEEP SCOPE SAFE:
## - Cut infinite/chunked terrain; enriched the existing 1440x810 map instead.
## - Cut guns, ammo, projectiles, weapon switching, and extra weapon sprite sheets; used one
##   crisp procedural pixel spear bound to Space with longer/wider melee reach.
## - Cut A* pathfinding around the house; used outer-edge clamping so enemies never clip walls.
## - Cut multi-tab settings menus and scrolling sky parallax; kept one lightweight Esc pause
##   menu and a clean top-center sky moon indicator.

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
var is_paused: bool = false
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
var _act1_yard_fills: Array[Node2D] = []
var _player: Player = null
var _solid_rects: Array[Rect2] = []

var _tint_tween: Tween = null
var _fences_standing_at_night_start: int = 0
var _raider_warned_this_dusk: bool = false

# Small-group wave scheduler: spawns 2-3 enemies from one side, then pauses for breathing room.
var _wave_groups: Array = []
var _active_group_types: Array[String] = []
var _active_group_side: int = 0
var _next_group_timer: float = 0.0
var _member_spawn_timer: float = 0.0
var _group_interval: float = 6.0


## Initializes random seeds, keyboard controls, and the full scene tree on game start.
func _ready() -> void:
	randomize()
	_setup_input_map()
	_build_scene_tree()
	_enter_title()


## Handles Pause (Esc), Mute (M), and editor-only Debug keys (F1-F4).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause", false):
		if _is_gameplay_phase() and not is_paused:
			get_viewport().set_input_as_handled()
			_open_pause_menu()
			return

	if event.is_action_pressed("mute", false):
		get_viewport().set_input_as_handled()
		_toggle_sound_mute()
		return

	if OS.is_debug_build() and event is InputEventKey:
		var key_ev: InputEventKey = event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			var code: Key = key_ev.physical_keycode
			if code == KEY_NONE:
				code = key_ev.keycode
			_handle_debug_key(code)


## Main gameplay loop: snaps camera, checks pickups/repairs, and advances the active phase.
func _process(delta: float) -> void:
	if _camera != null and _player != null:
		_camera.position = _player.position.round()

	if not _is_gameplay_phase() or is_paused:
		return

	_player.is_night_context = (phase == Phase.NIGHT)
	_check_pile_pickups()
	_check_house_dropoff()

	# Act 2 allows repairing or rebuilding damaged structures during Day and Dusk.
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


## Registers all keyboard actions in code so project.godot never needs manual edits.
func _setup_input_map() -> void:
	_bind_action(&"move_left", [KEY_LEFT, KEY_A])
	_bind_action(&"move_right", [KEY_RIGHT, KEY_D])
	_bind_action(&"move_up", [KEY_UP, KEY_W])
	_bind_action(&"move_down", [KEY_DOWN, KEY_S])
	_bind_action(&"swing", [KEY_SPACE])
	_bind_action(&"bounce", [KEY_B])
	_bind_action(&"repair", [KEY_E])
	_bind_action(&"confirm", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_R])
	_bind_action(&"pause", [KEY_ESCAPE])
	_bind_action(&"mute", [KEY_M])


func _bind_action(action: StringName, keys: Array[Key]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for key_code in keys:
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = key_code
		InputMap.action_add_event(action, ev)


## Builds the entire game world under Main (Ground, Decals, Entities, Camera, HUD, Cards, Sfx).
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
		Config.WORLD_SIZE, Config.HOUSE_CENTER, world_seed
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

	# Build the solid central farmhouse and the 6 perimeter defense fence slots.
	_house = Structure.new()
	_entities.add_child(_house)
	_house.setup_house()
	_house.destroyed.connect(_on_structure_destroyed)
	_structures.append(_house)

	_fences.clear()
	for i in range(Config.FENCE_SLOTS.size()):
		var fence: Structure = Structure.new()
		_entities.add_child(fence)
		fence.setup_fence(i, Config.FENCE_SLOTS[i] as Dictionary, _decals)
		fence.destroyed.connect(_on_structure_destroyed)
		_fences.append(fence)
		_structures.append(fence)

	# Build the visible farmhouse compound fence with the south front DOOR gap at HOUSE_DOOR.
	_act1_yard_fills = WorldBuilder.build_farmhouse_yard(
		_entities, Config.HOUSE_CENTER, Config.FENCE_SLOTS
	)

	# Scatter seeded trees, bushes, rocks, containers, cars, and wasteland props.
	_solid_rects = WorldBuilder.populate_scenery(
		_entities, _structures, Config.WORLD_SIZE,
		Config.HOUSE_CENTER, Config.ACT1_RECT, scenery_seed
	)

	# Create the player inside Entities so Y-sorting works naturally with the house and fences.
	_player = Player.new()
	_player.swung.connect(_on_player_swung)
	_player.bounced.connect(_on_player_bounced)
	_player.took_damage.connect(_on_player_took_damage)
	_entities.add_child(_player)

	# Create the pixel-snapped Camera2D (smoothing off so pixels stay crisp).
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.position_smoothing_enabled = false
	_camera.enabled = true
	add_child(_camera)
	_set_camera_limits(Config.ACT1_RECT)

	# Create HUD, StoryCard/Pause overlay, and procedural SFX pool.
	_hud = HUD.new()
	add_child(_hud)

	_story_card = StoryCard.new()
	_story_card.advance_requested.connect(_on_story_advance)
	_story_card.retry_requested.connect(_on_retry_requested)
	_story_card.restart_run_requested.connect(_on_restart_run_requested)
	_story_card.resume_requested.connect(_close_pause_menu)
	_story_card.mute_requested.connect(_toggle_sound_mute)
	add_child(_story_card)

	_sfx = Sfx.new()
	_sfx.name = "Sfx"
	_sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sfx)


func _is_gameplay_phase() -> bool:
	return phase in [Phase.DAY, Phase.DUSK, Phase.NIGHT, Phase.DAWN]


## Opens the Pause Menu and freezes gameplay movement, timers, and animations.
func _open_pause_menu() -> void:
	is_paused = true
	get_tree().paused = true
	_sfx.play("ui_blip")
	var can_retry_night: bool = (phase == Phase.NIGHT and not dusk_snapshot.is_empty())
	_story_card.show_pause(can_retry_night, _sfx.muted)


## Closes the Pause Menu and resumes gameplay cleanly.
func _close_pause_menu() -> void:
	if not is_paused:
		return
	is_paused = false
	get_tree().paused = false
	_story_card.hide_card()
	_sfx.play("ui_blip")


## Toggles sound mute from either gameplay or the Pause Menu.
func _toggle_sound_mute() -> void:
	if _sfx == null:
		return
	var is_muted: bool = _sfx.toggle_mute()
	if is_paused:
		_story_card.update_pause_mute_label(is_muted)
	elif _is_gameplay_phase():
		_hud.show_banner("Sound OFF" if is_muted else "Sound ON", Color(0.85, 0.9, 1.0), 1.5)


## Returns cleanly to the Title screen.
func _enter_title() -> void:
	_ensure_unpaused()
	phase = Phase.TITLE
	story_index = 0
	_clear_world_objects()
	_set_tint(Config.TINT_DAY, true)
	_set_camera_limits(Config.ACT1_RECT)
	_set_act1_yard_fills_visible(true)
	_player.controls_enabled = false
	_player.reset_state(Config.HOUSE_DOOR, Config.ACT1_RECT, Config.BOUNCE_CD_ACT1)
	_camera.position = _player.position.round()
	_hud.clear_banner()
	_hud.set_hud_visible(false)
	_story_card.show_title()


## Advances Title -> Story Cards 1, 2, 3 -> Act 1, Card 4 -> Act 2, and Card 5 -> Title.
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


## Restarts the ENTIRE run from Act 1, Day 1 (N key or button on Lose / Pause screens).
func _on_restart_run_requested() -> void:
	_ensure_unpaused()
	_sfx.play("bounce")
	dusk_snapshot.clear()
	_start_act1()


## Starts a fresh Act 1 run on Day 1 with the farmhouse yard intact and the house damaged.
func _start_act1() -> void:
	_ensure_unpaused()
	act = 1
	current_night = 1
	bag = 0
	stockpile = 0
	total_planks_dropped = 0
	_clear_world_objects()

	_house.set_active(true)
	_house.set_hp(act1_start_house_hp)

	# Act 1 shows decorative yard fence rails while destructible Act-2 slots stay off.
	_set_act1_yard_fills_visible(true)
	for fence in _fences:
		fence.set_active(false)
		fence.set_hp(0)

	_set_camera_limits(Config.ACT1_RECT)
	_player.reset_state(Config.HOUSE_DOOR, Config.ACT1_RECT, Config.BOUNCE_CD_ACT1)
	_player.controls_enabled = true
	_camera.position = _player.position.round()

	_story_card.hide_card()
	_hud.set_hud_visible(true)
	_set_tint(Config.TINT_DAY, true)
	_start_day(1)


## Opens the full 1440x810 Act 2 world and activates the 6 destructible farmhouse fence slots.
func _start_act2(from_debug: bool) -> void:
	_ensure_unpaused()
	act = 2
	current_night = 4
	bag = 0
	stockpile = Config.ACT2_START_STOCKPILE
	_clear_world_objects()

	_house.set_active(true)
	if from_debug:
		_house.set_hp(60)
	elif _house.hp <= 0:
		_house.set_hp(30)

	# Swap decorative yard fills out for the 6 destructible/repairable Fences.
	_set_act1_yard_fills_visible(false)
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


## Runs the 3-second Act 2 morning: free dawn repair, overnight damage report, and fresh loot.
func _start_dawn(day_num: int, is_act2_opening: bool = false) -> void:
	phase = Phase.DAWN
	current_night = day_num
	phase_timer = 3.0
	_set_tint(Config.TINT_DAY, is_act2_opening)

	if is_act2_opening:
		_house.heal(Config.DAWN_FREE_REPAIR)
		_hud.show_banner("The road is open! Gather planks and rebuild.", Color(0.88, 0.96, 1.0), 3.0)
	else:
		var fell: int = maxi(0, _fences_standing_at_night_start - _count_standing_fences())
		for struct_node in _structures:
			if struct_node.is_standing():
				struct_node.heal(Config.DAWN_FREE_REPAIR)

		var report: String = "Nothing fell."
		if fell == 1:
			report = "1 fence fell."
		elif fell > 1:
			report = "%d fences fell." % fell
		_hud.show_banner("Dawn. %s" % report, Color(1.0, 0.94, 0.72), 3.0)

	_scatter_act2_piles()
	_refresh_hud()


## Starts a daytime exploration and rebuilding phase.
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
		var msg: String = "Day %d. Blood Moon: night 7. This time it's true." % day_num
		_hud.show_banner(msg, Color(1.0, 0.95, 0.85), 3.0)

	_refresh_hud()


## Enters the final 15 seconds of an Act 2 day, warning the player to bring planks home.
func _enter_dusk() -> void:
	phase = Phase.DUSK
	_set_tint(Config.TINT_DUSK, false)
	_hud.show_banner("Dusk. Head home.", Color(1.0, 0.78, 0.52), 3.0)


## Starts a night wave: drops unbanked Act-2 planks, takes a dusk snapshot, and queues groups.
func _start_night(night_num: int, from_retry: bool) -> void:
	phase = Phase.NIGHT
	current_night = night_num
	_player.bounce_bonuses = 0

	if not from_retry:
		if act == 2 and Config.LOSE_BAG_AT_DUSK and bag > 0:
			_spawn_floating_text(
				_player.position + Vector2(0.0, -18.0), "Lost %d planks!" % bag, Color(1.0, 0.45, 0.35)
			)
			bag = 0
		_take_dusk_snapshot()
		_fences_standing_at_night_start = _count_standing_fences()

	var night_cfg: Dictionary = Config.NIGHTS.get(night_num, Config.NIGHTS[1]) as Dictionary
	phase_timer = float(night_cfg["len"])
	var zombies: int = int(night_cfg["zombies"])
	var raiders: int = int(night_cfg["raiders"])

	# Blood Moon hoarding penalties (gentler 1-per-3 ratio so nights 3 and 7 feel fair).
	if night_num == 3:
		zombies += floori(float(total_planks_dropped) / 3.0)
	elif night_num == 7:
		zombies += floori(float(stockpile) / 3.0)

	_build_wave_groups(zombies, raiders)

	var is_blood: bool = (night_num == 3 or night_num == 7)
	_set_tint(Config.TINT_BLOOD if is_blood else Config.TINT_NIGHT, from_retry)

	if is_blood:
		_sfx.play("blood_moon", -6.0)
		var blood_msg: String = "The Blood Moon rises early!"
		if night_num == 7:
			blood_msg = "Final Blood Moon! Raiders from the east!"
		_hud.show_banner(blood_msg, Color(1.0, 0.34, 0.34), 3.5)
	elif raiders > 0:
		_hud.show_banner("Raiders from the east!", Color(1.0, 0.65, 0.45), 3.0)
	else:
		_hud.show_banner("Night %d" % night_num, Color(0.76, 0.84, 1.0), 2.5)

	_refresh_hud()


## Runs the night timer, small-group spawner, enemy movement with house blocking, and spear hits.
func _step_night(delta: float) -> void:
	phase_timer -= delta
	_tick_wave_spawner(delta)

	var swing_active: bool = _player.is_swing_active()
	var swing_rect: Rect2 = _player.get_swing_rect() if swing_active else Rect2()
	var player_hurtbox: Rect2 = _player.get_hurtbox()
	var house_blocker: Rect2 = _house.get_enemy_blocker_rect()

	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy: Enemy = node as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue

		enemy.step(delta, _structures, house_blocker)
		if phase != Phase.NIGHT:
			return
		if not is_instance_valid(enemy) or not enemy.is_active_threat():
			continue

		var enemy_box: Rect2 = enemy.get_hurtbox()

		# Resolve spear thrust hits (each enemy can only be hit once per thrust).
		if swing_active and not _player.has_hit_enemy(enemy.get_instance_id()):
			if swing_rect.intersects(enemy_box):
				_player.mark_enemy_hit(enemy.get_instance_id())
				var was_killed: bool = enemy.apply_hit(_player.position)
				_sfx.play("hit", -7.0 if was_killed else -9.0)
				continue

		# Resolve enemy contact damage against the player.
		if not _player.is_dying and _player.invuln_timer <= 0.0:
			if player_hurtbox.intersects(enemy_box):
				_player.take_contact_damage(enemy.player_dmg)

	if phase == Phase.NIGHT and phase_timer <= 0.0 and _house.hp > 0:
		_complete_night()


## Spawns enemies in small clusters (2-3 from one direction) with calm pauses between clusters.
func _tick_wave_spawner(delta: float) -> void:
	if not _active_group_types.is_empty():
		_member_spawn_timer -= delta
		if _member_spawn_timer <= 0.0:
			_spawn_enemy_on_side(_active_group_types.pop_back(), _active_group_side)
			_member_spawn_timer = Config.WAVE_MEMBER_DELAY
		return

	if _wave_groups.is_empty():
		return

	_next_group_timer -= delta
	if _next_group_timer <= 0.0:
		var group_data: Dictionary = _wave_groups.pop_back() as Dictionary
		_active_group_types.clear()
		for item in group_data["members"] as Array:
			_active_group_types.append(String(item))
		_active_group_side = int(group_data["side"])
		_member_spawn_timer = 0.0
		_next_group_timer = _group_interval * randf_range(0.85, 1.15)


## Ends a survived night, dissolves remaining enemies, and moves to the next Day, Dawn, or Card.
func _complete_night() -> void:
	_dissolve_all_enemies()
	_player.is_night_context = false
	_player.recover_at_sunrise()

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


## Ends the night in defeat when the house hits 0 HP and opens the Lose screen.
func _trigger_game_over() -> void:
	if phase == Phase.LOST:
		return
	_ensure_unpaused()
	phase = Phase.LOST
	_clear_enemies()
	_player.controls_enabled = false
	_hud.clear_banner()
	_hud.set_hud_visible(false)
	_story_card.show_lost(current_night)


## Restores the dusk snapshot to retry ONLY the failed night (triggered by R or Enter).
func _on_retry_requested() -> void:
	_ensure_unpaused()
	_sfx.play("bounce")
	_clear_world_objects()

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
	_set_act1_yard_fills_visible(act == 1)

	var saved_fences: Array = dusk_snapshot["fence_hps"] as Array
	for i in range(_fences.size()):
		_fences[i].set_active(act == 2)
		_fences[i].set_hp(int(saved_fences[i]) if i < saved_fences.size() else 0)

	_fences_standing_at_night_start = _count_standing_fences()

	var active_rect: Rect2 = Config.ACT1_RECT if act == 1 else Config.WORLD_RECT
	var cd_max: float = Config.BOUNCE_CD_ACT1 if act == 1 else Config.BOUNCE_CD_ACT2
	_set_camera_limits(active_rect)
	_player.reset_state(Config.HOUSE_DOOR, active_rect, cd_max)
	_player.controls_enabled = true
	_camera.position = _player.position.round()

	_story_card.hide_card()
	_hud.set_hud_visible(true)
	_start_night(current_night, true)


## Saves a snapshot at nightfall so Retry Night restores the exact dusk state.
func _take_dusk_snapshot() -> void:
	var fence_hps: Array[int] = []
	for fence in _fences:
		fence_hps.append(fence.hp)

	dusk_snapshot = {
		"night": current_night,
		"act": act,
		"house_hp": _house.hp,
		"stockpile": stockpile,
		"fence_hps": fence_hps,
		"total_planks_dropped": total_planks_dropped,
	}


## Divides a night's enemies into small groups of 2-3 arriving from one side with pauses between.
func _build_wave_groups(zombies: int, raiders: int) -> void:
	_active_group_types.clear()
	var add_brute: bool = Config.BRUTE_ENABLED and current_night >= 6
	_wave_groups = WorldBuilder.build_wave_groups(
		zombies, raiders, Config.WAVE_GROUP_MIN, Config.WAVE_GROUP_MAX, add_brute
	)
	var group_count: int = maxi(1, _wave_groups.size())
	var total_enemies: int = zombies + raiders + (1 if add_brute else 0)
	var stagger_total: float = float(maxi(0, total_enemies - group_count)) * Config.WAVE_MEMBER_DELAY
	var spawn_end_target: float = maxf(phase_timer * 0.55, phase_timer - 9.0)
	var pause_budget: float = maxf(2.0, spawn_end_target - 1.0 - stagger_total)
	_group_interval = maxf(0.8, pause_budget / float(maxi(1, group_count - 1)))
	_next_group_timer = 1.0
	_member_spawn_timer = 0.0


## Spawns one enemy just outside the farmhouse view along the chosen edge (0=N, 1=S, 2=W, 3=E).
func _spawn_enemy_on_side(enemy_type: String, side: int) -> void:
	var spawn_ring: Rect2 = Config.ACT1_RECT
	if act == 2:
		spawn_ring = Rect2(Config.HOUSE_CENTER - Vector2(270.0, 175.0), Vector2(540.0, 350.0))
	var spawn_pos: Vector2 = WorldBuilder.pick_spawn_position(
		spawn_ring, enemy_type, side, Config.RAIDER_SIDE, _player.position, Config.WORLD_RECT
	)
	var enemy: Enemy = Enemy.new()
	_entities.add_child(enemy)
	enemy.setup(enemy_type, spawn_pos, _structures)
	enemy.struck_structure.connect(_on_enemy_struck_structure)


func _scatter_act1_planks() -> void:
	_clear_piles()
	WorldBuilder.scatter_act1_planks(
		_decals, Config.ACT1_RECT, Config.HOUSE_CENTER,
		Config.ACT1_PLANKS_PER_DAY, _structures, _solid_rects
	)


func _scatter_act2_piles() -> void:
	_clear_piles()
	WorldBuilder.scatter_act2_piles(
		_decals, Config.WORLD_RECT, Config.HOUSE_CENTER,
		Config.PILES, _structures, _solid_rects
	)


## Picks up any plank pile the player walks over and adds its planks to the bag.
func _check_pile_pickups() -> void:
	for node in get_tree().get_nodes_in_group("piles"):
		var pile: Pile = node as Pile
		if pile == null or not is_instance_valid(pile):
			continue
		var gained: int = pile.check_pickup(_player.position)
		if gained > 0:
			bag += gained
			_sfx.play("pickup")
			_spawn_floating_text(
				pile.position + Vector2(0.0, -10.0), "+%d" % gained, Color(1.0, 0.92, 0.55)
			)


## Drops off the player's bag when touching the house (heals house in Act 1, banks stock in Act 2).
func _check_house_dropoff() -> void:
	if bag <= 0 or not _house.footprint_rect.grow(10.0).has_point(_player.position):
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
			Config.HOUSE_DOOR + Vector2(0.0, -16.0), "+%d Stock" % dropped, Color(1.0, 0.9, 0.5)
		)


## Finds the nearest damaged House or Act-2 Fence within 40 px of the player.
func _find_nearest_repairable_structure() -> Structure:
	var best: Structure = null
	var best_dist: float = 40.0
	for struct_node in _structures:
		if not struct_node.active_in_game or struct_node.hp >= struct_node.max_hp:
			continue
		var dist: float = struct_node.distance_from_point(_player.position)
		if dist <= best_dist:
			best_dist = dist
			best = struct_node
	return best


## Spends stockpiled planks (1 plank = +8 HP) to repair or rebuild the closest structure.
func _try_repair_nearest() -> void:
	var target: Structure = _find_nearest_repairable_structure()
	if target == null:
		return
	if stockpile <= 0:
		_hud.show_banner("No planks", Color(1.0, 0.55, 0.45), 2.0)
		_sfx.play("ui_blip")
		return

	var missing_hp: int = target.max_hp - target.hp
	var planks_needed: int = int(ceili(float(missing_hp) / float(Config.PLANK_HEAL)))
	var planks_spent: int = mini(stockpile, planks_needed)
	if planks_spent <= 0:
		return

	var was_ruined: bool = (target.hp <= 0)
	stockpile -= planks_spent
	var healed: int = target.heal(planks_spent * Config.PLANK_HEAL)
	var popup_pos: Vector2 = target.get_target_point() + Vector2(0.0, -14.0)

	if was_ruined:
		_sfx.play("fence_rebuilt")
		_spawn_floating_text(popup_pos, "Rebuilt!", Color(0.55, 1.0, 0.65))
	else:
		_sfx.play("dropoff")
		_spawn_floating_text(popup_pos, "+%d HP" % healed, Color(0.55, 1.0, 0.65))


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
			Config.HOUSE_DOOR + Vector2(0.0, -24.0), "+%d Stock" % deposited, Color(1.0, 0.9, 0.5)
		)

	if phase == Phase.NIGHT and _player.bounce_bonuses > 0:
		var pct: int = int(
			round(float(_player.bounce_bonuses) * Config.SWING_GROWTH_PER_BOUNCE * 100.0)
		)
		_spawn_floating_text(
			Config.HOUSE_DOOR + Vector2(0.0, -14.0), "+%d%% Spear!" % pct, Color(0.45, 0.92, 1.0)
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


## Pushes the current game state into the HUD every frame.
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

	var repair_prompt: String = ""
	if act == 2 and (phase == Phase.DAY or phase == Phase.DUSK):
		var near_struct: Structure = _find_nearest_repairable_structure()
		if near_struct != null:
			var missing: int = near_struct.max_hp - near_struct.hp
			var needed: int = int(ceili(float(missing) / float(Config.PLANK_HEAL)))
			var verb: String = "Rebuild" if near_struct.hp <= 0 else "Repair"
			var struct_name: String = "House" if near_struct == _house else "Fence"
			repair_prompt = "[E] %s %s (%d)" % [verb, struct_name, needed]

	_hud.update_state({
		"player_hp": _player.hp,
		"house_hp": _house.hp,
		"house_max_hp": _house.max_hp,
		"phase_title": phase_title,
		"time_left": phase_timer,
		"is_night": phase == Phase.NIGHT,
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


func _set_act1_yard_fills_visible(show_fills: bool) -> void:
	for fill_node in _act1_yard_fills:
		if is_instance_valid(fill_node):
			fill_node.visible = show_fills


func _ensure_unpaused() -> void:
	is_paused = false
	if get_tree().paused:
		get_tree().paused = false


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
	for fence in _fences:
		if fence.is_standing():
			count += 1
	return count


func _get_pile_count() -> int:
	return get_tree().get_nodes_in_group("piles").size()


func _clear_world_objects() -> void:
	_clear_enemies()
	_clear_piles()
	if _effects != null:
		for child in _effects.get_children():
			child.queue_free()


func _clear_piles() -> void:
	for node in get_tree().get_nodes_in_group("piles"):
		node.queue_free()


func _clear_enemies() -> void:
	_wave_groups.clear()
	_active_group_types.clear()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()


func _dissolve_all_enemies() -> void:
	_wave_groups.clear()
	_active_group_types.clear()
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy: Enemy = node as Enemy
		if enemy != null:
			enemy.dissolve()


## Spawns a short rising text popup in world space using the shared retro pixel font Theme.
func _spawn_floating_text(world_pos: Vector2, text: String, color: Color) -> void:
	WorldBuilder.spawn_floating_text(
		_effects, world_pos, text, color, SpriteFactory.get_game_theme(Config.PIXEL_FONT_PATH)
	)


## Handles editor-only debug shortcuts (F1 skip phase, F2 god mode, F3 4x speed, F4 Act 2 jump).
func _handle_debug_key(code: Key) -> void:
	match code:
		KEY_F1:
			_debug_skip_phase()
		KEY_F2:
			god_mode = not god_mode
			var msg: String = "DEBUG: God Mode ON" if god_mode else "DEBUG: God Mode OFF"
			_hud.show_banner(msg, Color(1.0, 0.9, 0.4), 2.0)
		KEY_F3:
			Engine.time_scale = 4.0 if Engine.time_scale < 2.0 else 1.0
			_hud.show_banner("DEBUG: Speed %.0fx" % Engine.time_scale, Color(0.65, 0.95, 1.0), 2.0)
		KEY_F4:
			_start_act2(true)
			_start_day(4)
			_hud.show_banner("DEBUG: Jumped to Act 2 Day 4", Color(0.65, 0.95, 1.0), 2.5)


func _debug_skip_phase() -> void:
	_ensure_unpaused()
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
