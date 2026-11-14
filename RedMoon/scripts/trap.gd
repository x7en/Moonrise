class_name Trap
extends Node2D
## Placeable tactical traps (T2.3): Spike Trap, Snare, and Lure Post.

signal triggered(trap: Trap, enemy: Node)
signal broken(trap: Trap)

var trap_type: String = "trap_spike"
var triggers_left: int = 5
var hp: int = 25
var max_hp: int = 25
var radius: float = 12.0
var cooldown_left: float = 0.0
var attract_radius: float = 0.0

var _sprite: Sprite2D = null
var _hp_bar: ColorRect = null


func setup(p_type: String, world_pos: Vector2) -> void:
	trap_type = p_type
	position = world_pos.round()
	add_to_group("traps")
	var spec: Dictionary = Config.TRAPS.get(p_type, {}) as Dictionary
	radius = float(spec.get("radius", 12.0))
	triggers_left = int(spec.get("max_triggers", 1))
	hp = int(spec.get("hp", 25))
	max_hp = hp
	attract_radius = float(spec.get("attract_radius", 0.0))

	var shadow: Sprite2D = Sprite2D.new()
	shadow.texture = SpriteFactory.get_blob_shadow(14, 5)
	shadow.position = Vector2(0.0, 2.0)
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(shadow)

	_sprite = Sprite2D.new()
	_sprite.texture = SpriteFactory.get_icon_texture(p_type)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if p_type == "trap_lure":
		_sprite.offset = Vector2(0.0, -7.0)
	add_child(_sprite)

	if p_type == "trap_lure":
		_hp_bar = ColorRect.new()
		_hp_bar.position = Vector2(-8.0, -18.0)
		_hp_bar.size = Vector2(16.0, 2.0)
		_hp_bar.color = Color(0.92, 0.36, 0.28, 1.0)
		_hp_bar.visible = false
		add_child(_hp_bar)


func is_active() -> bool:
	if trap_type == "trap_lure":
		return hp > 0
	return triggers_left > 0


func take_lure_damage(dmg: int) -> void:
	if trap_type != "trap_lure" or hp <= 0:
		return
	hp = maxi(0, hp - dmg)
	if _hp_bar != null:
		_hp_bar.visible = hp < max_hp and hp > 0
		_hp_bar.size.x = maxf(1.0, 16.0 * (float(hp) / float(maxi(1, max_hp))))
	if hp <= 0:
		broken.emit(self)
		queue_free()


func step_trap(delta: float, enemies: Array) -> void:
	if not is_active():
		return
	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)
		return
	if trap_type == "trap_lure":
		return

	var spec: Dictionary = Config.TRAPS.get(trap_type, {}) as Dictionary
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		if enemy.position.distance_to(position) <= radius:
			if trap_type == "trap_spike":
				enemy.take_hit(int(spec.get("damage", 3)), Vector2.ZERO, false)
				cooldown_left = float(spec.get("cooldown", 0.8))
			elif trap_type == "trap_snare":
				enemy.apply_root(float(spec.get("root_time", 3.0)))
			triggers_left -= 1
			triggered.emit(self, enemy)
			if _sprite != null:
				_sprite.modulate = Color(1.3, 0.8, 0.8, 1.0)
			if triggers_left <= 0:
				broken.emit(self)
				queue_free()
			return
