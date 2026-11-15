class_name Fx
extends Node2D

signal meteor_impacted(impact_pos: Vector2)

var show_debug_colliders: bool = false
var _sparks: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _meteors: Array[Dictionary] = []
var _debug_structures: Array = []
var _debug_player: Node2D
var _debug_enemies: Array = []
var _trap_preview: Dictionary = {"active": false}


func set_debug_refs(structures: Array, player: Node2D, enemies: Array) -> void:
	_debug_structures = structures
	_debug_player = player
	_debug_enemies = enemies


func set_trap_preview(
	active: bool,
	pos: Vector2 = Vector2.ZERO,
	trigger_r: float = 13.0,
	extra_r: float = 0.0,
	valid: bool = true,
	icon_key: String = "trap_spike"
) -> void:
	_trap_preview = {
		"active": active,
		"pos": pos.round(),
		"trigger_r": trigger_r,
		"extra_r": extra_r,
		"valid": valid,
		"icon_key": icon_key,
	}
	queue_redraw()


func spawn_sparks(pos: Vector2, col: Color, count: int = 6) -> void:
	for i in range(count):
		var ang := randf_range(0.0, TAU)
		var spd := randf_range(24.0, 62.0)
		_sparks.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"col": col,
			"life": randf_range(0.14, 0.28),
			"max_life": 0.28,
		})
	queue_redraw()


func spawn_ring(pos: Vector2, max_r: float, col: Color) -> void:
	_rings.append({
		"pos": pos, "r": 6.0, "max_r": max_r, "col": col, "life": 0.34, "max_life": 0.34
	})
	queue_redraw()


func spawn_floating_text(pos: Vector2, text: String, col: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos + Vector2(-36.0, -18.0)
	lbl.size = Vector2(72.0, 12.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.z_index = 20
	Art.style_label(lbl, "bold", 8, col)
	add_child(lbl)

	var tw := create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 16.0, 0.70)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.70)
	tw.tween_callback(lbl.queue_free)


func schedule_meteor(impact_pos: Vector2) -> void:
	_meteors.append({
		"pos": impact_pos.round(),
		"timer": Config.METEOR_TELEGRAPH_TIME,
		"total": Config.METEOR_TELEGRAPH_TIME,
	})
	queue_redraw()


func clear_all() -> void:
	_sparks.clear()
	_rings.clear()
	_meteors.clear()
	for child in get_children():
		child.queue_free()
	queue_redraw()


func _process(delta: float) -> void:
	var dirty := show_debug_colliders

	var i := _sparks.size() - 1
	while i >= 0:
		var sp := _sparks[i]
		sp["life"] = float(sp["life"]) - delta
		if float(sp["life"]) <= 0.0:
			_sparks.remove_at(i)
		else:
			sp["pos"] = sp["pos"] + sp["vel"] * delta
			sp["vel"] = sp["vel"] * 0.90
		dirty = true
		i -= 1

	var r_idx := _rings.size() - 1
	while r_idx >= 0:
		var rg := _rings[r_idx]
		rg["life"] = float(rg["life"]) - delta
		if float(rg["life"]) <= 0.0:
			_rings.remove_at(r_idx)
		else:
			var t := 1.0 - float(rg["life"]) / float(rg["max_life"])
			rg["r"] = lerpf(8.0, float(rg["max_r"]), t)
		dirty = true
		r_idx -= 1

	var m_idx := _meteors.size() - 1
	while m_idx >= 0:
		var mt := _meteors[m_idx]
		mt["timer"] = float(mt["timer"]) - delta
		dirty = true
		if float(mt["timer"]) <= 0.0:
			var pos = mt["pos"]
			_meteors.remove_at(m_idx)
			spawn_sparks(pos, Color(1.0, 0.48, 0.20, 1.0), 14)
			spawn_ring(pos, Config.METEOR_RADIUS + 6.0, Color(1.0, 0.36, 0.18, 0.9))
			meteor_impacted.emit(pos)
		m_idx -= 1

	if dirty:
		queue_redraw()


func _draw() -> void:
	for sp in _sparks:
		var a := clampf(float(sp["life"]) / float(sp["max_life"]), 0.0, 1.0)
		var col = sp["col"]
		col.a *= a
		draw_rect(Rect2(sp["pos"] - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), col)

	for rg in _rings:
		var a := clampf(float(rg["life"]) / float(rg["max_life"]), 0.0, 1.0)
		var col = rg["col"]
		col.a *= a
		draw_arc(rg["pos"], float(rg["r"]), 0.0, TAU, 28, col, 1.5)

	for mt in _meteors:
		var pos = mt["pos"]
		var t := 1.0 - clampf(float(mt["timer"]) / float(mt["total"]), 0.0, 1.0)
		var shadow_r := lerpf(Config.METEOR_RADIUS * 1.15, 5.0, t)

		draw_circle(pos, shadow_r, Color(0.10, 0.04, 0.08, 0.40 + t * 0.35))
		draw_arc(pos, Config.METEOR_RADIUS, 0.0, TAU, 24, Color(1.0, 0.32, 0.22, 0.85), 1.0)

		var rock_pos = pos + Vector2(-42.0, -96.0) * (1.0 - t)
		draw_line(
			rock_pos + Vector2(-8.0, -18.0), rock_pos, Color(1.0, 0.52, 0.20, 0.85), 2.0
		)
		draw_circle(rock_pos, 3.0, Color(1.0, 0.88, 0.56, 1.0))

	if bool(_trap_preview.get("active", false)):
		var tp = _trap_preview["pos"]
		var ok := bool(_trap_preview["valid"])
		var tint := Color(0.35, 0.96, 0.50, 0.72) if ok else Color(1.0, 0.28, 0.28, 0.72)
		var extra_r := float(_trap_preview["extra_r"])

		if extra_r > 0.0:
			draw_arc(tp, extra_r, 0.0, TAU, 36, Color(tint.r, tint.g, tint.b, 0.28), 1.0)
		draw_circle(tp, float(_trap_preview["trigger_r"]), Color(tint.r, tint.g, tint.b, 0.18))
		draw_arc(tp, float(_trap_preview["trigger_r"]), 0.0, TAU, 20, tint, 1.0)

		var icon_tex := Art.get_icon_texture(String(_trap_preview["icon_key"]))
		if icon_tex != null:
			var sz := icon_tex.get_size()
			draw_texture(icon_tex, tp - sz * 0.5, Color(tint.r, tint.g, tint.b, 0.85))

	if show_debug_colliders:
		_draw_debug_colliders()


func _draw_debug_colliders() -> void:
	for s in _debug_structures:
		if not is_instance_valid(s) or not (s is Structure):
			continue
		var st = s
		var col := (
			Color(0.25, 0.95, 0.45, 0.90) if st.is_standing() else Color(0.5, 0.5, 0.6, 0.35)
		)
		draw_rect(st.footprint_rect, col, false, 1.0)

	if is_instance_valid(_debug_player):
		draw_rect(
			Rect2(_debug_player.position + Vector2(-4.0, -8.0), Vector2(8.0, 8.0)),
			Color(0.35, 0.78, 1.0, 0.95),
			false,
			1.0
		)

	for e in _debug_enemies:
		if is_instance_valid(e) and e.is_alive():
			draw_rect(
				Rect2(e.position + Vector2(-5.0, -10.0), Vector2(10.0, 10.0)),
				Color(1.0, 0.30, 0.30, 0.95),
				false,
				1.0
			)
