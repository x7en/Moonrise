class_name WorldBuilder
extends RefCounted
## Pre-renders the 1440x810 ground texture, builds the farmhouse yard fence, and scatters scenery.

const GRASS_KEYS: Array[String] = [
	"terrain/grass_0",
	"terrain/grass_1",
	"terrain/grass_2",
	"terrain/grass_3",
]
const WASTELAND_KEYS: Array[String] = [
	"terrain/wasteland_0",
	"terrain/wasteland_1",
	"terrain/wasteland_2",
	"terrain/wasteland_3",
]

const TREE_KEYS: Array[String] = [
	"nature/tree_1_spruce_green",
	"nature/tree_2_spruce-sparse_green",
	"nature/tree_3_normal_green",
	"nature/tree_5_big_green",
	"nature/tree_6_pine_big_green",
	"nature/tree_7_birch_green",
	"nature/tree_8_birch_green",
	"nature/tree_9_small-oak_green",
	"nature/tree_10_small-oak_green",
]

const SMALL_NATURE_KEYS: Array[String] = [
	"nature/bush_1_green",
	"nature/bush_2_green",
	"nature/grass_1_green",
	"nature/grass_2_green",
	"nature/grass_3_green",
	"nature/grass_4_green",
	"nature/grass_5_green",
	"nature/rock-grass",
]

const CONTAINER_KEYS: Array[String] = [
	"props/container_11_green_horizontal",
	"props/container_3_gray_horizontal",
	"props/container_7_red_horizontal",
	"props/container_1_gray_vertical",
	"props/container_5_red_vertical",
	"props/container_9_green_vertical",
]

const CAR_KEYS: Array[String] = [
	"vehicles/car_1_rust_blue",
	"vehicles/car_2_rust_blue_upsidedown",
	"vehicles/car_3_rust_blue_van",
	"vehicles/car_4_rust_red",
	"vehicles/car_6_rust_green_scrap",
	"vehicles/car_7_rust_green_truck_",
]

const MIDDLE_PROP_KEYS: Array[String] = [
	"props/barrel_blue_1",
	"props/barrel_red_1",
	"props/barrel_rust_blue_1",
	"props/barrel_rust_red_1",
	"props/tire_1",
	"props/trash-bag_1",
	"props/cardboard_1",
	"nature/tree-trunk_2_grass_green",
]

const FAR_PROP_KEYS: Array[String] = [
	"props/barrel_rust_red_1",
	"props/barrel_rust_blue_1",
	"props/garbage-bin_1",
	"props/shopping-cart",
	"props/street-light_1_side",
	"props/hydrant_1_red",
	"props/traffic-cone",
	"props/trash-can_1",
	"props/cardboard_2",
	"structures/ruins/gray-brick_debris",
	"structures/ruins/iron-beam",
	"structures/ruins/metal-plates",
]


## Pre-renders the entire 1440x810 ground into ONE ImageTexture for fast 60 fps rendering.
## Includes grass near home, bleak wasteland beyond 330 px, and a farmhouse yard/path dirt patch.
static func build_ground_texture(
	world_size: Vector2,
	house_center: Vector2,
	seed_val: int = 1337
) -> ImageTexture:
	var width: int = int(world_size.x)
	var height: int = int(world_size.y)
	var ground: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)

	var grass_imgs: Array[Image] = []
	for key in GRASS_KEYS:
		grass_imgs.append(SpriteFactory.get_image_rgba8(key))

	var waste_imgs: Array[Image] = []
	for key in WASTELAND_KEYS:
		waste_imgs.append(SpriteFactory.get_image_rgba8(key))

	# Stamp 16x16 terrain tiles across the entire world map.
	var cols: int = int(ceili(float(width) / 16.0))
	var rows: int = int(ceili(float(height) / 16.0))
	for ty in range(rows):
		var dst_y: int = ty * 16
		var blit_h: int = mini(16, height - dst_y)
		for tx in range(cols):
			var dst_x: int = tx * 16
			var blit_w: int = mini(16, width - dst_x)
			var tile_center: Vector2 = Vector2(float(dst_x + 8), float(dst_y + 8))
			var dist: float = tile_center.distance_to(house_center)

			var h_val: int = _tile_hash(tx, ty, seed_val)
			var variant: int = _pick_tile_variant(h_val)

			# Slight noise around 330 px makes the grass-to-wasteland edge look natural.
			var transition_r: float = 330.0 + float((h_val % 25) - 12)
			var tile_img: Image = grass_imgs[variant]
			if dist > transition_r:
				tile_img = waste_imgs[variant]

			ground.blit_rect(tile_img, Rect2i(0, 0, blit_w, blit_h), Vector2i(dst_x, dst_y))

	# Paint a warm packed-dirt yard inside the farmhouse fence and a path out the south gate.
	_paint_farmhouse_yard_dirt(ground, house_center, seed_val)

	return ImageTexture.create_from_image(ground)


