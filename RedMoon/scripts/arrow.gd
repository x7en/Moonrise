class_name Arrow
extends Node2D

signal hit_enemy(enemy: Node2D, arrow: Arrow, from_player: bool)

var velocity: Vector2 = Vector2.ZERO
var damage: int = 1
var pierce_left: int = 0
var range_left: float = 150.0
var from_player: bool = true
var hit_ids: Dictionary = {}

var _sprite: Sprite2D
var _dead: bool = false


func setup(
	start_pos: Vector2,
	direction: Vector2,
	speed: float,
	dmg: int,
	max_range: float,
	pierce: int = 0,
	by_player: bool = true
) -> void:
	position = start_pos
	var dir_n := (
		direction.normalized() if direction.length_squared() > 0.001 else Vector2.RIGHT
	)
	velocity = dir_n * speed
	damage = dmg
	pierce_left = pierce
	range_left = max_range
	from_player = by_player
	rotation = dir_n.angle()
	add_to_group("arrows")

	_sprite = Sprite2D.new()
	_sprite.texture = Art.tex("weapons/arrow_pierce" if pierce > 0 else "weapons/arrow")
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func step_arrow(delta: float, enemies: Array, world_bounds: Rect2) -> void:
	if _dead:
		return

	var step_vec := velocity * delta
	position += step_vec
	range_left -= step_vec.length()

	if range_left <= 0.0 or not world_bounds.has_point(position):
		_die()
		return

	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue

		var eid = enemy.get_instance_id()
		if hit_ids.has(eid):
			continue

		# grow hurtbox by 3px so fast arrows dont feel stingy
		var hurt_rect = enemy.get_hurtbox_rect()
		if hurt_rect.grow(3.0).has_point(position):
			hit_ids[eid] = true
			hit_enemy.emit(enemy, self, from_player)
			if pierce_left > 0:
				pierce_left -= 1
			else:
				_die()
				return


func _die() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("arrows")
	queue_free()
