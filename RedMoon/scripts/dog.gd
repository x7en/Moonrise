class_name Dog
extends CharacterBody2D

signal tamed(dog: Dog)
signal attacked_enemy(enemy: Node)
signal died(dog: Dog)

enum Mode { STRAY, FOLLOW, GUARD }

var mode: Mode = Mode.STRAY
var guard_anchor: Vector2 = Vector2.ZERO
var hp: int = Config.DOG_HP
var max_hp: int = Config.DOG_HP

var _sprite: AnimatedSprite2D
var _hp_bar_bg: ColorRect
var _hp_bar_fill: ColorRect
var _flash_timer: float = 0.0
var _attack_cd: float = 0.0
var _facing: String = "right"  # side-view sheets only have left/right silhouettes
var _flip_cd: float = 0.0
var _home_spot: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _wander_wait: float = 0.0
var _is_moving: bool = false
var _avoid_timer: float = 0.0
var _avoid_sign: float = 1.0
var _stuck_timer: float = 0.0
var _hop_timer: float = 0.0
var _lunge_timer: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _flank_sign: float = 1.0
var _current_target: Enemy = null


static func assets_available() -> bool:
	return (
		ResourceLoader.exists("res://assets/dog/idle_right.png")
		and ResourceLoader.exists("res://assets/dog/run_right.png")
	)


func setup(spawn_pos: Vector2) -> bool:
	if not Dog.assets_available():
		return false

	position = spawn_pos.round()
	_home_spot = position
	_wander_target = position
	_last_pos = position
	_flank_sign = 1.0 if (randi() % 2 == 0) else -1.0
	mode = Mode.STRAY
	max_hp = Config.DOG_HP
	hp = max_hp
	# doesn't physically block player movement; enemies check distance to damage tamed dogs
	collision_layer = 0
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("dogs")

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(8.0, 6.0)
	col.shape = shape
	col.position = Vector2(0.0, -3.0)
	add_child(col)

	var shadow := Sprite2D.new()
	shadow.texture = Art.get_blob_shadow(12, 5)
	shadow.position = Vector2(0.0, 1.0)
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(shadow)

	# dog sheets are 48x47 per frame so scale them down to match our 16px guy
	_sprite = AnimatedSprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.sprite_frames = _load_dog_frames()
	_sprite.scale = Vector2(0.5, 0.5)
	_sprite.offset = Vector2(-24.0, -40.0)
	_sprite.play(&"idle_right")
	add_child(_sprite)

	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.position = Vector2(-7.0, -21.0)
	_hp_bar_bg.size = Vector2(14.0, 3.0)
	_hp_bar_bg.color = Color(0.08, 0.06, 0.10, 0.85)
	_hp_bar_bg.visible = false
	add_child(_hp_bar_bg)

	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.position = Vector2(1.0, 1.0)
	_hp_bar_fill.size = Vector2(12.0, 1.0)
	_hp_bar_fill.color = Color(0.42, 0.90, 0.45, 1.0)
	_hp_bar_bg.add_child(_hp_bar_fill)
	return true


func is_tamed() -> bool:
	return mode != Mode.STRAY


func is_alive() -> bool:
	return hp > 0


func tame_now() -> bool:
	if mode != Mode.STRAY:
		return false
	mode = Mode.FOLLOW
	hp = max_hp
	_refresh_hp_bar()
	tamed.emit(self)
	return true


func take_damage(dmg: int) -> bool:
	if mode == Mode.STRAY or hp <= 0:
		return false
	hp = maxi(0, hp - dmg)
	_flash_timer = 0.16
	if _sprite != null:
		_sprite.modulate = Color(1.0, 0.42, 0.42, 1.0)
	_refresh_hp_bar()
	if hp <= 0:
		died.emit(self)
		queue_free()
		return true
	return false


func heal_for_new_day() -> void:
	if mode == Mode.STRAY or hp <= 0:
		return
	hp = mini(max_hp, hp + 5)
	_refresh_hp_bar()


