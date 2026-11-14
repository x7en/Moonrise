class_name Pile
extends Node2D
## Plank pickup (single plank in Act 1; near, middle, and far piles in Act 2).

var planks: int = 1
var tier: String = "single"
var pickup_radius: float = 12.0
var collected: bool = false


func setup(p_pos: Vector2, p_planks: int, p_tier: String) -> void:
	position = p_pos.round()
	planks = p_planks
	tier = p_tier
	add_to_group("piles")
	_build_visuals()


func check_pickup(player_pos: Vector2) -> int:
	if collected:
		return 0
	if position.distance_to(player_pos) <= pickup_radius:
		collected = true
		queue_free()
		return planks
	return 0


func _build_visuals() -> void:
	# Subtle ground shadow so piles stand out clearly on both grass and wasteland.
	var shadow: ColorRect = ColorRect.new()
	shadow.position = Vector2(-7.0, 2.0)
	shadow.size = Vector2(14.0, 4.0)
	shadow.color = Color(0.0, 0.0, 0.0, 0.28)
	add_child(shadow)

	if tier == "single" or tier == "near":
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = SpriteFactory.tex("pickups_planks/pallet_2")
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.offset = Vector2(-7.0, -6.0)
		add_child(spr)
	elif tier == "middle":
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = SpriteFactory.tex("pickups_planks/pallet_1")
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.offset = Vector2(-6.0, -9.0)
		add_child(spr)
	else:
		# Far ring pile: pallet_1 and pallet_2 stacked to signal high value (6 planks).
		var bottom_spr: Sprite2D = Sprite2D.new()
		bottom_spr.texture = SpriteFactory.tex("pickups_planks/pallet_1")
		bottom_spr.centered = false
		bottom_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bottom_spr.offset = Vector2(-6.0, -8.0)
		add_child(bottom_spr)

		var top_spr: Sprite2D = Sprite2D.new()
		top_spr.texture = SpriteFactory.tex("pickups_planks/pallet_2")
		top_spr.centered = false
		top_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		top_spr.offset = Vector2(-7.0, -13.0)
		add_child(top_spr)
