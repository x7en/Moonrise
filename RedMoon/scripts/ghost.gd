class_name Ghost
extends Node2D

# spectral zombie ghost (Act 2 / Day 4+ only): materialize -> drift -> slash -> dissolve
# implements the same target interface as Enemy so weapons & phase-2 boomerang hit both cleanly

signal player_damaged(damage: int, ghost: Node)
signal killed(ghost: Node, was_bow: bool)
signal damaged_feedback(pos: Vector2, is_kill: bool)
signal slash_started(pos: Vector2)

enum State { MATERIALIZE, DRIFT, ATTACK, DISSOLVE }

var variant: String = "scythe"
var hp: int = Config.GHOST_HP
var max_hp: int = Config.GHOST_HP
var speed: float = Config.GHOST_SPEED_SCYTHE
var state: State = State.MATERIALIZE

var _sprite: AnimatedSprite2D
var _shadow: Sprite2D
var _hp_holder: Node2D
var _hp_fill: ColorRect
var _facing_right: bool = false
var _damage_cd: float = 0.0
var _hit_this_swing: bool = false
var _life_timer: float = 0.0
var _indoors_wait: float = 0.0
var _flash_timer: float = 0.0
var _stun_timer: float = 0.0
var _bob_time: float = 0.0
var _was_bow_kill: bool = false
var _attack_range: float = 34.0
var _slash_reach: float = 40.0


func setup(spawn_pos: Vector2, ghost_variant: String = "scythe") -> void:
	variant = "lunge" if ghost_variant == "lunge" else "scythe"
	position = spawn_pos.round()
	max_hp = Config.GHOST_HP
	hp = max_hp
	speed = Config.GHOST_SPEED_LUNGE if variant == "lunge" else Config.GHOST_SPEED_SCYTHE
	_attack_range = 44.0 if variant == "lunge" else 34.0
	_slash_reach = 56.0 if variant == "lunge" else 42.0
	state = State.MATERIALIZE
	_life_timer = Config.GHOST_LIFETIME
	z_index = 2
	add_to_group("ghosts")
	add_to_group("hostiles")

	_shadow = get_node("Shadow") as Sprite2D
	_shadow.texture = Art.get_blob_shadow(12, 5)

	_sprite = get_node("Sprite") as AnimatedSprite2D
	_sprite.scale = Vector2(Config.GHOST_SCALE, Config.GHOST_SCALE)
	_sprite.sprite_frames = Art.get_ghost_frames(variant)
	_apply_facing_offset(false)
	if not _sprite.animation_finished.is_connected(_on_anim_finished):
		_sprite.animation_finished.connect(_on_anim_finished)
	_sprite.play(&"materialize")

	_hp_holder = get_node("HpBar") as Node2D
	_hp_holder.visible = false
	_hp_fill = get_node("HpBar/Fill") as ColorRect
	_hp_fill.size.x = 12.0


func is_alive() -> bool:
	return hp > 0 and state != State.DISSOLVE


func get_hurtbox_rect() -> Rect2:
	return Rect2(position + Vector2(-9.0, -22.0), Vector2(18.0, 22.0))


func apply_stun(duration: float) -> void:
	if not is_alive():
		return
	_stun_timer = maxf(_stun_timer, minf(duration, 2.5))
	if _sprite != null:
		_sprite.modulate = Color(0.75, 0.95, 1.0, 0.90)


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

	if push_dir.length_squared() > 0.001:
		position += push_dir.normalized() * (6.0 if from_bow else 10.0)
		position.x = clampf(position.x, 12.0, Config.WORLD_SIZE.x - 12.0)
		position.y = clampf(position.y, 12.0, Config.WORLD_SIZE.y - 12.0)

	if hp <= 0:
		damaged_feedback.emit(position + Vector2(0.0, -10.0), true)
		killed.emit(self, _was_bow_kill)
		start_dissolve()
		return true

	damaged_feedback.emit(position + Vector2(0.0, -10.0), false)
	return false


func start_dissolve() -> void:
	if state == State.DISSOLVE:
		return
	state = State.DISSOLVE
	_stun_timer = 0.0
	_flash_timer = 0.0
	if _hp_holder != null:
		_hp_holder.visible = false
	if _sprite != null:
		_sprite.modulate = Color(1.0, 1.0, 1.0, 0.92)
		_sprite.play(&"dissolve")


