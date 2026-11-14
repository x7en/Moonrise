class_name Player
extends CharacterBody2D
## Player controller: 4-way movement, punch swing, contact invulnerability, and Bounce Back.

signal swung()
signal bounced(was_death: bool)
signal took_damage(amount: int)

@export var speed_multiplier: float = 1.0

var hp: int = 50
var max_hp: int = 50
var facing: String = "down"
var last_h_facing: String = "right"

var swing_timer: float = 0.0
var swing_cd_timer: float = 0.0
var invuln_timer: float = 0.0
var bounce_cd_timer: float = 0.0
var bounce_cd_max: float = 10.0
var bounce_stun_timer: float = 0.0
var bounce_bonuses: int = 0
var is_dying: bool = false
var controls_enabled: bool = false
var is_night_context: bool = false
var clamp_rect: Rect2 = Rect2()

var _death_timer: float = 0.0
var _heal_accum: float = 0.0
var _heal_rate: float = 0.0
var _input_grace: float = 0.0
var _swing_hit_ids: Dictionary = {}
var _current_anim: String = ""

var _sprite: AnimatedSprite2D = null
var _heal_bar_bg: ColorRect = null
var _heal_bar_fill: ColorRect = null


func _ready() -> void:
	name = "Player"
	hp = Config.PLAYER_HP
	max_hp = Config.PLAYER_HP
	bounce_cd_max = Config.BOUNCE_CD_ACT1
	clamp_rect = Config.ACT1_RECT
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1

	var col: CollisionShape2D = CollisionShape2D.new()
	var rect_shape: RectangleShape2D = RectangleShape2D.new()
	rect_shape.size = Vector2(8.0, 6.0)
	col.shape = rect_shape
	col.position = Vector2(0.0, -3.0)
	add_child(col)

	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.sprite_frames = SpriteFactory.get_player_frames(Config.SWING_TIME)
	add_child(_sprite)

	# Small indicator bar shown while healing / unable to swing after Bounce Back.
	_heal_bar_bg = ColorRect.new()
	_heal_bar_bg.position = Vector2(-8.0, -22.0)
	_heal_bar_bg.size = Vector2(16.0, 3.0)
	_heal_bar_bg.color = Color(0.06, 0.1, 0.12, 0.85)
	_heal_bar_bg.visible = false
	add_child(_heal_bar_bg)

	_heal_bar_fill = ColorRect.new()
	_heal_bar_fill.position = Vector2(-7.0, -21.0)
	_heal_bar_fill.size = Vector2(14.0, 1.0)
	_heal_bar_fill.color = Color(0.35, 0.92, 0.72, 1.0)
	_heal_bar_fill.visible = false
	add_child(_heal_bar_fill)

	_play_anim("idle_down", true)


func reset_state(spawn_pos: Vector2, p_clamp_rect: Rect2, p_bounce_cd_max: float) -> void:
	position = spawn_pos.round()
	clamp_rect = p_clamp_rect
	bounce_cd_max = p_bounce_cd_max
	hp = max_hp
	facing = "down"
	last_h_facing = "right"
	swing_timer = 0.0
	swing_cd_timer = 0.0
	invuln_timer = 0.0
	bounce_cd_timer = 0.0
	bounce_stun_timer = 0.0
	bounce_bonuses = 0
	is_dying = false
	_death_timer = 0.0
	_heal_accum = 0.0
	_heal_rate = 0.0
	_input_grace = 0.1
	_swing_hit_ids.clear()
	velocity = Vector2.ZERO
	modulate = Color.WHITE
	if _heal_bar_bg != null:
		_heal_bar_bg.visible = false
	if _heal_bar_fill != null:
		_heal_bar_fill.visible = false
	_play_anim("idle_down", true)


func _physics_process(delta: float) -> void:
	if not controls_enabled:
		velocity = Vector2.ZERO
		if _sprite != null and not is_dying:
			_play_anim("idle_" + facing)
		return

	_tick_timers(delta)

	if is_dying:
		velocity = Vector2.ZERO
		_death_timer -= delta
		if _death_timer <= 0.0:
			is_dying = false
			bounce_back(true, is_night_context)
		return

	# Movement input
	var move_vec: Vector2 = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if move_vec.length_squared() > 1.0:
		move_vec = move_vec.normalized()

	# Update 4-direction facing along the larger axis when not mid-swing.
	if move_vec != Vector2.ZERO and swing_timer <= 0.0:
		if absf(move_vec.x) > absf(move_vec.y):
			facing = "right" if move_vec.x > 0.0 else "left"
			last_h_facing = facing
		else:
			facing = "down" if move_vec.y > 0.0 else "up"

	velocity = move_vec * (Config.PLAYER_SPEED * speed_multiplier)
	move_and_slide()

	# Clamp feet inside the active area (Act 1 cell or full Act 2 world).
	position.x = clampf(position.x, clamp_rect.position.x + 6.0, clamp_rect.end.x - 6.0)
	position.y = clampf(position.y, clamp_rect.position.y + 16.0, clamp_rect.end.y - 4.0)

	# Actions: Swing and Bounce Back (brief grace window prevents card-confirm Space from punching)
	if _input_grace > 0.0:
		_input_grace = maxf(0.0, _input_grace - delta)
	else:
		if Input.is_action_just_pressed("swing"):
			try_start_swing()
		if Input.is_action_just_pressed("bounce"):
			bounce_back(false, is_night_context)

	# Update animation
	if swing_timer > 0.0:
		_play_anim("punch_" + facing)
	elif move_vec != Vector2.ZERO:
		_play_anim("run_" + facing)
	else:
		_play_anim("idle_" + facing)