func _refresh_hp_bar() -> void:
	if _hp_bar_bg == null or _hp_bar_fill == null:
		return
	var show_bar := (mode != Mode.STRAY and hp > 0 and hp < max_hp)
	_hp_bar_bg.visible = show_bar
	if show_bar:
		var frac := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
		_hp_bar_fill.size.x = maxf(1.0, floorf(12.0 * frac))
		_hp_bar_fill.color = (
			Color(0.42, 0.90, 0.45) if frac > 0.5
			else (Color(0.95, 0.78, 0.25) if frac > 0.25 else Color(0.95, 0.30, 0.26))
		)


func toggle_guard_mode(anchor_pos: Vector2) -> String:
	if mode == Mode.STRAY:
		return ""

	if mode == Mode.FOLLOW:
		mode = Mode.GUARD
		guard_anchor = anchor_pos
		return "Dog guarding spot"

	mode = Mode.FOLLOW
	return "Dog following you"


func step_dog(
	delta: float,
	player_pos: Vector2,
	enemies: Array,
	world_bounds: Rect2,
	player_facing: Vector2 = Vector2.RIGHT,
	player_inside: bool = false
) -> void:
	if hp <= 0:
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_avoid_timer = maxf(0.0, _avoid_timer - delta)
	_flip_cd = maxf(0.0, _flip_cd - delta)
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		if _flash_timer <= 0.0 and _sprite != null:
			_sprite.modulate = Color.WHITE
	_update_hop_and_lunge(delta)

	if mode == Mode.STRAY:
		_step_stray_wander(delta, player_pos, world_bounds)
		return

	var follow_anchor = Config.HOUSE_DOOR if player_inside else player_pos
	var hunt_origin = guard_anchor if mode == Mode.GUARD else follow_anchor
	var target_enemy = _pick_target_enemy(enemies, hunt_origin)

	# catch up immediately if player recalled far away and we aren't actively fighting nearby
	if mode == Mode.FOLLOW and target_enemy == null and position.distance_to(follow_anchor) > 290.0:
		var warp_spot = _compute_heel_spot(follow_anchor, player_facing)
		position = warp_spot.clamp(
			world_bounds.position + Vector2(8.0, 8.0),
			world_bounds.end - Vector2(8.0, 8.0)
		)
		velocity = Vector2.ZERO
		_avoid_timer = 0.0
		_stuck_timer = 0.0
		_last_pos = position
		_face_horizontal(player_facing.x, true)
		_play_anim("idle")
		return

	var desired_vel = Vector2.ZERO
	if target_enemy != null:
		var to_e = target_enemy.position - position
		var dist_e = to_e.length()
		if dist_e <= 15.0:
			_face_horizontal(to_e.x, true)
			if _attack_cd <= 0.0:
				_attack_cd = Config.DOG_ATTACK_INTERVAL
				_lunge_timer = 0.16
				target_enemy.take_hit(Config.DOG_DAMAGE, to_e.normalized(), false)
				attacked_enemy.emit(target_enemy)
		else:
			desired_vel = _steer_toward(to_e / dist_e, Config.DOG_SPEED_CHASE)
	elif mode == Mode.GUARD:
		desired_vel = _compute_guard_patrol_vel(delta)
	else:
		var heel_pos = _compute_heel_spot(follow_anchor, player_facing)
		var to_heel = heel_pos - position
		var dist_h = to_heel.length()
		# hysteresis prevents jittering between run and idle at the edge of stop radius
		var stop_r = 10.0 if _is_moving else 22.0
		if dist_h > stop_r:
			var base_spd = Config.DOG_SPEED_FOLLOW
			var speed = (
				base_spd if dist_h < 68.0
				else minf(Config.DOG_SPEED_CATCHUP_MAX, base_spd + (dist_h - 68.0) * 0.4)
			)
			desired_vel = _steer_toward(to_heel / dist_h, speed)
		elif absf(player_facing.x) > 0.25:
			# align nicely with the player's facing direction when stopped at heel
			_face_horizontal(player_facing.x, false)

	_apply_smooth_movement(delta, desired_vel, world_bounds, true)


