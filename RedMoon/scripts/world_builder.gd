class_name WorldBuilder
extends RefCounted

# sets up the baked ground map, concentric fence rings, trees, bushes, and scrap wrecks

const TILESET_COLS := 6
const TILE_SIZE := 16
const MAX_SEG_LEN := 64.0
const FENCE_THICKNESS := 10.0

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var search_props: Array[Dictionary] = []
var _act1_boundary_overlay: Node2D = null
var _decals_layer: Node2D = null
var _entities_layer: Node2D = null


# splits each fence ring into contiguous segments + south gate with zero corner gaps
func build_onion_fence_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var half_t: float = FENCE_THICKNESS * 0.5
	var center: Vector2 = Config.HOUSE_CENTER
	var gate_half: float = Config.FENCE_GATE_WIDTH * 0.5

	for ring_def in Config.FENCE_RINGS:
		var ring_num: int = int(ring_def["ring"])
		var he: Vector2 = ring_def["half_extents"] as Vector2
		var gate_x: float = center.x + float(ring_def["gate_offset_x"])
		var built: bool = bool(ring_def["built_at_start"])

		var left_x: float = center.x - he.x
		var right_x: float = center.x + he.x
		var top_y: float = center.y - he.y
		var bottom_y: float = center.y + he.y

		# overlap corners by half thickness so zombies cant slip diagonally through
		_append_h_run(specs, ring_num, built, left_x - half_t, right_x + half_t, top_y)
		# south wall splits around the center gate
		_append_h_run(specs, ring_num, built, left_x - half_t, gate_x - gate_half, bottom_y)
		_append_h_run(specs, ring_num, built, gate_x + gate_half, right_x + half_t, bottom_y)

		# south gate — 2px overlap on both sides so nothing leaks when shut
		specs.append({
			"ring": ring_num,
			"horizontal": true,
			"built": built,
			"is_gate": true,
			"rect": Rect2(
				gate_x - gate_half - 2.0,
				bottom_y - half_t,
				Config.FENCE_GATE_WIDTH + 4.0,
				FENCE_THICKNESS
			),
		})

		# west and east walls overlap the corners too
		_append_v_run(specs, ring_num, built, left_x, top_y - half_t, bottom_y + half_t)
		_append_v_run(specs, ring_num, built, right_x, top_y - half_t, bottom_y + half_t)

	return specs


func _append_h_run(
	specs: Array[Dictionary],
	ring_num: int,
	built: bool,
	x0: float,
	x1: float,
	y_center: float
) -> void:
	var span: float = x1 - x0
	if span <= 4.0:
		return
	var count: int = maxi(1, ceili(span / MAX_SEG_LEN))
	var step: float = span / float(count)
	for i in range(count):
		var a: float = x0 + float(i) * step
		var b: float = x1 if (i == count - 1) else (x0 + float(i + 1) * step)
		specs.append({
			"ring": ring_num,
			"horizontal": true,
			"built": built,
			"is_gate": false,
			"rect": Rect2(a, y_center - FENCE_THICKNESS * 0.5, b - a, FENCE_THICKNESS),
		})


func _append_v_run(
	specs: Array[Dictionary],
	ring_num: int,
	built: bool,
	x_center: float,
	y0: float,
	y1: float
) -> void:
	var span: float = y1 - y0
	if span <= 4.0:
		return
	var count: int = maxi(1, ceili(span / MAX_SEG_LEN))
	var step: float = span / float(count)
	for i in range(count):
		var a: float = y0 + float(i) * step
		var b: float = y1 if (i == count - 1) else (y0 + float(i + 1) * step)
		specs.append({
			"ring": ring_num,
			"horizontal": false,
			"built": built,
			"is_gate": false,
			"rect": Rect2(x_center - FENCE_THICKNESS * 0.5, a, FENCE_THICKNESS, b - a),
		})


func build_world(
	ground_layer: Node2D,
	decals_layer: Node2D,
	entities_layer: Node2D,
	seed_val: int
) -> void:
	rng.seed = seed_val
	_decals_layer = decals_layer
	_entities_layer = entities_layer
	search_props.clear()

	_build_ground(ground_layer)
	_build_homestead_paths(decals_layer)
	_build_world_border_walls(entities_layer)
	_build_act1_boundary_overlay(decals_layer)
	_build_nature_and_pois(decals_layer, entities_layer)


func set_act1_fog_visible(is_visible: bool) -> void:
	if _act1_boundary_overlay != null:
		_act1_boundary_overlay.visible = is_visible


