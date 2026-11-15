class_name Enemy
extends CharacterBody2D

# zombie / raider / brute ai - walks to house, chews fences, chases player if provoked

signal structure_damaged(structure: Node, damage: int, enemy: Enemy)
signal player_damaged(damage: int, enemy: Enemy)
signal entered_house(enemy: Enemy)
signal killed(enemy: Enemy, was_bow: bool)
signal damaged_feedback(pos: Vector2, is_kill: bool)

enum State {
	WALK_TO_TARGET,
	ATTACK_STRUCTURE,
	CHASE_PLAYER,
	ATTACK_PLAYER,
	WANDER,
	ROOTED,
	KNOCKBACK,
	DYING,
	DISSOLVING,
}

var enemy_type: String = "zombie"
var hp: int = 2
var max_hp: int = 2
var speed: float = 33.0
var struct_dmg: int = 4
var attack_interval: float = 1.2
var player_dmg: int = 10
var aggro_radius: float = 56.0
var is_day_wanderer: bool = false
var wander_home: Vector2 = Vector2.ZERO

var state: State = State.WALK_TO_TARGET
var facing: String = "down"

var _base_tint: Color = Color.WHITE
var _sprite: AnimatedSprite2D
var _shadow: Sprite2D
var _hp_holder: Node2D
var _hp_fill: ColorRect

var _target_struct: Node2D
var _target_lure: Trap
var _attack_timer: float = 0.0
var _player_windup: float = 0.0
var _player_cd: float = 0.0
var _dog_attack_cd: float = 0.0
var _leash_timer: float = 0.0
var _root_timer: float = 0.0
var _stun_timer: float = 0.0
var _flash_timer: float = 0.0
var _kb_timer: float = 0.0
var _kb_vel: Vector2 = Vector2.ZERO
var _death_timer: float = 0.0
var _stuck_timer: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _detour_sign: float = 1.0
var _wander_target: Vector2 = Vector2.ZERO
var _wander_wait: float = 0.0
var _was_bow_kill: bool = false


func setup(kind: String, spawn_pos: Vector2, day_wanderer: bool = false) -> void:
	enemy_type = kind
	position = spawn_pos.round()
	_last_pos = position
	is_day_wanderer = day_wanderer
	wander_home = position
	_wander_target = position
	_detour_sign = 1.0 if (randi() % 2 == 0) else -1.0

	var info = Config.ENEMY_TYPES.get(kind, Config.ENEMY_TYPES["zombie"])
	hp = int(info["hits"])
	max_hp = hp
	speed = float(info["speed"])
	struct_dmg = int(info["struct_dmg"])
	attack_interval = float(info["attack_interval"])
	player_dmg = int(info["player_dmg"])
	aggro_radius = (
		Config.DAY_WANDERER_AGGRO if day_wanderer else float(info["aggro_radius"])
	)
	_base_tint = info["tint"]
	state = State.WANDER if day_wanderer else State.WALK_TO_TARGET

	# layer 3 = enemies, collide with walls (1) and player (2)
	collision_layer = 4
	collision_mask = 1 | 2
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("enemies")
	add_to_group("hostiles")

	var col = CollisionShape2D.new()
	var sh = RectangleShape2D.new()
	sh.size = Vector2(10.0, 10.0)
	col.shape = sh
	col.position = Vector2(0.0, -5.0)
	add_child(col)

	_shadow = Sprite2D.new()
	_shadow.texture = Art.get_blob_shadow(12, 5)
	_shadow.position = Vector2(0.0, 1.0)
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_shadow)

	_sprite = AnimatedSprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.sprite_frames = Art.get_enemy_frames(enemy_type)
	_sprite.offset = Art.feet_offset_for_animated("enemies/%s/walk_down" % enemy_type)
	_sprite.modulate = _base_tint
	_sprite.play(&"walk_down")
	add_child(_sprite)

	_hp_holder = Node2D.new()
	_hp_holder.position = Vector2(0.0, -21.0)
	_hp_holder.visible = false
	var bg = ColorRect.new()
	bg.position = Vector2(-7.0, 0.0)
	bg.size = Vector2(14.0, 3.0)
	bg.color = Color(0.08, 0.06, 0.10, 0.88)
	_hp_holder.add_child(bg)
	_hp_fill = ColorRect.new()
	_hp_fill.position = Vector2(-6.0, 1.0)
	_hp_fill.size = Vector2(12.0, 1.0)
	_hp_fill.color = Color(0.95, 0.30, 0.28, 1.0)
	_hp_holder.add_child(_hp_fill)
	add_child(_hp_holder)


