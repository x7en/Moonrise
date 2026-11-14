class_name Structure
extends Node2D
## Represents either the solid central House or one of the 6 perimeter Fences.
## Both share health, damage, repair, and reach logic so combat stays simple and bug-free.

signal destroyed(structure: Structure)

enum Kind { HOUSE, FENCE }

var kind: Kind = Kind.HOUSE
var hp: int = 100
var max_hp: int = 100
var reach: float = 56.0
var slot_index: int = -1
var is_horizontal: bool = true
var active_in_game: bool = true

var target_center: Vector2 = Vector2.ZERO
var footprint_rect: Rect2 = Rect2()

var _house_sprite: Sprite2D = null
var _damage_overlay: Sprite2D = null
var _fence_sprites: Array[Sprite2D] = []
var _ruin_node: Node2D = null
var _hp_bar_bg: ColorRect = null
var _hp_bar_fill: ColorRect = null
var _flash_timer: float = 0.0


## Sets up this node as the solid central farmhouse at Config.HOUSE_CENTER.
func setup_house() -> void:
	name = "House"
	kind = Kind.HOUSE
	max_hp = Config.HOUSE_HP
	hp = Config.HOUSE_HP
	reach = Config.HOUSE_REACH
	slot_index = -1
	active_in_game = true
	target_center = Config.HOUSE_CENTER

	# The house sprite is 96x90 centered on HOUSE_CENTER.
	footprint_rect = Rect2(Config.HOUSE_CENTER - Vector2(48.0, 45.0), Vector2(96.0, 90.0))

	# Place the node origin at the bottom edge of the house so Y-sorting works properly.
	position = Config.HOUSE_CENTER + Vector2(0.0, 45.0)
	add_to_group("structures")
	_build_house_nodes()


## Sets up this node as one of the 6 repairable Act-2 fence slots around the yard.
func setup_fence(idx: int, slot_data: Dictionary, decals_layer: Node2D) -> void:
	name = "Fence_%d" % idx
	kind = Kind.FENCE
	max_hp = Config.FENCE_HP
	hp = 0
	reach = Config.FENCE_REACH
	slot_index = idx
	is_horizontal = bool(slot_data["horizontal"])
	active_in_game = false

	var slot_offset: Vector2 = slot_data["offset"] as Vector2
	var center: Vector2 = Config.HOUSE_CENTER + slot_offset
	target_center = center

	if is_horizontal:
		footprint_rect = Rect2(center - Vector2(24.0, 7.0), Vector2(48.0, 14.0))
		position = Vector2(center.x, center.y + 7.0)
	else:
		footprint_rect = Rect2(center - Vector2(4.0, 16.0), Vector2(8.0, 32.0))
		position = Vector2(center.x, center.y + 16.0)

	add_to_group("structures")
	_build_fence_nodes(decals_layer)


## Clears the brief red hit flash after taking damage.
func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		if _flash_timer <= 0.0:
			modulate = Color.WHITE


## Returns true if this structure is active and still has HP left.
func is_standing() -> bool:
	return active_in_game and hp > 0


## Returns the world point enemies aim toward when walking to this structure.
func get_target_point() -> Vector2:
	return target_center


## Returns the shortest distance from any world point to this structure's outer rectangle.
## Used both for repairing from any side of the house and for keeping enemies outside the walls.
func distance_from_point(world_point: Vector2) -> float:
	var clamped_x: float = clampf(world_point.x, footprint_rect.position.x, footprint_rect.end.x)
	var clamped_y: float = clampf(world_point.y, footprint_rect.position.y, footprint_rect.end.y)
	return world_point.distance_to(Vector2(clamped_x, clamped_y))


## Returns the padded solid rectangle that enemies must never enter or walk through.
## Extra padding accounts for an enemy sprite's half-width so sprites never overlap the walls.
func get_enemy_blocker_rect() -> Rect2:
	return Rect2(
		footprint_rect.position.x - 6.0,
		footprint_rect.position.y - 4.0,
		footprint_rect.size.x + 12.0,
		footprint_rect.size.y + 8.0
	)


## Returns true when an enemy at enemy_pos is close enough to strike this structure's edge.
## For the House, we measure from the outer edge using reach so enemies stop outside the sprite.
func is_within_attack_reach(enemy_pos: Vector2) -> bool:
	if kind == Kind.HOUSE:
		# Half-width of the 96px house is 48px, so (reach - 48) sets the outer strike margin.
		var edge_margin: float = maxf(6.0, reach - 48.0)
		return distance_from_point(enemy_pos) <= edge_margin
	return enemy_pos.distance_to(target_center) <= reach


