class_name Pile
extends Node2D
## Collectible pickup in group "piles": planks, scrap/meteor shards, or arrow bundles.
## Always freed when picked up or cleared at nightfall (T0.3).

var item_type: String = "plank"
var amount: int = 1
var tier: String = "single"
var pickup_radius: float = 13.0
var collected: bool = false


func setup(p_pos: Vector2, p_amount: int, p_tier: String, p_item_type: String = "plank") -> void:
	position = p_pos.round()
	amount = maxi(1, p_amount)
	tier = p_tier
	item_type = p_item_type
	add_to_group("piles")
	_build_visuals()


## Attempts pickup if player is within radius and has room. Returns amount collected.
func try_pickup(player_pos: Vector2, max_can_take: int) -> int:
	if collected or max_can_take <= 0:
		return 0
	if position.distance_to(player_pos) > pickup_radius:
		return 0

	var taken: int = mini(amount, max_can_take)
	amount -= taken
	if amount <= 0:
		collected = true
		queue_free()
	return taken


func _build_visuals() -> void:
	# Consistent elliptical blob shadow (T1.4).
	var shadow: Sprite2D = Sprite2D.new()
	shadow.texture = SpriteFactory.get_blob_shadow(16, 6)
	shadow.position = Vector2(0.0, 3.0)
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(shadow)

	if item_type == "scrap":
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = SpriteFactory.get_icon_texture("scrap")
		spr.centered = false
		spr.offset = Vector2(-6.0, -9.0)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if tier == "meteor":
			spr.modulate = Color(1.0, 0.72, 0.45, 1.0)
		add_child(spr)
		return

	if item_type == "arrow":
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = SpriteFactory.get_icon_texture("arrow")
		spr.centered = false
		spr.offset = Vector2(-6.0, -9.0)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(spr)
		return

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
