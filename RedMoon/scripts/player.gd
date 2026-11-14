class_name Player
extends CharacterBody2D
## Solid player (layer 2, mask 1|3) with spear melee, auto-aim hunting bow (T1.2),
## inside-house shelter + healing (T1.5), lantern light, and workshop upgrades (T2.2).

signal spear_swung(hitbox: Rect2, facing_dir: Vector2, damage: int)
signal bow_fired(origin: Vector2, target_dir: Vector2, damage: int, pierce: int)
signal bow_empty_clicked()
signal bow_reloaded()
signal died()

var hp: int = 50
var max_hp: int = 50
var facing: String = "down"
var facing_vec: Vector2 = Vector2.DOWN
var dead: bool = false
var inside_house: bool = false
var active_weapon: String = "spear"  # "spear" or "bow"

# Bow state (T1.2)
var mag: int = 6
var mag_max: int = 6
var reserve_max: int = 30
var bow_reload_time: float = 2.2
var bow_damage: int = 1
var bow_pierce: int = 0
var reload_timer: float = 0.0
var bow_cd: float = 0.0

# Workshop upgrades (T2.2)
var melee_damage: int = 1
var speed_mult: float = 1.0
var bounce_cd_mult: float = 1.0
var bounce_bonus_count: int = 0

var _sprite: AnimatedSprite2D = null
var _shadow: Sprite2D = null
var _spear: Sprite2D = null
var _lantern: PointLight2D = null
var _swing_timer: float = 0.0
var _swing_cd: float = 0.0
var _invuln_timer: float = 0.0
var _heal_timer: float = 0.0
var _last_safe_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	name = "Player"
	collision_layer = 2
	collision_mask = 1 | 4
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	var col: CollisionShape2D = CollisionShape2D.new()
	var sh: RectangleShape2D = RectangleShape2D.new()
	sh.size = Vector2(8.0, 8.0)
	col.shape = sh
	col.position = Vector2(0.0, -4.0)
	add_child(col)

	_shadow = Sprite2D.new()
	_shadow.texture = SpriteFactory.get_blob_shadow(12, 5)
	_shadow.position = Vector2(0.0, 1.0)
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_shadow)

	_sprite = AnimatedSprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.sprite_frames = SpriteFactory.get_player_frames(Config.SWING_TIME)
	_sprite.offset = SpriteFactory.feet_offset_for_animated("player/idle_down")
	_sprite.play(&"idle_down")
	add_child(_sprite)

	_spear = Sprite2D.new()
	_spear.texture = SpriteFactory.get_spear_texture()
	_spear.centered = false
	_spear.offset = Vector2(-5.0, -3.0)
	_spear.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_spear.visible = false
	add_child(_spear)

	_lantern = PointLight2D.new()
	_lantern.texture = SpriteFactory.get_radial_light_texture(128)
	_lantern.texture_scale = 0.85
	_lantern.energy = 0.48
	_lantern.color = Color(1.0, 0.82, 0.54, 1.0)
	_lantern.position = Vector2(0.0, -8.0)
	_lantern.visible = false
	add_child(_lantern)


func reset_for_new_game(spawn_pos: Vector2) -> void:
	position = spawn_pos.round()
	_last_safe_pos = position
	max_hp = Config.PLAYER_HP
	hp = max_hp
	facing = "down"
	facing_vec = Vector2.DOWN
	dead = false
	inside_house = false
	active_weapon = "spear"
	melee_damage = 1
	speed_mult = 1.0
	bounce_cd_mult = 1.0
	bounce_bonus_count = 0
	mag_max = Config.BOW_MAG
	mag = mag_max
	reserve_max = Config.BOW_RESERVE_MAX
	bow_reload_time = Config.BOW_RELOAD
	bow_damage = Config.BOW_DAMAGE
	bow_pierce = 0
	reload_timer = 0.0
	bow_cd = 0.0
	_swing_timer = 0.0
	_swing_cd = 0.0
	_invuln_timer = 0.0
	_heal_timer = 0.0
	_apply_visibility_and_collision()
	if _sprite != null:
		_sprite.modulate = Color.WHITE
		_sprite.offset = SpriteFactory.feet_offset_for_animated("player/idle_down")
		_sprite.play(&"idle_down")
	if _spear != null:
		_spear.visible = false


func set_inside_house(
	is_in: bool, exit_pos: Vector2 = Config.HOUSE_DOOR_STEP + Vector2(0.0, 10.0)
) -> void:
	inside_house = is_in
	if is_in:
		position = Config.HOUSE_CENTER
		velocity = Vector2.ZERO
		_swing_timer = 0.0
		if _spear != null:
			_spear.visible = false
	else:
		position = exit_pos.round()
		_last_safe_pos = position
	_apply_visibility_and_collision()