## Builds the visible farmhouse yard fence around the house with a clear front DOOR gap at south.
## Returns the 6 Act-1 decorative fill segments so main.gd can hide them when Act-2 fences activate.
static func build_farmhouse_yard(
	entities_parent: Node2D,
	house_center: Vector2,
	fence_slots: Array
) -> Array[Node2D]:
	var left_x: float = house_center.x - 92.0
	var right_x: float = house_center.x + 92.0
	var top_y: float = house_center.y - 62.0
	var bottom_y: float = house_center.y + 62.0

	# 1. Four wooden corner posts tying the yard walls into one tidy farmhouse compound.
	_place_yard_piece(
		entities_parent,
		"structures/fence_wood/left-side_right_down-connect",
		Vector2(left_x - 6.0, top_y + 9.0)
	)
	_place_yard_piece(
		entities_parent,
		"structures/fence_wood/right-side_left_down-connect",
		Vector2(right_x - 6.0, top_y + 9.0)
	)
	_place_yard_piece(
		entities_parent,
		"structures/fence_wood/left-side_right_up-connect",
		Vector2(left_x - 6.0, bottom_y + 7.0)
	)
	_place_yard_piece(
		entities_parent,
		"structures/fence_wood/right-side_left_up-connect",
		Vector2(right_x - 6.0, bottom_y + 7.0)
	)

	# 2. North center fence rail connecting the top-left and top-right fence slots.
	var north_x: float = house_center.x - 46.0
	for i in range(6):
		_place_yard_piece(
			entities_parent,
			"structures/fence_wood/horizontal",
			Vector2(north_x + float(i * 16), top_y + 7.0)
		)

	# 3. South front yard fence WITH A CLEAR DOOR GAP centered on HOUSE_DOOR (x = 720).
	# Left wing runs up to x = 700, right wing starts at x = 740, leaving a clear doorway.
	_place_yard_piece(
		entities_parent,
		"structures/fence_wood/horizontal",
		Vector2(house_center.x - 46.0, bottom_y + 7.0)
	)
	_place_yard_piece(
		entities_parent,
		"structures/fence_wood/horizontal",
		Vector2(house_center.x - 34.0, bottom_y + 7.0)
	)
	_place_yard_piece(
		entities_parent,
		"structures/fence_wood/vertical_for-gate",
		Vector2(house_center.x - 20.0, bottom_y + 7.0)
	)

	_place_yard_piece(
		entities_parent,
		"structures/fence_wood/vertical_for-gate",
		Vector2(house_center.x + 13.0, bottom_y + 7.0)
	)
	_place_yard_piece(
		entities_parent,
		"structures/fence_wood/horizontal",
		Vector2(house_center.x + 18.0, bottom_y + 7.0)
	)
	_place_yard_piece(
		entities_parent,
		"structures/fence_wood/horizontal",
		Vector2(house_center.x + 30.0, bottom_y + 7.0)
	)

	# 4. West and East vertical rails connecting corners to the middle side fence slots.
	for side_x in [left_x - 4.0, right_x - 4.0]:
		_place_yard_piece(
			entities_parent,
			"structures/fence_wood/vertical",
			Vector2(side_x, top_y + 28.0)
		)
		_place_yard_piece(
			entities_parent,
			"structures/fence_wood/vertical",
			Vector2(side_x, top_y + 45.0)
		)
		_place_yard_piece(
			entities_parent,
			"structures/fence_wood/vertical",
			Vector2(side_x, bottom_y - 30.0)
		)
		_place_yard_piece(
			entities_parent,
			"structures/fence_wood/vertical",
			Vector2(side_x, bottom_y - 11.0)
		)

	# 5. Act-1 decorative fills for the 6 defense slots so the yard fence is complete in Act 1,
	#    then cleanly swaps out for real destructible/repairable Fences in Act 2.
	var act1_slot_fills: Array[Node2D] = []
	for slot_item in fence_slots:
		var slot: Dictionary = slot_item as Dictionary
		var slot_center: Vector2 = house_center + (slot["offset"] as Vector2)
		var is_horiz: bool = bool(slot["horizontal"])
		var fill_holder: Node2D = Node2D.new()

		if is_horiz:
			fill_holder.position = Vector2(slot_center.x, slot_center.y + 7.0)
			for seg_idx in range(3):
				var spr: Sprite2D = Sprite2D.new()
				spr.texture = SpriteFactory.tex("structures/fence_wood/horizontal")
				spr.centered = false
				spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				spr.position = Vector2(-24.0 + float(seg_idx * 16), -14.0)
				fill_holder.add_child(spr)
		else:
			fill_holder.position = Vector2(slot_center.x, slot_center.y + 16.0)
			for seg_idx in range(2):
				var spr: Sprite2D = Sprite2D.new()
				spr.texture = SpriteFactory.tex("structures/fence_wood/vertical")
				spr.centered = false
				spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				spr.position = Vector2(-4.0, -32.0 + float(seg_idx * 16))
				fill_holder.add_child(spr)

		entities_parent.add_child(fill_holder)
		act1_slot_fills.append(fill_holder)

	return act1_slot_fills