# drops a scorched crater decal when meteors hit during blood moon
func spawn_crater_decal(world_pos: Vector2) -> void:
	if _decals_layer == null:
		return

	var crater_idx := rng.randi_range(1, 6)
	var spr := Sprite2D.new()
	spr.texture = SpriteFactory.tex("ground/crater_%d" % crater_idx)
	spr.centered = true
	spr.position = world_pos.round()
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.modulate = Color(0.90, 0.84, 0.88, 0.92)
	_decals_layer.add_child(spr)


func find_nearest_searchable(world_pos: Vector2, max_dist: float = 30.0) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = max_dist
	for prop in search_props:
		if bool(prop["searched"]):
			continue
		var d: float = world_pos.distance_to(prop["pos"] as Vector2)
		if d <= best_d:
			best_d = d
			best = prop
	return best


func mark_prop_searched(prop_id: int) -> void:
	for prop in search_props:
		if int(prop["id"]) == prop_id:
			prop["searched"] = true
			var node: Node2D = prop["node"] as Node2D
			if is_instance_valid(node):
				node.modulate = Color(0.68, 0.66, 0.68, 1.0)
			return


func spawn_homestead_structures(
	decals_layer: Node2D, entities_layer: Node2D, on_crumbled: Callable
) -> Dictionary:
	var h: Structure = Structure.new()
	h.setup_house(decals_layer)
	h.crumbled_finished.connect(on_crumbled)
	entities_layer.add_child(h)
	var fence_list: Array[Structure] = []
	var all_list: Array[Structure] = [h]
	var specs: Array[Dictionary] = build_onion_fence_specs()
	for i in range(specs.size()):
		var seg: Structure = Structure.new()
		seg.setup_fence_segment(i, specs[i], decals_layer)
		entities_layer.add_child(seg)
		fence_list.append(seg)
		all_list.append(seg)
	return {"house": h, "fences": fence_list, "structures": all_list}


# scatters day 1-3 planks outside ring 1 so you actually have to step out of the yard
func build_act1_plank_positions(count: int, seed_val: int) -> Array[Vector2]:
	var prng: RandomNumberGenerator = RandomNumberGenerator.new()
	prng.seed = seed_val
	var positions: Array[Vector2] = []
	var rect: Rect2 = Config.ACT1_RECT.grow(-24.0)
	var inner_clear: Rect2 = Rect2(Config.HOUSE_CENTER - Vector2(132.0, 96.0), Vector2(264.0, 192.0))
	var tries: int = 0
	while positions.size() < count and tries < 600:
		tries += 1
		var p: Vector2 = Vector2(
			prng.randf_range(rect.position.x, rect.end.x),
			prng.randf_range(rect.position.y, rect.end.y)
		).round()
		if inner_clear.has_point(p):
			continue
		if _too_close(p, positions, 26.0):
			continue
		positions.append(p)
	return positions


func build_act2_pile_specs(seed_val: int) -> Array[Dictionary]:
	var prng: RandomNumberGenerator = RandomNumberGenerator.new()
	prng.seed = seed_val
	var specs: Array[Dictionary] = []
	var used: Array[Vector2] = []
	var tier_names: Array[String] = ["near", "middle", "far"]

	for idx in range(Config.PILES.size()):
		var def: Dictionary = Config.PILES[idx]
		var count: int = int(def["count"])
		var planks: int = int(def["planks"])
		var r_min: float = float(def["r_min"])
		var r_max: float = float(def["r_max"])
		var tier_name: String = tier_names[mini(idx, 2)]
		var tries: int = 0
		var spawned: int = 0
		while spawned < count and tries < 800:
			tries += 1
			var ang: float = prng.randf_range(0.0, TAU)
			var dist: float = prng.randf_range(r_min, r_max)
			var p: Vector2 = (Config.HOUSE_CENTER + Vector2(cos(ang), sin(ang)) * dist).round()
			if not Config.WORLD_RECT.grow(-48.0).has_point(p):
				continue
			if _too_close(p, used, 36.0):
				continue
			used.append(p)
			specs.append({"pos": p, "amount": planks, "tier": tier_name, "type": "plank"})
			spawned += 1

	# Scatter loose scrap piles around mid/outer ruins as well.
	for _s in range(6):
		var ang_s: float = prng.randf_range(0.0, TAU)
		var dist_s: float = prng.randf_range(290.0, 920.0)
		var ps: Vector2 = (Config.HOUSE_CENTER + Vector2(cos(ang_s), sin(ang_s)) * dist_s).round()
		if Config.WORLD_RECT.grow(-52.0).has_point(ps):
			specs.append({
				"pos": ps,
				"amount": prng.randi_range(1, 2),
				"tier": "scrap",
				"type": "scrap",
			})
	return specs