func set_night_lantern(is_night: bool) -> void:
	if _lantern != null:
		_lantern.visible = is_night and not inside_house and not dead


func step_player(
	delta: float,
	move_input: Vector2,
	world_bounds: Rect2,
	allow_move: bool,
	inventory: Inventory
) -> void:
	if _invuln_timer > 0.0:
		_invuln_timer = maxf(0.0, _invuln_timer - delta)
		if _sprite != null:
			_sprite.modulate.a = 0.45 if (int(_invuln_timer * 18.0) % 2 == 0) else 1.0
			if _invuln_timer <= 0.0:
				_sprite.modulate = Color.WHITE

	if _swing_cd > 0.0:
		_swing_cd = maxf(0.0, _swing_cd - delta)
	if bow_cd > 0.0:
		bow_cd = maxf(0.0, bow_cd - delta)

	# Handle bow reload countdown (T1.2).
	if reload_timer > 0.0:
		reload_timer = maxf(0.0, reload_timer - delta)
		if reload_timer <= 0.0:
			var need: int = mag_max - mag
			var drawn: int = inventory.remove("arrow", need)
			mag += drawn
			bow_reloaded.emit()

	if dead:
		velocity = Vector2.ZERO
		return

	# Slow passive healing while sheltered inside the house (T1.5C).
	if inside_house:
		velocity = Vector2.ZERO
		if hp < max_hp:
			_heal_timer += delta
			if _heal_timer >= Config.INSIDE_HEAL_INTERVAL:
				_heal_timer = 0.0
				hp = mini(max_hp, hp + 1)
		return

	_heal_timer = 0.0

	if _swing_timer > 0.0:
		_swing_timer = maxf(0.0, _swing_timer - delta)
		_update_spear_pose()
		if _swing_timer <= 0.0 and _spear != null:
			_spear.visible = false

	if allow_move and move_input.length_squared() > 0.01:
		var move_dir: Vector2 = move_input.normalized()
		facing_vec = move_dir
		facing = _vec_to_dir(move_dir)
		var speed: float = Config.PLAYER_SPEED * speed_mult * (0.65 if _swing_timer > 0.0 else 1.0)
		velocity = move_dir * speed
		move_and_slide()
		position.x = clampf(position.x, world_bounds.position.x + 8.0, world_bounds.end.x - 8.0)
		position.y = clampf(position.y, world_bounds.position.y + 8.0, world_bounds.end.y - 8.0)
		_last_safe_pos = position
		if _swing_timer <= 0.0:
			_play_anim("run_" + facing)
	else:
		velocity = Vector2.ZERO
		if _swing_timer <= 0.0:
			_play_anim("idle_" + facing)


func try_swing() -> bool:
	if dead or inside_house or _swing_cd > 0.0 or _swing_timer > 0.0:
		return false
	active_weapon = "spear"
	_swing_timer = Config.SWING_TIME
	_swing_cd = Config.SWING_COOLDOWN
	_play_anim("punch_" + facing)
	_update_spear_pose()
	if _spear != null:
		_spear.visible = true
	spear_swung.emit(_compute_swing_hitbox(), _dir_vector(facing), melee_damage)
	return true


## T1.2: Fires an auto-aimed arrow at the nearest enemy in range (also works from house windows!).
func try_fire_bow(enemies: Array, inventory: Inventory) -> bool:
	if dead or bow_cd > 0.0 or reload_timer > 0.0:
		return false
	active_weapon = "bow"
	if mag <= 0:
		if inventory.count("arrow") > 0:
			start_reload(inventory)
		else:
			bow_empty_clicked.emit()
		return false

	var origin: Vector2 = _get_bow_origin(enemies)
	var target: Enemy = _find_auto_aim_target(origin, enemies)
	var aim_dir: Vector2 = _dir_vector(facing)
	if target != null:
		aim_dir = (target.position + Vector2(0.0, -8.0) - origin).normalized()
		facing = _vec_to_dir(aim_dir)
		facing_vec = aim_dir

	mag -= 1
	bow_cd = Config.BOW_FIRE_INTERVAL
	bow_fired.emit(origin, aim_dir, bow_damage, bow_pierce)
	if mag <= 0 and inventory.count("arrow") > 0:
		start_reload(inventory)
	return true


func start_reload(inventory: Inventory) -> bool:
	if dead or reload_timer > 0.0 or mag >= mag_max or inventory.count("arrow") <= 0:
		return false
	reload_timer = bow_reload_time
	return true


func is_reloading() -> bool:
	return reload_timer > 0.0


