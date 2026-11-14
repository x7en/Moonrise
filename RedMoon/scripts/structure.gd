class_name Structure
extends Node2D
## Solid House (with 3D shading, door, lighting, damage stages, crumble -> rubble, rebuild)
## and solid concentric-ring Fence segments (level 1-3, spikes, ghost foundations, collider).

signal destroyed(structure: Structure)
signal crumbled_finished(structure: Structure)
signal door_state_changed(is_open: bool)

enum Kind { HOUSE, FENCE }
enum DoorState { CLOSED, OPENING, OPEN, CLOSING }

var kind: Kind = Kind.HOUSE
var hp: int = 100
var max_hp: int = 100
var reach: float = 56.0
var slot_index: int = -1
var ring: int = 0
var is_horizontal: bool = true
var active_in_game: bool = true

var level: int = 1
var is_built: bool = true
var spiked: bool = false
var is_fallen: bool = false  # House crumbled into rubble (NOT game over, T1.5)
var door_state: DoorState = DoorState.CLOSED
var is_hovered: bool = false

var target_center: Vector2 = Vector2.ZERO
var footprint_rect: Rect2 = Rect2()
var segment_length: float = 48.0

var _house_sprite: Sprite2D = null
var _damage_overlay: Sprite2D = null
var _cracks_overlay: Node2D = null
var _cast_shadow: Polygon2D = null
var _chimney_smoke: CPUParticles2D = null
var _damage_smoke: CPUParticles2D = null
var _damage_flames: CPUParticles2D = null
var _window_lights: Array[PointLight2D] = []
var _occluder: LightOccluder2D = null
var _rubble_node: Node2D = null
var _intruder_marks: Node2D = null

var _fence_sprites: Array[Sprite2D] = []
var _ghost_rect: ColorRect = null
var _spike_bar: Node2D = null
var _ruin_node: Node2D = null
var _hover_outline: Line2D = null

var _body: StaticBody2D = null
var _collider: CollisionShape2D = null
var _door_body: StaticBody2D = null
var _door_collider: CollisionShape2D = null

var _hp_bar_holder: Node2D = null
var _hp_bar_fill: ColorRect = null
var _hp_bar_label: Label = null
var _house_bar_fade_timer: float = 0.0

var _flash_timer: float = 0.0
var _door_anim_timer: float = 0.0
var _crumble_timer: float = 0.0
var _is_crumbling: bool = false


## Sets up the central solid farmhouse with 3D shading, door, lighting, and world-space HP bar.
func setup_house(decals_layer: Node2D) -> void:
	name = "House"
	kind = Kind.HOUSE
	level = 1
	max_hp = Config.HOUSE_HP
	hp = Config.HOUSE_HP
	reach = Config.HOUSE_REACH
	slot_index = -1
	ring = 0
	is_built = true
	is_fallen = false
	active_in_game = true
	target_center = Config.HOUSE_CENTER
	footprint_rect = Rect2(Config.HOUSE_CENTER - Vector2(48.0, 45.0), Vector2(96.0, 90.0))
	position = Config.HOUSE_CENTER + Vector2(0.0, 45.0)
	add_to_group("structures")
	_build_house_nodes(decals_layer)


