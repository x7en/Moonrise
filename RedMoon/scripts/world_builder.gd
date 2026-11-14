class_name WorldBuilder
extends RefCounted
## Pre-renders the 1440 x 810 ground texture and populates deterministic seeded scenery.

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


static func build_ground_texture(
	world_size: Vector2,
	house_center: Vector2,
	seed_val: int = 1337
) -> ImageTexture:
	var w: int = int(world_size.x)
	var h: int = int(world_size.y)
	var ground: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)

	var grass_imgs: Array[Image] = []
	for k in GRASS_KEYS:
		grass_imgs.append(SpriteFactory.get_image_rgba8(k))
	var waste_imgs: Array[Image] = []
	for k in WASTELAND_KEYS:
		waste_imgs.append(SpriteFactory.get_image_rgba8(k))

	var cols: int = int(ceili(float(w) / 16.0))
	var rows: int = int(ceili(float(h) / 16.0))
	for ty in range(rows):
		var dst_y: int = ty * 16
		var blit_h: int = mini(16, h - dst_y)
		for tx in range(cols):
			var dst_x: int = tx * 16
			var blit_w: int = mini(16, w - dst_x)
			var tile_center: Vector2 = Vector2(float(dst_x + 8), float(dst_y + 8))
			var dist: float = tile_center.distance_to(house_center)

			var h_val: int = _tile_hash(tx, ty, seed_val)
			var variant: int = 0
			var roll: int = h_val % 100
			if roll < 68:
				variant = 0
			elif roll < 80:
				variant = 1
			elif roll < 91:
				variant = 2
			else:
				variant = 3

			# Soft noisy edge right around 330 px so grass transitions organically into wasteland.
			var jitter_r: float = 330.0 + float((h_val % 25) - 12)
			var tile_img: Image = waste_imgs[variant] if dist > jitter_r else grass_imgs[variant]
			ground.blit_rect(tile_img, Rect2i(0, 0, blit_w, blit_h), Vector2i(dst_x, dst_y))

	return ImageTexture.create_from_image(ground)


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

	# 1. Act 1 cell border framing: a few trees and props around the corners/edges only.
	var act1_border_spots: Array[Vector2] = [
		Vector2(506.0, 298.0),
		Vector2(548.0, 288.0),
		Vector2(932.0, 298.0),
		Vector2(890.0, 288.0),
		Vector2(504.0, 520.0),
		Vector2(552.0, 528.0),
		Vector2(934.0, 522.0),
		Vector2(886.0, 528.0),
		Vector2(498.0, 362.0),
		Vector2(498.0, 462.0),
		Vector2(942.0, 362.0),
		Vector2(942.0, 462.0),
	]
	for spot in act1_border_spots:
		var tree_key: String = TREE_KEYS[rng.randi() % TREE_KEYS.size()]
		_try_place_scenery(
			entities_parent,
			tree_key,
			spot + Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-4.0, 4.0)),
			true,
			house_center,
			structures,
			solid_rects,
			placed_positions,
			16.0
		)

	var act1_props: Array[Vector2] = [
		Vector2(526.0, 326.0),
		Vector2(912.0, 326.0),
		Vector2(532.0, 496.0),
		Vector2(906.0, 496.0),
		Vector2(614.0, 286.0),
		Vector2(826.0, 286.0),
		Vector2(616.0, 526.0),
		Vector2(824.0, 526.0),
	]
	for p_spot in act1_props:
		var prop_key: String = SMALL_NATURE_KEYS[rng.randi() % SMALL_NATURE_KEYS.size()]
		_try_place_scenery(
			entities_parent,
			prop_key,
			p_spot,
			false,
			house_center,
			structures,
			solid_rects,
			placed_positions,
			12.0
		)

	# 2. Middle and far rings: solid trees, containers, rusty cars.
	var act1_inner: Rect2 = act1_rect.grow(-12.0)

	# Trees across the grassy middle ring and sparse far border.
	for _i in range(85):
		var pos: Vector2 = _random_world_pos(rng, world_size, 28.0)
		var dist: float = pos.distance_to(house_center)
		if dist < 135.0 or act1_inner.has_point(pos):
			continue
		if dist > 350.0 and rng.randf() > 0.25:
			continue
		var t_key: String = TREE_KEYS[rng.randi() % TREE_KEYS.size()]
		_try_place_scenery(
			entities_parent,
			t_key,
			pos,
			true,
			house_center,
			structures,
			solid_rects,
			placed_positions,
			28.0
		)

	# Shipping containers in middle and far rings.
	for _i in range(16):
		var pos: Vector2 = _random_world_pos(rng, world_size, 42.0)
		var dist: float = pos.distance_to(house_center)
		if dist < 210.0 or act1_inner.has_point(pos):
			continue
		var c_key: String = CONTAINER_KEYS[rng.randi() % CONTAINER_KEYS.size()]
		_try_place_scenery(
			entities_parent,
			c_key,
			pos,
			true,
			house_center,
			structures,
			solid_rects,
			placed_positions,
			46.0
		)

	# Rusty cars in middle and far wasteland rings.
	for _i in range(18):
		var pos: Vector2 = _random_world_pos(rng, world_size, 44.0)
		var dist: float = pos.distance_to(house_center)
		if dist < 220.0 or act1_inner.has_point(pos):
			continue
		var v_key: String = CAR_KEYS[rng.randi() % CAR_KEYS.size()]
		_try_place_scenery(
			entities_parent,
			v_key,
			pos,
			true,
			house_center,
			structures,
			solid_rects,
			placed_positions,
			48.0
		)

	# 3. Non-solid detail: grass tufts, bushes, rocks, barrels, wasteland debris.
	for _i in range(120):
		var pos: Vector2 = _random_world_pos(rng, world_size, 20.0)
		var dist: float = pos.distance_to(house_center)
		if dist < 120.0:
			continue
		var key: String = ""
		if dist <= 330.0:
			if rng.randf() < 0.78:
				key = SMALL_NATURE_KEYS[rng.randi() % SMALL_NATURE_KEYS.size()]
			else:
				key = MIDDLE_PROP_KEYS[rng.randi() % MIDDLE_PROP_KEYS.size()]
		else:
			if rng.randf() < 0.35:
				key = "nature/rock-grass"
			else:
				key = FAR_PROP_KEYS[rng.randi() % FAR_PROP_KEYS.size()]
		_try_place_scenery(
			entities_parent,
			key,
			pos,
			false,
			house_center,
			structures,
			solid_rects,
			placed_positions,
			16.0
		)

	return solid_rects


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
	if snapped.distance_to(house_center) < 120.0:
		return false

	# Keep clear of the house and all 6 fence slots.
	for item in structures:
		var s: Structure = item as Structure
		if s != null and s.distance_from_point(snapped) < 28.0:
			return false

	var col_size: Vector2 = _collider_size_for_key(key)
	var world_col: Rect2 = Rect2(
		snapped.x - col_size.x * 0.5,
		snapped.y - col_size.y,
		col_size.x,
		col_size.y
	)

	# Prevent overlapping solid colliders so the player can never get stuck.
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


static func _collider_size_for_key(key: String) -> Vector2:
	if key.begins_with("nature/tree"):
		return Vector2(12.0, 6.0)
	if key.begins_with("props/container"):
		var dims: Array = SpriteData.STATIC.get(key, [24, 24])
		var w: float = float(dims[0])
		var h: float = float(dims[1])
		return Vector2(maxf(12.0, w - 6.0), clampf(h * 0.45, 10.0, 22.0))
	if key.begins_with("vehicles/"):
		var dims: Array = SpriteData.STATIC.get(key, [24, 24])
		var w: float = float(dims[0])
		var h: float = float(dims[1])
		return Vector2(maxf(14.0, w - 8.0), clampf(h * 0.42, 10.0, 20.0))
	return Vector2(10.0, 6.0)


static func _random_world_pos(
	rng: RandomNumberGenerator,
	world_size: Vector2,
	margin: float
) -> Vector2:
	return Vector2(
		rng.randf_range(margin, world_size.x - margin),
		rng.randf_range(margin, world_size.y - margin)
	)


static func _tile_hash(tx: int, ty: int, seed_val: int) -> int:
	var n: int = tx * 374761393 + ty * 668265263 + seed_val * 1442695041
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return n & 0x7FFFFFFF