func take_damage(amount: int) -> bool:
	if dead or _invuln_timer > 0.0 or amount <= 0:
		return false
	hp = maxi(0, hp - amount)
	_invuln_timer = Config.CONTACT_INVULN
	if hp <= 0:
		dead = true
		inside_house = false
		_apply_visibility_and_collision()
		if _spear != null:
			_spear.visible = false
		var d_anim: String = "death_left" if facing == "left" else "death_right"
		_play_anim(d_anim)
		died.emit()
	return true


func apply_upgrade_stats(upgrades: Dictionary) -> void:
	melee_damage = 2 if bool(upgrades.get("heavy_bat", false)) else 1
	speed_mult = 1.15 if bool(upgrades.get("swift_boots", false)) else 1.0
	bounce_cd_mult = 0.70 if bool(upgrades.get("quick_bounce", false)) else 1.0
	mag_max = 12 if bool(upgrades.get("bigger_quiver", false)) else Config.BOW_MAG
	reserve_max = 50 if bool(upgrades.get("bigger_quiver", false)) else Config.BOW_RESERVE_MAX
	bow_reload_time = 1.4 if bool(upgrades.get("quick_hands", false)) else Config.BOW_RELOAD
	bow_pierce = 1 if bool(upgrades.get("barbed_arrows", false)) else 0


func _apply_visibility_and_collision() -> void:
	visible = not inside_house
	if inside_house or dead:
		collision_layer = 0
		collision_mask = 0
	else:
		collision_layer = 2
		collision_mask = 1 | 4


func _get_bow_origin(enemies: Array) -> Vector2:
	if not inside_house:
		return position + Vector2(0.0, -8.0)
	# When inside the house, fire from whichever front window is closest to the nearest threat.
	var left_win: Vector2 = Config.HOUSE_CENTER + Vector2(-22.0, 18.0)
	var right_win: Vector2 = Config.HOUSE_CENTER + Vector2(22.0, 18.0)
	var nearest: Enemy = _find_auto_aim_target(Config.HOUSE_CENTER, enemies)
	if nearest != null and nearest.position.x < Config.HOUSE_CENTER.x:
		return left_win
	return right_win


func _find_auto_aim_target(origin: Vector2, enemies: Array) -> Enemy:
	var best: Enemy = null
	var best_d: float = Config.BOW_RANGE
	for e in enemies:
		if not is_instance_valid(e) or not (e is Enemy) or not (e as Enemy).is_alive():
			continue
		var d: float = origin.distance_to((e as Node2D).position)
		if d <= best_d:
			best_d = d
			best = e as Enemy
	return best


func _compute_swing_hitbox() -> Rect2:
	var scale_mult: float = 1.0 + float(bounce_bonus_count) * Config.SWING_GROWTH_PER_BOUNCE
	var box_size: Vector2 = Config.SWING_BOX * scale_mult
	if facing == "up" or facing == "down":
		box_size = Vector2(box_size.y, box_size.x)
	var center: Vector2 = (
		position + Vector2(0.0, -7.0) + _dir_vector(facing) * (Config.SWING_OFFSET * scale_mult)
	)
	return Rect2(center - box_size * 0.5, box_size)


func _update_spear_pose() -> void:
	if _spear == null:
		return
	var progress: float = 1.0 - clampf(_swing_timer / maxf(0.01, Config.SWING_TIME), 0.0, 1.0)
	var thrust: float = sin(progress * PI) * 9.0
	var scale_mult: float = 1.0 + float(bounce_bonus_count) * Config.SWING_GROWTH_PER_BOUNCE
	_spear.scale = Vector2(scale_mult, scale_mult)
	match facing:
		"right":
			_spear.rotation = 0.0
			_spear.position = Vector2(4.0 + thrust, -7.0)
			_spear.z_index = 1
		"left":
			_spear.rotation = PI
			_spear.position = Vector2(-4.0 - thrust, -7.0)
			_spear.z_index = 1
		"down":
			_spear.rotation = PI * 0.5
			_spear.position = Vector2(2.0, -3.0 + thrust)
			_spear.z_index = 1
		_:
			_spear.rotation = -PI * 0.5
			_spear.position = Vector2(2.0, -11.0 - thrust)
			_spear.z_index = -1


func _play_anim(anim_name: String) -> void:
	if _sprite == null:
		return
	if _sprite.animation != anim_name or not _sprite.is_playing():
		_sprite.offset = SpriteFactory.feet_offset_for_animated("player/" + anim_name)
		_sprite.play(anim_name)


func _dir_vector(dir_name: String) -> Vector2:
	match dir_name:
		"up":
			return Vector2.UP
		"down":
			return Vector2.DOWN
		"left":
			return Vector2.LEFT
		_:
			return Vector2.RIGHT


func _vec_to_dir(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "right" if v.x >= 0.0 else "left"
	return "down" if v.y >= 0.0 else "up"