## Populates the 1440x810 map with richer seeded trees, bushes, rocks, containers, cars, and props.
## Returns solid collider Rect2s so plank piles never spawn trapped inside solid obstacles.
static func populate_scenery(
	entities_parent: Node2D,
	structures: Array,
	world_size: Vector2,
	house_center: Vector2,
	act1_rect: Rect2,
	seed_val: int = 4242
) -> Array[Rect2]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val

	var solid_rects: Array[Rect2] = []
	var placed_positions: Array[Vector2] = []

	# 1. Act 1 border framing: trees and natural accents around the edges of the center screen.
	var act1_border_trees: Array[Vector2] = [
		Vector2(504.0, 296.0),
		Vector2(546.0, 286.0),
		Vector2(934.0, 296.0),
		Vector2(892.0, 286.0),
		Vector2(504.0, 522.0),
		Vector2(552.0, 530.0),
		Vector2(934.0, 522.0),
		Vector2(886.0, 530.0),
		Vector2(496.0, 358.0),
		Vector2(496.0, 464.0),
		Vector2(944.0, 358.0),
		Vector2(944.0, 464.0),
	]
	for spot in act1_border_trees:
		var tree_key: String = TREE_KEYS[rng.randi() % TREE_KEYS.size()]
		var jitter: Vector2 = Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0))
		_try_place_scenery(
			entities_parent,
			tree_key,
			spot + jitter,
			true,
			house_center,
			structures,
			solid_rects,
			placed_positions,
			16.0
		)

	var act1_border_details: Array[Vector2] = [
		Vector2(526.0, 326.0),
		Vector2(912.0, 326.0),
		Vector2(532.0, 496.0),
		Vector2(906.0, 496.0),
		Vector2(604.0, 286.0),
		Vector2(836.0, 286.0),
		Vector2(606.0, 528.0),
		Vector2(834.0, 528.0),
		Vector2(556.0, 405.0),
		Vector2(884.0, 405.0),
	]
	for detail_spot in act1_border_details:
		var detail_key: String = SMALL_NATURE_KEYS[rng.randi() % SMALL_NATURE_KEYS.size()]
		_try_place_scenery(
			entities_parent,
			detail_key,
			detail_spot,
			false,
			house_center,
			structures,
			solid_rects,
			placed_positions,
			12.0
		)

	# 2. Enriched middle and outer rings: denser groves of trees, shipping containers, and cars.
	var act1_inner: Rect2 = act1_rect.grow(-14.0)

	# Place trees across the grassy ring and sparse dead-edge pines in the wasteland.
	for _i in range(135):
		var pos: Vector2 = _random_world_pos(rng, world_size, 26.0)
		var dist: float = pos.distance_to(house_center)
		if dist < 140.0 or act1_inner.has_point(pos):
			continue
		if dist > 360.0 and rng.randf() > 0.28:
			continue
		var tree_key: String = TREE_KEYS[rng.randi() % TREE_KEYS.size()]
		_try_place_scenery(
			entities_parent,
			tree_key,
			pos,
			true,
			house_center,
			structures,
			solid_rects,
			placed_positions,
			26.0
		)

	# Place shipping containers in middle and far wasteland zones as strong landmarks.
	for _i in range(24):
		var pos: Vector2 = _random_world_pos(rng, world_size, 42.0)
		var dist: float = pos.distance_to(house_center)
		if dist < 205.0 or act1_inner.has_point(pos):
			continue
		var container_key: String = CONTAINER_KEYS[rng.randi() % CONTAINER_KEYS.size()]
		_try_place_scenery(
			entities_parent,
			container_key,
			pos,
			true,
			house_center,
			structures,
			solid_rects,
			placed_positions,
			44.0
		)

	# Place abandoned rusty cars and trucks throughout the middle and outer wasteland.
	for _i in range(26):
		var pos: Vector2 = _random_world_pos(rng, world_size, 44.0)
		var dist: float = pos.distance_to(house_center)
		if dist < 210.0 or act1_inner.has_point(pos):
			continue
		var car_key: String = CAR_KEYS[rng.randi() % CAR_KEYS.size()]
		_try_place_scenery(
			entities_parent,
			car_key,
			pos,
			true,
			house_center,
			structures,
			solid_rects,
			placed_positions,
			44.0
		)

	# 3. Generous non-solid details: bushes, grass tufts, rocks, barrels, and wasteland debris.
	for _i in range(220):
		var pos: Vector2 = _random_world_pos(rng, world_size, 18.0)
		var dist: float = pos.distance_to(house_center)
		if dist < 130.0:
			continue

		var prop_key: String = ""
		if dist <= 330.0:
			if rng.randf() < 0.75:
				prop_key = SMALL_NATURE_KEYS[rng.randi() % SMALL_NATURE_KEYS.size()]
			else:
				prop_key = MIDDLE_PROP_KEYS[rng.randi() % MIDDLE_PROP_KEYS.size()]
		else:
			if rng.randf() < 0.30:
				prop_key = "nature/rock-grass"
			else:
				prop_key = FAR_PROP_KEYS[rng.randi() % FAR_PROP_KEYS.size()]

		_try_place_scenery(
			entities_parent,
			prop_key,
			pos,
			false,
			house_center,
			structures,
			solid_rects,
			placed_positions,
			14.0
		)

	return solid_rects