## Sets up one solid fence segment belonging to concentric ring 1, 2, or 3 (T0.4).
func setup_fence_segment(idx: int, seg_spec: Dictionary, decals_layer: Node2D) -> void:
	name = "Fence_R%d_%d" % [int(seg_spec["ring"]), idx]
	kind = Kind.FENCE
	ring = int(seg_spec["ring"])
	slot_index = idx
	is_horizontal = bool(seg_spec["horizontal"])
	is_built = bool(seg_spec["built"])
	level = 1
	spiked = false
	max_hp = Config.FENCE_HP
	hp = max_hp if is_built else 0
	reach = Config.FENCE_REACH
	active_in_game = true

	var seg_rect: Rect2 = seg_spec["rect"] as Rect2
	footprint_rect = seg_rect
	target_center = seg_rect.get_center()
	segment_length = seg_rect.size.x if is_horizontal else seg_rect.size.y
	position = Vector2(target_center.x, seg_rect.end.y)
	add_to_group("structures")
	_build_fence_nodes(decals_layer)


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		if _flash_timer <= 0.0:
			modulate = Color.WHITE

	if _door_anim_timer > 0.0:
		_door_anim_timer = maxf(0.0, _door_anim_timer - delta)
		if _door_anim_timer <= 0.0:
			if door_state == DoorState.OPENING:
				door_state = DoorState.OPEN
				_sync_door_collider()
				door_state_changed.emit(true)
			elif door_state == DoorState.CLOSING:
				door_state = DoorState.CLOSED
				_sync_door_collider()
				door_state_changed.emit(false)
			refresh_visuals()

	if _is_crumbling:
		_step_crumble(delta)

	if kind == Kind.HOUSE and _hp_bar_holder != null and not is_fallen:
		if _house_bar_fade_timer > 0.0:
			_house_bar_fade_timer = maxf(0.0, _house_bar_fade_timer - delta)
			if _house_bar_fade_timer <= 0.0 and hp >= max_hp:
				_hp_bar_holder.visible = false
		if hp < max_hp and _house_bar_fade_timer > 0.0:
			_hp_bar_holder.visible = true
			_hp_bar_holder.modulate.a = clampf(_house_bar_fade_timer, 0.0, 1.0)
		elif hp < max_hp:
			_hp_bar_holder.visible = false


func is_standing() -> bool:
	if kind == Kind.HOUSE:
		return active_in_game and not is_fallen and not _is_crumbling and hp > 0
	return active_in_game and is_built and hp > 0


func is_door_open() -> bool:
	return door_state == DoorState.OPEN or door_state == DoorState.OPENING


func distance_from_point(world_point: Vector2) -> float:
	var cx: float = clampf(world_point.x, footprint_rect.position.x, footprint_rect.end.x)
	var cy: float = clampf(world_point.y, footprint_rect.position.y, footprint_rect.end.y)
	return world_point.distance_to(Vector2(cx, cy))


func is_within_attack_reach(enemy_pos: Vector2) -> bool:
	var margin: float = 11.0 if kind == Kind.HOUSE else 12.0
	return distance_from_point(enemy_pos) <= margin


func set_hovered(hovered: bool) -> void:
	if is_hovered == hovered:
		return
	is_hovered = hovered
	if _hover_outline != null:
		_hover_outline.visible = hovered


func set_hp(new_hp: int) -> void:
	hp = clampi(new_hp, 0, max_hp)
	_flash_timer = 0.0
	modulate = Color.WHITE
	if kind == Kind.HOUSE and hp > 0 and is_fallen:
		is_fallen = false
		_is_crumbling = false
	refresh_visuals()


func set_level(new_level: int, fill_hp: bool = true) -> void:
	level = clampi(new_level, 1, 3)
	if kind == Kind.HOUSE:
		max_hp = int(Config.HOUSE_LEVEL_HP[level - 1])
	else:
		max_hp = int(Config.FENCE_LEVEL_HP[level - 1])
	if fill_hp:
		hp = max_hp
	else:
		hp = mini(hp, max_hp)
	refresh_visuals()


func build_from_foundation() -> void:
	if kind != Kind.FENCE or is_built:
		return
	is_built = true
	level = 1
	max_hp = Config.FENCE_HP
	hp = max_hp
	refresh_visuals()


func heal(amount: int) -> int:
	if amount <= 0 or hp >= max_hp or not is_built or is_fallen:
		return 0
	var before: int = hp
	hp = mini(max_hp, hp + amount)
	if kind == Kind.HOUSE:
		_house_bar_fade_timer = 4.0
	refresh_visuals()
	return hp - before


func take_damage(amount: int) -> void:
	if amount <= 0 or not is_standing():
		return
	hp = maxi(0, hp - amount)
	_flash_timer = 0.10
	modulate = Color(1.4, 0.75, 0.75, 1.0)
	if kind == Kind.HOUSE:
		_house_bar_fade_timer = 4.0
	refresh_visuals()
	if hp == 0:
		if kind == Kind.HOUSE:
			_start_crumble()
		destroyed.emit(self)


