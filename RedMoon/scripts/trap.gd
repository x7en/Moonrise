class_name Trap
extends Node2D

# spike strip, bear trap snare, and burning lure post

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
var _anim_sprite: AnimatedSprite2D = null
var _hp_bar: ColorRect = null
var _pulse_time: float = 0.0
var _flash_time: float = 0.0
var _break_delay: float = -1.0


func setup(p_type: String, world_pos: Vector2) -> void:
	trap_type = p_type
	position = world_pos.round()
	add_to_group("traps")

	var spec: Dictionary = Config.TRAPS.get(p_type, {}) as Dictionary
	radius = float(spec.get("radius", 13.0))
	triggers_left = int(spec.get("max_triggers", 1))
	hp = int(spec.get("hp", 30))
	max_hp = hp
	attract_radius = float(spec.get("attract_radius", 0.0))

	var shadow := Sprite2D.new()
	shadow.texture = SpriteFactory.get_blob_shadow(18, 7)
	shadow.position = Vector2(0.0, 4.0)
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(shadow)

	if p_type == "trap_spike":
		_anim_sprite = _build_sheet_anim(
			"traps/spike_sheet", 14, [3], [6, 8, 9, 10, 11, 13, 3], 18.0
		)
		_anim_sprite.scale = Vector2(0.75, 0.75)
		add_child(_anim_sprite)

	elif p_type == "trap_snare":
		_anim_sprite = _build_sheet_anim("traps/snare_sheet", 4, [0], [1, 2, 3], 14.0)
		_anim_sprite.scale = Vector2(0.75, 0.75)
		add_child(_anim_sprite)

	elif p_type == "trap_lure":
		_sprite = Sprite2D.new()
		_sprite.texture = SpriteFactory.tex("fences/wood/post")
		_sprite.offset = Vector2(0.0, -7.0)
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)

		_anim_sprite = _build_sheet_anim("traps/lure_fire", 3, [0, 1, 2], [0, 1, 2], 9.0, true)
		_anim_sprite.position = Vector2(0.0, -17.0)
		add_child(_anim_sprite)

	else:
		_sprite = Sprite2D.new()
		_sprite.texture = SpriteFactory.get_icon_texture(p_type)
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)

	if p_type == "trap_lure":
		_hp_bar = ColorRect.new()
		_hp_bar.position = Vector2(-9.0, -25.0)
		_hp_bar.size = Vector2(18.0, 2.0)
		_hp_bar.color = Color(0.95, 0.36, 0.28, 1.0)
		_hp_bar.visible = false
		add_child(_hp_bar)


func _build_sheet_anim(
	tex_key: String,
	count: int,
	idle_indices: Array,
	spring_indices: Array,
	fps: float,
	loop_idle: bool = false
) -> AnimatedSprite2D:
	var strip := SpriteFactory.tex(tex_key)
	var fw := floorf(float(strip.get_width()) / float(maxi(1, count)))
	var fh := float(strip.get_height())

	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")

	sf.add_animation(&"idle")
	sf.set_animation_speed(&"idle", fps)
	sf.set_animation_loop(&"idle", loop_idle)
	for idx in idle_indices:
		var at := AtlasTexture.new()
		at.atlas = strip
		at.region = Rect2(float(int(idx)) * fw, 0.0, fw, fh)
		sf.add_frame(&"idle", at)

	sf.add_animation(&"spring")
	sf.set_animation_speed(&"spring", fps)
	sf.set_animation_loop(&"spring", false)
	for idx in spring_indices:
		var at2 := AtlasTexture.new()
		at2.atlas = strip
		at2.region = Rect2(float(int(idx)) * fw, 0.0, fw, fh)
		sf.add_frame(&"spring", at2)

	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = sf
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anim.play(&"idle")
	return anim


func _draw() -> void:
	if trap_type == "trap_lure" and is_active():
		var pulse_r := 16.0 + fmod(_pulse_time * 36.0, 32.0)
		var alpha := clampf(1.0 - (pulse_r - 16.0) / 32.0, 0.0, 1.0) * 0.45
		draw_arc(Vector2(0.0, -4.0), pulse_r, 0.0, TAU, 24, Color(1.0, 0.84, 0.34, alpha), 1.0)


func is_active() -> bool:
	if _break_delay >= 0.0:
		return false
	if trap_type == "trap_lure":
		return hp > 0
	return triggers_left > 0


func take_lure_damage(dmg: int) -> void:
	if trap_type != "trap_lure" or hp <= 0:
		return

	hp = maxi(0, hp - dmg)
	_flash_time = 0.12
	_set_visual_tint(Color(1.5, 0.8, 0.8, 1.0))

	if _hp_bar != null:
		_hp_bar.visible = hp < max_hp and hp > 0
		_hp_bar.size.x = maxf(1.0, 18.0 * (float(hp) / float(maxi(1, max_hp))))

	if hp <= 0:
		remove_from_group("traps")
		broken.emit(self)
		queue_free()


func step_trap(delta: float, enemies: Array) -> void:
	# let the snap animation finish before freeing the bear trap
	if _break_delay >= 0.0:
		_break_delay -= delta
		modulate.a = clampf(_break_delay / 0.35, 0.0, 1.0)
		if _break_delay <= 0.0:
			remove_from_group("traps")
			broken.emit(self)
			queue_free()
		return

	if not is_active():
		return

	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		if _flash_time <= 0.0:
			_set_visual_tint(Color.WHITE)

	if trap_type == "trap_lure":
		_pulse_time += delta
		queue_redraw()
		return

	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)
		return

	var spec: Dictionary = Config.TRAPS.get(trap_type, {}) as Dictionary
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue

		if enemy.position.distance_to(position) <= radius:
			if trap_type == "trap_spike":
				enemy.take_hit(int(spec.get("damage", 3)), Vector2.ZERO, false)
				cooldown_left = float(spec.get("cooldown", 0.7))
			elif trap_type == "trap_snare":
				enemy.take_hit(int(spec.get("damage", 1)), Vector2.ZERO, false)
				enemy.apply_root(float(spec.get("root_time", 3.5)))

			triggers_left -= 1
			_flash_time = 0.16
			triggered.emit(self, enemy)
			_set_visual_tint(Color(1.4, 0.85, 0.85, 1.0))

			if _anim_sprite != null:
				_anim_sprite.play(&"spring")

			if triggers_left <= 0:
				_break_delay = 0.55 if trap_type == "trap_snare" else 0.35
			return


func _set_visual_tint(col: Color) -> void:
	if _sprite != null:
		_sprite.modulate = col
	if _anim_sprite != null:
		_anim_sprite.modulate = col