## Paints packed earth inside the farmhouse fence yard and a worn dirt lane out the front gate.
static func _paint_farmhouse_yard_dirt(
	ground: Image,
	house_center: Vector2,
	seed_val: int
) -> void:
	var yard_rect: Rect2i = Rect2i(
		int(house_center.x) - 90,
		int(house_center.y) - 60,
		180,
		122
	)
	var path_rect: Rect2i = Rect2i(
		int(house_center.x) - 16,
		int(house_center.y) + 54,
		32,
		72
	)
	var dirt_warm: Color = Color(0.56, 0.45, 0.34, 1.0)
	var dirt_dark: Color = Color(0.46, 0.36, 0.27, 1.0)

	_blend_dirt_rect(ground, yard_rect, dirt_warm, dirt_dark, 0.42, seed_val)
	_blend_dirt_rect(ground, path_rect, dirt_warm, dirt_dark, 0.56, seed_val + 99)


## Blends subtle speckled packed dirt over a rectangular area of the ground texture.
static func _blend_dirt_rect(
	ground: Image,
	rect: Rect2i,
	light_col: Color,
	dark_col: Color,
	strength: float,
	seed_val: int
) -> void:
	var max_w: int = ground.get_width()
	var max_h: int = ground.get_height()
	var x0: int = maxi(0, rect.position.x)
	var y0: int = maxi(0, rect.position.y)
	var x1: int = mini(max_w, rect.end.x)
	var y1: int = mini(max_h, rect.end.y)

	for y in range(y0, y1):
		for x in range(x0, x1):
			# Feather the outer 4 pixels so the yard dirt blends softly into the grass.
			var edge_x: int = mini(x - x0, (x1 - 1) - x)
			var edge_y: int = mini(y - y0, (y1 - 1) - y)
			var edge_dist: int = mini(edge_x, edge_y)
			var edge_fade: float = clampf(float(edge_dist + 1) / 5.0, 0.15, 1.0)

			var h_val: int = _tile_hash(x, y, seed_val)
			var dirt_col: Color = light_col if (h_val % 3 != 0) else dark_col
			var base_col: Color = ground.get_pixel(x, y)
			var blended: Color = base_col.lerp(dirt_col, strength * edge_fade)
			ground.set_pixel(x, y, blended)