## T1.5C: Toggles the house door between open and closed (force_close snaps shut).
func toggle_door(force_close: bool = false) -> bool:
	if kind != Kind.HOUSE:
		return false
	if force_close:
		door_state = DoorState.CLOSED
		_door_anim_timer = 0.0
		_sync_door_collider()
		refresh_visuals()
		return true
	if is_fallen or _is_crumbling:
		return false
	if door_state == DoorState.CLOSED or door_state == DoorState.CLOSING:
		door_state = DoorState.OPENING
		_door_anim_timer = 0.3
		_sync_door_collider()
		refresh_visuals()
		return true
	door_state = DoorState.CLOSING
	_door_anim_timer = 0.3
	_sync_door_collider()
	refresh_visuals()
	return true


## T1.5D: Plays the 3-second house collapse into a walkable rubble pile (NOT game over).
func _start_crumble() -> void:
	if kind != Kind.HOUSE or is_fallen or _is_crumbling:
		return
	_is_crumbling = true
	_crumble_timer = 3.0
	toggle_door(true)
	if _collider != null:
		_collider.set_deferred("disabled", true)
	if _damage_smoke != null:
		_damage_smoke.emitting = true
	if _damage_flames != null:
		_damage_flames.emitting = true


## T1.5D: Restores the fallen house at 40% HP, level 1, door closed.
func rebuild_house() -> void:
	if kind != Kind.HOUSE:
		return
	is_fallen = false
	_is_crumbling = false
	_crumble_timer = 0.0
	level = 1
	max_hp = Config.HOUSE_HP
	hp = int(round(float(max_hp) * 0.40))
	toggle_door(true)
	if _house_sprite != null:
		_house_sprite.position = Vector2.ZERO
		_house_sprite.scale = Vector2.ONE
		_house_sprite.modulate = Color.WHITE
		_house_sprite.visible = true
	if _collider != null:
		_collider.set_deferred("disabled", false)
	_house_bar_fade_timer = 4.0
	refresh_visuals()


## Updates cast shadow & window lights based on time of day (T1.4).
func update_lighting(is_night: bool, is_dusk: bool, is_blood: bool, intruder_count: int) -> void:
	if kind != Kind.HOUSE:
		return
	if _cast_shadow != null:
		_cast_shadow.visible = not is_fallen and not is_night
		if is_dusk:
			_cast_shadow.scale = Vector2(1.45, 1.35)
			_cast_shadow.color = Color(0.08, 0.05, 0.12, 0.30)
		else:
			_cast_shadow.scale = Vector2(1.0, 1.0)
			_cast_shadow.color = Color(0.08, 0.06, 0.12, 0.34)
	for i in range(_window_lights.size()):
		var light: PointLight2D = _window_lights[i]
		var extra_lv3: bool = (i >= 3 and level < 3)
		light.visible = (is_night or is_dusk) and not is_fallen and not extra_lv3
		if is_blood:
			light.color = Color(1.0, 0.56, 0.34, 1.0)
		else:
			light.color = Color(1.0, 0.74, 0.40, 1.0)
	if _intruder_marks != null:
		_intruder_marks.visible = (intruder_count > 0 and not is_fallen)


func get_tooltip_text() -> String:
	if kind == Kind.HOUSE:
		if is_fallen:
			return "House Rubble - Rebuild to restore shelter"
		return "House - %d/%d HP - Lv %d" % [hp, max_hp, level]
	if not is_built:
		return "Ring %d Foundation - Unbuilt" % ring
	var spk: String = " [Spiked]" if spiked else ""
	return "Fence R%d - %d/%d HP - Lv %d%s" % [ring, hp, max_hp, level, spk]


func to_snapshot() -> Dictionary:
	return {
		"hp": hp,
		"max_hp": max_hp,
		"level": level,
		"is_built": is_built,
		"spiked": spiked,
		"is_fallen": is_fallen,
		"door_open": is_door_open(),
	}


