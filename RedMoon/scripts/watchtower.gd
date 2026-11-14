class_name Watchtower
extends Node2D
## Automated defensive archer tower (T2.2). Max 2 placed near the farmhouse.

signal fire_requested(origin: Vector2, target: Node)
signal destroyed(tower: Watchtower)

var hp: int = 40
var max_hp: int = 40
var attack_range: float = 120.0
var fire_timer: float = 0.0
var footprint_rect: Rect2 = Rect2()

var _sprite: Sprite2D = null
var _hp_fill: ColorRect = null
var _hp_holder: Node2D = null


func setup(world_pos: Vector2) -> void:
	position = world_pos.round()
	max_hp = Config.WATCHTOWER_HP
	hp = max_hp
	attack_range = Config.WATCHTOWER_RANGE
	footprint_rect = Rect2(position - Vector2(10.0, 14.0), Vector2(20.0, 18.0))
	add_to_group("watchtowers")

	var shadow: Sprite2D = Sprite2D.new()
	shadow.texture = SpriteFactory.get_blob_shadow(22, 8)
	shadow.position = Vector2(0.0, 2.0)
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(shadow)

	_sprite = Sprite2D.new()
	_sprite.texture = SpriteFactory.get_icon_texture("watchtower")
	_sprite.centered = false
	_sprite.offset = Vector2(-10.0, -34.0)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)

	var body: StaticBody2D = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col: CollisionShape2D = CollisionShape2D.new()
	var sh: RectangleShape2D = RectangleShape2D.new()
	sh.size = Vector2(16.0, 12.0)
	col.shape = sh
	col.position = Vector2(0.0, -6.0)
	body.add_child(col)
	add_child(body)

	_hp_holder = Node2D.new()
	_hp_holder.position = Vector2(0.0, -39.0)
	_hp_holder.visible = false
	var bg: ColorRect = ColorRect.new()
	bg.position = Vector2(-10.0, 0.0)
	bg.size = Vector2(20.0, 3.0)
	bg.color = Color(0.08, 0.06, 0.10, 0.85)
	_hp_holder.add_child(bg)
	_hp_fill = ColorRect.new()
	_hp_fill.position = Vector2(-9.0, 1.0)
	_hp_fill.size = Vector2(18.0, 1.0)
	_hp_fill.color = Color(0.42, 0.86, 0.48, 1.0)
	_hp_holder.add_child(_hp_fill)
	add_child(_hp_holder)


func is_standing() -> bool:
	return hp > 0


func take_damage(dmg: int) -> void:
	if dmg <= 0 or hp <= 0:
		return
	hp = maxi(0, hp - dmg)
	if _hp_holder != null and _hp_fill != null:
		_hp_holder.visible = hp > 0 and hp < max_hp
		_hp_fill.size.x = maxf(1.0, 18.0 * (float(hp) / float(maxi(1, max_hp))))
	if hp <= 0:
		remove_from_group("watchtowers")
		destroyed.emit(self)
		queue_free()


func step_tower(delta: float, enemies: Array) -> void:
	if hp <= 0:
		return
	fire_timer = maxf(0.0, fire_timer - delta)
	if fire_timer > 0.0:
		return
	var best: Node = null
	var best_d: float = attack_range
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var d: float = position.distance_to(enemy.position)
		if d <= best_d:
			best_d = d
			best = enemy
	if best != null:
		fire_timer = Config.WATCHTOWER_FIRE_INTERVAL
		fire_requested.emit(position + Vector2(0.0, -24.0), best)
