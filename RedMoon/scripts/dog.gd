class_name Dog
extends CharacterBody2D
## Asset-gated companion dog (T3.2a). Remains completely dormant until dog_idle_* and
## dog_run_* sprite sheets are placed in res://assets/animals/. Never invents placeholder art.

signal tamed(dog: Dog)
signal attacked_enemy(enemy: Node)

enum Mode { STRAY, FOLLOW, GUARD }

var mode: Mode = Mode.STRAY
var hp: int = 20
var max_hp: int = 20
var guard_anchor: Vector2 = Vector2.ZERO
var tame_progress: float = 0.0

var _sprite: AnimatedSprite2D = null
var _attack_cd: float = 0.0
var _facing: String = "down"


## Checks res://assets/animals/ for real dog idle & run sprite strips before enabling T3.2a.
static func assets_available() -> bool:
	var dir: DirAccess = DirAccess.open("res://assets/animals")
	if dir == null:
		return false
	var has_idle: bool = false
	var has_run: bool = false
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and fname.ends_with(".png"):
			if fname.begins_with("dog_idle_"):
				has_idle = true
			elif fname.begins_with("dog_run_"):
				has_run = true
		fname = dir.get_next()
	dir.list_dir_end()
	return has_idle and has_run


func setup(spawn_pos: Vector2) -> bool:
	if not Dog.assets_available():
		return false
	position = spawn_pos.round()
	max_hp = Config.DOG_HP
	hp = max_hp
	mode = Mode.STRAY
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("dogs")

	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(8.0, 6.0)
	col.shape = shape
	col.position = Vector2(0.0, -3.0)
	add_child(col)

	var shadow: Sprite2D = Sprite2D.new()
	shadow.texture = SpriteFactory.get_blob_shadow(12, 5)
	shadow.position = Vector2(0.0, 1.0)
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(shadow)

	_sprite = AnimatedSprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.sprite_frames = _load_dog_frames()
	_sprite.offset = Vector2(-8.0, -16.0)
	_sprite.play(&"idle_down")
	add_child(_sprite)
	return true


func toggle_guard_mode(anchor_pos: Vector2) -> String:
	if mode == Mode.STRAY:
		return ""
	if mode == Mode.FOLLOW:
		mode = Mode.GUARD
		guard_anchor = anchor_pos
		return "Dog guarding spot"
	mode = Mode.FOLLOW
	return "Dog following you"


func advance_tame(delta: float, is_holding: bool) -> bool:
	if mode != Mode.STRAY:
		return false
	if is_holding:
		tame_progress += delta
		if tame_progress >= Config.DOG_TAME_TIME:
			mode = Mode.FOLLOW
			tamed.emit(self)
			return true
	else:
		tame_progress = maxf(0.0, tame_progress - delta * 2.0)
	return false


func step_dog(
	delta: float,
	player_pos: Vector2,
	enemies: Array,
	world_bounds: Rect2
) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if mode == Mode.STRAY:
		velocity = Vector2.ZERO
		_play_anim("idle")
		return

	var target_enemy: Node = null
	var origin: Vector2 = guard_anchor if mode == Mode.GUARD else player_pos
	var best_d: float = Config.DOG_GUARD_RANGE
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var d: float = enemy.position.distance_to(origin)
		if d < best_d:
			best_d = d
			target_enemy = enemy

	if target_enemy != null:
		var to_e: Vector2 = target_enemy.position - position
		if to_e.length() <= 14.0:
			velocity = Vector2.ZERO
			if _attack_cd <= 0.0:
				_attack_cd = Config.DOG_ATTACK_INTERVAL
				target_enemy.take_hit(1, to_e.normalized(), false)
				attacked_enemy.emit(target_enemy)
		else:
			velocity = to_e.normalized() * 78.0
	else:
		var follow_target: Vector2 = guard_anchor if mode == Mode.GUARD else player_pos
		var to_t: Vector2 = follow_target - position
		velocity = to_t.normalized() * 72.0 if to_t.length() > 22.0 else Vector2.ZERO

	if velocity.length_squared() > 1.0:
		_facing = _vec_to_dir(velocity)
		move_and_slide()
		position.x = clampf(position.x, world_bounds.position.x + 8.0, world_bounds.end.x - 8.0)
		position.y = clampf(position.y, world_bounds.position.y + 8.0, world_bounds.end.y - 8.0)
		_play_anim("run")
	else:
		_play_anim("idle")


func _play_anim(prefix: String) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var anim: StringName = StringName("%s_%s" % [prefix, _facing])
	if not _sprite.sprite_frames.has_animation(anim):
		anim = StringName("%s_down" % prefix)
	if _sprite.sprite_frames.has_animation(anim) and _sprite.animation != anim:
		_sprite.play(anim)


func _vec_to_dir(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "right" if v.x >= 0.0 else "left"
	return "down" if v.y >= 0.0 else "up"


func _load_dog_frames() -> SpriteFrames:
	var sf: SpriteFrames = SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	var dir: DirAccess = DirAccess.open("res://assets/animals")
	if dir == null:
		return sf
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and fname.ends_with(".png") and fname.begins_with("dog_"):
			var parsed: Dictionary = _parse_strip_name(fname)
			if not parsed.is_empty():
				var full_path: String = "res://assets/animals/" + fname
				var strip_tex: Texture2D = load(full_path) as Texture2D
				if strip_tex != null:
					var count: int = maxi(1, int(parsed["frames"]))
					var fw: int = maxi(1, int(floorf(float(strip_tex.get_width()) / float(count))))
					var fh: int = maxi(1, strip_tex.get_height())
					var anim_key: String = "%s_%s" % [parsed["anim"], parsed["dir"]]
					sf.add_animation(anim_key)
					sf.set_animation_speed(anim_key, 8.0)
					sf.set_animation_loop(anim_key, true)
					for i in range(count):
						var at: AtlasTexture = AtlasTexture.new()
						at.atlas = strip_tex
						at.region = Rect2(float(i * fw), 0.0, float(fw), float(fh))
						sf.add_frame(anim_key, at)
		fname = dir.get_next()
	dir.list_dir_end()
	return sf


func _parse_strip_name(fname: String) -> Dictionary:
	var stem: String = fname.trim_suffix(".png")
	var parts: PackedStringArray = stem.split("-Sheet")
	var frames_n: int = int(parts[1]) if parts.size() >= 2 else 1
	var head: PackedStringArray = parts[0].split("_")
	if head.size() < 3:
		return {}
	return {"anim": head[1], "dir": head[2], "frames": frames_n}