func _build_ground(ground_layer: Node2D) -> void:
	var cols: int = int(Config.WORLD_SIZE.x / float(TILE_SIZE))
	var rows: int = int(Config.WORLD_SIZE.y / float(TILE_SIZE))
	var grass_imgs: Array[Image] = [
		SpriteFactory.get_image_rgba8("ground/grass_0"),
		SpriteFactory.get_image_rgba8("ground/grass_1"),
		SpriteFactory.get_image_rgba8("ground/grass_2"),
		SpriteFactory.get_image_rgba8("ground/grass_3"),
	]
	var waste_imgs: Array[Image] = [
		SpriteFactory.get_image_rgba8("ground/dirt_0"),
		SpriteFactory.get_image_rgba8("ground/dirt_1"),
		SpriteFactory.get_image_rgba8("ground/dirt_2"),
		SpriteFactory.get_image_rgba8("ground/dirt_3"),
	]
	var road_img: Image = _make_asphalt_tile(waste_imgs[0])
	var world_img: Image = Image.create_empty(
		int(Config.WORLD_SIZE.x), int(Config.WORLD_SIZE.y), false, Image.FORMAT_RGBA8
	)

	var hc: Vector2 = Config.HOUSE_CENTER
	var yard_rect: Rect2 = Rect2(hc - Vector2(226.0, 186.0), Vector2(452.0, 372.0))
	var road_y_top: float = hc.y + 206.0
	var road_y_bot: float = hc.y + 254.0
	var road_x_left: float = hc.x - 18.0
	var road_x_right: float = hc.x + 18.0
	var tile_rect: Rect2i = Rect2i(0, 0, TILE_SIZE, TILE_SIZE)

	for ty in range(rows):
		var wy: float = float(ty * TILE_SIZE + 8)
		for tx in range(cols):
			var wx: float = float(tx * TILE_SIZE + 8)
			var pt: Vector2 = Vector2(wx, wy)
			var src_img: Image = grass_imgs[rng.randi() % grass_imgs.size()]
			var on_main_road: bool = (wy >= road_y_top and wy <= road_y_bot)
			var on_driveway: bool = (
				wx >= road_x_left and wx <= road_x_right and wy >= hc.y + 160.0 and wy <= road_y_bot
			)
			if on_main_road or on_driveway:
				src_img = road_img
			elif not yard_rect.has_point(pt) and rng.randf() < 0.16:
				src_img = waste_imgs[rng.randi() % waste_imgs.size()]

			world_img.blit_rect(src_img, tile_rect, Vector2i(tx * TILE_SIZE, ty * TILE_SIZE))

	var ground_spr: Sprite2D = Sprite2D.new()
	ground_spr.name = "GroundBaked"
	ground_spr.texture = ImageTexture.create_from_image(world_img)
	ground_spr.centered = false
	ground_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ground_layer.add_child(ground_spr)


func _make_asphalt_tile(base_img: Image) -> Image:
	var out: Image = base_img.duplicate() as Image
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c: Color = out.get_pixel(x, y)
			var gray: float = (c.r * 0.3 + c.g * 0.5 + c.b * 0.2) * 0.58
			out.set_pixel(x, y, Color(gray * 0.98, gray * 0.96, gray * 1.04, 1.0))
	return out


func _build_homestead_paths(decals_layer: Node2D) -> void:
	# Stepping stones leading from the cottage porch steps through the south gates to the road.
	var hc: Vector2 = Config.HOUSE_CENTER
	var stones: Array = [
		[Vector2(-5.0, 49.0), Vector2(6.0, 4.0)],
		[Vector2(2.0, 53.0), Vector2(5.0, 4.0)],
		[Vector2(-3.0, 58.0), Vector2(6.0, 4.0)],
		[Vector2(2.0, 64.0), Vector2(5.0, 4.0)],
		[Vector2(-4.0, 74.0), Vector2(6.0, 4.0)],
		[Vector2(2.0, 81.0), Vector2(5.0, 4.0)],
		[Vector2(-3.0, 90.0), Vector2(6.0, 4.0)],
		[Vector2(2.0, 98.0), Vector2(5.0, 4.0)],
		[Vector2(-4.0, 118.0), Vector2(6.0, 4.0)],
		[Vector2(2.0, 128.0), Vector2(6.0, 4.0)],
		[Vector2(-3.0, 140.0), Vector2(6.0, 4.0)],
		[Vector2(2.0, 162.0), Vector2(6.0, 4.0)],
		[Vector2(-3.0, 174.0), Vector2(6.0, 4.0)],
	]
	for st in stones:
		var off: Vector2 = st[0] as Vector2
		var sz: Vector2 = st[1] as Vector2
		var border: ColorRect = ColorRect.new()
		border.position = (hc + off - Vector2(1.0, 1.0)).round()
		border.size = sz + Vector2(2.0, 2.0)
		border.color = Color(0.16, 0.14, 0.18, 0.78)
		decals_layer.add_child(border)
		var fill: ColorRect = ColorRect.new()
		fill.position = (hc + off).round()
		fill.size = sz
		fill.color = Color(0.60, 0.63, 0.70, 0.92)
		decals_layer.add_child(fill)