func apply_snapshot(snap: Dictionary) -> void:
	level = int(snap.get("level", 1))
	is_built = bool(snap.get("is_built", true))
	spiked = bool(snap.get("spiked", false))
	is_fallen = bool(snap.get("is_fallen", false))
	_is_crumbling = false
	if kind == Kind.HOUSE:
		max_hp = int(Config.HOUSE_LEVEL_HP[clampi(level - 1, 0, 2)])
		door_state = DoorState.OPEN if bool(snap.get("door_open", false)) else DoorState.CLOSED
		_sync_door_collider()
	else:
		max_hp = int(Config.FENCE_LEVEL_HP[clampi(level - 1, 0, 2)])
	hp = clampi(int(snap.get("hp", max_hp)), 0, max_hp)
	_flash_timer = 0.0
	modulate = Color.WHITE
	refresh_visuals()


func refresh_visuals() -> void:
	if kind == Kind.HOUSE:
		_refresh_house_visuals()
	else:
		_refresh_fence_visuals()


func _refresh_house_visuals() -> void:
	var standing: bool = not is_fallen
	if _house_sprite != null:
		_house_sprite.visible = standing
		_house_sprite.texture = SpriteFactory.get_shaded_house_texture(level, is_door_open())
	if _damage_overlay != null:
		_damage_overlay.visible = standing
		var dmg_ratio: float = 1.0 - (float(hp) / float(maxi(1, max_hp)))
		_damage_overlay.modulate.a = clampf(dmg_ratio * 0.36, 0.0, 0.36)
	if _rubble_node != null:
		_rubble_node.visible = is_fallen
	if _occluder != null:
		_occluder.visible = standing
	if _collider != null and not _is_crumbling:
		_collider.set_deferred("disabled", is_fallen)

	var frac: float = float(hp) / float(maxi(1, max_hp))
	if _cracks_overlay != null:
		_cracks_overlay.visible = standing and frac <= 0.75
	if _chimney_smoke != null:
		_chimney_smoke.emitting = standing
	if _damage_smoke != null:
		_damage_smoke.emitting = standing and frac <= 0.50
	if _damage_flames != null:
		_damage_flames.emitting = standing and frac <= 0.25

	if _hp_bar_holder != null and _hp_bar_fill != null and _hp_bar_label != null:
		if is_fallen:
			_hp_bar_holder.visible = false
		else:
			_hp_bar_fill.size.x = maxf(1.0, floorf(56.0 * frac)) if hp > 0 else 0.0
			if frac > 0.6:
				_hp_bar_fill.color = Color(0.35, 0.85, 0.42, 1.0)
			elif frac > 0.3:
				_hp_bar_fill.color = Color(0.95, 0.80, 0.25, 1.0)
			else:
				_hp_bar_fill.color = Color(0.92, 0.24, 0.24, 1.0)
			_hp_bar_label.text = "%d/%d" % [hp, max_hp]


func _refresh_fence_visuals() -> void:
	var standing: bool = is_built and hp > 0
	if _collider != null:
		_collider.set_deferred("disabled", not standing)

	var tex_key: String = ""
	if standing:
		var use_reinf: bool = (level >= 2 or hp >= Config.FENCE_REINFORCED_MIN_HP)
		var folder: String = "fence_reinforced" if use_reinf else "fence_wood"
		var orient: String = "horizontal" if is_horizontal else "vertical"
		tex_key = "structures/%s/%s" % [folder, orient]

	for spr in _fence_sprites:
		spr.visible = standing
		if standing:
			spr.texture = SpriteFactory.tex(tex_key)
			spr.modulate = Color(0.76, 0.82, 0.90, 1.0) if level >= 3 else Color.WHITE

	if _ghost_rect != null:
		_ghost_rect.visible = not is_built
	if _ruin_node != null:
		_ruin_node.visible = is_built and hp <= 0
	if _spike_bar != null:
		_spike_bar.visible = standing and spiked

	if _hp_bar_holder != null and _hp_bar_fill != null:
		var show_bar: bool = standing and hp < max_hp
		_hp_bar_holder.visible = show_bar
		if show_bar:
			var frac: float = float(hp) / float(maxi(1, max_hp))
			_hp_bar_fill.size.x = maxf(1.0, floorf(22.0 * frac))
			if frac > 0.6:
				_hp_bar_fill.color = Color(0.42, 0.86, 0.45, 1.0)
			elif frac > 0.3:
				_hp_bar_fill.color = Color(0.95, 0.76, 0.26, 1.0)
			else:
				_hp_bar_fill.color = Color(0.92, 0.26, 0.26, 1.0)