func is_alive() -> bool:
	return state != State.DYING and state != State.DISSOLVING


func get_hurtbox_rect() -> Rect2:
	return Rect2(position + Vector2(-7.0, -18.0), Vector2(14.0, 18.0))


func apply_stun(duration: float) -> void:
	if not is_alive():
		return
	_stun_timer = maxf(_stun_timer, duration)
	if _sprite != null:
		_sprite.modulate = Color(0.70, 0.90, 1.0, 1.0)


func apply_root(duration: float) -> void:
	if not is_alive():
		return
	_root_timer = maxf(_root_timer, duration)
	state = State.ROOTED


func start_dissolve() -> void:
	if not is_alive():
		return
	state = State.DISSOLVING
	_death_timer = 0.45
	collision_layer = 0
	collision_mask = 0


func take_hit(dmg: int, push_dir: Vector2, from_bow: bool = false) -> bool:
	if not is_alive():
		return false
	hp -= maxi(1, dmg)
	_flash_timer = 0.14
	_was_bow_kill = from_bow
	if _sprite != null:
		_sprite.modulate = Color(2.2, 2.2, 2.2, 1.0)
	if _hp_holder != null and _hp_fill != null:
		_hp_holder.visible = hp > 0 and hp < max_hp
		_hp_fill.size.x = maxf(1.0, 12.0 * (float(hp) / float(maxi(1, max_hp))))

	if hp <= 0:
		_enter_dying()
		damaged_feedback.emit(position + Vector2(0.0, -10.0), true)
		return true

	if push_dir.length_squared() > 0.001:
		var kb_dist = Config.KNOCKBACK * (0.45 if from_bow else 1.0)
		_kb_vel = push_dir.normalized() * (kb_dist / 0.16)
		_kb_timer = 0.16
		state = State.KNOCKBACK
	elif state != State.ROOTED:
		state = State.CHASE_PLAYER
		_leash_timer = 0.0

	damaged_feedback.emit(position + Vector2(0.0, -10.0), false)
	return false


func step_enemy(
	delta: float,
	structures: Array,
	watchtowers: Array,
	traps: Array,
	player_pos: Vector2,
	player_inside: bool,
	house: Structure,
	all_enemies: Array,
	world_bounds: Rect2,
	dogs: Array = []
) -> void:
	_tick_timers(delta)
	if state == State.DYING or state == State.DISSOLVING:
		_step_death_or_dissolve(delta)
		return

	if _stun_timer > 0.0:
		velocity = Vector2.ZERO
		if _sprite != null and _sprite.is_playing():
			_sprite.pause()
		return

	if state == State.KNOCKBACK:
		_kb_timer -= delta
		velocity = _kb_vel
		move_and_slide()
		_clamp_to_bounds(world_bounds)
		_kb_vel = _kb_vel.lerp(Vector2.ZERO, minf(1.0, delta * 12.0))
		if _kb_timer <= 0.0:
			state = State.CHASE_PLAYER if not player_inside else State.WALK_TO_TARGET
			_leash_timer = 0.0
		return

	if state == State.ROOTED:
		_root_timer -= delta
		velocity = Vector2.ZERO
		if _sprite != null:
			_sprite.modulate = Color(0.85, 0.72, 0.50, 1.0)
		if _root_timer <= 0.0:
			if _sprite != null:
				_sprite.modulate = _base_tint
			state = State.WANDER if is_day_wanderer else State.WALK_TO_TARGET
		return

	# enemies fight back against nearby tamed dogs (untamed strays are ignored)
	if not dogs.is_empty() and _dog_attack_cd <= 0.0:
		if _try_bite_tamed_dog(dogs):
			return

	# aggro on player if they wander too close while outside
	var dist_player = position.distance_to(player_pos)
	if not player_inside:
		var trigger_aggro = (
			state != State.CHASE_PLAYER
			and state != State.ATTACK_PLAYER
			and dist_player <= aggro_radius
		)
		if trigger_aggro:
			state = State.CHASE_PLAYER
			_leash_timer = 0.0
	elif state == State.CHASE_PLAYER or state == State.ATTACK_PLAYER:
		state = State.WANDER if is_day_wanderer else State.WALK_TO_TARGET

	match state:
		State.WANDER:
			_step_wander(delta, world_bounds)
		State.CHASE_PLAYER:
			_step_chase_player(delta, player_pos, player_inside, all_enemies, world_bounds)
		State.ATTACK_PLAYER:
			_step_attack_player(delta, player_pos, player_inside)
		State.ATTACK_STRUCTURE:
			_step_attack_structure(delta)
		_:
			_step_walk_to_target(
				delta,
				structures,
				watchtowers,
				traps,
				player_pos,
				player_inside,
				house,
				all_enemies,
				world_bounds
			)


