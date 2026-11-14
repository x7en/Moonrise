class_name Player
extends CharacterBody2D
## Player controller: 4-way movement, spear melee thrust, contact invulnerability, and Bounce Back.

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
var _damaged_during_stun: bool = false
var _input_grace: float = 0.0
var _swing_hit_ids: Dictionary = {}
var _current_anim: String = ""

var _sprite: AnimatedSprite2D = null
var _spear_sprite: Sprite2D = null
var _heal_bar_bg: ColorRect = null
var _heal_bar_fill: ColorRect = null


## Builds the player's foot collider, animated sprite, held spear sprite, and heal bar.
func _ready() -> void:
	name = "Player"
	hp = Config.PLAYER_HP
	max_hp = Config.PLAYER_HP
	bounce_cd_max = Config.BOUNCE_CD_ACT1
	clamp_rect = Config.ACT1_RECT

	# Floating motion mode gives smooth top-down sliding along house walls and trees.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1

	# Small collision box at the player's feet so movement around trees and corners feels fair.
	var collider: CollisionShape2D = CollisionShape2D.new()
	var rect_shape: RectangleShape2D = RectangleShape2D.new()
	rect_shape.size = Vector2(8.0, 6.0)
	collider.shape = rect_shape
	collider.position = Vector2(0.0, -3.0)
	add_child(collider)

	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.sprite_frames = SpriteFactory.get_player_frames(Config.SWING_TIME)
	add_child(_sprite)

	# Crisp pixel-art spear carried at the ready and thrust forward on Space.
	_spear_sprite = Sprite2D.new()
	_spear_sprite.name = "SpearSprite"
	_spear_sprite.texture = SpriteFactory.get_spear_texture()
	_spear_sprite.centered = false
	_spear_sprite.offset = Vector2(-6.0, -3.5)
	_spear_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_spear_sprite)

	# Small progress bar above the player's head while healing from Bounce Back.
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
	_update_spear_visual()


## Resets health, timers, position, and movement bounds at the start of an Act, retry, or new run.
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
	_damaged_during_stun = false
	_input_grace = 0.12
	_swing_hit_ids.clear()
	velocity = Vector2.ZERO
	modulate = Color.WHITE

	if _heal_bar_bg != null:
		_heal_bar_bg.visible = false
	if _heal_bar_fill != null:
		_heal_bar_fill.visible = false

	_play_anim("idle_down", true)
	_update_spear_visual()


## Handles movement, wall collision, spear attacks, and Bounce Back every physics frame.
func _physics_process(delta: float) -> void:
	if not controls_enabled:
		velocity = Vector2.ZERO
		if _sprite != null and not is_dying:
			_play_anim("idle_" + facing)
		_update_spear_visual()
		return

	_tick_timers(delta)

	# During the 0.6s death animation, pause movement until auto Bounce Back triggers.
	if is_dying:
		velocity = Vector2.ZERO
		_death_timer -= delta
		_update_spear_visual()
		if _death_timer <= 0.0:
			is_dying = false
			bounce_back(true, is_night_context)
		return

	# Read 4-way movement input and normalize diagonals so diagonal speed is never faster.
	var move_input: Vector2 = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if move_input.length_squared() > 1.0:
		move_input = move_input.normalized()

	# Update 4-direction facing along the stronger movement axis while not mid-thrust.
	if move_input != Vector2.ZERO and swing_timer <= 0.0:
		if absf(move_input.x) > absf(move_input.y):
			facing = "right" if move_input.x > 0.0 else "left"
			last_h_facing = facing
		else:
			facing = "down" if move_input.y > 0.0 else "up"

	velocity = move_input * (Config.PLAYER_SPEED * speed_multiplier)
	move_and_slide()

	# Keep the player inside the Act 1 center screen or the full Act 2 world map.
	position.x = clampf(position.x, clamp_rect.position.x + 6.0, clamp_rect.end.x - 6.0)
	position.y = clampf(position.y, clamp_rect.position.y + 16.0, clamp_rect.end.y - 4.0)

	# Brief grace timer stops a Space keypress on a story card from immediately swinging.
	if _input_grace > 0.0:
		_input_grace = maxf(0.0, _input_grace - delta)
	else:
		if Input.is_action_just_pressed("swing"):
			try_start_swing()
		if Input.is_action_just_pressed("bounce"):
			bounce_back(false, is_night_context)

	if swing_timer > 0.0:
		_play_anim("punch_" + facing)
	elif move_input != Vector2.ZERO:
		_play_anim("run_" + facing)
	else:
		_play_anim("idle_" + facing)

	_update_spear_visual()