func _build_world_border_walls(entities_layer: Node2D) -> void:
	var border_body: StaticBody2D = StaticBody2D.new()
	border_body.name = "WorldBorder"
	border_body.collision_layer = 1
	border_body.collision_mask = 0
	var ws: Vector2 = Config.WORLD_SIZE
	for wall in [
		{"pos": Vector2(ws.x * 0.5, -8.0), "size": Vector2(ws.x + 32.0, 16.0)},
		{"pos": Vector2(ws.x * 0.5, ws.y + 8.0), "size": Vector2(ws.x + 32.0, 16.0)},
		{"pos": Vector2(-8.0, ws.y * 0.5), "size": Vector2(16.0, ws.y + 32.0)},
		{"pos": Vector2(ws.x + 8.0, ws.y * 0.5), "size": Vector2(16.0, ws.y + 32.0)},
	]:
		var col: CollisionShape2D = CollisionShape2D.new()
		var sh: RectangleShape2D = RectangleShape2D.new()
		sh.size = wall["size"] as Vector2
		col.shape = sh
		col.position = wall["pos"] as Vector2
		border_body.add_child(col)
	entities_layer.add_child(border_body)


func _build_act1_boundary_overlay(decals_layer: Node2D) -> void:
	_act1_boundary_overlay = Node2D.new()
	_act1_boundary_overlay.name = "Act1FogFrame"
	_act1_boundary_overlay.z_index = 4
	var ar: Rect2 = Config.ACT1_RECT
	var ws: Vector2 = Config.WORLD_SIZE
	var fog_col: Color = Color(0.06, 0.05, 0.09, 0.62)
	for rect_def in [
		Rect2(0.0, 0.0, ws.x, ar.position.y),
		Rect2(0.0, ar.end.y, ws.x, ws.y - ar.end.y),
		Rect2(0.0, ar.position.y, ar.position.x, ar.size.y),
		Rect2(ar.end.x, ar.position.y, ws.x - ar.end.x, ar.size.y),
	]:
		var r: ColorRect = ColorRect.new()
		r.position = rect_def.position
		r.size = rect_def.size
		r.color = fog_col
		_act1_boundary_overlay.add_child(r)
	decals_layer.add_child(_act1_boundary_overlay)