## Places a single decorative wooden fence piece inside Entities using its bottom-left feet point.
static func _place_yard_piece(
	entities_parent: Node2D,
	tex_key: String,
	bottom_left_pos: Vector2
) -> void:
	var dims: Array = SpriteData.STATIC.get(tex_key, [16, 14])
	var sprite_h: float = float(dims[1])

	var holder: Node2D = Node2D.new()
	holder.position = Vector2(bottom_left_pos.x, bottom_left_pos.y).round()

	var spr: Sprite2D = Sprite2D.new()
	spr.texture = SpriteFactory.tex(tex_key)
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = Vector2(0.0, -sprite_h)
	holder.add_child(spr)
	entities_parent.add_child(holder)


## Validates spacing and places either a solid StaticBody2D prop or a decorative Node2D prop.
static func _try_place_scenery(
	entities_parent: Node2D,
	key: String,
	pos: Vector2,
	is_solid: bool,
	house_center: Vector2,
	structures: Array,
	solid_rects: Array[Rect2],
	placed_positions: Array[Vector2],
	min_spacing: float
) -> bool:
	var snapped: Vector2 = pos.round()
	if snapped.distance_to(house_center) < 125.0:
		return false

	# Keep clear of the house, front door path, and all 6 fence slots.
	for item in structures:
		var struct_node: Structure = item as Structure
		if struct_node != null and struct_node.distance_from_point(snapped) < 30.0:
			return false

	var col_size: Vector2 = _collider_size_for_key(key)
	var world_col: Rect2 = Rect2(
		snapped.x - col_size.x * 0.5,
		snapped.y - col_size.y,
		col_size.x,
		col_size.y
	)

	# Keep breathing room between solid obstacles so fast player movement never gets wedged.
	var pad: float = 18.0 if is_solid else 6.0
	for existing in solid_rects:
		if existing.grow(pad).intersects(world_col):
			return false

	var min_sq: float = min_spacing * min_spacing
	for prev in placed_positions:
		if prev.distance_squared_to(snapped) < min_sq:
			return false

	var node: Node2D = null
	if is_solid:
		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape_node: CollisionShape2D = CollisionShape2D.new()
		var rect_shape: RectangleShape2D = RectangleShape2D.new()
		rect_shape.size = col_size
		shape_node.shape = rect_shape
		shape_node.position = Vector2(0.0, -col_size.y * 0.5)
		body.add_child(shape_node)
		node = body
		solid_rects.append(world_col)
	else:
		node = Node2D.new()

	node.position = snapped
	var spr: Sprite2D = SpriteFactory.make_static_sprite(key, true)
	node.add_child(spr)
	entities_parent.add_child(node)
	placed_positions.append(snapped)
	return true