## Turns a fence slot on (Act 2) or off (Act 1) and refreshes its visuals.
func set_active(enabled: bool) -> void:
	active_in_game = enabled
	_flash_timer = 0.0
	modulate = Color.WHITE
	refresh_visuals()


## Sets HP directly (used on start, dawn setup, and dusk snapshot retry).
func set_hp(new_hp: int) -> void:
	hp = clampi(new_hp, 0, max_hp)
	_flash_timer = 0.0
	modulate = Color.WHITE
	refresh_visuals()


## Heals this structure up to max_hp and returns how many HP were actually restored.
func heal(amount: int) -> int:
	if amount <= 0 or hp >= max_hp:
		return 0
	var hp_before: int = hp
	hp = mini(max_hp, hp + amount)
	refresh_visuals()
	return hp - hp_before


## Applies enemy damage, plays a brief flash, and emits destroyed if HP hits 0.
func take_damage(amount: int) -> void:
	if amount <= 0 or not is_standing():
		return
	hp = maxi(0, hp - amount)
	_flash_timer = 0.12
	modulate = Color(1.4, 0.75, 0.75, 1.0)
	refresh_visuals()
	if hp == 0:
		destroyed.emit(self)


## Syncs the sprites, damage tint, ruin debris, and fence HP bar with current HP.
func refresh_visuals() -> void:
	if kind == Kind.HOUSE:
		visible = active_in_game
		if _damage_overlay != null:
			var damage_ratio: float = 1.0 - (float(hp) / float(maxi(1, max_hp)))
			_damage_overlay.modulate.a = clampf(damage_ratio * 0.4, 0.0, 0.4)
		return

	# Fence visuals are hidden while inactive (Act 1).
	if not active_in_game:
		visible = false
		if _ruin_node != null:
			_ruin_node.visible = false
		return

	visible = true
	var standing: bool = hp > 0
	var tex_key: String = ""
	if standing:
		var folder: String = "fence_wood"
		if hp >= Config.FENCE_REINFORCED_MIN_HP:
			folder = "fence_reinforced"
		var orient: String = "horizontal" if is_horizontal else "vertical"
		tex_key = "structures/%s/%s" % [folder, orient]

	for spr in _fence_sprites:
		spr.visible = standing
		if standing:
			spr.texture = SpriteFactory.tex(tex_key)

	if _ruin_node != null:
		_ruin_node.visible = not standing

	# Show a tiny health bar above damaged fences so repairs are easy to spot.
	if _hp_bar_bg != null and _hp_bar_fill != null:
		var show_bar: bool = standing and hp < max_hp
		_hp_bar_bg.visible = show_bar
		_hp_bar_fill.visible = show_bar
		if show_bar:
			var hp_fraction: float = float(hp) / float(maxi(1, max_hp))
			_hp_bar_fill.size.x = maxf(1.0, floorf(20.0 * hp_fraction))
			if hp >= Config.FENCE_REINFORCED_MIN_HP:
				_hp_bar_fill.color = Color(0.55, 0.85, 0.5, 1.0)
			else:
				_hp_bar_fill.color = Color(0.95, 0.65, 0.25, 1.0)


## Builds the House sprite, pixel-matched red damage overlay, and solid StaticBody2D collider.
func _build_house_nodes() -> void:
	_house_sprite = Sprite2D.new()
	_house_sprite.name = "HouseSprite"
	_house_sprite.texture = SpriteFactory.tex("structures/house")
	_house_sprite.centered = false
	_house_sprite.offset = Vector2(-48.0, -90.0)
	_house_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_house_sprite)

	# Dark-red damage silhouette that fades in as the house loses HP.
	_damage_overlay = Sprite2D.new()
	_damage_overlay.name = "DamageOverlay"
	_damage_overlay.texture = SpriteFactory.get_tinted_silhouette(
		"structures/house",
		Color(0.55, 0.0, 0.0, 1.0)
	)
	_damage_overlay.centered = false
	_damage_overlay.offset = Vector2(-48.0, -90.0)
	_damage_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_damage_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_damage_overlay)

	# Full solid collider (layer 1) so the player can never walk through or overlap the house.
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "HouseBody"
	body.collision_layer = 1
	body.collision_mask = 0

	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var rect_shape: RectangleShape2D = RectangleShape2D.new()
	rect_shape.size = Vector2(96.0, 86.0)
	shape_node.shape = rect_shape
	shape_node.position = Vector2(0.0, -45.0)
	body.add_child(shape_node)
	add_child(body)

	refresh_visuals()