func _pick_target_enemy(enemies: Array, origin: Vector2) -> Enemy:
	var max_range = Config.DOG_HUNT_RANGE
	var leash_max = max_range + 50.0
	if (
		is_instance_valid(_current_target)
		and _current_target.is_alive()
		and (
			_current_target.position.distance_to(position) <= leash_max
			or _current_target.position.distance_to(origin) <= leash_max
		)
	):
		return _current_target

	_current_target = null
	var best = null
	var best_score = max_range
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var d_self = enemy.position.distance_to(position)
		var d_origin = enemy.position.distance_to(origin)
		var score = minf(d_self, d_origin)
		if score < best_score:
			best_score = score
			best = enemy
	_current_target = best
	return best


func _compute_heel_spot(anchor: Vector2, player_facing: Vector2) -> Vector2:
	var f_dir = player_facing.normalized() if player_facing.length_squared() > 0.01 else Vector2.RIGHT
	var side = Vector2(-f_dir.y, f_dir.x) * _flank_sign
	return anchor - f_dir * 16.0 + side * 12.0


func _step_stray_wander(delta: float, player_pos: Vector2, world_bounds: Rect2) -> void:
	# pause and face the player when they walk up to tame
	if position.distance_to(player_pos) <= 34.0:
		_face_horizontal(player_pos.x - position.x, true)
		_apply_smooth_movement(delta, Vector2.ZERO, world_bounds, false)
		return

	if _wander_wait > 0.0:
		_wander_wait -= delta
		_apply_smooth_movement(delta, Vector2.ZERO, world_bounds, false)
		return

	var to_w = _wander_target - position
	if to_w.length() <= 6.0:
		_wander_wait = randf_range(1.4, 3.2)
		var ang = randf_range(0.0, TAU)
		var rad = randf_range(16.0, 54.0)
		_wander_target = (_home_spot + Vector2(cos(ang), sin(ang)) * rad).clamp(
			world_bounds.position + Vector2(24.0, 24.0),
			world_bounds.end - Vector2(24.0, 24.0)
		)
		_apply_smooth_movement(delta, Vector2.ZERO, world_bounds, false)
		return

	_apply_smooth_movement(delta, _steer_toward(to_w.normalized(), 34.0), world_bounds, false)


func _compute_guard_patrol_vel(delta: float) -> Vector2:
	var to_anchor = guard_anchor - position
	if to_anchor.length() > 36.0:
		return _steer_toward(to_anchor.normalized(), Config.DOG_SPEED_FOLLOW)
	if _wander_wait > 0.0:
		_wander_wait -= delta
		return Vector2.ZERO
	var to_patrol = _wander_target - position
	if to_patrol.length() <= 5.0 or _wander_target.distance_to(guard_anchor) > 30.0:
		_wander_wait = randf_range(1.0, 2.4)
		var ang = randf_range(0.0, TAU)
		_wander_target = guard_anchor + Vector2(cos(ang), sin(ang)) * randf_range(12.0, 26.0)
		return Vector2.ZERO
	return _steer_toward(to_patrol.normalized(), 34.0)


func _steer_toward(dir_n: Vector2, speed: float) -> Vector2:
	if _avoid_timer > 0.0 and _hop_timer <= 0.0:
		var side = Vector2(-dir_n.y, dir_n.x) * _avoid_sign
		return (dir_n * 0.45 + side * 0.89).normalized() * speed
	return dir_n * speed