func _tick_timers(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		if _flash_timer <= 0.0 and _sprite != null:
			_sprite.modulate = Color(0.70, 0.90, 1.0, 1.0) if _stun_timer > 0.0 else _base_tint
	if _stun_timer > 0.0:
		_stun_timer = maxf(0.0, _stun_timer - delta)
		if _stun_timer <= 0.0 and _sprite != null:
			_sprite.modulate = _base_tint
	if _player_cd > 0.0:
		_player_cd = maxf(0.0, _player_cd - delta)
	if _dog_attack_cd > 0.0:
		_dog_attack_cd = maxf(0.0, _dog_attack_cd - delta)


func _try_bite_tamed_dog(dogs: Array) -> bool:
	var best_dog = null
	var best_d = 20.0
	for d in dogs:
		if not is_instance_valid(d) or not d.is_tamed() or not d.is_alive():
			continue
		var dist = position.distance_to(d.position)
		if dist <= best_d:
			best_d = dist
			best_dog = d
	if best_dog == null:
		return false
	_dog_attack_cd = attack_interval
	velocity = Vector2.ZERO
	facing = _vec_to_dir(best_dog.position - position)
	_play_attack(facing)
	best_dog.take_damage(Config.DOG_ENEMY_DMG)
	return true


func _step_wander(delta: float, world_bounds: Rect2) -> void:
	if _wander_wait > 0.0:
		_wander_wait -= delta
		velocity = Vector2.ZERO
		return
	var to_t = _wander_target - position
	if to_t.length() <= 6.0:
		_wander_wait = randf_range(0.9, 2.2)
		var ang = randf_range(0.0, TAU)
		_wander_target = wander_home + Vector2(cos(ang), sin(ang)) * randf_range(18.0, 56.0)
		return
	var dir = to_t.normalized()
	_move_solid(dir * (speed * 0.55), [], world_bounds)
	_play_walk(dir)


func _step_chase_player(
	delta: float,
	player_pos: Vector2,
	player_inside: bool,
	all_enemies: Array,
	world_bounds: Rect2
) -> void:
	if player_inside:
		state = State.WANDER if is_day_wanderer else State.WALK_TO_TARGET
		return
	var to_p = player_pos - position
	var dist = to_p.length()
	if dist > Config.ENEMY_LEASH_RADIUS:
		_leash_timer += delta
		if _leash_timer >= Config.ENEMY_LEASH_TIME:
			state = State.WANDER if is_day_wanderer else State.WALK_TO_TARGET
			_leash_timer = 0.0
			return
	else:
		_leash_timer = 0.0

	if dist <= 14.0 and _player_cd <= 0.0:
		state = State.ATTACK_PLAYER
		_player_windup = Config.ENEMY_PLAYER_WINDUP
		facing = _vec_to_dir(to_p)
		_play_attack(facing)
		return

	var dir = to_p.normalized() if dist > 0.1 else Vector2.DOWN
	_move_solid(dir * speed, all_enemies, world_bounds)
	_play_walk(dir)


func _step_attack_player(delta: float, player_pos: Vector2, player_inside: bool) -> void:
	velocity = Vector2.ZERO
	if player_inside:
		state = State.WANDER if is_day_wanderer else State.WALK_TO_TARGET
		return
	_player_windup -= delta
	if _player_windup <= 0.0:
		if position.distance_to(player_pos) <= 18.0:
			player_damaged.emit(player_dmg, self)
		_player_cd = Config.ENEMY_PLAYER_COOLDOWN
		state = State.CHASE_PLAYER


func _step_attack_structure(delta: float) -> void:
	velocity = Vector2.ZERO
	if _target_lure != null:
		if not is_instance_valid(_target_lure) or not _target_lure.is_active():
			_target_lure = null
			state = State.WALK_TO_TARGET
			return
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = attack_interval
			_play_attack(facing)
			_target_lure.take_lure_damage(struct_dmg)
		return

	var still_blocks = false
	if is_instance_valid(_target_struct):
		if _target_struct is Structure:
			still_blocks = (_target_struct as Structure).is_blocking()
		elif _target_struct is Watchtower:
			still_blocks = (_target_struct as Watchtower).is_standing()
	if not still_blocks:
		_target_struct = null
		state = State.WALK_TO_TARGET
		return

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = attack_interval
		_play_attack(facing)
		structure_damaged.emit(_target_struct, struct_dmg, self)
		if _target_struct is Structure and (_target_struct as Structure).spiked:
			take_hit(1, Vector2.ZERO, false)


func _step_walk_to_target(
	delta: float,
	structures: Array,
	watchtowers: Array,
	traps: Array,
	player_pos: Vector2,
	player_inside: bool,
	house: Structure,
	all_enemies: Array,
	world_bounds: Rect2
) -> void:
	# lure posts pull zombies away from the fences first
	var lure := _find_lure(traps)
	if lure != null:
		var to_lure := lure.position - position
		if to_lure.length() <= lure.radius + 6.0:
			_target_lure = lure
			_target_struct = null
			_attack_timer = 0.25
			facing = _vec_to_dir(to_lure)
			state = State.ATTACK_STRUCTURE
			return
		var dir_l := to_lure.normalized()
		_move_solid(dir_l * speed, all_enemies, world_bounds)
		_play_walk(dir_l)
		return

	# if you forgot to shut the front door they sneak straight inside
	if house != null and house.is_standing() and house.is_door_open():
		var dist_door := position.distance_to(Config.HOUSE_DOOR_STEP)
		if dist_door <= 15.0:
			remove_from_group("enemies")
			entered_house.emit(self)
			queue_free()
			return

	# if already pressed up against a fence or tower, stop and chew it
	var blocker = _find_adjacent_blocker(structures, watchtowers)
	if blocker != null:
		_target_struct = blocker
		_target_lure = null
		_attack_timer = 0.35
		var t_pos = (
			blocker.target_center if blocker is Structure else blocker.position
		)
		facing = _vec_to_dir(t_pos - position)
		state = State.ATTACK_STRUCTURE
		return

	# head for open door, otherwise house, otherwise player if house is gone
	var goal = Config.HOUSE_CENTER
	if house != null and house.is_standing():
		if house.is_door_open() and position.distance_to(Config.HOUSE_DOOR_STEP) < 110.0:
			goal = Config.HOUSE_DOOR_STEP
		else:
			goal = Config.HOUSE_CENTER
	elif not player_inside:
		goal = player_pos

	var to_goal = goal - position
	var desired_dir = to_goal.normalized() if to_goal.length() > 1.0 else Vector2.DOWN

	# simple stuck check: if barely moving, either chew a nearby fence or sidestep around a tree
	var moved_px = position.distance_to(_last_pos)
	if moved_px < 4.0 * delta:
		_stuck_timer += delta
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.0)
	_last_pos = position

	if _stuck_timer > 0.7:
		var near_b = _find_adjacent_blocker(structures, watchtowers, 20.0)
		if near_b != null:
			_target_struct = near_b
			_attack_timer = 0.30
			state = State.ATTACK_STRUCTURE
			return
		desired_dir = desired_dir.rotated(_detour_sign * 0.78)
		if _stuck_timer > 2.2:
			_detour_sign = -_detour_sign
			_stuck_timer = 0.0

	_move_solid(desired_dir * speed, all_enemies, world_bounds)
	_play_walk(desired_dir)