## Starts a spear melee thrust on Space if not dying, stunned, or on cooldown.
func try_start_swing() -> bool:
	if is_dying or not controls_enabled:
		return false
	if bounce_stun_timer > 0.0 or swing_timer > 0.0 or swing_cd_timer > 0.0:
		return false

	swing_timer = Config.SWING_TIME
	swing_cd_timer = Config.SWING_COOLDOWN
	_swing_hit_ids.clear()
	_play_anim("punch_" + facing, true)
	_update_spear_visual()
	swung.emit()
	return true


## Returns true while the spear hitbox is active and able to strike enemies.
func is_swing_active() -> bool:
	return swing_timer > 0.0 and not is_dying


## Tracks which enemies were already hit during this thrust so each takes at most 1 hit per swing.
func has_hit_enemy(enemy_id: int) -> bool:
	return _swing_hit_ids.has(enemy_id)


func mark_enemy_hit(enemy_id: int) -> void:
	_swing_hit_ids[enemy_id] = true


## Computes the directional spear hitbox in front of the player (longer reach + wider sweep).
func get_swing_rect() -> Rect2:
	var growth: float = 1.0 + float(bounce_bonuses) * Config.SWING_GROWTH_PER_BOUNCE
	var box_size: Vector2 = Config.SWING_BOX * growth

	# Swap width and height when thrusting up or down so the spear always reaches farthest forward.
	if facing == "up" or facing == "down":
		box_size = Vector2(Config.SWING_BOX.y, Config.SWING_BOX.x) * growth

	var dir_vec: Vector2 = _facing_vector()
	var center: Vector2 = position + Vector2(0.0, -7.0) + dir_vec * Config.SWING_OFFSET
	return Rect2(center - box_size * 0.5, box_size)


## Returns the player's body hurtbox used to detect enemy contact damage.
func get_hurtbox() -> Rect2:
	return Rect2(position.x - 5.0, position.y - 13.0, 10.0, 13.0)


## Applies contact damage from a touching enemy and triggers auto Bounce Back if HP hits 0.
func take_contact_damage(amount: int) -> bool:
	if amount <= 0 or is_dying or invuln_timer > 0.0:
		return false

	hp = maxi(0, hp - amount)
	invuln_timer = Config.CONTACT_INVULN
	if bounce_stun_timer > 0.0:
		_damaged_during_stun = true
	took_damage.emit(amount)

	if hp <= 0:
		is_dying = true
		swing_timer = 0.0
		bounce_stun_timer = 0.0
		_death_timer = 0.6
		modulate.a = 1.0
		_play_anim("death_" + last_h_facing, true)
		_update_spear_visual()

	return true


## Teleports the player home to the farmhouse front door gap, heals over 5 s, and locks attacks.
func bounce_back(is_death: bool, is_night: bool) -> bool:
	if not is_death:
		if is_dying or bounce_cd_timer > 0.0:
			return false
		bounce_cd_timer = bounce_cd_max
	else:
		# Dying bypasses an active cooldown, but starts one if it was idle.
		if bounce_cd_timer <= 0.0:
			bounce_cd_timer = bounce_cd_max

	position = Config.HOUSE_DOOR
	velocity = Vector2.ZERO
	swing_timer = 0.0
	_swing_hit_ids.clear()
	is_dying = false

	# Smoothly regenerate to full HP over Config.BOUNCE_STUN seconds.
	if hp <= 0:
		hp = 1
	bounce_stun_timer = Config.BOUNCE_STUN
	_heal_accum = 0.0
	_damaged_during_stun = false
	_heal_rate = float(max_hp - hp) / maxf(Config.BOUNCE_STUN, 0.1)
	invuln_timer = maxf(invuln_timer, Config.CONTACT_INVULN)

	# Each Bounce Back during a night boosts spear reach/width by 15% (up to 3 stacks).
	if is_night:
		bounce_bonuses = mini(bounce_bonuses + 1, Config.MAX_BOUNCE_BONUSES)

	_play_anim("idle_down", true)
	_update_spear_visual()
	bounced.emit(is_death)
	return true