func _build_nature_and_pois(decals_layer: Node2D, entities_layer: Node2D) -> void:
	var hc: Vector2 = Config.HOUSE_CENTER
	var safe_yard: Rect2 = Rect2(hc - Vector2(236.0, 196.0), Vector2(472.0, 392.0))
	var used_spots: Array[Vector2] = []

	# searchable scrap wrecks scattered around the valley
	var poi_templates: Array = [
		["Crashed Sedan", "props/car_red", Vector2(36, 16), 2, 1],
		["Wrecked Blue Car", "props/car_blue", Vector2(22, 22), 2, 1],
		["Wrecked Van", "props/van_blue", Vector2(40, 18), 3, 1],
		["Shipping Container", "props/crate_gray", Vector2(38, 18), 2, 2],
		["Supply Container", "props/crate_red", Vector2(38, 18), 3, 1],
		["Burnt Barrel Cache", "props/barrel_red", Vector2(14, 10), 2, 1],
		["Ruined Shack", "props/rubble", Vector2(18, 12), 2, 3],
		["Iron Beam Wreck", "props/beam", Vector2(16, 8), 3, 0],
		["Roadside Barricade", "props/dumpster", Vector2(24, 14), 2, 2],
		["Abandoned Camp", "props/box", Vector2(12, 8), 1, 3],
		["Collapsed Shed", "props/metal", Vector2(20, 12), 2, 2],
		["Green Cargo Box", "props/crate_green", Vector2(38, 18), 3, 1],
		["Scrap Truck", "props/truck_scrap", Vector2(36, 16), 3, 1],
		["Old Shopping Cart", "props/cart", Vector2(12, 10), 2, 2],
		["Fuel Drum Pile", "props/barrel_blue", Vector2(14, 10), 2, 1],
	]

	var prop_id := 1
	# keep the first 4 inside the starter area so players can actually find scrap early
	for idx in range(poi_templates.size()):
		var tpl: Array = poi_templates[idx]
		var in_act1 := (idx < 4)
		var pos := _pick_poi_position(in_act1, safe_yard, used_spots)
		used_spots.append(pos)

		var node := _spawn_prop_node(entities_layer, String(tpl[1]), pos, tpl[2] as Vector2)

		var stain := ColorRect.new()
		stain.position = pos + Vector2(-18.0, -8.0)
		stain.size = Vector2(36.0, 16.0)
		stain.color = Color(0.16, 0.14, 0.15, 0.25)
		decals_layer.add_child(stain)

		search_props.append({
			"id": prop_id,
			"node": node,
			"pos": pos,
			"name": String(tpl[0]),
			"searched": false,
			"loot_scrap": int(tpl[3]),
			"loot_plank": int(tpl[4]),
		})
		prop_id += 1

	# random trees and bushes outside the fenced yard
	var tree_keys: Array[String] = [
		"nature/spruce_1",
		"nature/spruce_2",
		"nature/tree_1",
		"nature/tree_big",
		"nature/pine_big",
		"nature/birch_1",
		"nature/birch_2",
		"nature/oak",
	]
	var bush_keys: Array[String] = [
		"nature/bush_1",
		"nature/bush_2",
		"nature/tuft",
		"nature/rock",
	]
	for _t in range(72):
		var tp: Vector2 = Vector2(
			rng.randf_range(44.0, Config.WORLD_SIZE.x - 44.0),
			rng.randf_range(44.0, Config.WORLD_SIZE.y - 44.0)
		).round()
		if safe_yard.has_point(tp):
			continue
		if absf(tp.y - (hc.y + 212.0)) < 36.0:
			continue
		if _too_close(tp, used_spots, 42.0):
			continue
		used_spots.append(tp)
		var key_t: String = tree_keys[rng.randi() % tree_keys.size()]
		_spawn_prop_node(entities_layer, key_t, tp, Vector2(14.0, 10.0))

	for _b in range(60):
		var bp: Vector2 = Vector2(
			rng.randf_range(32.0, Config.WORLD_SIZE.x - 32.0),
			rng.randf_range(32.0, Config.WORLD_SIZE.y - 32.0)
		).round()
		if safe_yard.has_point(bp):
			continue
		var bush_spr: Sprite2D = SpriteFactory.make_static_sprite(
			bush_keys[rng.randi() % bush_keys.size()], true
		)
		bush_spr.position = bp
		entities_layer.add_child(bush_spr)


func _pick_poi_position(in_act1: bool, safe_yard: Rect2, used: Array[Vector2]) -> Vector2:
	var region: Rect2 = (
		Config.ACT1_RECT.grow(-36.0) if in_act1 else Config.WORLD_RECT.grow(-90.0)
	)
	for _attempt in range(250):
		var p: Vector2 = Vector2(
			rng.randf_range(region.position.x, region.end.x),
			rng.randf_range(region.position.y, region.end.y)
		).round()
		if safe_yard.has_point(p):
			continue
		if not in_act1 and Config.ACT1_RECT.grow(24.0).has_point(p):
			continue
		if _too_close(p, used, 90.0):
			continue
		return p
	return Vector2(region.position.x + 48.0, region.position.y + 48.0)


func _spawn_prop_node(
	parent: Node2D,
	tex_key: String,
	pos: Vector2,
	solid_size: Vector2
) -> Node2D:
	var holder: Node2D = Node2D.new()
	holder.position = pos.round()

	var shadow: Sprite2D = Sprite2D.new()
	shadow.texture = SpriteFactory.get_blob_shadow(
		maxi(14, int(solid_size.x + 6.0)), maxi(6, int(solid_size.y * 0.55))
	)
	shadow.position = Vector2(0.0, 2.0)
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.add_child(shadow)

	var spr: Sprite2D = SpriteFactory.make_static_sprite(tex_key, true)
	holder.add_child(spr)

	if solid_size.x > 0.0 and solid_size.y > 0.0:
		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var col: CollisionShape2D = CollisionShape2D.new()
		var sh: RectangleShape2D = RectangleShape2D.new()
		sh.size = solid_size
		col.shape = sh
		col.position = Vector2(0.0, -solid_size.y * 0.5)
		body.add_child(col)
		holder.add_child(body)

	parent.add_child(holder)
	return holder


func _too_close(p: Vector2, others: Array[Vector2], min_d: float) -> bool:
	var min_sq: float = min_d * min_d
	for o in others:
		if p.distance_squared_to(o) < min_sq:
			return true
	return false