func _move_solid(move_vel: Vector2, all_enemies: Array, world_bounds: Rect2) -> void:
	# gentle push away from nearby zombies so they dont stack into one ugly blob
	var sep := Vector2.ZERO
	var sep_r = Config.ENEMY_SEPARATION_RADIUS
	var sep_r_sq = sep_r * sep_r
	for other in all_enemies:
		if other == self or not is_instance_valid(other) or not other.is_alive():
			continue
		var diff = position - other.position
		var d_sq = diff.length_squared()
		if d_sq > 0.01 and d_sq < sep_r_sq:
			var d = sqrt(d_sq)
			sep += (diff / d) * ((sep_r - d) / sep_r) * 34.0
	velocity = move_vel + sep
	move_and_slide()
	_clamp_to_bounds(world_bounds)


func _clamp_to_bounds(world_bounds: Rect2) -> void:
	position.x = clampf(position.x, world_bounds.position.x + 6.0, world_bounds.end.x - 6.0)
	position.y = clampf(position.y, world_bounds.position.y + 6.0, world_bounds.end.y - 6.0)


func _find_lure(traps: Array) -> Trap:
	var best = null
	var best_d = 999999.0
	for t in traps:
		if not is_instance_valid(t) or not (t is Trap):
			continue
		var trap_node = t
		if trap_node.trap_type != "trap_lure" or not trap_node.is_active():
			continue
		var d = position.distance_to(trap_node.position)
		if d <= trap_node.attract_radius and d < best_d:
			best_d = d
			best = trap_node
	return best