## Builds the standing fence sprites, damaged HP bar, and ground ruin decal for a fence slot.
func _build_fence_nodes(decals_layer: Node2D) -> void:
	_fence_sprites.clear()
	if is_horizontal:
		# Draw 3 horizontal fence segments (16x14 each) side by side.
		for i in range(3):
			var spr: Sprite2D = Sprite2D.new()
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.position = Vector2(-24.0 + float(i * 16), -14.0)
			add_child(spr)
			_fence_sprites.append(spr)
	else:
		# Draw 2 vertical fence segments (8x16 each) stacked top-to-bottom.
		for i in range(2):
			var spr: Sprite2D = Sprite2D.new()
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.position = Vector2(-4.0, -32.0 + float(i * 16))
			add_child(spr)
			_fence_sprites.append(spr)

	var bar_y: float = -19.0 if is_horizontal else -37.0
	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.position = Vector2(-11.0, bar_y)
	_hp_bar_bg.size = Vector2(22.0, 4.0)
	_hp_bar_bg.color = Color(0.08, 0.06, 0.07, 0.85)
	_hp_bar_bg.visible = false
	add_child(_hp_bar_bg)

	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.position = Vector2(-10.0, bar_y + 1.0)
	_hp_bar_fill.size = Vector2(20.0, 2.0)
	_hp_bar_fill.color = Color(0.55, 0.85, 0.5, 1.0)
	_hp_bar_fill.visible = false
	add_child(_hp_bar_fill)

	# Ruin debris and faint corner brackets live in Decals so entities walk over them cleanly.
	_ruin_node = Node2D.new()
	_ruin_node.name = "FenceRuin_%d" % slot_index
	_ruin_node.position = target_center
	_ruin_node.visible = false
	decals_layer.add_child(_ruin_node)

	var debris_tex: Texture2D = SpriteFactory.tex("structures/ruins/gray-brick_debris")
	if is_horizontal:
		for x_off in [-12.0, 10.0]:
			var debris: Sprite2D = Sprite2D.new()
			debris.texture = debris_tex
			debris.centered = false
			debris.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			debris.position = Vector2(x_off - 8.0, -7.0)
			_ruin_node.add_child(debris)
	else:
		var debris: Sprite2D = Sprite2D.new()
		debris.texture = debris_tex
		debris.centered = false
		debris.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		debris.position = Vector2(-8.0, -7.0)
		_ruin_node.add_child(debris)

	_add_corner_marks(_ruin_node, footprint_rect.size)
	refresh_visuals()


## Draws four subtle corner brackets so an empty ruined fence slot is always easy to spot.
func _add_corner_marks(parent_node: Node2D, slot_size: Vector2) -> void:
	var half_w: float = slot_size.x * 0.5
	var half_h: float = slot_size.y * 0.5
	var mark_color: Color = Color(1.0, 0.92, 0.72, 0.45)

	var horiz_corners: Array[Vector2] = [
		Vector2(-half_w, -half_h),
		Vector2(half_w - 3.0, -half_h),
		Vector2(-half_w, half_h - 1.0),
		Vector2(half_w - 3.0, half_h - 1.0),
	]
	for corner_pos in horiz_corners:
		var horiz_line: ColorRect = ColorRect.new()
		horiz_line.position = corner_pos
		horiz_line.size = Vector2(3.0, 1.0)
		horiz_line.color = mark_color
		parent_node.add_child(horiz_line)

	var vert_corners: Array[Vector2] = [
		Vector2(-half_w, -half_h),
		Vector2(half_w - 1.0, -half_h),
		Vector2(-half_w, half_h - 3.0),
		Vector2(half_w - 1.0, half_h - 3.0),
	]
	for corner_pos in vert_corners:
		var vert_line: ColorRect = ColorRect.new()
		vert_line.position = corner_pos
		vert_line.size = Vector2(1.0, 3.0)
		vert_line.color = mark_color
		parent_node.add_child(vert_line)