## Chooses an appropriate base footprint collider size for trees, containers, and cars.
static func _collider_size_for_key(key: String) -> Vector2:
	if key.begins_with("nature/tree"):
		return Vector2(12.0, 6.0)
	if key.begins_with("props/container"):
		var dims: Array = SpriteData.STATIC.get(key, [24, 24])
		var width: float = float(dims[0])
		var height: float = float(dims[1])
		return Vector2(maxf(12.0, width - 6.0), clampf(height * 0.45, 10.0, 22.0))
	if key.begins_with("vehicles/"):
		var dims: Array = SpriteData.STATIC.get(key, [24, 24])
		var width: float = float(dims[0])
		var height: float = float(dims[1])
		return Vector2(maxf(14.0, width - 8.0), clampf(height * 0.42, 10.0, 20.0))
	return Vector2(10.0, 6.0)


## Picks a seeded ground tile index (mostly variant 0, with accents sprinkled in).
static func _pick_tile_variant(hash_val: int) -> int:
	var roll: int = hash_val % 100
	if roll < 68:
		return 0
	if roll < 80:
		return 1
	if roll < 91:
		return 2
	return 3


## Picks a random point inside the world with a safety margin from the map edges.
static func _random_world_pos(
	rng: RandomNumberGenerator,
	world_size: Vector2,
	margin: float
) -> Vector2:
	return Vector2(
		rng.randf_range(margin, world_size.x - margin),
		rng.randf_range(margin, world_size.y - margin)
	)


## Divides a night's zombies and raiders into small clusters of 2-3 arriving from one side.
## Rotating sides prevents an unfair 360-degree wall while keeping every wave exciting.
static func build_wave_groups(
	zombies: int,
	raiders: int,
	group_min: int,
	group_max: int,
	include_brute: bool
) -> Array:
	var groups: Array = []

	var remaining_zombies: int = zombies
	var last_side: int = -1
	while remaining_zombies > 0:
		var group_size: int = mini(randi_range(group_min, group_max), remaining_zombies)
		remaining_zombies -= group_size

		var chosen_side: int = randi() % 4
		if chosen_side == last_side:
			chosen_side = (chosen_side + 1 + (randi() % 3)) % 4
		last_side = chosen_side

		var members: Array[String] = []
		for _k in range(group_size):
			members.append("zombie")
		groups.append({"side": chosen_side, "members": members})

	# Raiders always march in pairs from the east edge (side 3).
	var remaining_raiders: int = raiders
	while remaining_raiders > 0:
		var raider_size: int = mini(2, remaining_raiders)
		remaining_raiders -= raider_size
		var r_members: Array[String] = []
		for _k in range(raider_size):
			r_members.append("raider")
		groups.append({"side": 3, "members": r_members})

	if include_brute:
		groups.append({"side": randi() % 4, "members": ["brute"]})

	groups.shuffle()
	return groups