func _step_crumble(delta: float) -> void:
	_crumble_timer -= delta
	var progress: float = 1.0 - clampf(_crumble_timer / 3.0, 0.0, 1.0)
	if _house_sprite != null:
		var shake_x: float = sin(progress * 90.0) * (1.0 - progress) * 4.0
		_house_sprite.position = Vector2(shake_x, progress * 16.0)
		_house_sprite.scale = Vector2(1.0, maxf(0.15, 1.0 - progress * 0.85))
		_house_sprite.modulate.a = clampf(1.0 - progress * 0.9, 0.1, 1.0)
	if _crumble_timer <= 0.0:
		_is_crumbling = false
		is_fallen = true
		if _house_sprite != null:
			_house_sprite.position = Vector2.ZERO
			_house_sprite.scale = Vector2.ONE
			_house_sprite.modulate = Color.WHITE
		refresh_visuals()
		crumbled_finished.emit(self)


func _sync_door_collider() -> void:
	if _door_collider != null:
		var passable: bool = is_door_open() or is_fallen
		_door_collider.set_deferred("disabled", passable)


func _build_house_nodes(decals_layer: Node2D) -> void:
	# Ground cast shadow pointing bottom-right (top-left light, T1.4).
	_cast_shadow = Polygon2D.new()
	_cast_shadow.polygon = PackedVector2Array([
		Vector2(-44.0, 0.0), Vector2(48.0, 0.0), Vector2(68.0, 18.0), Vector2(-24.0, 18.0)
	])
	_cast_shadow.color = Color(0.08, 0.06, 0.12, 0.34)
	_cast_shadow.z_index = -2
	add_child(_cast_shadow)

	_house_sprite = Sprite2D.new()
	_house_sprite.name = "HouseSprite"
	_house_sprite.texture = SpriteFactory.get_shaded_house_texture(1, false)
	_house_sprite.centered = false
	_house_sprite.offset = Vector2(-48.0, -90.0)
	_house_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_house_sprite)

	_damage_overlay = Sprite2D.new()
	_damage_overlay.texture = SpriteFactory.get_tinted_silhouette(
		"structures/house", Color(0.55, 0.0, 0.0, 1.0)
	)
	_damage_overlay.centered = false
	_damage_overlay.offset = Vector2(-48.0, -90.0)
	_damage_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_damage_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_damage_overlay)

	# Procedural facade cracks shown below 75% HP (T1.5B).
	_cracks_overlay = Node2D.new()
	_cracks_overlay.visible = false
	for crack_pts in [
		[Vector2(-24.0, -36.0), Vector2(-18.0, -28.0), Vector2(-21.0, -18.0)],
		[Vector2(20.0, -40.0), Vector2(26.0, -30.0), Vector2(22.0, -22.0)],
	]:
		var ln: Line2D = Line2D.new()
		ln.width = 1.5
		ln.default_color = Color(0.14, 0.10, 0.14, 0.9)
		ln.points = PackedVector2Array(crack_pts)
		_cracks_overlay.add_child(ln)
	add_child(_cracks_overlay)

	# Window intruder silhouettes (T1.5C).
	_intruder_marks = Node2D.new()
	_intruder_marks.visible = false
	for wx in [-24.0, 20.0]:
		var sil: ColorRect = ColorRect.new()
		sil.position = Vector2(wx, -30.0)
		sil.size = Vector2(6.0, 8.0)
		sil.color = Color(0.88, 0.16, 0.16, 0.85)
		_intruder_marks.add_child(sil)
	add_child(_intruder_marks)

	# Chimney smoke, 50% roof smoke, and 25% flames (2px pixel squares).
	_chimney_smoke = _make_particles(Vector2(-28.0, -86.0), Color(0.75, 0.78, 0.84, 0.55), 5, 1.8)
	add_child(_chimney_smoke)
	_damage_smoke = _make_particles(Vector2(0.0, -68.0), Color(0.28, 0.26, 0.30, 0.75), 10, 1.5)
	_damage_smoke.emitting = false
	add_child(_damage_smoke)
	_damage_flames = _make_particles(Vector2(6.0, -56.0), Color(1.0, 0.45, 0.15, 0.90), 14, 0.7)
	_damage_flames.emitting = false
	add_child(_damage_flames)

	# Warm 2D refuge lights at windows, door, and ambient yard (T1.4).
	_window_lights.clear()
	var light_tex: GradientTexture2D = SpriteFactory.get_radial_light_texture(128)
	for spec in [
		{"pos": Vector2(-22.0, -26.0), "scale": 0.9, "energy": 0.75},
		{"pos": Vector2(22.0, -26.0), "scale": 0.9, "energy": 0.75},
		{"pos": Vector2(0.0, -10.0), "scale": 2.2, "energy": 0.55},
		{"pos": Vector2(0.0, -52.0), "scale": 1.4, "energy": 0.65},
	]:
		var pl: PointLight2D = PointLight2D.new()
		pl.texture = light_tex
		pl.position = spec["pos"] as Vector2
		pl.texture_scale = float(spec["scale"])
		pl.energy = float(spec["energy"])
		pl.color = Color(1.0, 0.74, 0.40, 1.0)
		pl.shadow_enabled = true
		pl.visible = false
		add_child(pl)
		_window_lights.append(pl)

	_occluder = LightOccluder2D.new()
	var occ_poly: OccluderPolygon2D = OccluderPolygon2D.new()
	occ_poly.polygon = PackedVector2Array([
		Vector2(-46.0, -84.0), Vector2(46.0, -84.0), Vector2(46.0, -2.0), Vector2(-46.0, -2.0)
	])
	_occluder.occluder = occ_poly
	add_child(_occluder)

	# Solid house body (layer 1) + door blocker across the doorway when CLOSED.
	_body = StaticBody2D.new()
	_body.name = "HouseBody"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_collider = CollisionShape2D.new()
	var rect_shape: RectangleShape2D = RectangleShape2D.new()
	rect_shape.size = Vector2(96.0, 86.0)
	_collider.shape = rect_shape
	_collider.position = Vector2(0.0, -45.0)
	_body.add_child(_collider)
	add_child(_body)

	_door_body = StaticBody2D.new()
	_door_body.name = "DoorBody"
	_door_body.collision_layer = 1
	_door_body.collision_mask = 0
	_door_collider = CollisionShape2D.new()
	var door_shape: RectangleShape2D = RectangleShape2D.new()
	door_shape.size = Vector2(18.0, 6.0)
	_door_collider.shape = door_shape
	_door_collider.position = Vector2(0.0, 1.0)
	_door_body.add_child(_door_collider)
	add_child(_door_body)

	# World-space floating HP bar above the house roof (T1.5B).
	_hp_bar_holder = Node2D.new()
	_hp_bar_holder.position = Vector2(0.0, -100.0)
	_hp_bar_holder.z_index = 12
	_hp_bar_holder.visible = false
	var bar_bg: ColorRect = ColorRect.new()
	bar_bg.position = Vector2(-29.0, 0.0)
	bar_bg.size = Vector2(58.0, 7.0)
	bar_bg.color = Color(0.08, 0.06, 0.10, 0.90)
	_hp_bar_holder.add_child(bar_bg)
	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.position = Vector2(-28.0, 1.0)
	_hp_bar_fill.size = Vector2(56.0, 5.0)
	_hp_bar_fill.color = Color(0.35, 0.85, 0.42, 1.0)
	_hp_bar_holder.add_child(_hp_bar_fill)
	_hp_bar_label = Label.new()
	_hp_bar_label.position = Vector2(-34.0, -10.0)
	_hp_bar_label.size = Vector2(68.0, 10.0)
	_hp_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SpriteFactory.style_label(_hp_bar_label, "bold", 8, Color.WHITE)
	_hp_bar_holder.add_child(_hp_bar_label)
	add_child(_hp_bar_holder)

	_hover_outline = _make_hover_outline(Rect2(-48.0, -90.0, 96.0, 90.0))
	add_child(_hover_outline)

	# Walkable house rubble pile placed in Decals (hidden until house crumbles, T1.5D).
	_rubble_node = Node2D.new()
	_rubble_node.name = "HouseRubble"
	_rubble_node.position = Config.HOUSE_CENTER
	_rubble_node.visible = false
	var stain: ColorRect = ColorRect.new()
	stain.position = Vector2(-46.0, -38.0)
	stain.size = Vector2(92.0, 76.0)
	stain.color = Color(0.14, 0.11, 0.14, 0.55)
	_rubble_node.add_child(stain)
	for piece in [
		{"key": "structures/ruins/gray-brick_debris", "pos": Vector2(-36.0, -24.0)},
		{"key": "structures/ruins/metal-plates", "pos": Vector2(-10.0, -18.0)},
		{"key": "structures/ruins/gray-brick_debris", "pos": Vector2(18.0, -14.0)},
		{"key": "structures/ruins/iron-beam", "pos": Vector2(-22.0, 8.0)},
		{"key": "structures/ruins/metal-plates", "pos": Vector2(4.0, 10.0)},
		{"key": "structures/ruins/gray-brick_debris", "pos": Vector2(-34.0, 14.0)},
	]:
		var rs: Sprite2D = Sprite2D.new()
		rs.texture = SpriteFactory.tex(String(piece["key"]))
		rs.centered = false
		rs.position = piece["pos"] as Vector2
		rs.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_rubble_node.add_child(rs)
	decals_layer.add_child(_rubble_node)
	refresh_visuals()


