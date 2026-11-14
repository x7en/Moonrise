class_name Enemy
extends Node2D
## Unified enemy controller driven by Config.ENEMY_TYPES (zombie, raider, or brute).
## Walks toward the nearest standing structure, never overlaps the house, and attacks on arrival.

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


## Initializes stats, sprite animations, and picks the nearest standing structure as target.
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


## Returns true while this enemy is alive and able to hurt the player or be hit.
func is_active_threat() -> bool:
	return state == State.WALK


## Returns the enemy's simple rectangle hurtbox for melee spear and contact checks.
func get_hurtbox() -> Rect2:
	return Rect2(position.x - 5.0, position.y - 14.0, 10.0, 14.0)


## Advances movement, knockback, attack finish, or death timers each frame.
func step(delta: float, structures: Array, house_blocker: Rect2) -> void:
	# End the brief white hit-flash once its timer runs out.
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		if _flash_timer <= 0.0 and state != State.DISSOLVING:
			modulate = base_tint

	match state:
		State.WALK:
			_step_walk(delta, structures, house_blocker)
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


## Applies one melee hit from the player's spear. Returns true if this hit killed the enemy.
func apply_hit(from_pos: Vector2) -> bool:
	if state != State.WALK:
		return false

	hits_left -= 1
	if hits_left > 0:
		# Push the surviving enemy away from the player over 0.15 seconds.
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

	# Final hit: play the death animation and free this enemy after 0.5 seconds.
	state = State.DYING
	_death_timer = 0.5
	_kb_timer = 0.0
	modulate = base_tint
	_play_anim("death_" + last_h_facing, true)
	return true


## Fades out remaining enemies at sunrise when the night timer reaches zero.
func dissolve() -> void:
	if state == State.DISSOLVING or state == State.DYING:
		return
	state = State.DISSOLVING
	if _dissolve_tween != null and _dissolve_tween.is_valid():
		_dissolve_tween.kill()
	_dissolve_tween = create_tween()
	_dissolve_tween.tween_property(self, "modulate:a", 0.0, 0.45)
	_dissolve_tween.tween_callback(queue_free)


## Moves the enemy toward its target while strictly blocking it from overlapping the house.
func _step_walk(delta: float, structures: Array, house_blocker: Rect2) -> void:
	# If knocked back by the player's spear, slide back and still respect the house walls.
	if _kb_timer > 0.0:
		var kb_step: float = minf(delta, _kb_timer)
		position += _kb_velocity * kb_step
		_push_outside_house(house_blocker)
		_kb_timer = maxf(0.0, _kb_timer - delta)
		return

	# Pick a new nearest standing structure if our previous target was destroyed.
	if target == null or not is_instance_valid(target) or not target.is_standing():
		_pick_nearest_target(structures)
		if target == null:
			return

	# Check reach BEFORE stepping so the enemy stops strictly at the structure's outer edge.
	if target.is_within_attack_reach(position):
		_begin_structure_attack()
		return

	var goal: Vector2 = target.get_target_point()
	var to_goal: Vector2 = goal - position
	var distance: float = to_goal.length()
	var move_velocity: Vector2 = (to_goal / maxf(distance, 0.001)) * speed
	position += move_velocity * delta

	# Never let any enemy enter or walk through the house sprite.
	var hit_house_wall: bool = _push_outside_house(house_blocker)
	# If an enemy aiming for a fence ran into the house wall, re-pick the nearest target (house).
	if hit_house_wall and target.kind != Structure.Kind.HOUSE:
		_pick_nearest_target(structures)
		if target == null:
			return

	# Re-check reach right after clamping to the house edge so enemies attack immediately on touch.
	if target.is_within_attack_reach(position):
		_begin_structure_attack()
		return

	_update_facing(move_velocity)
	_play_anim("walk_" + facing)


## Keeps this enemy strictly outside the solid house rectangle by clamping to the nearest edge.
## Returns true if clamping was needed, preventing walk-throughs and corner stalls.
func _push_outside_house(house_blocker: Rect2) -> bool:
	if not house_blocker.has_point(position):
		return false

	var dist_left: float = absf(position.x - house_blocker.position.x)
	var dist_right: float = absf(house_blocker.end.x - position.x)
	var dist_top: float = absf(position.y - house_blocker.position.y)
	var dist_bottom: float = absf(house_blocker.end.y - position.y)

	var min_dist: float = minf(minf(dist_left, dist_right), minf(dist_top, dist_bottom))
	if min_dist == dist_left:
		position.x = house_blocker.position.x - 0.5
	elif min_dist == dist_right:
		position.x = house_blocker.end.x + 0.5
	elif min_dist == dist_top:
		position.y = house_blocker.position.y - 0.5
	else:
		position.y = house_blocker.end.y + 0.5
	return true


## Triggers a one-shot attack against the target structure, then removes the enemy after 0.3 s.
func _begin_structure_attack() -> void:
	state = State.ATTACK
	_attack_timer = 0.3
	if target != null and is_instance_valid(target):
		var to_goal: Vector2 = target.get_target_point() - position
		if to_goal.length_squared() > 0.001:
			_update_facing(to_goal)
		struck_structure.emit(self, target, struct_dmg)
	_play_anim("attack_" + facing, true)


## Finds the closest standing structure (fence or house) to the enemy's current position.
func _pick_nearest_target(structures: Array) -> void:
	var best: Structure = null
	var best_dist_sq: float = INF

	for item in structures:
		var struct_node: Structure = item as Structure
		if struct_node == null or not is_instance_valid(struct_node):
			continue
		if not struct_node.is_standing():
			continue

		var dist_sq: float = position.distance_squared_to(struct_node.get_target_point())
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = struct_node

	target = best
	if target != null:
		_update_facing(target.get_target_point() - position)
		_play_anim("walk_" + facing)


## Faces along whichever axis (horizontal or vertical) the enemy is moving faster on.
func _update_facing(move_vec: Vector2) -> void:
	if absf(move_vec.x) > absf(move_vec.y):
		facing = "right" if move_vec.x >= 0.0 else "left"
		last_h_facing = facing
	else:
		facing = "down" if move_vec.y >= 0.0 else "up"


## Creates the AnimatedSprite2D child using SpriteFactory's cached SpriteFrames.
func _build_sprite() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.sprite_frames = SpriteFactory.get_enemy_frames(enemy_type)
	modulate = base_tint
	add_child(_sprite)
	_play_anim("walk_down", true)


## Plays an animation and re-centers its feet offset every time the animation changes.
func _play_anim(anim_name: String, force_restart: bool = false) -> void:
	if _sprite == null:
		return
	if not force_restart and _current_anim == anim_name and _sprite.is_playing():
		return
	_current_anim = anim_name

	# Keep the raider body steady during wide left/right axe swings.
	var x_shift: float = 0.0
	if enemy_type == "raider":
		if anim_name == "attack_right":
			x_shift = 2.0
		elif anim_name == "attack_left":
			x_shift = -2.0

	var key: String = "enemies/%s/%s" % [enemy_type, anim_name]
	_sprite.offset = SpriteFactory.feet_offset_for_animated(key, x_shift)
	_sprite.play(anim_name)