## Picks a perimeter spawn coordinate just outside the active spawn ring along the chosen side.
## Side indices: 0 = North, 1 = South, 2 = West, 3 = East. Never spawns on top of the player.
static func pick_spawn_position(
	area: Rect2,
	enemy_type: String,
	side: int,
	raider_side: String,
	player_pos: Vector2,
	world_rect: Rect2
) -> Vector2:
	var margin: float = 14.0
	var chosen_pos: Vector2 = Vector2.ZERO

	if enemy_type == "raider" and raider_side == "east":
		chosen_pos = Vector2(
			area.end.x + margin,
			randf_range(area.position.y + 40.0, area.end.y - 40.0)
		)
	else:
		match side:
			0:
				chosen_pos = Vector2(
					randf_range(area.position.x + 36.0, area.end.x - 36.0),
					area.position.y - margin
				)
			1:
				chosen_pos = Vector2(
					randf_range(area.position.x + 36.0, area.end.x - 36.0),
					area.end.y + margin
				)
			2:
				chosen_pos = Vector2(
					area.position.x - margin,
					randf_range(area.position.y + 36.0, area.end.y - 36.0)
				)
			_:
				chosen_pos = Vector2(
					area.end.x + margin,
					randf_range(area.position.y + 36.0, area.end.y - 36.0)
				)

	# If the player wandered near the spawn ring at dusk, push the spawn safely off-screen.
	if chosen_pos.distance_to(player_pos) < 160.0:
		var away: Vector2 = chosen_pos - player_pos
		if away.length_squared() < 1.0:
			away = Vector2.RIGHT
		chosen_pos = player_pos + away.normalized() * 175.0
		chosen_pos.x = clampf(chosen_pos.x, world_rect.position.x - margin, world_rect.end.x + margin)
		chosen_pos.y = clampf(chosen_pos.y, world_rect.position.y - margin, world_rect.end.y + margin)

	return chosen_pos


## Scatters Act 1 single planks around the center screen and returns nothing (adds to decals).
static func scatter_act1_planks(
	decals_parent: Node2D,
	act1_rect: Rect2,
	house_center: Vector2,
	plank_count: int,
	structures: Array,
	solid_rects: Array[Rect2]
) -> void:
	var placed: Array[Vector2] = []
	var bounds: Rect2 = act1_rect.grow(-22.0)

	for _i in range(plank_count):
		var pos: Vector2 = find_valid_plank_pos(
			bounds, house_center, 82.0, 260.0, structures, solid_rects, placed
		)
		placed.append(pos)
		var pile: Pile = Pile.new()
		decals_parent.add_child(pile)
		pile.setup(pos, 1, "single")


## Scatters Act 2 plank piles across the 3 distance rings (near, middle, far wasteland).
static func scatter_act2_piles(
	decals_parent: Node2D,
	world_rect: Rect2,
	house_center: Vector2,
	pile_rings: Array,
	structures: Array,
	solid_rects: Array[Rect2]
) -> void:
	var placed: Array[Vector2] = []
	var bounds: Rect2 = world_rect.grow(-28.0)
	var tier_names: Array[String] = ["near", "middle", "far"]

	for ring_idx in range(pile_rings.size()):
		var ring: Dictionary = pile_rings[ring_idx] as Dictionary
		var count: int = int(ring["count"])
		var planks_val: int = int(ring["planks"])
		var r_min: float = float(ring["r_min"])
		var r_max: float = float(ring["r_max"])
		var tier_name: String = tier_names[mini(ring_idx, tier_names.size() - 1)]

		for _j in range(count):
			var pos: Vector2 = find_valid_ring_pos(
				bounds, house_center, r_min, r_max, structures, solid_rects, placed
			)
			placed.append(pos)
			var pile: Pile = Pile.new()
			decals_parent.add_child(pile)
			pile.setup(pos, planks_val, tier_name)