## Cancels an in-progress death animation at sunrise so you never die into peaceful Dawn/Day.
func recover_at_sunrise() -> void:
	if not is_dying:
		return
	is_dying = false
	_death_timer = 0.0
	hp = maxi(hp, 10)
	modulate = Color.WHITE
	_play_anim("idle_" + facing, true)
	_update_spear_visual()


## Updates all active player cooldowns, healing progress, and invulnerability blink.
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
			var whole_hp: int = int(floor(_heal_accum))
			_heal_accum -= float(whole_hp)
			hp = mini(max_hp, hp + whole_hp)
		if bounce_stun_timer <= 0.0:
			if not _damaged_during_stun:
				hp = max_hp
			_heal_accum = 0.0
			_damaged_during_stun = false
		_update_heal_bar()
	else:
		if _heal_bar_bg != null and _heal_bar_bg.visible:
			_heal_bar_bg.visible = false
			_heal_bar_fill.visible = false

	# Blink sprite opacity during post-hit invulnerability frames.
	if invuln_timer > 0.0:
		invuln_timer = maxf(0.0, invuln_timer - delta)
		if not is_dying:
			var blink_on: bool = int(floor(invuln_timer * 14.0)) % 2 == 0
			modulate.a = 1.0 if blink_on else 0.35
		if invuln_timer <= 0.0:
			modulate.a = 1.0


## Refreshes the tiny healing bar above the player during the 5-second Bounce Back recovery.
func _update_heal_bar() -> void:
	if _heal_bar_bg == null or _heal_bar_fill == null:
		return
	_heal_bar_bg.visible = true
	_heal_bar_fill.visible = true
	var progress: float = 1.0 - (bounce_stun_timer / maxf(Config.BOUNCE_STUN, 0.1))
	_heal_bar_fill.size.x = clampf(floorf(14.0 * progress), 1.0, 14.0)


## Positions and rotates the spear sprite so it rests at the player's side and lunges on Space.
func _update_spear_visual() -> void:
	if _spear_sprite == null:
		return

	# Hide the spear while dying or while attacks are locked during Bounce Back healing.
	if is_dying or bounce_stun_timer > 0.0:
		_spear_sprite.visible = false
		return

	_spear_sprite.visible = true
	var dir_vec: Vector2 = _facing_vector()
	var base_hand: Vector2 = Vector2(0.0, -7.0)
	var thrust_dist: float = 0.0

	if swing_timer > 0.0:
		# Quick forward thrust peaking mid-swing, matching the extended spear hitbox.
		var swing_t: float = 1.0 - (swing_timer / maxf(Config.SWING_TIME, 0.05))
		var thrust_curve: float = sin(clampf(swing_t, 0.0, 1.0) * PI)
		var bonus_scale: float = 1.0 + float(bounce_bonuses) * Config.SWING_GROWTH_PER_BOUNCE
		thrust_dist = 15.0 * thrust_curve * bonus_scale
		_spear_sprite.scale = Vector2(bonus_scale, 1.0)
	else:
		# Subtle idle hold tucked near the body.
		thrust_dist = -2.0
		_spear_sprite.scale = Vector2.ONE

	# Draw the spear behind the player when facing up, and in front for all other directions.
	_spear_sprite.z_index = -1 if facing == "up" else 1
	_spear_sprite.rotation = dir_vec.angle()
	_spear_sprite.position = base_hand + dir_vec * (4.0 + thrust_dist)


## Converts the 4-way facing string into a unit Vector2.
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


## Switches the player's AnimatedSprite2D and updates feet-origin offset to prevent jitter.
func _play_anim(anim_name: String, force_restart: bool = false) -> void:
	if _sprite == null:
		return
	if not force_restart and _current_anim == anim_name and _sprite.is_playing():
		return
	_current_anim = anim_name

	# Shift wide horizontal attack strips so the character's torso stays aligned with idle frames.
	var x_shift: float = 0.0
	if anim_name == "punch_right":
		x_shift = 4.0
	elif anim_name == "punch_left":
		x_shift = -4.0

	_sprite.offset = SpriteFactory.feet_offset_for_animated("player/" + anim_name, x_shift)
	_sprite.play(anim_name)
