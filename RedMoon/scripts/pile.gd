class_name Pile
extends Node2D

var item_type: String = "plank"
var amount: int = 1
var tier: String = "single"
var pickup_radius: float = 13.0
var collected: bool = false


func setup(pos: Vector2, amt: int, pile_tier: String, item: String = "plank") -> void:
	position = pos.round()
	amount = maxi(1, amt)
	tier = pile_tier
	item_type = item
	add_to_group("piles")
	_build_visuals()


func try_pickup(player_pos: Vector2, max_can_take: int) -> int:
	if collected or max_can_take <= 0:
		return 0
	if position.distance_to(player_pos) > pickup_radius:
		return 0

	var taken := mini(amount, max_can_take)
	amount -= taken

	if amount <= 0:
		collected = true
		# pull out of group right away or the dusk check still counts it this frame
		remove_from_group("piles")
		queue_free()

	return taken


func _build_visuals() -> void:
	var shadow := Sprite2D.new()
	shadow.texture = Art.get_blob_shadow(16, 6)
	shadow.position = Vector2(0.0, 3.0)
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(shadow)

	if item_type == "scrap":
		var spr := Sprite2D.new()
		spr.texture = Art.get_icon_texture("scrap")
		spr.centered = false
		spr.offset = Vector2(-6.0, -9.0)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if tier == "meteor":
			spr.modulate = Color(1.0, 0.72, 0.45, 1.0)
		add_child(spr)
		return

	if item_type == "arrow":
		var spr := Sprite2D.new()
		spr.texture = Art.get_icon_texture("arrow")
		spr.centered = false
		spr.offset = Vector2(-6.0, -9.0)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(spr)
		return

	if tier == "single" or tier == "near":
		var spr := Sprite2D.new()
		spr.texture = Art.tex("items/planks_2")
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.offset = Vector2(-7.0, -6.0)
		add_child(spr)
	elif tier == "middle":
		var spr := Sprite2D.new()
		spr.texture = Art.tex("items/planks_1")
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.offset = Vector2(-6.0, -9.0)
		add_child(spr)
	else:
		# stack two pallets on top of each other for big piles
		var bottom_spr := Sprite2D.new()
		bottom_spr.texture = Art.tex("items/planks_1")
		bottom_spr.centered = false
		bottom_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bottom_spr.offset = Vector2(-6.0, -8.0)
		add_child(bottom_spr)

		var top_spr := Sprite2D.new()
		top_spr.texture = Art.tex("items/planks_2")
		top_spr.centered = false
		top_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		top_spr.offset = Vector2(-7.0, -13.0)
		add_child(top_spr)