func try_start_swing() -> bool:
	if is_dying or not controls_enabled:
		return false
	if bounce_stun_timer > 0.0 or swing_timer > 0.0 or swing_cd_timer > 0.0:
		return false
	swing_timer = Config.SWING_TIME
	swing_cd_timer = Config.SWING_COOLDOWN
	_swing_hit_ids.clear()
	_play_anim("punch_" + facing, true)
	swung.emit()
	return true


func is_swing_active() -> bool:
	return swing_timer > 0.0 and not is_dying


func has_hit_enemy(enemy_id: int) -> bool:
	return _swing_hit_ids.has(enemy_id)


func mark_enemy_hit(enemy_id: int) -> void:
	_swing_hit_ids[enemy_id] = true


func get_swing_rect() -> Rect2:
	var growth: float = 1.0 + float(bounce_bonuses) * Config.SWING_GROWTH_PER_BOUNCE
	var box_size: Vector2 = Config.SWING_BOX * growth
	var dir_vec: Vector2 = _facing_vector()
	var center: Vector2 = position + Vector2(0.0, -6.0) + dir_vec * Config.SWING_OFFSET
	return Rect2(center - box_size * 0.5, box_size)


func get_hurtbox() -> Rect2:
	return Rect2(position.x - 5.0, position.y - 13.0, 10.0, 13.0)


func take_contact_damage(amount: int) -> bool:
	if amount <= 0 or is_dying or invuln_timer > 0.0:
		return false
	hp = maxi(0, hp - amount)
	invuln_timer = Config.CONTACT_INVULN
	took_damage.emit(amount)
	if hp <= 0:
		is_dying = true
		swing_timer = 0.0
		bounce_stun_timer = 0.0
		_death_timer = 0.6
		modulate.a = 1.0
		_play_anim("death_" + last_h_facing, true)
	return true


func bounce_back(is_death: bool, is_night: bool) -> bool:
	if not is_death:
		if is_dying or bounce_cd_timer > 0.0:
			return false
		bounce_cd_timer = bounce_cd_max
	else:
		# Dying ignores the cooldown gate, but still starts cooldown if it was idle.
		if bounce_cd_timer <= 0.0:
			bounce_cd_timer = bounce_cd_max

	position = Config.HOUSE_DOOR
	velocity = Vector2.ZERO
	swing_timer = 0.0
	_swing_hit_ids.clear()
	is_dying = false

	# Heal smoothly to full over Config.BOUNCE_STUN seconds; cannot swing during this time.
	if hp <= 0:
		hp = 1
	bounce_stun_timer = Config.BOUNCE_STUN
	_heal_accum = 0.0
	_heal_rate = float(max_hp - hp) / maxf(Config.BOUNCE_STUN, 0.1)
	invuln_timer = maxf(invuln_timer, Config.CONTACT_INVULN)

	if is_night:
		bounce_bonuses = mini(bounce_bonuses + 1, Config.MAX_BOUNCE_BONUSES)

	_play_anim("idle_down", true)
	bounced.emit(is_death)
	return true


func _tick_timers(delta: float) -> void:
	if swing_timer > 0.0:
		swing_timer = maxf(0.0, swing_timer - delta)
	if swing_cd_timer > 0.0:
		swing_cd_timer = maxf(0.0, swing_cd_timer - delta)
	if bounce_cd_timer > 0.0:
		bounce_cd_timer = maxf(0.0, bounce_cd_timer - delta)

	if bounce_stun_timer > 0.0:
		bounce_stun_timer = maxf(0.0, bounce_stun_timer - delta)
		_heal_accum += _heal_rate * delta
		if _heal_accum >= 1.0:
			var whole: int = int(floor(_heal_accum))
			_heal_accum -= float(whole)
			hp = mini(max_hp, hp + whole)
		if bounce_stun_timer <= 0.0:
			hp = max_hp
			_heal_accum = 0.0
		_update_heal_bar()
	else:
		if _heal_bar_bg != null and _heal_bar_bg.visible:
			_heal_bar_bg.visible = false
			_heal_bar_fill.visible = false

	if invuln_timer > 0.0:
		invuln_timer = maxf(0.0, invuln_timer - delta)
		if not is_dying:
			var blink_on: bool = int(floor(invuln_timer * 14.0)) % 2 == 0
			modulate.a = 1.0 if blink_on else 0.35
		if invuln_timer <= 0.0:
			modulate.a = 1.0


func _update_heal_bar() -> void:
	if _heal_bar_bg == null or _heal_bar_fill == null:
		return
	_heal_bar_bg.visible = true
	_heal_bar_fill.visible = true
	var progress: float = 1.0 - (bounce_stun_timer / maxf(Config.BOUNCE_STUN, 0.1))
	_heal_bar_fill.size.x = clampf(floorf(14.0 * progress), 1.0, 14.0)


func _facing_vector() -> Vector2:
	match facing:
		"right":
			return Vector2.RIGHT
		"left":
			return Vector2.LEFT
		"up":
			return Vector2.UP
		_:
			return Vector2.DOWN


func _play_anim(anim_name: String, force_restart: bool = false) -> void:
	if _sprite == null:
		return
	if not force_restart and _current_anim == anim_name and _sprite.is_playing():
		return
	_current_anim = anim_name

	# Shift horizontal punch animations by half the width difference so the body does not jump.
	var x_shift: float = 0.0
	if anim_name == "punch_right":
		x_shift = 4.0
	elif anim_name == "punch_left":
		x_shift = -4.0

	_sprite.offset = SpriteFactory.feet_offset_for_animated("player/" + anim_name, x_shift)
	_sprite.play(anim_name)