func _find_adjacent_blocker(
	structures: Array,
	watchtowers: Array,
	extra_reach: float = 0.0
) -> Node2D:
	var best = null
	var best_d = 999999.0
	for s in structures:
		if not is_instance_valid(s) or not (s is Structure):
			continue
		var st = s
		if not st.is_blocking():
			continue
		var d = st.distance_from_point(position)
		var limit = (11.0 if st.kind == Structure.Kind.HOUSE else 12.0) + extra_reach
		if d <= limit and d < best_d:
			best_d = d
			best = st
	for wt in watchtowers:
		if not is_instance_valid(wt) or not (wt is Watchtower):
			continue
		var tower = wt
		if not tower.is_standing():
			continue
		var d_wt = position.distance_to(tower.position)
		if d_wt <= 18.0 + extra_reach and d_wt < best_d:
			best_d = d_wt
			best = tower
	return best


func _enter_dying() -> void:
	state = State.DYING
	_death_timer = 0.55
	collision_layer = 0
	collision_mask = 0
	if _hp_holder != null:
		_hp_holder.visible = false
	var anim = "death_left" if facing == "left" else "death_right"
	if _sprite != null:
		_sprite.modulate = _base_tint
		_sprite.offset = Art.feet_offset_for_animated(
			"enemies/%s/%s" % [enemy_type, anim]
		)
		_sprite.play(anim)
	killed.emit(self, _was_bow_kill)


func _step_death_or_dissolve(delta: float) -> void:
	_death_timer -= delta
	if _sprite != null:
		_sprite.modulate.a = clampf(_death_timer / 0.45, 0.0, 1.0)
	if _shadow != null:
		_shadow.modulate.a = clampf(_death_timer / 0.45, 0.0, 1.0)
	if _death_timer <= 0.0:
		remove_from_group("enemies")
		remove_from_group("hostiles")
		queue_free()


func _play_walk(dir: Vector2) -> void:
	facing = _vec_to_dir(dir)
	var anim = "walk_" + facing
	if _sprite != null and (_sprite.animation != anim or not _sprite.is_playing()):
		_sprite.offset = Art.feet_offset_for_animated(
			"enemies/%s/%s" % [enemy_type, anim]
		)
		_sprite.play(anim)


func _play_attack(dir_name: String) -> void:
	var anim = "attack_" + dir_name
	if _sprite != null:
		_sprite.offset = Art.feet_offset_for_animated(
			"enemies/%s/%s" % [enemy_type, anim]
		)
		_sprite.play(anim)


func _vec_to_dir(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "right" if v.x >= 0.0 else "left"
	return "down" if v.y >= 0.0 else "up"
