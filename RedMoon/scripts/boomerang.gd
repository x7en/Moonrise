class_name Boomerang
extends Node2D

# reusable bounce-back thrown weapon projectile (used by player; boss-ready via owner_node/targets)

signal hit_target(target: Node, boomerang: Boomerang, is_return_leg: bool)
signal bounced(pos: Vector2, hit_enemy: bool)
signal caught(boomerang: Boomerang)

enum Leg { OUTBOUND, RETURN }

var owner_node: Node2D
var leg: Leg = Leg.OUTBOUND
var velocity: Vector2 = Vector2.ZERO
var outbound_speed: float = Config.BOOMERANG_SPEED
var return_speed: float = Config.BOOMERANG_RETURN_SPEED
var range_left: float = Config.BOOMERANG_RANGE
var damage: int = Config.BOOMERANG_DAMAGE
var hit_radius: float = Config.BOOMERANG_HIT_RADIUS
var spin_speed: float = Config.BOOMERANG_SPIN_SPEED
var from_player: bool = true

var _sprite: Sprite2D
var _shadow: Sprite2D
var _fallback_return_pos: Vector2 = Vector2.ZERO
var _hit_outbound_ids: Dictionary = {}
var _hit_return_ids: Dictionary = {}
var _bounce_grace_id: int = -1
var _bounce_grace_timer: float = 0.0
var _return_elapsed: float = 0.0
var _finished: bool = false


func setup(
	thrower: Node2D,
	origin: Vector2,
	aim_dir: Vector2,
	dmg: int = Config.BOOMERANG_DAMAGE,
	max_range: float = Config.BOOMERANG_RANGE,
	is_from_player: bool = true,
	tex_key: String = "placeholders/boomerang_placeholder"
) -> void:
	owner_node = thrower
	position = origin
	_fallback_return_pos = origin
	from_player = is_from_player
	damage = dmg
	range_left = max_range
	outbound_speed = Config.BOOMERANG_SPEED
	return_speed = Config.BOOMERANG_RETURN_SPEED
	hit_radius = Config.BOOMERANG_HIT_RADIUS
	spin_speed = Config.BOOMERANG_SPIN_SPEED

	var d := aim_dir.normalized() if aim_dir.length_squared() > 0.0001 else Vector2.RIGHT
	velocity = d * outbound_speed
	leg = Leg.OUTBOUND
	z_index = 4
	add_to_group("boomerangs")

	_shadow = Sprite2D.new()
	_shadow.texture = Art.get_blob_shadow(12, 4)
	_shadow.position = Vector2(0.0, 7.0)
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_shadow)

	_sprite = Sprite2D.new()
	_sprite.texture = Art.tex(tex_key)
	_sprite.centered = true
	_sprite.scale = Vector2(0.72, 0.72)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func is_active() -> bool:
	return not _finished


func step_boomerang(delta: float, targets: Array, world_bounds: Rect2) -> void:
	if _finished:
		return

	if _sprite != null:
		_sprite.rotation += spin_speed * delta
	if _bounce_grace_timer > 0.0:
		_bounce_grace_timer = maxf(0.0, _bounce_grace_timer - delta)

	if leg == Leg.OUTBOUND:
		_step_outbound(delta, targets, world_bounds)
	else:
		_step_return(delta, targets)


func _step_outbound(delta: float, targets: Array, world_bounds: Rect2) -> void:
	var step_vec := velocity * delta
	position += step_vec
	range_left -= step_vec.length()

	for t in targets:
		if not _can_hit_target(t, _hit_outbound_ids):
			continue
		if _overlaps_target(t):
			var tid := t.get_instance_id()
			_hit_outbound_ids[tid] = true
			_bounce_grace_id = tid
			_bounce_grace_timer = 0.18
			hit_target.emit(t, self, false)
			_begin_return(true)
			return

	if range_left <= 0.0 or not world_bounds.has_point(position):
		position.x = clampf(position.x, world_bounds.position.x + 4.0, world_bounds.end.x - 4.0)
		position.y = clampf(position.y, world_bounds.position.y + 4.0, world_bounds.end.y - 4.0)
		_begin_return(false)


func _step_return(delta: float, targets: Array) -> void:
	_return_elapsed += delta
	var catch_pos := _get_catch_point()
	var to_owner := catch_pos - position
	var dist := to_owner.length()
	var step_dist := return_speed * delta

	if dist <= maxf(12.0, step_dist) or _return_elapsed >= 4.0:
		position = catch_pos
		_finish_catch()
		return

	velocity = (to_owner / dist) * return_speed
	position += velocity * delta

	for t in targets:
		if not _can_hit_target(t, _hit_return_ids):
			continue
		var tid := t.get_instance_id()
		if tid == _bounce_grace_id and _bounce_grace_timer > 0.0:
			continue
		if _overlaps_target(t):
			_hit_return_ids[tid] = true
			hit_target.emit(t, self, true)


func _begin_return(hit_enemy: bool) -> void:
	if leg == Leg.RETURN:
		return
	leg = Leg.RETURN
	_return_elapsed = 0.0
	bounced.emit(position, hit_enemy)


func _get_catch_point() -> Vector2:
	if is_instance_valid(owner_node):
		if owner_node is Player and owner_node.inside_house:
			return Config.HOUSE_DOOR
		return owner_node.position + Vector2(0.0, -8.0)
	return _fallback_return_pos


func _can_hit_target(t: Variant, seen: Dictionary) -> bool:
	if not is_instance_valid(t) or not (t is Node2D):
		return false
	if t == owner_node or t is Dog:
		return false
	if from_player and t is Player:
		return false
	if not t.has_method("is_alive") or not t.is_alive():
		return false
	if not t.has_method("get_hurtbox_rect"):
		return false
	return not seen.has(t.get_instance_id())


func _overlaps_target(t: Node2D) -> bool:
	var hurt_rect: Rect2 = t.get_hurtbox_rect()
	return hurt_rect.grow(hit_radius * 0.5).has_point(position)


func _finish_catch() -> void:
	if _finished:
		return
	_finished = true
	remove_from_group("boomerangs")
	caught.emit(self)
	queue_free()