func step_ghost(
	delta: float,
	player_pos: Vector2,
	player_inside: bool,
	world_bounds: Rect2
) -> void:
	_bob_time += delta
	if _damage_cd > 0.0:
		_damage_cd = maxf(0.0, _damage_cd - delta)
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		if _flash_timer <= 0.0 and _sprite != null:
			_sprite.modulate = Color(0.75, 0.95, 1.0, 0.90) if _stun_timer > 0.0 else Color.WHITE
	if _stun_timer > 0.0:
		_stun_timer = maxf(0.0, _stun_timer - delta)
		if _stun_timer <= 0.0 and _sprite != null:
			_sprite.modulate = Color.WHITE
		return

	match state:
		State.DISSOLVE:
			if _sprite != null:
				_sprite.modulate.a = maxf(0.0, _sprite.modulate.a - delta * 3.5)
			if _shadow != null:
				_shadow.modulate.a = maxf(0.0, _shadow.modulate.a - delta * 2.0)
		State.MATERIALIZE:
			if _sprite != null:
				_sprite.position.y = sin(_bob_time * 3.8) * 2.5
			_apply_facing_offset(player_pos.x >= position.x)
		State.ATTACK:
			if _sprite != null:
				_sprite.position.y = sin(_bob_time * 3.8) * 2.5
			_check_slash_hit_window(player_pos, player_inside)
		State.DRIFT:
			if _sprite != null:
				_sprite.position.y = sin(_bob_time * 3.8) * 2.5
			_step_drift(delta, player_pos, player_inside, world_bounds)


func _step_drift(
	delta: float,
	player_pos: Vector2,
	player_inside: bool,
	world_bounds: Rect2
) -> void:
	_life_timer -= delta
	if _life_timer <= 0.0:
		start_dissolve()
		return

	if player_inside:
		_indoors_wait += delta
		if _indoors_wait >= 2.5:
			start_dissolve()
		return
	_indoors_wait = 0.0

	var to_p := player_pos - position
	var dist := to_p.length()
	_apply_facing_offset(to_p.x >= 0.0)
	if dist <= _attack_range and _damage_cd <= 0.0:
		state = State.ATTACK
		_hit_this_swing = false
		if _sprite != null:
			_sprite.play(&"attack")
		slash_started.emit(position)
		return

	if dist > 4.0:
		position += (to_p / dist) * speed * delta
		position.x = clampf(position.x, world_bounds.position.x + 12.0, world_bounds.end.x - 12.0)
		position.y = clampf(position.y, world_bounds.position.y + 12.0, world_bounds.end.y - 12.0)


func _check_slash_hit_window(player_pos: Vector2, player_inside: bool) -> void:
	if _hit_this_swing or _damage_cd > 0.0 or player_inside or _sprite == null:
		return
	# attack animation frames [1, 2] match strip frames 6-7 (scythe) & 5-6 (lunge)
	var cur_frame := _sprite.frame
	if cur_frame != 1 and cur_frame != 2:
		return
	var reach_x := _slash_reach
	var hit_rect := (
		Rect2(position + Vector2(-4.0, -24.0), Vector2(reach_x, 32.0))
		if _facing_right
		else Rect2(position + Vector2(-reach_x + 4.0, -24.0), Vector2(reach_x, 32.0))
	)
	if hit_rect.has_point(player_pos + Vector2(0.0, -6.0)):
		_hit_this_swing = true
		_damage_cd = Config.GHOST_DAMAGE_COOLDOWN
		player_damaged.emit(Config.GHOST_DAMAGE, self)


func _apply_facing_offset(face_right: bool) -> void:
	_facing_right = face_right
	if _sprite == null:
		return
	_sprite.flip_h = face_right
	# mirrored cell anchors keep the ghost body pinned at (0, -12) when flipping left/right
	if variant == "lunge":
		_sprite.offset = Vector2(-24.0 if face_right else -96.0, -28.0)
	else:
		_sprite.offset = Vector2(-30.0 if face_right else -50.0, -38.0)


func _on_anim_finished() -> void:
	if state == State.MATERIALIZE:
		state = State.DRIFT
		if _sprite != null:
			_sprite.play(&"drift")
	elif state == State.ATTACK:
		start_dissolve()
	elif state == State.DISSOLVE:
		remove_from_group("ghosts")
		remove_from_group("hostiles")
		queue_free()
