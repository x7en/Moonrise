class_name Enemy
extends Node2D
## Unified enemy class driven by Config.ENEMY_TYPES (zombie, raider, brute).

signal struck_structure(enemy: Enemy, structure: Structure, damage: int)

enum State { WALK, ATTACK, DYING, DISSOLVING }

var enemy_type: String = "zombie"
var hits_left: int = 2
var speed: float = 33.0
var struct_dmg: int = 10
var player_dmg: int = 10
var base_tint: Color = Color.WHITE

var facing: String = "down"
var last_h_facing: String = "right"
var state: State = State.WALK
var target: Structure = null

var _kb_timer: float = 0.0
var _kb_velocity: Vector2 = Vector2.ZERO
var _flash_timer: float = 0.0
var _attack_timer: float = 0.0
var _death_timer: float = 0.0
var _current_anim: String = ""
var _sprite: AnimatedSprite2D = null
var _dissolve_tween: Tween = null


func setup(p_type: String, spawn_pos: Vector2, structures: Array) -> void:
	enemy_type = p_type if Config.ENEMY_TYPES.has(p_type) else "zombie"
	position = spawn_pos
	add_to_group("enemies")

	var data: Dictionary = Config.ENEMY_TYPES[enemy_type] as Dictionary
	hits_left = int(data["hits"])
	speed = float(data["speed"])
	struct_dmg = int(data["struct_dmg"])
	player_dmg = int(data["player_dmg"])
	base_tint = data["tint"] as Color

	_build_sprite()
	_pick_nearest_target(structures)


func is_active_threat() -> bool:
	return state == State.WALK


func get_hurtbox() -> Rect2:
	return Rect2(position.x - 5.0, position.y - 14.0, 10.0, 14.0)


func step(delta: float, structures: Array) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		if _flash_timer <= 0.0 and state != State.DISSOLVING:
			modulate = base_tint

	match state:
		State.WALK:
			_step_walk(delta, structures)
		State.ATTACK:
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				queue_free()
		State.DYING:
			_death_timer -= delta
			if _death_timer <= 0.0:
				queue_free()
		State.DISSOLVING:
			pass


func apply_hit(from_pos: Vector2) -> bool:
	if state != State.WALK:
		return false

	hits_left -= 1
	if hits_left > 0:
		var push_dir: Vector2 = position - from_pos
		if push_dir.length_squared() < 0.001:
			push_dir = Vector2.RIGHT
		else:
			push_dir = push_dir.normalized()
		_kb_timer = 0.15
		_kb_velocity = push_dir * (Config.KNOCKBACK / 0.15)
		_flash_timer = 0.12
		modulate = Color(1.8, 1.8, 1.8, 1.0)
		return false

	state = State.DYING
	_death_timer = 0.5
	_kb_timer = 0.0
	modulate = base_tint
	_play_anim("death_" + last_h_facing, true)
	return true


func dissolve() -> void:
	if state == State.DISSOLVING or state == State.DYING:
		return
	state = State.DISSOLVING
	if _dissolve_tween != null and _dissolve_tween.is_valid():
		_dissolve_tween.kill()
	_dissolve_tween = create_tween()
	_dissolve_tween.tween_property(self, "modulate:a", 0.0, 0.45)
	_dissolve_tween.tween_callback(queue_free)


func _step_walk(delta: float, structures: Array) -> void:
	if _kb_timer > 0.0:
		var kb_step: float = minf(delta, _kb_timer)
		position += _kb_velocity * kb_step
		_kb_timer = maxf(0.0, _kb_timer - delta)
		return

	if target == null or not is_instance_valid(target) or not target.is_standing():
		_pick_nearest_target(structures)
		if target == null:
			return

	var goal: Vector2 = target.get_target_point()
	var to_goal: Vector2 = goal - position
	var dist: float = to_goal.length()
	if dist <= target.reach:
		_begin_structure_attack()
		return

	var vel: Vector2 = (to_goal / maxf(dist, 0.001)) * speed
	position += vel * delta
	_update_facing(vel)
	_play_anim("walk_" + facing)


func _begin_structure_attack() -> void:
	state = State.ATTACK
	_attack_timer = 0.3
	if target != null and is_instance_valid(target):
		var to_goal: Vector2 = target.get_target_point() - position
		if to_goal.length_squared() > 0.001:
			_update_facing(to_goal)
		struck_structure.emit(self, target, struct_dmg)
	_play_anim("attack_" + facing, true)


func _pick_nearest_target(structures: Array) -> void:
	var best: Structure = null
	var best_dist_sq: float = INF
	for item in structures:
		var s: Structure = item as Structure
		if s == null or not is_instance_valid(s) or not s.is_standing():
			continue
		var d_sq: float = position.distance_squared_to(s.get_target_point())
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = s
	target = best
	if target != null:
		_update_facing(target.get_target_point() - position)
		_play_anim("walk_" + facing)


func _update_facing(vec: Vector2) -> void:
	if absf(vec.x) > absf(vec.y):
		facing = "right" if vec.x >= 0.0 else "left"
		last_h_facing = facing
	else:
		facing = "down" if vec.y >= 0.0 else "up"


func _build_sprite() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.sprite_frames = SpriteFactory.get_enemy_frames(enemy_type)
	modulate = base_tint
	add_child(_sprite)
	_play_anim("walk_down", true)


func _play_anim(anim_name: String, force_restart: bool = false) -> void:
	if _sprite == null:
		return
	if not force_restart and _current_anim == anim_name and _sprite.is_playing():
		return
	_current_anim = anim_name

	var x_shift: float = 0.0
	if enemy_type == "raider":
		if anim_name == "attack_right":
			x_shift = 2.0
		elif anim_name == "attack_left":
			x_shift = -2.0

	var key: String = "enemies/%s/%s" % [enemy_type, anim_name]
	_sprite.offset = SpriteFactory.feet_offset_for_animated(key, x_shift)
	_sprite.play(anim_name)
