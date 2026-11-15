class_name Dog
extends CharacterBody2D

signal tamed(dog: Dog)
signal attacked_enemy(enemy: Node)

enum Mode { STRAY, FOLLOW, GUARD }

var mode: Mode = Mode.STRAY
var hp: int = 20
var max_hp: int = 20
var guard_anchor: Vector2 = Vector2.ZERO
var tame_progress: float = 0.0

var _sprite: AnimatedSprite2D
var _attack_cd: float = 0.0
var _facing: String = "down"
var _home_spot: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _wander_wait: float = 0.0
var _is_moving: bool = false
var _avoid_timer: float = 0.0
var _avoid_sign: float = 1.0
var _stuck_timer: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _heel_angle: float = 0.8


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
	_heel_angle = randf_range(0.5, 2.6)
	max_hp = Config.DOG_HP
	hp = max_hp
	mode = Mode.STRAY
	collision_layer = 2
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
	_sprite.play(&"idle_down")
	add_child(_sprite)
	return true


func toggle_guard_mode(anchor_pos: Vector2) -> String:
	if mode == Mode.STRAY:
		return ""

	if mode == Mode.FOLLOW:
		mode = Mode.GUARD
		guard_anchor = anchor_pos
		return "Dog guarding spot"

	mode = Mode.FOLLOW
	return "Dog following you"


func advance_tame(delta: float, is_holding: bool) -> bool:
	if mode != Mode.STRAY:
		return false

	if is_holding:
		tame_progress += delta
		if tame_progress >= Config.DOG_TAME_TIME:
			mode = Mode.FOLLOW
			tamed.emit(self)
			return true
	else:
		tame_progress = maxf(0.0, tame_progress - delta * 2.0)

	return false


func step_dog(
	delta: float,
	player_pos: Vector2,
	enemies: Array,
	world_bounds: Rect2
) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_avoid_timer = maxf(0.0, _avoid_timer - delta)

	if mode == Mode.STRAY:
		_step_stray_wander(delta, player_pos, world_bounds)
		return

	# catch up immediately if the player recalled home or left the dog far behind a gate
	if mode == Mode.FOLLOW and position.distance_to(player_pos) > 260.0:
		position = (player_pos + Vector2(cos(_heel_angle), sin(_heel_angle)) * 18.0).clamp(
			world_bounds.position + Vector2(8.0, 8.0),
			world_bounds.end - Vector2(8.0, 8.0)
		)
		velocity = Vector2.ZERO
		_avoid_timer = 0.0
		_stuck_timer = 0.0
		_last_pos = position
		_play_anim("idle")
		return

	var target_enemy = null
	var origin := guard_anchor if mode == Mode.GUARD else player_pos
	var best_d := Config.DOG_GUARD_RANGE + 24.0

	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var d = enemy.position.distance_to(origin)
		if d < best_d:
			best_d = d
			target_enemy = enemy

	var desired_vel = Vector2.ZERO
	if target_enemy != null:
		var to_e = target_enemy.position - position
		var dist_e = to_e.length()
		if dist_e <= 14.0:
			_facing = _vec_to_dir(to_e)
			if _attack_cd <= 0.0:
				_attack_cd = Config.DOG_ATTACK_INTERVAL
				target_enemy.take_hit(1, to_e.normalized(), false)
				attacked_enemy.emit(target_enemy)
		else:
			desired_vel = _steer_toward(to_e / dist_e, 96.0)
	elif mode == Mode.GUARD:
		desired_vel = _compute_guard_patrol_vel(delta)
	else:
		var heel_pos = player_pos + Vector2(cos(_heel_angle), sin(_heel_angle)) * 18.0
		var to_heel = heel_pos - position
		var dist_h = to_heel.length()
		# hysteresis prevents jittering between run and idle at the edge of stop radius
		var stop_r = 14.0 if _is_moving else 26.0
		if dist_h > stop_r:
			var speed = 78.0 if dist_h < 72.0 else minf(118.0, 78.0 + (dist_h - 72.0) * 0.55)
			desired_vel = _steer_toward(to_heel / dist_h, speed)

	_apply_smooth_movement(delta, desired_vel, world_bounds)