func _build_fence_nodes(decals_layer: Node2D) -> void:
	_fence_sprites.clear()
	var half_l: float = segment_length * 0.5
	var seg_w: float = footprint_rect.size.x
	var seg_h: float = footprint_rect.size.y

	# Solid StaticBody2D on layer 1 matching exact drawn footprint (T0.4).
	_body = StaticBody2D.new()
	_body.name = "FenceBody"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_collider = CollisionShape2D.new()
	var rect_shape: RectangleShape2D = RectangleShape2D.new()
	rect_shape.size = Vector2(seg_w, seg_h)
	_collider.shape = rect_shape
	_collider.position = Vector2(0.0, -seg_h * 0.5)
	_body.add_child(_collider)
	add_child(_body)

	# Tile wooden fence sprites cleanly across the exact segment length with zero gap/overhang.
	if is_horizontal:
		var step: float = 16.0
		var tile_count: int = maxi(1, ceili(segment_length / step))
		for i in range(tile_count):
			var x_pos: float = -half_l + float(i) * step
			if x_pos + step > half_l:
				x_pos = half_l - step
			var spr: Sprite2D = Sprite2D.new()
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.position = Vector2(x_pos, -14.0)
			add_child(spr)
			_fence_sprites.append(spr)
	else:
		var step_v: float = 16.0
		var tile_count_v: int = maxi(1, ceili(segment_length / step_v))
		for i in range(tile_count_v):
			var y_pos: float = -segment_length + float(i) * step_v
			if y_pos + step_v > 0.0:
				y_pos = -step_v
			var spr: Sprite2D = Sprite2D.new()
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.position = Vector2(-4.0, y_pos)
			add_child(spr)
			_fence_sprites.append(spr)

	# Faint ghost foundation outline for unbuilt Ring-3 segments (T0.4 / T1.6C).
	_ghost_rect = ColorRect.new()
	_ghost_rect.position = Vector2(-seg_w * 0.5, -seg_h)
	_ghost_rect.size = Vector2(seg_w, seg_h)
	_ghost_rect.color = Color(0.72, 0.84, 0.92, 0.30)
	_ghost_rect.visible = not is_built
	add_child(_ghost_rect)

	# Visible metal spikes overlay when Spiked Fences upgrade is installed (T2.2).
	_spike_bar = Node2D.new()
	_spike_bar.visible = false
	var spike_count: int = maxi(2, int(segment_length / 12.0))
	for s in range(spike_count):
		var sp: ColorRect = ColorRect.new()
		var frac: float = (float(s) + 0.5) / float(spike_count)
		if is_horizontal:
			sp.position = Vector2(-half_l + frac * segment_length - 1.0, -15.0)
			sp.size = Vector2(2.0, 4.0)
		else:
			sp.position = Vector2(-5.0, -segment_length + frac * segment_length - 1.0)
			sp.size = Vector2(4.0, 2.0)
		sp.color = Color(0.88, 0.92, 0.96, 1.0)
		_spike_bar.add_child(sp)
	add_child(_spike_bar)

	# Small HP bar shown only while standing and damaged.
	var bar_y: float = -19.0 if is_horizontal else (-segment_length - 6.0)
	_hp_bar_holder = Node2D.new()
	_hp_bar_holder.position = Vector2(0.0, bar_y)
	_hp_bar_holder.visible = false
	var fbg: ColorRect = ColorRect.new()
	fbg.position = Vector2(-12.0, 0.0)
	fbg.size = Vector2(24.0, 4.0)
	fbg.color = Color(0.08, 0.06, 0.10, 0.85)
	_hp_bar_holder.add_child(fbg)
	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.position = Vector2(-11.0, 1.0)
	_hp_bar_fill.size = Vector2(22.0, 2.0)
	_hp_bar_fill.color = Color(0.45, 0.86, 0.45, 1.0)
	_hp_bar_holder.add_child(_hp_bar_fill)
	add_child(_hp_bar_holder)

	_hover_outline = _make_hover_outline(Rect2(-seg_w * 0.5, -seg_h, seg_w, seg_h))
	add_child(_hover_outline)

	# Ruin debris in Decals when broken (HP == 0).
	_ruin_node = Node2D.new()
	_ruin_node.position = target_center
	_ruin_node.visible = false
	var debris: Sprite2D = Sprite2D.new()
	debris.texture = SpriteFactory.tex("structures/ruins/gray-brick_debris")
	debris.centered = false
	debris.offset = Vector2(-8.0, -7.0)
	debris.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ruin_node.add_child(debris)
	decals_layer.add_child(_ruin_node)

	refresh_visuals()


func _make_hover_outline(local_rect: Rect2) -> Line2D:
	var ln: Line2D = Line2D.new()
	ln.width = 1.0
	ln.default_color = Color(1.0, 0.94, 0.52, 0.95)
	ln.closed = true
	ln.points = PackedVector2Array([
		local_rect.position,
		Vector2(local_rect.end.x, local_rect.position.y),
		local_rect.end,
		Vector2(local_rect.position.x, local_rect.end.y),
	])
	ln.visible = false
	ln.z_index = 10
	return ln


func _make_particles(
	pos: Vector2,
	col: Color,
	amount_n: int,
	lifetime_s: float
) -> CPUParticles2D:
	var cp: CPUParticles2D = CPUParticles2D.new()
	cp.position = pos
	cp.amount = amount_n
	cp.lifetime = lifetime_s
	cp.direction = Vector2(0.15, -1.0)
	cp.spread = 22.0
	cp.gravity = Vector2(4.0, -8.0)
	cp.initial_velocity_min = 6.0
	cp.initial_velocity_max = 14.0
	cp.scale_amount_min = 2.0
	cp.scale_amount_max = 2.0
	cp.color = col
	return cp