func _apply_smooth_movement(
	delta: float,
	desired_vel: Vector2,
	world_bounds: Rect2,
	allow_fence_hop: bool
) -> void:
	var accel = 13.0 if desired_vel.length_squared() > 1.0 else 18.0
	velocity = velocity.lerp(desired_vel, minf(1.0, delta * accel))
	if velocity.length_squared() > 16.0:
		_is_moving = true
		_face_horizontal(velocity.x, false)
		move_and_slide()
		position.x = clampf(position.x, world_bounds.position.x + 8.0, world_bounds.end.x - 8.0)
		position.y = clampf(position.y, world_bounds.position.y + 8.0, world_bounds.end.y - 8.0)
		var blocked = is_on_wall() or (
			desired_vel.length() > 25.0 and position.distance_to(_last_pos) < 0.35
		)
		if blocked:
			_stuck_timer += delta
			if _stuck_timer >= 0.14 and _avoid_timer <= 0.0:
				_avoid_timer = 0.48
				_avoid_sign = -_avoid_sign if randf() < 0.35 else _avoid_sign
			if allow_fence_hop and _stuck_timer >= 0.34 and _hop_timer <= 0.0:
				# bound cleanly over a closed fence or obstacle to chase zombies freely
				_hop_timer = 0.34
				_stuck_timer = 0.0
				collision_mask = 0
		else:
			_stuck_timer = maxf(0.0, _stuck_timer - delta)
		_last_pos = position
		_play_anim("run")
		if _sprite != null:
			_sprite.speed_scale = clampf(velocity.length() / 76.0, 0.75, 1.55)
	else:
		_is_moving = false
		velocity = Vector2.ZERO
		_stuck_timer = 0.0
		_last_pos = position
		_play_anim("idle")
		if _sprite != null:
			_sprite.speed_scale = 1.0

	# subtle slope lean when moving vertically/diagonally so side-view sprites feel directional
	if _sprite != null:
		var target_tilt = 0.0
		if _is_moving and velocity.length() > 12.0:
			var slope = clampf(velocity.y / maxf(24.0, velocity.length()), -1.0, 1.0)
			var sign_x = 1.0 if _facing == "right" else -1.0
			target_tilt = slope * 0.16 * sign_x
		_sprite.rotation = lerpf(_sprite.rotation, target_tilt, minf(1.0, delta * 12.0))


func _update_hop_and_lunge(delta: float) -> void:
	if _hop_timer > 0.0:
		_hop_timer = maxf(0.0, _hop_timer - delta)
		if _hop_timer <= 0.0:
			collision_mask = 1
	if _lunge_timer > 0.0:
		_lunge_timer = maxf(0.0, _lunge_timer - delta)
	if _sprite == null:
		return
	var hop_y = -sin((_hop_timer / 0.34) * PI) * 8.0 if _hop_timer > 0.0 else 0.0
	var lunge_x = 0.0
	if _lunge_timer > 0.0:
		var p = sin((_lunge_timer / 0.16) * PI)
		lunge_x = (4.5 if _facing == "right" else -4.5) * p
		hop_y -= 2.5 * p
	_sprite.position = Vector2(lunge_x, hop_y)


func _face_horizontal(dx: float, force: bool) -> void:
	if absf(dx) < (1.0 if force else 6.0):
		return
	var want = "right" if dx >= 0.0 else "left"
	if want != _facing and (force or _flip_cd <= 0.0):
		_facing = want
		_flip_cd = 0.14


func _play_anim(prefix: String) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return

	var anim := StringName("%s_%s" % [prefix, _facing])
	if not _sprite.sprite_frames.has_animation(anim):
		anim = StringName("%s_right" % prefix)

	if _sprite.sprite_frames.has_animation(anim) and _sprite.animation != anim:
		_sprite.play(anim)


func _load_dog_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")

	for anim_name in ["idle", "run"]:
		for dir_name in ["left", "right"]:
			var full_path := "res://assets/dog/%s_%s.png" % [anim_name, dir_name]
			if not ResourceLoader.exists(full_path):
				continue

			var strip_tex = load(full_path)
			if strip_tex == null:
				continue

			var fh := maxi(1, strip_tex.get_height())
			var count := maxi(1, roundi(float(strip_tex.get_width()) / float(maxi(1, fh))))
			var fw := maxi(1, int(floorf(float(strip_tex.get_width()) / float(count))))

			var anim_key := "%s_%s" % [anim_name, dir_name]
			sf.add_animation(anim_key)
			sf.set_animation_speed(anim_key, 9.0 if anim_name == "run" else 6.0)
			sf.set_animation_loop(anim_key, true)

			for i in range(count):
				var at := AtlasTexture.new()
				at.atlas = strip_tex
				at.region = Rect2(float(i * fw), 0.0, float(fw), float(fh))
				sf.add_frame(anim_key, at)

	return sf