func _step_stray_wander(delta: float, player_pos: Vector2, world_bounds: Rect2) -> void:
	# pause and look at the player when they walk up to tame
	if position.distance_to(player_pos) <= 34.0:
		_facing = _vec_to_dir(player_pos - position)
		_apply_smooth_movement(delta, Vector2.ZERO, world_bounds)
		return

	if _wander_wait > 0.0:
		_wander_wait -= delta
		_apply_smooth_movement(delta, Vector2.ZERO, world_bounds)
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
		_apply_smooth_movement(delta, Vector2.ZERO, world_bounds)
		return

	_apply_smooth_movement(delta, _steer_toward(to_w.normalized(), 34.0), world_bounds)


func _compute_guard_patrol_vel(delta: float) -> Vector2:
	var to_anchor = guard_anchor - position
	if to_anchor.length() > 30.0:
		return _steer_toward(to_anchor.normalized(), 74.0)
	if _wander_wait > 0.0:
		_wander_wait -= delta
		return Vector2.ZERO
	var to_patrol = _wander_target - position
	if to_patrol.length() <= 5.0 or _wander_target.distance_to(guard_anchor) > 26.0:
		_wander_wait = randf_range(1.0, 2.4)
		var ang = randf_range(0.0, TAU)
		_wander_target = guard_anchor + Vector2(cos(ang), sin(ang)) * randf_range(10.0, 22.0)
		return Vector2.ZERO
	return _steer_toward(to_patrol.normalized(), 42.0)


func _steer_toward(dir_n: Vector2, speed: float) -> Vector2:
	if _avoid_timer > 0.0:
		var side = Vector2(-dir_n.y, dir_n.x) * _avoid_sign
		return (dir_n * 0.45 + side * 0.89).normalized() * speed
	return dir_n * speed


func _apply_smooth_movement(delta: float, desired_vel: Vector2, world_bounds: Rect2) -> void:
	var accel = 12.0 if desired_vel.length_squared() > 1.0 else 16.0
	velocity = velocity.lerp(desired_vel, minf(1.0, delta * accel))
	if velocity.length_squared() > 16.0:
		_is_moving = true
		_facing = _vec_to_dir(velocity)
		move_and_slide()
		position.x = clampf(position.x, world_bounds.position.x + 8.0, world_bounds.end.x - 8.0)
		position.y = clampf(position.y, world_bounds.position.y + 8.0, world_bounds.end.y - 8.0)
		# detect obstacle snag and steer smoothly around it
		if is_on_wall() or (desired_vel.length() > 25.0 and position.distance_to(_last_pos) < 0.3):
			_stuck_timer += delta
			if _stuck_timer >= 0.16:
				_stuck_timer = 0.0
				_avoid_timer = 0.55
				_avoid_sign = -_avoid_sign if randf() < 0.35 else _avoid_sign
		else:
			_stuck_timer = maxf(0.0, _stuck_timer - delta)
		_last_pos = position
		_play_anim("run")
	else:
		_is_moving = false
		velocity = Vector2.ZERO
		_stuck_timer = 0.0
		_last_pos = position
		_play_anim("idle")


func _play_anim(prefix: String) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return

	var anim := StringName("%s_%s" % [prefix, _facing])
	if not _sprite.sprite_frames.has_animation(anim):
		anim = StringName("%s_down" % prefix)

	if _sprite.sprite_frames.has_animation(anim) and _sprite.animation != anim:
		_sprite.play(anim)


func _vec_to_dir(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "right" if v.x >= 0.0 else "left"
	return "down" if v.y >= 0.0 else "up"


func _load_dog_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")

	for anim_name in ["idle", "run"]:
		for dir_name in ["down", "up", "left", "right"]:
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