## Finds an unobstructed spot for an Act 1 plank inside the center screen.
static func find_valid_plank_pos(
	bounds: Rect2,
	house_center: Vector2,
	min_dist: float,
	max_dist: float,
	structures: Array,
	solid_rects: Array[Rect2],
	existing: Array[Vector2]
) -> Vector2:
	for _attempt in range(60):
		var candidate: Vector2 = Vector2(
			randf_range(bounds.position.x, bounds.end.x),
			randf_range(bounds.position.y, bounds.end.y)
		).round()

		var dist: float = candidate.distance_to(house_center)
		if dist < min_dist or dist > max_dist:
			continue
		if _is_pile_pos_blocked(candidate, house_center, structures, solid_rects, existing):
			continue
		return candidate

	return (house_center + Vector2(115.0, 0.0)).round()


## Finds a randomized spot inside a loot ring (r_min..r_max) that honors the minimum distance.
## Rejecting too-close clamped points guarantees far piles sit 6-10 seconds away at 85 px/s.
static func find_valid_ring_pos(
	bounds: Rect2,
	house_center: Vector2,
	r_min: float,
	r_max: float,
	structures: Array,
	solid_rects: Array[Rect2],
	existing: Array[Vector2]
) -> Vector2:
	for _attempt in range(90):
		var angle: float = randf_range(0.0, TAU)
		var radius: float = randf_range(r_min, r_max)
		var candidate: Vector2 = house_center + Vector2(cos(angle), sin(angle)) * radius
		candidate.x = clampf(candidate.x, bounds.position.x, bounds.end.x)
		candidate.y = clampf(candidate.y, bounds.position.y, bounds.end.y)
		candidate = candidate.round()

		if candidate.distance_to(house_center) < r_min * 0.92:
			continue
		if _is_pile_pos_blocked(candidate, house_center, structures, solid_rects, existing):
			continue
		return candidate

	var fallback_side: float = 1.0 if randf() >= 0.5 else -1.0
	var fallback_x: float = clampf(
		house_center.x + fallback_side * r_min,
		bounds.position.x,
		bounds.end.x
	)
	return Vector2(fallback_x, house_center.y).round()


## Returns true if a loot pile overlaps the farmhouse yard, structures, scenery, or another pile.
static func _is_pile_pos_blocked(
	pos: Vector2,
	house_center: Vector2,
	structures: Array,
	solid_rects: Array[Rect2],
	existing: Array[Vector2]
) -> bool:
	# Keep all planks outside the wooden farmhouse yard fence perimeter.
	var yard_rect: Rect2 = Rect2(house_center - Vector2(104.0, 76.0), Vector2(208.0, 152.0))
	if yard_rect.has_point(pos):
		return true
	for item in structures:
		var struct_node: Structure = item as Structure
		if struct_node != null and struct_node.footprint_rect.grow(16.0).has_point(pos):
			return true
	for col_rect in solid_rects:
		if col_rect.grow(10.0).has_point(pos):
			return true
	for prev in existing:
		if prev.distance_squared_to(pos) < 900.0:
			return true
	return false


## Spawns a rising world-space floating text popup using the shared retro pixel font Theme.
static func spawn_floating_text(
	effects_parent: Node2D,
	world_pos: Vector2,
	text: String,
	color: Color,
	ui_theme: Theme
) -> void:
	var holder: Node2D = Node2D.new()
	holder.position = world_pos.round()

	var lbl: Label = Label.new()
	lbl.text = text
	lbl.position = Vector2(-42.0, -8.0)
	lbl.size = Vector2(84.0, 12.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.theme = ui_theme
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", color)
	holder.add_child(lbl)
	effects_parent.add_child(holder)

	var tw: Tween = holder.create_tween()
	tw.set_parallel(true)
	tw.tween_property(holder, "position:y", holder.position.y - 14.0, 0.85)
	tw.tween_property(holder, "modulate:a", 0.0, 0.85)
	tw.chain().tween_callback(holder.queue_free)


## Deterministic integer hash used for ground tiling and dirt speckling.
static func _tile_hash(tx: int, ty: int, seed_val: int) -> int:
	var n: int = tx * 374761393 + ty * 668265263 + seed_val * 1442695041
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return n & 0x7FFFFFFF
